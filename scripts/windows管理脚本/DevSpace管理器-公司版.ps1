$ErrorActionPreference = 'Stop'

$edition = '公司版'
$logPrefix = 'devspace-work'

# 显式环境配置。留空时使用系统环境变量 NODE_DIR、NPM_GLOBAL 或 NPM_CONFIG_PREFIX、GIT_BASH。
$configuredNodeDirectory = 'D:\AppGallery\Portable\develop\FNM\fnm\node-versions\v24.13.0\installation'
$configuredNpmGlobal = 'D:\AppGallery\Portable\develop\FNM\npm-global'
$configuredGitBashDirectory = 'D:\AppGallery\Software\Git\bin'

function Start-ManagerProcess {
    param([switch]$Elevated)

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Host '[错误] 未找到 PowerShell 7（pwsh.exe）。' -ForegroundColor Red
        Read-Host '按 Enter 键退出'
        exit 1
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Elevated) {
        Start-Process -FilePath $pwsh.Source -ArgumentList $arguments -Verb RunAs
    } else {
        Start-Process -FilePath $pwsh.Source -ArgumentList $arguments
    }
    exit
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Start-ManagerProcess
}

$isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdministrator) {
    try {
        Write-Host '正在请求管理员权限...'
        Start-ManagerProcess -Elevated
    } catch {
        Write-Host "[错误] 无法获取管理员权限：$($_.Exception.Message)" -ForegroundColor Red
        Read-Host '按 Enter 键退出'
        exit 1
    }
}

[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
try { $Host.UI.RawUI.WindowTitle = "DevSpace 管理器 - $edition" } catch {}

$managerDirectory = $PSScriptRoot
$devspaceDirectory = if ($env:DEVSPACE_CONFIG_DIR) { $env:DEVSPACE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.devspace' }
$configFile = Join-Path $devspaceDirectory 'config.json'
$authFile = Join-Path $devspaceDirectory 'auth.json'
$nodeDirectory = if ($configuredNodeDirectory) { $configuredNodeDirectory } else { $env:NODE_DIR }
$nodePath = if ($nodeDirectory) { Join-Path $nodeDirectory 'node.exe' } else { $null }
$npmGlobal = if ($configuredNpmGlobal) { $configuredNpmGlobal } elseif ($env:NPM_GLOBAL) { $env:NPM_GLOBAL } else { $env:NPM_CONFIG_PREFIX }
$devspaceCli = if ($npmGlobal) { Join-Path $npmGlobal 'node_modules\@waishnav\devspace\dist\cli.js' } else { $null }
$gitBashPath = if ($configuredGitBashDirectory) { $configuredGitBashDirectory } else { $env:GIT_BASH }
$gitBashDirectory = if ($gitBashPath -and [IO.Path]::GetExtension($gitBashPath) -eq '.exe') { Split-Path -Parent $gitBashPath } else { $gitBashPath }
$cloudflareService = 'Cloudflared'
$workingDirectory = $env:USERPROFILE
$outputLog = Join-Path $managerDirectory "$logPrefix.log"
$errorLog = Join-Path $managerDirectory "$logPrefix-error.log"
$env:PATH = (@($nodeDirectory, $npmGlobal, $gitBashDirectory, $env:PATH) | Where-Object { $_ }) -join ';'

function Get-DevSpaceSettings {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        throw "配置文件不存在：$configFile"
    }

    $config = Get-Content -Raw -LiteralPath $configFile | ConvertFrom-Json
    $portValue = if ($env:PORT) { $env:PORT } elseif ($null -ne $config.port) { $config.port } else { 7676 }
    $port = 0
    if (-not [int]::TryParse([string]$portValue, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw "端口配置无效：$portValue"
    }

    $publicBaseUrl = if ($env:DEVSPACE_PUBLIC_BASE_URL) { $env:DEVSPACE_PUBLIC_BASE_URL } else { $config.publicBaseUrl }
    [pscustomobject]@{
        Port          = $port
        PublicMcp     = if ($publicBaseUrl) { "$($publicBaseUrl.TrimEnd('/'))/mcp" } else { "http://127.0.0.1:$port/mcp" }
        AllowedRoots  = @($config.allowedRoots)
    }
}

function Test-DevSpaceEnvironment {
    try {
        $settings = Get-DevSpaceSettings
    } catch {
        Write-Host "[DevSpace] $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }

    foreach ($item in @(
        @{ Name = 'Node'; Path = $nodePath; RequiredEnvironment = '脚本开头的 $configuredNodeDirectory 或 NODE_DIR' },
        @{ Name = 'DevSpace CLI'; Path = $devspaceCli; RequiredEnvironment = '脚本开头的 $configuredNpmGlobal、NPM_GLOBAL 或 NPM_CONFIG_PREFIX' },
        @{ Name = 'Git Bash'; Path = if ($gitBashDirectory) { Join-Path $gitBashDirectory 'bash.exe' } else { $null }; RequiredEnvironment = '脚本开头的 $configuredGitBashDirectory 或 GIT_BASH' }
    )) {
        if (-not $item.Path) {
            Write-Host "[DevSpace] $($item.Name) 未配置，请设置环境变量：$($item.RequiredEnvironment)" -ForegroundColor Red
            return $null
        }
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
            Write-Host "[DevSpace] $($item.Name) 不存在：$($item.Path)" -ForegroundColor Red
            return $null
        }
    }

    return $settings
}

function Get-ListenerProcessId {
    param([int]$Port)

    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($connection) { return [int]$connection.OwningProcess }
    return $null
}

function Test-DevSpaceHealth {
    param([int]$Port)

    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/healthz" -TimeoutSec 2
        return $health.ok -eq $true -and $health.name -eq 'devspace'
    } catch {
        return $false
    }
}

function Get-DevSpaceState {
    param([int]$Port)

    $listenerProcessId = Get-ListenerProcessId -Port $Port
    if ($null -eq $listenerProcessId) {
        return [pscustomobject]@{ Status = 'Stopped'; ProcessId = $null }
    }
    if (Test-DevSpaceHealth -Port $Port) {
        return [pscustomobject]@{ Status = 'Running'; ProcessId = $listenerProcessId }
    }
    return [pscustomobject]@{ Status = 'Occupied'; ProcessId = $listenerProcessId }
}

function Show-StartupLogs {
    foreach ($log in @($errorLog, $outputLog)) {
        if ((Test-Path -LiteralPath $log -PathType Leaf) -and (Get-Item -LiteralPath $log).Length -gt 0) {
            Write-Host "--- $(Split-Path -Leaf $log) ---" -ForegroundColor Yellow
            Get-Content -LiteralPath $log -Tail 30
        }
    }
}

function Start-DevSpace {
    $settings = Test-DevSpaceEnvironment
    if ($null -eq $settings) { return $false }

    $state = Get-DevSpaceState -Port $settings.Port
    if ($state.Status -eq 'Running') {
        Write-Host "[DevSpace] 已经在运行，PID: $($state.ProcessId)" -ForegroundColor Yellow
        return $true
    }
    if ($state.Status -eq 'Occupied') {
        Write-Host "[DevSpace] $($settings.Port) 端口已被其他程序占用，PID: $($state.ProcessId)" -ForegroundColor Red
        return $false
    }

    Remove-Item -LiteralPath $outputLog, $errorLog -Force -ErrorAction SilentlyContinue
    try {
        $process = Start-Process -FilePath $nodePath -ArgumentList @($devspaceCli, 'serve') `
            -WorkingDirectory $workingDirectory -WindowStyle Hidden `
            -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog -PassThru
    } catch {
        Write-Host "[DevSpace] 启动命令执行失败：$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    Write-Host "[DevSpace] 正在启动，进程 PID: $($process.Id)"
    Write-Host "[DevSpace] 等待 $($settings.Port) 端口..."
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-DevSpaceHealth -Port $settings.Port) {
            $listenerProcessId = Get-ListenerProcessId -Port $settings.Port
            Write-Host "[DevSpace] 启动成功，PID: $listenerProcessId" -ForegroundColor Green
            return $true
        }
        if ($process.HasExited) { break }
    }

    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[DevSpace] 启动失败，健康检查未通过。" -ForegroundColor Red
    Show-StartupLogs
    return $false
}

function Stop-DevSpace {
    $settings = Test-DevSpaceEnvironment
    if ($null -eq $settings) { return $false }

    $state = Get-DevSpaceState -Port $settings.Port
    if ($state.Status -eq 'Stopped') {
        Write-Host '[DevSpace] 未运行'
        return $true
    }
    if ($state.Status -eq 'Occupied') {
        Write-Host "[DevSpace] $($settings.Port) 端口被其他程序占用，未执行终止操作。PID: $($state.ProcessId)" -ForegroundColor Yellow
        return $false
    }

    Write-Host "[DevSpace] 正在停止 PID $($state.ProcessId)..."
    & taskkill.exe /PID $state.ProcessId /T /F *> $null
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        Start-Sleep -Milliseconds 500
        if ($null -eq (Get-ListenerProcessId -Port $settings.Port)) {
            Write-Host '[DevSpace] 已停止' -ForegroundColor Green
            return $true
        }
    }

    Write-Host "[DevSpace] 停止失败，$($settings.Port) 仍在监听。" -ForegroundColor Red
    return $false
}

function Get-TunnelService {
    Get-Service -Name $cloudflareService -ErrorAction SilentlyContinue
}

function Start-Tunnel {
    $service = Get-TunnelService
    if (-not $service) {
        Write-Host '[Cloudflare] Cloudflared 服务不存在' -ForegroundColor Red
        return $false
    }
    if ($service.Status -eq 'Running') {
        Write-Host '[Cloudflare] 已经在运行' -ForegroundColor Yellow
        return $true
    }

    try {
        Start-Service -Name $cloudflareService
        (Get-TunnelService).WaitForStatus('Running', [TimeSpan]::FromSeconds(10))
        Write-Host '[Cloudflare] 启动成功' -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[Cloudflare] 启动失败：$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Stop-Tunnel {
    $service = Get-TunnelService
    if (-not $service) {
        Write-Host '[Cloudflare] Cloudflared 服务不存在' -ForegroundColor Red
        return $false
    }
    if ($service.Status -eq 'Stopped') {
        Write-Host '[Cloudflare] 已经停止'
        return $true
    }

    try {
        Stop-Service -Name $cloudflareService
        (Get-TunnelService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(10))
        Write-Host '[Cloudflare] 已停止' -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[Cloudflare] 停止失败：$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-Status {
    Write-Host '============================================================'
    Write-Host '                       当前状态'
    Write-Host '============================================================'
    Write-Host
    Write-Host "[配置文件] $configFile"

    try {
        $settings = Get-DevSpaceSettings
        Write-Host '[Allowed Roots]'
        if ($settings.AllowedRoots.Count -eq 0) {
            Write-Host '  未配置' -ForegroundColor Yellow
        } else {
            $settings.AllowedRoots | ForEach-Object { Write-Host "  $_" }
        }

        Write-Host
        $state = Get-DevSpaceState -Port $settings.Port
        switch ($state.Status) {
            'Running' { Write-Host "[DevSpace] 运行中，PID: $($state.ProcessId)" -ForegroundColor Green }
            'Occupied' { Write-Host "[DevSpace] $($settings.Port) 被其他程序占用，PID: $($state.ProcessId)" -ForegroundColor Red }
            default { Write-Host '[DevSpace] 未运行' }
        }

        Write-Host
        Write-Host "[MCP 地址] $($settings.PublicMcp)"
        try {
            $response = Invoke-WebRequest -Uri $settings.PublicMcp -Method Get -SkipHttpErrorCheck -TimeoutSec 5
            if ($response.StatusCode -eq 401) {
                Write-Host '[公网连接] 正常（HTTP 401）' -ForegroundColor Green
            } elseif ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                Write-Host "[公网连接] 可访问（HTTP $($response.StatusCode)）" -ForegroundColor Yellow
            } else {
                Write-Host "[公网连接] 异常（HTTP $($response.StatusCode)）" -ForegroundColor Red
            }
        } catch {
            Write-Host "[公网连接] 无法访问：$($_.Exception.Message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "[DevSpace] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host
    $service = Get-TunnelService
    if (-not $service) {
        Write-Host '[Cloudflare Tunnel] 服务不存在' -ForegroundColor Red
    } elseif ($service.Status -eq 'Running') {
        Write-Host '[Cloudflare Tunnel] 运行中' -ForegroundColor Green
    } else {
        Write-Host "[Cloudflare Tunnel] $($service.Status)"
    }
}

function Show-OwnerPassword {
    if (-not (Test-Path -LiteralPath $authFile -PathType Leaf)) {
        Write-Host "[DevSpace] 认证文件不存在：$authFile" -ForegroundColor Red
        return
    }
    try {
        $auth = Get-Content -Raw -LiteralPath $authFile | ConvertFrom-Json
        if ($auth.ownerToken) {
            Write-Host "Owner password: $($auth.ownerToken)"
        } else {
            Write-Host '[DevSpace] auth.json 中不存在 ownerToken。' -ForegroundColor Red
        }
    } catch {
        Write-Host "[DevSpace] 无法读取认证文件：$($_.Exception.Message)" -ForegroundColor Red
    }
}

function Open-ConfigFile {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        Write-Host "[DevSpace] 配置文件不存在：$configFile" -ForegroundColor Red
        return
    }
    try {
        Start-Process -FilePath $configFile
        Write-Host "[DevSpace] 已打开配置文件：$configFile" -ForegroundColor Green
    } catch {
        Write-Host "[DevSpace] 无法打开配置文件：$($_.Exception.Message)" -ForegroundColor Red
    }
}

function Wait-ForUser {
    Write-Host
    Read-Host '按 Enter 键返回菜单' | Out-Null
}

while ($true) {
    Clear-Host
    Write-Host '============================================================'
    Write-Host "                 DevSpace 管理器 - $edition"
    Write-Host '============================================================'
    Write-Host
    Write-Host '  [1] 启动全部'
    Write-Host '  [2] 停止全部'
    Write-Host '  [3] 重启全部'
    Write-Host '  [4] 查看状态'
    Write-Host
    Write-Host '  [5] 启动 DevSpace'
    Write-Host '  [6] 停止 DevSpace'
    Write-Host '  [7] 启动 Cloudflare Tunnel'
    Write-Host '  [8] 停止 Cloudflare Tunnel'
    Write-Host '  [9] 查看 DevSpace Owner 密码'
    Write-Host ' [10] 打开 DevSpace 配置文件'
    Write-Host
    Write-Host '  [0] 退出'
    Write-Host

    switch (Read-Host '请选择操作') {
        '1' {
            Write-Host '[1/2] 启动 DevSpace...'
            if (Start-DevSpace) {
                Write-Host
                Write-Host '[2/2] 启动 Cloudflare Tunnel...'
                Start-Tunnel | Out-Null
            } else {
                Write-Host '[错误] DevSpace 未正常启动，已取消启动 Cloudflare Tunnel。' -ForegroundColor Red
            }
            Wait-ForUser
        }
        '2' {
            Write-Host '[1/2] 停止 Cloudflare Tunnel...'
            Stop-Tunnel | Out-Null
            Write-Host
            Write-Host '[2/2] 停止 DevSpace...'
            Stop-DevSpace | Out-Null
            Wait-ForUser
        }
        '3' {
            Write-Host '[1/4] 停止 Cloudflare Tunnel...'
            Stop-Tunnel | Out-Null
            Write-Host
            Write-Host '[2/4] 停止 DevSpace...'
            Stop-DevSpace | Out-Null
            Start-Sleep -Seconds 2
            Write-Host
            Write-Host '[3/4] 启动 DevSpace...'
            if (Start-DevSpace) {
                Write-Host
                Write-Host '[4/4] 启动 Cloudflare Tunnel...'
                Start-Tunnel | Out-Null
            } else {
                Write-Host '[错误] DevSpace 未正常启动，已取消启动 Cloudflare Tunnel。' -ForegroundColor Red
            }
            Wait-ForUser
        }
        '4' { Show-Status; Wait-ForUser }
        '5' { Start-DevSpace | Out-Null; Wait-ForUser }
        '6' { Stop-DevSpace | Out-Null; Wait-ForUser }
        '7' { Start-Tunnel | Out-Null; Wait-ForUser }
        '8' { Stop-Tunnel | Out-Null; Wait-ForUser }
        '9' { Show-OwnerPassword; Wait-ForUser }
        '10' { Open-ConfigFile; Wait-ForUser }
        '0' { return }
        default {
            Write-Host '无效选项。' -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
