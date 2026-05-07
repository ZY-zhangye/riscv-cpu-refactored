@echo off
setlocal EnableExtensions

REM === instructions definition ===
set UI_INSTS=lh lhu sh sb lb lbu sw lw add addi sub and andi or ori xor xori sll srl sra slli srli srai slt slti jalr sltu sltiu beq bne blt bge bltu bgeu jal lui auipc
set MI_INSTS=csr scall sbreak ma_fetch
set UM_INSTS=mul mulh mulhu mulhsu div divu rem remu

REM === currently implemented Z-bitman instructions ===
set ZBA_INSTS=sh1add sh2add sh3add
set ZBB_INSTS=andn orn xnor min max minu maxu sext_b sext_h zext_h orc_b rev8
set ZBKB_INSTS=brev8 pack packh zip unzip
set ZBS_INSTS=bclr bclri bext bexti binv binvi bset bseti

set MODE=%~1
if "%MODE%"=="" set MODE=all

REM === compilation ===
vlog -sv rtl/cpu_top/*.sv rtl/cpu_top/*.svh test/*.sv
if errorlevel 1 (
    echo Compile failed!
    exit /b 1
)
if not exist results (
    mkdir results
)
echo.

if /I "%MODE%"=="z" goto :run_z_only
if /I "%MODE%"=="zba" goto :run_zba_only
if /I "%MODE%"=="zbb" goto :run_zbb_only
if /I "%MODE%"=="zbkb" goto :run_zbkb_only
if /I "%MODE%"=="zbs" goto :run_zbs_only
if /I "%MODE%"=="base" goto :run_base_only
if /I not "%MODE%"=="all" goto :usage

:run_base
set "GROUP_NAME=UI instructions"
set "TEST_PREFIX=rv32ui-p"
set "TEST_LIST=%UI_INSTS%"
set "RESULT_PREFIX=ui"
call :run_group
if errorlevel 1 goto :fail

set "GROUP_NAME=MI instructions"
set "TEST_PREFIX=rv32mi-p"
set "TEST_LIST=%MI_INSTS%"
set "RESULT_PREFIX=mi"
call :run_group
if errorlevel 1 goto :fail

set "GROUP_NAME=UM instructions"
set "TEST_PREFIX=rv32um-p"
set "TEST_LIST=%UM_INSTS%"
set "RESULT_PREFIX=um"
call :run_group
if errorlevel 1 goto :fail

if /I "%MODE%"=="base" (
    echo.
    echo Base tests finished!
    echo BASE TESTS PASSED!
    pause
    exit /b 0
)

if /I "%MODE%"=="all" (
    call :run_z_groups
    if errorlevel 1 goto :fail
    echo.
    echo All tests finished!
    echo ALL TESTS PASSED!
    pause
    exit /b 0
)

:run_base_only
set MODE=base
goto :run_base

:run_z_only
call :run_z_groups
if errorlevel 1 goto :fail
echo.
echo Z extension tests finished!
echo Z TESTS PASSED!
pause
exit /b 0

:run_z_groups
set "GROUP_NAME=Zba instructions"
set "TEST_PREFIX=rv32uzba-p"
set "TEST_LIST=%ZBA_INSTS%"
set "RESULT_PREFIX=zba"
call :run_group
if errorlevel 1 exit /b 1
set "GROUP_NAME=Zbb implemented instructions"
set "TEST_PREFIX=rv32uzbb-p"
set "TEST_LIST=%ZBB_INSTS%"
set "RESULT_PREFIX=zbb"
call :run_group
if errorlevel 1 exit /b 1
set "GROUP_NAME=Zbkb instructions"
set "TEST_PREFIX=rv32uzbkb-p"
set "TEST_LIST=%ZBKB_INSTS%"
set "RESULT_PREFIX=zbkb"
call :run_group
if errorlevel 1 exit /b 1
set "GROUP_NAME=Zbs instructions"
set "TEST_PREFIX=rv32uzbs-p"
set "TEST_LIST=%ZBS_INSTS%"
set "RESULT_PREFIX=zbs"
call :run_group
if errorlevel 1 exit /b 1
exit /b 0

:run_zba_only
set "GROUP_NAME=Zba instructions"
set "TEST_PREFIX=rv32uzba-p"
set "TEST_LIST=%ZBA_INSTS%"
set "RESULT_PREFIX=zba"
call :run_group
if errorlevel 1 goto :fail
echo Zba tests finished!
pause
exit /b 0

:run_zbb_only
set "GROUP_NAME=Zbb implemented instructions"
set "TEST_PREFIX=rv32uzbb-p"
set "TEST_LIST=%ZBB_INSTS%"
set "RESULT_PREFIX=zbb"
call :run_group
if errorlevel 1 goto :fail
echo Zbb tests finished!
pause
exit /b 0

:run_zbkb_only
set "GROUP_NAME=Zbkb instructions"
set "TEST_PREFIX=rv32uzbkb-p"
set "TEST_LIST=%ZBKB_INSTS%"
set "RESULT_PREFIX=zbkb"
call :run_group
if errorlevel 1 goto :fail
echo Zbkb tests finished!
pause
exit /b 0

:run_zbs_only
set "GROUP_NAME=Zbs instructions"
set "TEST_PREFIX=rv32uzbs-p"
set "TEST_LIST=%ZBS_INSTS%"
set "RESULT_PREFIX=zbs"
call :run_group
if errorlevel 1 goto :fail
echo Zbs tests finished!
pause
exit /b 0

:run_group
echo Starting simulation for %GROUP_NAME%...
for %%i in (%TEST_LIST%) do (
    echo.
    echo ====== Simulating %TEST_PREFIX%-%%i ======
    if not exist "hex\riscv-tests\%TEST_PREFIX%-%%i.hex" (
        powershell -Command "Write-Host '[MISSING] %TEST_PREFIX%-%%i.hex' -ForegroundColor Yellow"
        exit /b 1
    )
    copy /Y "hex\riscv-tests\%TEST_PREFIX%-%%i.hex" "hex\riscv-tests\rv32-p-riscv.hex" >nul
    vsim -c -do "run -all; quit -force" tb_cpu_top > "results\%RESULT_PREFIX%_%%i.txt"
    findstr /C:"Test passed." "results\%RESULT_PREFIX%_%%i.txt" >nul
    if errorlevel 1 (
        powershell -Command "Write-Host '[FAILED] %TEST_PREFIX%-%%i' -ForegroundColor Red"
        powershell -Command "Write-Host 'Simulating failed on: %TEST_PREFIX%-%%i' -ForegroundColor Red"
        type "results\%RESULT_PREFIX%_%%i.txt"
        exit /b 1
    ) else (
        powershell -Command "Write-Host '[PASSED] %TEST_PREFIX%-%%i' -ForegroundColor Green"
    )
)
echo.
exit /b 0

:fail
echo.
powershell -Command "Write-Host 'failure detected during simulation.' -ForegroundColor Red"
pause
exit /b 1

:usage
echo Unknown mode: %MODE%
echo Usage: run_all.bat [all^|base^|z^|zba^|zbb^|zbkb^|zbs]
exit /b 1
