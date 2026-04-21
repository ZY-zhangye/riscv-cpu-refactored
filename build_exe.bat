@echo off
setlocal

REM 进入仓库根目录（本脚本所在目录）
cd /d "%~dp0"

REM 本机要求用 py 启动器，而不是 python 命令
where py >nul 2>nul
if errorlevel 1 (
    echo [ERROR] 未找到 py 启动器，请先安装 Python 并勾选 py launcher。
    exit /b 1
)

REM 安装/升级打包器
echo Installing/Updating PyInstaller...
py -m pip install --upgrade pyinstaller
if errorlevel 1 (
    echo [ERROR] PyInstaller 安装失败。
    exit /b 1
)

REM 打包入口：run_all.py
REM --onefile: 单文件 EXE
REM --name run_all: 输出名为 run_all.exe
echo Building EXE...
py -m PyInstaller --noconfirm --clean --onefile --name run_all run_all.py
if errorlevel 1 (
    echo [ERROR] 打包失败。
    exit /b 1
)

echo.
echo [OK] 打包完成：dist\run_all.exe
exit /b 0
