@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title DevSpace 管理器 - 家庭版

where.exe pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo [错误] 未找到 PowerShell 7 pwsh.exe
    echo 请先安装 PowerShell 7，并确保 pwsh.exe 已加入 PATH。
    echo.
    pause
    exit /b 1
)

fltmc >nul 2>&1
if errorlevel 1 (
    echo 正在请求管理员权限...
    pwsh.exe -NoProfile -Command ^
      "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"
    exit /b 0
)

set "PWSH=pwsh.exe"

rem ============================================================
rem 环境配置
rem ============================================================

set "MANAGER_DIR=%~dp0"
set "PID_FILE=%MANAGER_DIR%devspace.pid"

set "PROJECT_ROOT=D:\code"
set "NODE_DIR=D:\Program\Portable\devtools\FNM\fnm\aliases\default"
set "NODE=%NODE_DIR%\node.exe"
set "NPM_GLOBAL=D:\Program\Portable\devtools\FNM\npm-global"
set "DEVSPACE_CLI=%NPM_GLOBAL%\node_modules\@waishnav\devspace\dist\cli.js"
set "GIT_BASH=D:\Program\Portable\devtools\PortableGit\bin"
set "PATH=%SystemRoot%\System32;%SystemRoot%;%NODE_DIR%;%NPM_GLOBAL%;%GIT_BASH%;%PATH%"

set "DEVSPACE_PORT=7676"
set "CLOUDFLARE_SERVICE=Cloudflared"
set "PUBLIC_MCP=https://home.neoli.cyou/mcp"

:MENU
cls
echo ============================================================
echo(                DevSpace 管理器 家庭版 纯 CMD
echo ============================================================
echo.
echo   [1] 启动全部
echo   [2] 停止全部
echo   [3] 重启全部
echo   [4] 查看状态
echo.
echo   [5] 启动 DevSpace
echo   [6] 停止 DevSpace
echo   [7] 启动 Cloudflare Tunnel
echo   [8] 停止 Cloudflare Tunnel
echo.
echo   [0] 退出
echo.

set "choice="
set /p "choice=请选择操作："

if "%choice%"=="1" goto START_ALL
if "%choice%"=="2" goto STOP_ALL
if "%choice%"=="3" goto RESTART_ALL
if "%choice%"=="4" goto STATUS
if "%choice%"=="5" goto START_DEVSPACE
if "%choice%"=="6" goto STOP_DEVSPACE
if "%choice%"=="7" goto START_TUNNEL
if "%choice%"=="8" goto STOP_TUNNEL
if "%choice%"=="0" exit /b 0

echo.
echo 无效选项。
timeout /t 1 /nobreak >nul
goto MENU

:START_ALL
cls
echo [1/2] 启动 DevSpace...
call :START_DEVSPACE_FUNC
if errorlevel 1 (
    echo.
    echo [错误] DevSpace 未正常启动，已取消启动 Cloudflare Tunnel。
    pause
    goto MENU
)
echo.
echo [2/2] 启动 Cloudflare Tunnel...
call :START_TUNNEL_FUNC
echo.
pause
goto MENU

:STOP_ALL
cls
echo [1/2] 停止 Cloudflare Tunnel...
call :STOP_TUNNEL_FUNC
echo.
echo [2/2] 停止 DevSpace...
call :STOP_DEVSPACE_FUNC
echo.
pause
goto MENU

:RESTART_ALL
cls
echo [1/4] 停止 Cloudflare Tunnel...
call :STOP_TUNNEL_FUNC
echo.
echo [2/4] 停止 DevSpace...
call :STOP_DEVSPACE_FUNC
timeout /t 2 /nobreak >nul
echo.
echo [3/4] 启动 DevSpace...
call :START_DEVSPACE_FUNC
if errorlevel 1 (
    echo.
    echo [错误] DevSpace 未正常启动，已取消启动 Cloudflare Tunnel。
    pause
    goto MENU
)
echo.
echo [4/4] 启动 Cloudflare Tunnel...
call :START_TUNNEL_FUNC
echo.
pause
goto MENU

:STATUS
cls
echo ============================================================
echo                       当前状态
echo ============================================================
echo.
call :CHECK_DEVSPACE_FUNC
echo.
call :CHECK_TUNNEL_FUNC
echo.
echo MCP 地址：
echo %PUBLIC_MCP%
echo.
pause
goto MENU

:START_DEVSPACE
cls
call :START_DEVSPACE_FUNC
echo.
pause
goto MENU

:STOP_DEVSPACE
cls
call :STOP_DEVSPACE_FUNC
echo.
pause
goto MENU

:START_TUNNEL
cls
call :START_TUNNEL_FUNC
echo.
pause
goto MENU

:STOP_TUNNEL
cls
call :STOP_TUNNEL_FUNC
echo.
pause
goto MENU

:CHECK_DEVSPACE_ENV_FUNC
if not exist "%NODE%" (
    echo [DevSpace] Node 不存在：
    echo %NODE%
    exit /b 1
)
if not exist "%DEVSPACE_CLI%" (
    echo [DevSpace] DevSpace CLI 不存在：
    echo %DEVSPACE_CLI%
    exit /b 1
)
if not exist "%PROJECT_ROOT%\" (
    echo [DevSpace] 项目目录不存在：
    echo %PROJECT_ROOT%
    exit /b 1
)
if not exist "%GIT_BASH%\bash.exe" (
    echo [DevSpace] Git Bash 不存在：
    echo %GIT_BASH%\bash.exe
    exit /b 1
)
exit /b 0

:GET_DEVSPACE_PID_FUNC
set "PID="
for /f "delims=" %%a in ('%PWSH% -NoProfile -Command "$c = @(Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue)[0]; $c.OwningProcess" 2^>nul') do if not defined PID set "PID=%%a"
exit /b 0

:CHECK_NODE_PROCESS_FUNC
rem 已由本脚本启动的实例以 PID 文件为准，避免 Win32_Process.CommandLine 在受限上下文中不可读。
if exist "%PID_FILE%" (
    set "MANAGED_PID="
    set /p "MANAGED_PID="<"%PID_FILE%"
    if "!MANAGED_PID!"=="%PID%" exit /b 0
)

"%PWSH%" -NoProfile -Command ^
  "$p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + %PID%) -ErrorAction SilentlyContinue;" ^
  "if ($p -and $p.CommandLine -like '*@waishnav\devspace*cli.js*serve*') { exit 0 };" ^
  "exit 1;"
if errorlevel 1 exit /b 1
exit /b 0

:CHECK_DEVSPACE_FUNC
call :GET_DEVSPACE_PID_FUNC
if not defined PID (
    echo [DevSpace] 未运行
    exit /b 1
)
call :CHECK_NODE_PROCESS_FUNC
if errorlevel 1 (
    echo [DevSpace] %DEVSPACE_PORT% 被其他程序占用，PID: !PID!
    exit /b 2
)
echo [DevSpace] 运行中，PID: !PID!
exit /b 0

:START_DEVSPACE_FUNC
call :CHECK_DEVSPACE_ENV_FUNC
if errorlevel 1 exit /b 1

call :CHECK_DEVSPACE_FUNC >nul
if not errorlevel 1 (
    echo [DevSpace] 已经在运行，PID: !PID!
    exit /b 0
)
if errorlevel 2 exit /b 1

if exist "%PID_FILE%" del /f /q "%PID_FILE%" >nul 2>&1

"%PWSH%" -NoProfile -Command "$p = Start-Process -FilePath '%NODE%' -ArgumentList @('%DEVSPACE_CLI%','serve') -WorkingDirectory '%PROJECT_ROOT%' -WindowStyle Hidden -PassThru; Write-Host ('[DevSpace] 正在启动，PID: ' + $p.Id);"

echo [DevSpace] 等待 %DEVSPACE_PORT% 端口...
for /l %%i in (1,1,10) do (
    timeout /t 1 /nobreak >nul
    call :GET_DEVSPACE_PID_FUNC
    if defined PID goto DEVSPACE_STARTED
)

echo [DevSpace] 启动失败，%DEVSPACE_PORT% 端口未正常监听。
exit /b 1

:DEVSPACE_STARTED
>"%PID_FILE%" echo(!PID!
echo [DevSpace] 启动成功，PID: !PID!
exit /b 0

:STOP_DEVSPACE_FUNC
set "FILE_PID="
if exist "%PID_FILE%" set /p "FILE_PID="<"%PID_FILE%"

call :GET_DEVSPACE_PID_FUNC
if not defined PID (
    if exist "%PID_FILE%" del /f /q "%PID_FILE%" >nul 2>&1
    echo [DevSpace] 未运行
    exit /b 0
)

call :CHECK_NODE_PROCESS_FUNC
if errorlevel 1 (
    echo [DevSpace] %DEVSPACE_PORT% 被其他程序占用，未执行终止操作。
    if exist "%PID_FILE%" del /f /q "%PID_FILE%" >nul 2>&1
    exit /b 2
)

if defined FILE_PID if not "!FILE_PID!"=="!PID!" echo [DevSpace] PID 文件已过期，按当前端口进程处理。
echo [DevSpace] 正在停止 PID !PID!...
taskkill /PID !PID! /T /F >nul 2>&1
if errorlevel 1 (
    echo [DevSpace] 停止失败，可能需要管理员权限。
    exit /b 1
)

for /l %%i in (1,1,5) do (
    timeout /t 1 /nobreak >nul
    call :GET_DEVSPACE_PID_FUNC
    if not defined PID (
        if exist "%PID_FILE%" del /f /q "%PID_FILE%" >nul 2>&1
        echo [DevSpace] 已停止
        exit /b 0
    )
)

echo [DevSpace] 停止失败，%DEVSPACE_PORT% 仍在监听。
exit /b 1

:CHECK_TUNNEL_FUNC
sc query "%CLOUDFLARE_SERVICE%" >nul 2>&1
if errorlevel 1 (
    echo [Cloudflare Tunnel] 服务不存在
    exit /b 2
)
sc query "%CLOUDFLARE_SERVICE%" | findstr /I "RUNNING" >nul
if not errorlevel 1 (
    echo [Cloudflare Tunnel] 运行中
    exit /b 0
)
echo [Cloudflare Tunnel] 未运行
exit /b 1

:START_TUNNEL_FUNC
sc query "%CLOUDFLARE_SERVICE%" >nul 2>&1
if errorlevel 1 (
    echo [Cloudflare] Cloudflared 服务不存在
    exit /b 2
)
call :CHECK_TUNNEL_FUNC >nul
if not errorlevel 1 (
    echo [Cloudflare] 已经在运行
    exit /b 0
)
net start "%CLOUDFLARE_SERVICE%" >nul 2>&1
if errorlevel 1 (
    echo [Cloudflare] 启动失败，可能需要管理员权限。
    exit /b 1
)
call :CHECK_TUNNEL_FUNC >nul
if errorlevel 1 (
    echo [Cloudflare] 启动命令已返回，但服务未进入运行状态。
    exit /b 1
)
echo [Cloudflare] 启动成功
exit /b 0

:STOP_TUNNEL_FUNC
sc query "%CLOUDFLARE_SERVICE%" >nul 2>&1
if errorlevel 1 (
    echo [Cloudflare] Cloudflared 服务不存在
    exit /b 2
)
call :CHECK_TUNNEL_FUNC >nul
if errorlevel 1 (
    echo [Cloudflare] 已经停止
    exit /b 0
)
net stop "%CLOUDFLARE_SERVICE%" >nul 2>&1
if errorlevel 1 (
    echo [Cloudflare] 停止失败，可能需要管理员权限。
    exit /b 1
)
call :CHECK_TUNNEL_FUNC >nul
if not errorlevel 1 (
    echo [Cloudflare] 停止命令已返回，但服务仍在运行。
    exit /b 1
)
echo [Cloudflare] 已停止
exit /b 0
