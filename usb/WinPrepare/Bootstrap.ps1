# ============================================================================
#  WinPrepare - Bootstrap (выполняется 1 раз при установке ОС от SYSTEM)
#  Вызывается из SetupComplete.cmd. Регистрирует автозапуск UI-приложения.
# ============================================================================

$ErrorActionPreference = 'Continue'
$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Base 'Config.ps1')
. (Join-Path $Base 'Common.ps1')

$BootLog = Join-Path $WinPrepareDir 'bootstrap.log'
function Write-BLog { param([string]$Msg) Add-LogLine -Tag 'BOOT' -Message $Msg -LogFile $BootLog }

Write-BLog '=== WinPrepare Bootstrap started ==='

if (-not (Test-Path $WinPrepareDir)) {
    New-Item -Path $WinPrepareDir -ItemType Directory -Force | Out-Null
}

# 1. Начальное состояние
if (-not (Get-WinPrepareState)) {
    Save-WinPrepareState ([pscustomobject]@{
        phase       = 'start'
        cycles      = 0
        noChange    = 0
        searchFails = 0
    })
    Write-BLog 'Initial state created.'
}

# 2. Отключение сна и гибернации на время настройки
try {
    & powercfg.exe /change standby-timeout-ac 0   | Out-Null
    & powercfg.exe /change standby-timeout-dc 0   | Out-Null
    & powercfg.exe /change hibernate-timeout-ac 0 | Out-Null
    & powercfg.exe /change hibernate-timeout-dc 0 | Out-Null
    Write-BLog 'Sleep and hibernation timeouts disabled.'
} catch { }

# 3. Отключение P2P Delivery Optimization (режим HTTP-only через BITS)
try {
    $doPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    if (-not (Test-Path $doPath)) { New-Item -Path $doPath -ItemType Directory -Force | Out-Null }
    Set-ItemProperty -Path $doPath -Name 'DODownloadMode' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-BLog 'Delivery Optimization set to HTTP-only (DODownloadMode=0).'
} catch { }

# 4. Фиксация бесконечного AutoAdminLogon
try {
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $p = Get-ItemProperty -Path $winlogon -ErrorAction Stop
    if ($p.DefaultUserName) {
        Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '1' -Type String -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
        Write-BLog ("AutoAdminLogon armed for user '{0}' without logon count limits." -f $p.DefaultUserName)
    }
} catch { }

# 5. Регистрация единственной задачи WinPrepare-App для запуска UI на рабочем столе
try {
    $scriptFile = Join-Path $Base 'Main-UI.ps1'
    $action     = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $scriptFile)
    $trigger    = New-ScheduledTaskTrigger -AtLogOn
    $principal  = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Administrators' -RunLevel Highest
    $settings   = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 24) -MultipleInstances IgnoreNew
    
    Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    Write-BLog 'Scheduled task WinPrepare-App registered successfully.'
} catch {
    Write-BLog ("Scheduled task registration failed: {0}" -f $_.Exception.Message)
}

Write-BLog '=== WinPrepare Bootstrap finished ==='
exit 0
