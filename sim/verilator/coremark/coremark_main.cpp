#include "Vmy_cpu.h"
#include "Vmy_cpu___024root.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

constexpr uint32_t kUartCyclesPerBit = 1520;
constexpr std::array<uint8_t, 28> kCompletionMarker = {
    'C', 'o', 'r', 'r', 'e', 'c', 't', ' ',
    'o', 'p', 'e', 'r', 'a', 't', 'i', 'o', 'n', ' ',
    'v', 'a', 'l', 'i', 'd', 'a', 't', 'e', 'd', '.'
};

class UartDecoder {
public:
    bool sample(bool tx) {
        switch (state_) {
        case State::Idle:
            if (!tx) {
                state_ = State::Start;
                countdown_ = kUartCyclesPerBit / 2 - 1;
            }
            break;
        case State::Start:
            if (countdown_-- == 0) {
                if (!tx) {
                    state_ = State::Data;
                    countdown_ = kUartCyclesPerBit - 1;
                    bit_ = 0;
                    value_ = 0;
                } else {
                    state_ = State::Idle;
                }
            }
            break;
        case State::Data:
            if (countdown_-- == 0) {
                value_ |= static_cast<uint8_t>(tx) << bit_;
                countdown_ = kUartCyclesPerBit - 1;
                if (bit_ == 7) {
                    state_ = State::Stop;
                } else {
                    ++bit_;
                }
            }
            break;
        case State::Stop:
            if (countdown_-- == 0) {
                if (!tx) {
                    throw std::runtime_error("UART framing error");
                }
                state_ = State::Idle;
                return emit(value_);
            }
            break;
        }
        return false;
    }

private:
    enum class State { Idle, Start, Data, Stop };

    bool emit(uint8_t value) {
        std::cout.put(static_cast<char>(value));
        std::cout.flush();

        if (!marker_seen_) {
            if (value == kCompletionMarker[marker_pos_]) {
                ++marker_pos_;
            } else {
                marker_pos_ = value == kCompletionMarker[0] ? 1 : 0;
            }
            if (marker_pos_ == kCompletionMarker.size()) {
                marker_seen_ = true;
            }
        } else if (value == '\n') {
            return true;
        }
        return false;
    }

    State state_ = State::Idle;
    uint32_t countdown_ = 0;
    uint32_t bit_ = 0;
    uint8_t value_ = 0;
    std::size_t marker_pos_ = 0;
    bool marker_seen_ = false;
};

uint64_t parse_u64(const std::string& value) {
    std::size_t used = 0;
    const uint64_t result = std::stoull(value, &used, 0);
    if (used != value.size()) {
        throw std::runtime_error("invalid integer: " + value);
    }
    return result;
}

template <std::size_t Words>
void load_hex(const std::string& path, VlUnpacked<IData, Words>& memory) {
    std::ifstream input(path);
    if (!input) {
        throw std::runtime_error("cannot open memory image: " + path);
    }

    std::string token;
    std::size_t index = 0;
    while (input >> token) {
        if (index >= Words) {
            throw std::runtime_error("memory image is too large: " + path);
        }
        memory[index++] = static_cast<uint32_t>(std::stoul(token, nullptr, 16));
    }
    if (index != Words) {
        throw std::runtime_error("memory image word count mismatch: " + path);
    }
}

void feed_test_bit(UartDecoder& decoder, bool value) {
    for (uint32_t i = 0; i < kUartCyclesPerBit; ++i) {
        decoder.sample(value);
    }
}

bool uart_selftest() {
    UartDecoder decoder;
    for (uint8_t value : kCompletionMarker) {
        feed_test_bit(decoder, false);
        for (uint32_t bit = 0; bit < 8; ++bit) {
            feed_test_bit(decoder, (value >> bit) & 1U);
        }
        feed_test_bit(decoder, true);
    }
    for (uint8_t value : std::array<uint8_t, 2>{'\r', '\n'}) {
        feed_test_bit(decoder, false);
        for (uint32_t bit = 0; bit < 8; ++bit) {
            feed_test_bit(decoder, (value >> bit) & 1U);
        }
        bool complete = false;
        for (uint32_t i = 0; i < kUartCyclesPerBit; ++i) {
            complete |= decoder.sample(true);
        }
        if (complete) {
            return true;
        }
    }
    return false;
}

} // namespace

int main(int argc, char** argv) {
    try {
        std::string inst_hex;
        std::string data_hex;
        uint64_t max_cycles = 30'000'000'000ULL;
        bool selftest = false;

        for (int i = 1; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg.rfind("+INST_HEX=", 0) == 0) {
                inst_hex = arg.substr(10);
            } else if (arg.rfind("+DATA_HEX=", 0) == 0) {
                data_hex = arg.substr(10);
            } else if (arg.rfind("+MAX_CYCLES=", 0) == 0) {
                max_cycles = parse_u64(arg.substr(12));
            } else if (arg == "+UART_DECODER_SELFTEST") {
                selftest = true;
            }
        }

        if (selftest) {
            return uart_selftest() ? 0 : 1;
        }
        if (inst_hex.empty() || data_hex.empty()) {
            throw std::runtime_error("+INST_HEX and +DATA_HEX are required");
        }

        VerilatedContext context;
        context.commandArgs(argc, argv);
        Vmy_cpu model{&context};

        load_hex(inst_hex, model.rootp->my_cpu__DOT__u_inst_ram__DOT__mem);
        load_hex(data_hex, model.rootp->my_cpu__DOT__u_data_ram__DOT__mem);

        model.clk = 0;
        model.clk_uart = 0;
        model.rst_n = 0;
        model.uart_rx = 1;
        model.external_interrupts = 0;
        model.eval();

        UartDecoder decoder;
        uint64_t cycles = 0;
        while (cycles < max_cycles) {
            model.clk = 0;
            model.clk_uart = 0;
            model.eval();

            model.clk = 1;
            model.clk_uart = 1;
            model.eval();
            ++cycles;

            if (cycles == 16) {
                model.rst_n = 1;
            }
            if (cycles > 16 && decoder.sample(model.uart_tx)) {
                model.final();
                return 0;
            }
        }

        model.final();
        std::cerr << "CoreMark timeout after " << cycles << " CPU cycles\n";
        return 2;
    } catch (const std::exception& error) {
        std::cerr << "CoreMark simulation error: " << error.what() << '\n';
        return 1;
    }
}
