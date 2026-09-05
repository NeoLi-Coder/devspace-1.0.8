@echo off
chcp 65001 >nul

setlocal EnableExtensions DisableDelayedExpansion

title DevSpace 管理器 - 公司版 v4



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

    pwsh.exe -NoProfile -Command ^
      "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"

    exit /b
)



set "PWSH=pwsh.exe"

set "MANAGER_DIR=%~dp0"

set "PID_FILE=%MANAGER_DIR%devspace.pid"

set "PROJECT_ROOT=D:\Neo\project"

set "NODE_DIR=D:\AppGallery\Portable\develop\FNM\fnm\node-versions\v24.13.0\installation"

set "NODE=%NODE_DIR%\node.exe"

set "NPM_GLOBAL=D:\AppGallery\Portable\develop\FNM\npm-global"

set "DEVSPACE_CLI=%NPM_GLOBAL%\node_modules\@waishnav\devspace\dist\cli.js"

set "GIT_BASH=D:\AppGallery\Software\Git\bin"

set "DEVSPACE_PORT=7676"

set "CLOUDFLARE_SERVICE=Cloudflared"

set "PUBLIC_MCP=https://work.neoli.cyou/mcp"



:MENU

cls

echo ============================================================
echo                     DevSpace 管理器
echo                     公司版 v4
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
set /p choice=请选择操作：

if "%choice%"=="1" goto START_ALL
if "%choice%"=="2" goto STOP_ALL
if "%choice%"=="3" goto RESTART_ALL
if "%choice%"=="4" goto STATUS
if "%choice%"=="5" goto START_DEVSPACE
if "%choice%"=="6" goto STOP_DEVSPACE
if "%choice%"=="7" goto START_TUNNEL
if "%choice%"=="8" goto STOP_TUNNEL
if "%choice%"=="0" exit /b

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
    echo.
    pause
    goto MENU
)

echo.
echo [2/2] 启动 Cloudflare Tunnel...
call :START_TUNNEL_FUNC

echo.
echo ============================================================
echo 启动流程完成
echo ============================================================
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
echo ============================================================
echo 停止流程完成
echo ============================================================
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
    echo.
    pause
    goto MENU
)

echo.
echo [4/4] 启动 Cloudflare Tunnel...
call :START_TUNNEL_FUNC

echo.
echo ============================================================
echo 重启流程完成
echo ============================================================
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



:STATUS

cls

echo ============================================================
echo                       当前状态
echo ============================================================
echo.



"%PWSH%" -NoProfile -Command ^
  "$c = Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
  "if (-not $c) {" ^
  "    Write-Host '[DevSpace]          未运行' -ForegroundColor DarkGray;" ^
  "    exit;" ^
  "}" ^
  "$pidValue = $c.OwningProcess;" ^
  "$p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $pidValue) -ErrorAction SilentlyContinue;" ^
  "if ($p -and $p.CommandLine -like '*@waishnav\devspace*cli.js*serve*') {" ^
  "    Write-Host '[DevSpace]          运行中' -ForegroundColor Green;" ^
  "    Write-Host ('                    PID: ' + $pidValue);" ^
  "} else {" ^
  "    Write-Host '[DevSpace]          异常' -ForegroundColor Red;" ^
  "    Write-Host ('                    7676 被其他程序占用，PID: ' + $pidValue);" ^
  "}"


echo.



"%PWSH%" -NoProfile -Command ^
  "$s = Get-Service '%CLOUDFLARE_SERVICE%' -ErrorAction SilentlyContinue;" ^
  "if (-not $s) {" ^
  "    Write-Host '[Cloudflare Tunnel] 服务不存在' -ForegroundColor Red;" ^
  "} elseif ($s.Status -eq 'Running') {" ^
  "    Write-Host '[Cloudflare Tunnel] 运行中' -ForegroundColor Green;" ^
  "} else {" ^
  "    Write-Host '[Cloudflare Tunnel] 未运行' -ForegroundColor DarkGray;" ^
  "}"


echo.
echo MCP 地址：
echo %PUBLIC_MCP%
echo.



"%PWSH%" -NoProfile -Command ^
  "try {" ^
  "    $r = Invoke-WebRequest -Uri '%PUBLIC_MCP%' -Method Get -SkipHttpErrorCheck -TimeoutSec 5;" ^
  "    if ($r.StatusCode -eq 401) {" ^
  "        Write-Host '[公网连接]          正常（HTTP 401）' -ForegroundColor Green;" ^
  "    } elseif ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {" ^
  "        Write-Host ('[公网连接]          可访问（HTTP ' + $r.StatusCode + '）') -ForegroundColor Yellow;" ^
  "    } else {" ^
  "        Write-Host ('[公网连接]          异常（HTTP ' + $r.StatusCode + '）') -ForegroundColor Red;" ^
  "    }" ^
  "} catch {" ^
  "    Write-Host '[公网连接]          无法访问' -ForegroundColor Red;" ^
  "    Write-Host ('                    ' + $_.Exception.Message);" ^
  "}"


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



:START_DEVSPACE_FUNC

call :CHECK_DEVSPACE_ENV_FUNC

if errorlevel 1 (
    exit /b 1
)



"%PWSH%" -NoProfile -Command ^
  "$c = Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
  "if (-not $c) { exit 0 };" ^
  "$pidValue = $c.OwningProcess;" ^
  "$p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $pidValue) -ErrorAction SilentlyContinue;" ^
  "if ($p -and $p.CommandLine -like '*@waishnav\devspace*cli.js*serve*') {" ^
  "    Write-Host ('[DevSpace] 已经在运行，PID: ' + $pidValue) -ForegroundColor Yellow;" ^
  "    exit 10;" ^
  "}" ^
  "Write-Host ('[DevSpace] 无法启动：7676 已被其他程序占用，PID: ' + $pidValue) -ForegroundColor Red;" ^
  "exit 11;"

set "CHECK_RC=%errorlevel%"

if "%CHECK_RC%"=="10" (
    exit /b 0
)

if "%CHECK_RC%"=="11" (
    exit /b 1
)



if exist "%PID_FILE%" (
    del /f /q "%PID_FILE%" >nul 2>&1
)



"%PWSH%" -NoProfile -Command ^
  "$env:PATH='%NODE_DIR%;%NPM_GLOBAL%;%GIT_BASH%;' + $env:PATH;" ^
  "$p = Start-Process" ^
  "    -FilePath '%NODE%'" ^
  "    -ArgumentList @('%DEVSPACE_CLI%','serve')" ^
  "    -WorkingDirectory '%PROJECT_ROOT%'" ^
  "    -WindowStyle Hidden" ^
  "    -PassThru;" ^
  "Set-Content -Path '%PID_FILE%' -Value $p.Id -Encoding ascii;" ^
  "Write-Host ('[DevSpace] 正在启动，PID: ' + $p.Id);"


echo [DevSpace] 等待 %DEVSPACE_PORT% 端口...



"%PWSH%" -NoProfile -Command ^
  "for ($i = 0; $i -lt 20; $i++) {" ^
  "    $c = Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
  "    if ($c) {" ^
  "        $pidValue = $c.OwningProcess;" ^
  "        $p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $pidValue) -ErrorAction SilentlyContinue;" ^
  "        if ($p -and $p.CommandLine -like '*@waishnav\devspace*cli.js*serve*') {" ^
  "            exit 0;" ^
  "        }" ^
  "    }" ^
  "    Start-Sleep -Milliseconds 500;" ^
  "}" ^
  "exit 1;"


if errorlevel 1 (
    echo [DevSpace] 启动失败，%DEVSPACE_PORT% 端口未正常监听。

    "%PWSH%" -NoProfile -Command ^
      "if (Test-Path '%PID_FILE%') {" ^
      "    $savedPid = Get-Content '%PID_FILE%' -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
      "    if ($savedPid -match '^\d+$') {" ^
      "        $p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $savedPid) -ErrorAction SilentlyContinue;" ^
      "        if ($p -and $p.CommandLine -like '*@waishnav\devspace*cli.js*serve*') {" ^
      "            Stop-Process -Id ([int]$savedPid) -Force -ErrorAction SilentlyContinue;" ^
      "        }" ^
      "    }" ^
      "    Remove-Item '%PID_FILE%' -Force -ErrorAction SilentlyContinue;" ^
      "}"

    exit /b 1
)


echo [DevSpace] 启动成功。

exit /b 0



:STOP_DEVSPACE_FUNC



if exist "%PID_FILE%" (

    set /p DEVSPACE_PID=<"%PID_FILE%"

    "%PWSH%" -NoProfile -Command ^
      "$savedPid = '%DEVSPACE_PID%';" ^
      "if ($savedPid -notmatch '^\d+$') { exit 1 };" ^
      "$p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $savedPid) -ErrorAction SilentlyContinue;" ^
      "if (-not $p) { exit 1 };" ^
      "if ($p.CommandLine -notlike '*@waishnav\devspace*cli.js*serve*') { exit 2 };" ^
      "exit 0;"

    set "PID_RC=%errorlevel%"

    if "%PID_RC%"=="0" (

        echo [DevSpace] 正在停止 PID %DEVSPACE_PID%...

        taskkill /PID %DEVSPACE_PID% /T /F >nul 2>&1

        if errorlevel 1 (
            echo [DevSpace] 停止失败。
            exit /b 1
        )

        del /f /q "%PID_FILE%" >nul 2>&1

        echo [DevSpace] 已停止。
        exit /b 0
    )

    if "%PID_RC%"=="2" (
        echo [DevSpace] PID %DEVSPACE_PID% 已被其他程序复用，不会执行终止操作。
        del /f /q "%PID_FILE%" >nul 2>&1
    )

    if "%PID_RC%"=="1" (
        echo [DevSpace] PID 文件已失效，正在检查 7676 端口...
        del /f /q "%PID_FILE%" >nul 2>&1
    )
)



"%PWSH%" -NoProfile -Command ^
  "$c = Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
  "if (-not $c) {" ^
  "    Write-Host '[DevSpace] 未运行';" ^
  "    exit 0;" ^
  "}" ^
  "$pidValue = $c.OwningProcess;" ^
  "$p = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $pidValue) -ErrorAction SilentlyContinue;" ^
  "if (-not $p -or $p.CommandLine -notlike '*@waishnav\devspace*cli.js*serve*') {" ^
  "    Write-Host ('[DevSpace] 7676 被其他程序占用，PID: ' + $pidValue) -ForegroundColor Yellow;" ^
  "    Write-Host '[DevSpace] 为避免误杀，不会终止该进程。';" ^
  "    exit 2;" ^
  "}" ^
  "Write-Host ('[DevSpace] 找到 DevSpace 进程，PID: ' + $pidValue);" ^
  "& taskkill.exe /PID $pidValue /T /F | Out-Null;" ^
  "Start-Sleep -Milliseconds 500;" ^
  "$remaining = Get-NetTCPConnection -LocalPort %DEVSPACE_PORT% -State Listen -ErrorAction SilentlyContinue;" ^
  "if ($remaining) {" ^
  "    Write-Host '[DevSpace] 停止失败' -ForegroundColor Red;" ^
  "    exit 1;" ^
  "}" ^
  "Write-Host '[DevSpace] 已停止' -ForegroundColor Green;" ^
  "exit 0;"

exit /b %errorlevel%



:START_TUNNEL_FUNC

"%PWSH%" -NoProfile -Command ^
  "$s = Get-Service '%CLOUDFLARE_SERVICE%' -ErrorAction SilentlyContinue;" ^
  "if (-not $s) {" ^
  "    Write-Host '[Cloudflare] Cloudflared 服务不存在' -ForegroundColor Red;" ^
  "    exit 2;" ^
  "}" ^
  "if ($s.Status -eq 'Running') {" ^
  "    Write-Host '[Cloudflare] 已经在运行' -ForegroundColor Yellow;" ^
  "    exit 0;" ^
  "}" ^
  "try {" ^
  "    Start-Service '%CLOUDFLARE_SERVICE%' -ErrorAction Stop;" ^
  "    $s = Get-Service '%CLOUDFLARE_SERVICE%';" ^
  "    $s.WaitForStatus('Running',[TimeSpan]::FromSeconds(10));" ^
  "    Write-Host '[Cloudflare] 启动成功' -ForegroundColor Green;" ^
  "    exit 0;" ^
  "} catch {" ^
  "    Write-Host '[Cloudflare] 启动失败' -ForegroundColor Red;" ^
  "    Write-Host $_.Exception.Message;" ^
  "    exit 1;" ^
  "}"

exit /b %errorlevel%



:STOP_TUNNEL_FUNC

"%PWSH%" -NoProfile -Command ^
  "$s = Get-Service '%CLOUDFLARE_SERVICE%' -ErrorAction SilentlyContinue;" ^
  "if (-not $s) {" ^
  "    Write-Host '[Cloudflare] Cloudflared 服务不存在' -ForegroundColor Red;" ^
  "    exit 2;" ^
  "}" ^
  "if ($s.Status -eq 'Stopped') {" ^
  "    Write-Host '[Cloudflare] 已经停止';" ^
  "    exit 0;" ^
  "}" ^
  "Write-Host '[Cloudflare] 正在停止...';" ^
  "& sc.exe stop '%CLOUDFLARE_SERVICE%' | Out-Null;" ^
  "$stopped = $false;" ^
  "for ($i = 0; $i -lt 20; $i++) {" ^
  "    Start-Sleep -Milliseconds 500;" ^
  "    $s = Get-Service '%CLOUDFLARE_SERVICE%' -ErrorAction SilentlyContinue;" ^
  "    if ($s.Status -eq 'Stopped') {" ^
  "        $stopped = $true;" ^
  "        break;" ^
  "    }" ^
  "}" ^
  "if ($stopped) {" ^
  "    Write-Host '[Cloudflare] 已停止' -ForegroundColor Green;" ^
  "    exit 0;" ^
  "}" ^
  "Write-Host '[Cloudflare] 正常停止超时，正在结束 Cloudflared 服务进程...' -ForegroundColor Yellow;" ^
  "$svc = Get-CimInstance Win32_Service -Filter ""Name='%CLOUDFLARE_SERVICE%'"" -ErrorAction SilentlyContinue;" ^
  "if ($svc -and $svc.ProcessId -gt 0) {" ^
  "    Stop-Process -Id $svc.ProcessId -Force -ErrorAction SilentlyContinue;" ^
  "    Start-Sleep -Seconds 1;" ^
  "}" ^
  "$s = Get-Service '%CLOUDFLARE_SERVICE%' -ErrorAction SilentlyContinue;" ^
  "if ($s.Status -eq 'Stopped') {" ^
  "    Write-Host '[Cloudflare] 已停止' -ForegroundColor Green;" ^
  "    exit 0;" ^
  "}" ^
  "Write-Host '[Cloudflare] 停止失败' -ForegroundColor Red;" ^
  "exit 1;"

exit /b %errorlevel%
