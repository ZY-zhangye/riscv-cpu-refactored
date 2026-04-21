@echo off
setlocal

REM 脚本所在目录（保证从任意位置双击/调用都能正确定位）
set SCRIPT_DIR=%~dp0
REM 优先使用打包后的 EXE
set EXE_PATH=%SCRIPT_DIR%dist\run_all.exe

REM 1) 如果有 EXE，优先跑 EXE
REM 2) 没有 EXE，则回退到 py + run_all.py
if exist "%EXE_PATH%" (
    "%EXE_PATH%" %*
) else (
    py "%SCRIPT_DIR%run_all.py" %*
)

REM 透传退出码，便于 CI/脚本判断成功失败
exit /b %errorlevel%
