@echo off
REM === instructions definition ===
set UI_INSTS=lh lhu sh sb lb lbu sw lw add addi sub and andi or ori xor xori sll srl sra slli srli srai slt slti jalr sltu sltiu beq bne blt bge bltu bgeu jal lui auipc 
set MI_INSTS=csr scall sbreak ma_fetch
set UM_INSTS=mul mulh mulhu mulhsu div divu rem remu

REM === 仿真前编译 ===
vlog -sv rtl/cpu_top/*.sv rtl/cpu_top/*.svh test/*.sv
if errorlevel 1 (
    echo Compile failed!
    exit /b 1
)
if not exist results (
    mkdir results
)
echo.

=== UI instructions simulation ===
echo Starting simulation for UI instructions...
for %%i in (%UI_INSTS%) do (
    echo.
    echo ====== Simulating rv32ui-p-%%i ======
    copy /Y "hex\riscv-tests\rv32ui-p-%%i.hex" "hex\riscv-tests\rv32-p-riscv.hex" >nul
    vsim -c -do "run -all; quit -force" tb_cpu_top > results\%%i.txt
    findstr /C:"Test passed." results\%%i.txt >nul
    if errorlevel 1 (
        powershell -Command "Write-Host '[FAILED] rv32ui-p-%%i' -ForegroundColor Red"
        powershell -Command "Write-Host 'Simulating failed on: rv32ui-p-%%i' -ForegroundColor Red"
        type results\%%i.txt
        goto :fail
    ) else (
        powershell -Command "Write-Host '[PASSED] rv32ui-p-%%i' -ForegroundColor Green"
    )
)
echo.

REM === MI instructions simulation ===
echo Starting simulation for MI instructions...
for %%i in (%MI_INSTS%) do (
    echo.
    echo ====== Simulating rv32mi-p-%%i ======
    copy /Y "hex\riscv-tests\rv32mi-p-%%i.hex" "hex\riscv-tests\rv32-p-riscv.hex" >nul
    vsim -c -do "run -all; quit -force" tb_cpu_top > results\%%i.txt
    findstr /C:"Test passed." results\%%i.txt >nul
    if errorlevel 1 (
        powershell -Command "Write-Host '[FAILED] rv32mi-p-%%i' -ForegroundColor Red"
        powershell -Command "Write-Host 'Simulating failed on: rv32mi-p-%%i' -ForegroundColor Red"
        type results\%%i.txt
        goto :fail
    ) else (
        powershell -Command "Write-Host '[PASSED] rv32mi-p-%%i' -ForegroundColor Green"
    )
)
echo.

REM === UM instructions simulation ===
echo Starting simulation for UM instructions...
for %%i in (%UM_INSTS%) do (
    echo.
    echo ====== Simulating rv32um-p-%%i ======
    copy /Y "hex\riscv-tests\rv32um-p-%%i.hex" "hex\riscv-tests\rv32-p-riscv.hex" >nul
    vsim -c -do "run -all; quit -force" tb_cpu_top > results\%%i.txt
    findstr /C:"Test passed." results\%%i.txt >nul
    if errorlevel 1 (
        powershell -Command "Write-Host '[FAILED] rv32um-p-%%i' -ForegroundColor Red"
        powershell -Command "Write-Host 'Simulating failed on: rv32um-p-%%i' -ForegroundColor Red"
        type results\%%i.txt
        goto :fail
    ) else (
        powershell -Command "Write-Host '[PASSED] rv32um-p-%%i' -ForegroundColor Green"
    )
)
echo.
echo All tests finished!
echo ALL TESTS PASSED!
pause
exit /b 0

:fail
echo.
powershell -Command "Write-Host 'failure detected during simulation.' -ForegroundColor Red"
powershell -Command "Write-Host 'See results\\%%i.txt for details.' -ForegroundColor Red"
pause
exit /b 1