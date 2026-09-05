@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

where.exe pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 PowerShell 7（pwsh.exe）。
    pause
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set /a SCRIPT_COUNT=0
for %%F in ("%SCRIPT_DIR%*.ps1") do if exist "%%~fF" (
    set /a SCRIPT_COUNT+=1
    set "SCRIPT_!SCRIPT_COUNT!=%%~fF"
    set "SCRIPT_NAME_!SCRIPT_COUNT!=%%~nxF"
)

if !SCRIPT_COUNT! EQU 0 (
    echo [错误] 未找到同级 PowerShell 脚本：
    echo %SCRIPT_DIR%*.ps1
    pause
    exit /b 1
)

if !SCRIPT_COUNT! EQU 1 (
    set "SCRIPT=!SCRIPT_1!"
) else (
    echo 找到 !SCRIPT_COUNT! 个 PowerShell 脚本，请选择：
    echo.
    for /l %%I in (1,1,!SCRIPT_COUNT!) do echo   [%%I] !SCRIPT_NAME_%%I!
    echo.
    set "CHOICE="
    set /p "CHOICE=请选择脚本："
    if not defined SCRIPT_!CHOICE! (
        echo [错误] 无效选择。
        pause
        exit /b 1
    )
    for %%I in (!CHOICE!) do set "SCRIPT=!SCRIPT_%%I!"
)

echo [启动] !SCRIPT!
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!"
if errorlevel 1 (
    echo.
    echo [错误] PowerShell 脚本执行失败，退出码：%errorlevel%
    pause
)
endlocal
