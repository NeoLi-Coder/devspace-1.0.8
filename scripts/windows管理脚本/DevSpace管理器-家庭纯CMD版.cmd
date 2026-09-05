@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title DevSpace 管理器 - 家庭版

where.exe pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo [错误] 未找到 PowerShell 7 ^(pwsh.exe^)
    echo 请先安装 PowerShell 7，并确保 pwsh.exe 已加入 PATH。
    echo.
    pause
    exit /b 1
)

fltmc >nul 2>&1
if errorlevel 1 (
    echo 正在请求管理员权限...
    pwsh.exe -NoProfile -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"
    exit /b 0
)

set "PWSH=pwsh.exe"

rem ============================================================
rem 家庭环境配置
rem ============================================================
set "MANAGER_DIR=%~dp0"
set "PID_FILE=%MANAGER_DIR%devspace-home.pid"

if defined DEVSPACE_CONFIG_DIR (
    set "DEVSPACE_DIR=%DEVSPACE_CONFIG_DIR%"
) else (
    set "DEVSPACE_DIR=%USERPROFILE%\.devspace"
)
set "CONFIG_FILE=%DEVSPACE_DIR%\config.json"
set "AUTH_FILE=%DEVSPACE_DIR%\auth.json"

set "NODE_DIR=D:\Program\Portable\devtools\FNM\fnm\aliases\default"
set "NODE=%NODE_DIR%\node.exe"
set "NPM_GLOBAL=D:\Program\Portable\devtools\FNM\npm-global"
set "DEVSPACE_CLI=%NPM_GLOBAL%\node_modules\@waishnav\devspace\dist\cli.js"
set "GIT_BASH=D:\Program\Portable\devtools\PortableGit\bin"
set "PATH=%SystemRoot%\System32;%SystemRoot%;%NODE_DIR%;%NPM_GLOBAL%;%GIT_BASH%;%PATH%"

set "CLOUDFLARE_SERVICE=Cloudflared"
set "WORKING_DIR=%USERPROFILE%"
set "DEVSPACE_PORT=7676"
set "PUBLIC_MCP=https://home.neoli.cyou/mcp"

:MENU
cls
echo ============================================================
echo                  DevSpace 管理器 - 家庭版
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
echo   [9] 查看 DevSpace Owner 密码
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
if "%choice%"=="9" goto SHOW_PASSWORD
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
echo [配置文件] %CONFIG_FILE%
call :SHOW_ALLOWED_ROOTS_FUNC
echo.
call :CHECK_DEVSPACE_FUNC
echo.
call :CHECK_TUNNEL_FUNC
echo.
echo [MCP 地址] %PUBLIC_MCP%
call :CHECK_PUBLIC_MCP_FUNC
echo.
pause
goto MENU

:SHOW_PASSWORD
cls
echo ============================================================
echo                  DevSpace Owner 密码
echo ============================================================
echo.
call :SHOW_PASSWORD_FUNC
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

:SHOW_ALLOWED_ROOTS_FUNC
if not exist "%CONFIG_FILE%" (
    echo [Allowed Roots] 配置文件不存在
    exit /b 1
)
"%PWSH%" -NoProfile -Command "$c = Get-Content -Raw -LiteralPath $env:CONFIG_FILE | ConvertFrom-Json; if ($c.allowedRoots -and $c.allowedRoots.Count -gt 0) { Write-Host '[Allowed Roots]'; $c.allowedRoots | ForEach-Object { Write-Host ('  ' + $_) } } else { Write-Host '[Allowed Roots] 未配置' -ForegroundColor Yellow }"
exit /b %errorlevel%

:SHOW_PASSWORD_FUNC
if not exist "%AUTH_FILE%" (
    echo [DevSpace] 认证文件不存在：
    echo %AUTH_FILE%
    exit /b 1
)
"%PWSH%" -NoProfile -Command "$a = Get-Content -Raw -LiteralPath '%AUTH_FILE%' | ConvertFrom-Json; if ($a.ownerToken) { Write-Host ('Owner password: ' + $a.ownerToken) } else { Write-Host '[DevSpace] auth.json 中不存在 ownerToken。' -ForegroundColor Red; exit 1 }"
exit /b %errorlevel%

:CHECK_DEVSPACE_ENV_FUNC
if not exist "%CONFIG_FILE%" (
    echo [DevSpace] 配置文件不存在：
    echo %CONFIG_FILE%
    exit /b 1
)
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
if not exist "%GIT_BASH%\bash.exe" (
    echo [DevSpace] Git Bash 不存在：
    echo %GIT_BASH%\bash.exe
    exit /b 1
)
exit /b 0

:GET_DEVSPACE_PID_FUNC
set "PID="
for /f "delims=" %%a in ('"%PWSH%" -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue ^| Select-Object -First 1; if ($c) { $c.OwningProcess }" 2^>nul') do if not defined PID set "PID=%%a"
exit /b 0

:CHECK_NODE_PROCESS_FUNC
if exist "%PID_FILE%" (
    set "MANAGED_PID="
    set /p "MANAGED_PID="<"%PID_FILE%"
    if "!MANAGED_PID!"=="!PID!" exit /b 0
)

"%PWSH%" -NoProfile -Command "$p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + !PID!) -ErrorAction SilentlyContinue; if ($p -and $p.CommandLine -like '*@waishnav\devspace*cli.js*serve*') { exit 0 }; exit 1"
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
if errorlevel 2 (
    echo [DevSpace] %DEVSPACE_PORT% 已被其他程序占用，未执行启动。
    exit /b 1
)

if exist "%PID_FILE%" del /f /q "%PID_FILE%" >nul 2>&1

"%PWSH%" -NoProfile -Command "$p = Start-Process -FilePath '%NODE%' -ArgumentList @('%DEVSPACE_CLI%','serve') -WorkingDirectory '%WORKING_DIR%' -WindowStyle Hidden -PassThru; Write-Host ('[DevSpace] 正在启动，进程 PID: ' + $p.Id)"

echo [DevSpace] 等待 %DEVSPACE_PORT% 端口...
for /l %%i in (1,1,10) do (
    timeout /t 1 /nobreak >nul
    call :GET_DEVSPACE_PID_FUNC
    if defined PID goto DEVSPACE_STARTED
)

echo [DevSpace] 启动失败，%DEVSPACE_PORT% 端口未正常监听。
exit /b 1

:DEVSPACE_STARTED
call :CHECK_NODE_PROCESS_FUNC
if errorlevel 1 (
    echo [DevSpace] 启动后发现 %DEVSPACE_PORT% 监听进程不是 DevSpace，PID: !PID!
    exit /b 1
)
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
    echo [DevSpace] 停止失败。
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
    echo [Cloudflare] 启动失败。
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
    echo [Cloudflare] 停止失败。
    exit /b 1
)
call :CHECK_TUNNEL_FUNC >nul
if not errorlevel 1 (
    echo [Cloudflare] 停止命令已返回，但服务仍在运行。
    exit /b 1
)
echo [Cloudflare] 已停止
exit /b 0

:CHECK_PUBLIC_MCP_FUNC
"%PWSH%" -NoProfile -Command "try { $r = Invoke-WebRequest -Uri '%PUBLIC_MCP%' -Method Get -SkipHttpErrorCheck -TimeoutSec 5; if ($r.StatusCode -eq 401) { Write-Host '[公网连接] 正常（HTTP 401）' -ForegroundColor Green; exit 0 }; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { Write-Host ('[公网连接] 可访问（HTTP ' + $r.StatusCode + '）') -ForegroundColor Yellow; exit 0 }; Write-Host ('[公网连接] 异常（HTTP ' + $r.StatusCode + '）') -ForegroundColor Red; exit 1 } catch { Write-Host '[公网连接] 无法访问' -ForegroundColor Red; Write-Host ('           ' + $_.Exception.Message); exit 1 }"
exit /b %errorlevel%
