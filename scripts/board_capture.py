"""Capture actual board UART bytes; optionally validate a CoreMark result.

Start this process before programming so the startup banner is retained. This
tool never transmits commands or changes the board configuration.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import time

import serial
from serial.tools import list_ports


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', default='COM6')
    parser.add_argument('--baud', type=int, default=115200)
    parser.add_argument('--duration', type=float, default=180)
    parser.add_argument('--until', default='COREMARK_RESULT')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu-hz', type=int)
    parser.add_argument('--require-valid-coremark', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    devices = [{'port': p.device, 'description': p.description, 'hwid': p.hwid}
               for p in list_ports.comports()]
    selected = [p for p in devices if p['port'].casefold() == args.port.casefold()]
    if len(selected) != 1 or '1A86:7523' not in selected[0]['hwid'].upper():
        raise RuntimeError('Selected port is not the expected unique CH340 board UART')
    start = time.monotonic()
    capture = bytearray()
    marker_time = None
    started_at = now()
    with serial.Serial(args.port, args.baud, timeout=0.1, write_timeout=1,
                       bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                       stopbits=serial.STOPBITS_ONE, xonxoff=False,
                       rtscts=False, dsrdtr=False) as uart, \
         (args.output/'rx.jsonl').open('w', encoding='utf-8') as events, \
         (args.output/'rx.bin').open('wb') as raw:
        uart.reset_input_buffer()
        (args.output/'ready.json').write_text(json.dumps({
            'port': selected[0], 'started_at': started_at, 'baud': args.baud,
            'transmitted_bytes': 0,
        }, indent=2)+'\n', encoding='utf-8')
        print('BOARD_UART_CAPTURE_READY '+str(args.output.resolve()), flush=True)
        while time.monotonic()-start < args.duration:
            chunk = uart.read(max(1, min(uart.in_waiting, 8192)))
            if chunk:
                capture.extend(chunk)
                raw.write(chunk)
                raw.flush()
                event = {'utc': now(), 'elapsed_s': time.monotonic()-start,
                         'rx_hex': chunk.hex(), 'byte_count': len(chunk)}
                events.write(json.dumps(event)+'\n')
                events.flush()
                sys.stdout.write(chunk.decode('ascii', errors='replace'))
                sys.stdout.flush()
                if args.until.encode('ascii') in capture and b'\n' in capture[capture.find(args.until.encode('ascii')):]:
                    marker_time = time.monotonic()
            if marker_time is not None and time.monotonic()-marker_time > 1:
                break
    text = capture.decode('ascii', errors='replace')
    (args.output/'uart.txt').write_text(text, encoding='utf-8')
    result = {'started_at': started_at, 'finished_at': now(), 'port': selected[0],
              'baud': args.baud, 'bytes': len(capture), 'transmitted_bytes': 0,
              'duration_s': time.monotonic()-start,
              'raw_sha256': hashlib.sha256(capture).hexdigest(),
              'marker_found': marker_time is not None,
              'valid_coremark': False, 'status': 'CAPTURED'}
    lines = [line for line in text.splitlines() if line.startswith('COREMARK_RESULT ')]
    if lines:
        fields = dict(re.findall(r'(\w+)=([^\s]+)', lines[-1]))
        result['coremark'] = fields
        result['valid_coremark'] = (
            len(lines) == 1 and fields.get('status') == 'PASS'
            and fields.get('valid') == '1'
            and 'COREMARK_CRC status=PASS' in text
            and 'Correct operation validated.' in text
            and 'ERROR!' not in text and 'Errors detected' not in text
            and int(fields.get('elapsed_ms', '0')) >= 10000
            and int(fields.get('iterations', '0')) > 0
            and int(fields.get('cycles', '0')) > 0
            and (args.cpu_hz is None or int(fields.get('cpu_hz', '0')) == args.cpu_hz)
        )
        if result['valid_coremark']:
            expected = (int(fields['iterations'])*int(fields['cpu_hz'])*1000)//int(fields['cycles'])
            result['independent_score_x1000'] = expected
            if abs(expected-int(fields.get('score_x1000', '-100'))) > 1:
                result['valid_coremark'] = False
        result['status'] = 'PASS' if result['valid_coremark'] else 'INVALID_COREMARK'
    elif not result['marker_found']:
        result['status'] = 'TIMEOUT'
    elif 'SMOKE_FAIL' in text:
        result['status'] = 'FIRMWARE_FAIL'
    elif 'SMOKE_PASS' in text:
        result['status'] = 'SMOKE_PASS'
    (args.output/'capture_result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('\nBOARD_CAPTURE_RESULT '+json.dumps(result), flush=True)
    if args.require_valid_coremark and not result['valid_coremark']:
        return 1
    return 0 if result['marker_found'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
