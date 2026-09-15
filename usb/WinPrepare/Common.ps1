# ============================================================================
#  WinPrepare - Общие вспомогательные функции
# ============================================================================

$WinPrepareDir  = 'C:\ProgramData\WinPrepare'
$StatePath      = Join-Path $WinPrepareDir 'state.json'
$TaskPath       = '\WinPrepare\'
$TaskName       = 'WinPrepare-App'
$MainLog        = Join-Path $WinPrepareDir 'winprepare.log'

function Add-LogLine {
    param(
        [string]$Tag,
        [string]$Message,
        [string]$LogFile = $MainLog
    )
    try {
        if (-not (Test-Path $WinPrepareDir)) {
            New-Item -Path $WinPrepareDir -ItemType Directory -Force | Out-Null
        }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Tag, $Message
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    } catch { }
}

function Get-WinPrepareState {
    if (Test-Path $StatePath) {
        try {
            return Get-Content -Path $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json
        } catch { }
    }
    return $null
}

function Save-WinPrepareState {
    param($State)
    try {
        if (-not (Test-Path $WinPrepareDir)) {
            New-Item -Path $WinPrepareDir -ItemType Directory -Force | Out-Null
        }
        $State | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

# ------------------------------------------------------------------ Сеть и Wi-Fi
function Test-Internet {
    foreach ($target in @('77.88.8.8', '8.8.8.8', '1.1.1.1')) {
        try {
            if (Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true }
        } catch { }
    }
    foreach ($name in @('www.msftconnecttest.com', 'dns.msftncsi.com')) {
        try {
            if (Resolve-DnsName -Name $name -Type A -ErrorAction Stop) { return $true }
        } catch { }
    }
    try {
        $resp = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { return $true }
    } catch { }
    return $false
}

function Import-WifiProfiles {
    param([string]$BaseDir)
    if (-not (Get-Service -Name WlanSvc -ErrorAction SilentlyContinue)) { return }
    try {
        $svc = Get-Service -Name WlanSvc
        if ($svc.StartType -eq 'Disabled') {
            Set-Service -Name WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue
        }
        Start-Service -Name WlanSvc -ErrorAction SilentlyContinue
    } catch { }

    $wlanInterfaces = & netsh.exe wlan show interfaces 2>&1
    if ($wlanInterfaces -match 'State|Состояние|GUID|Interface|Интерфейс') {
        foreach ($profileFile in $Config.WlanProfiles) {
            $path = Join-Path $BaseDir $profileFile
            if (Test-Path $path) {
                & netsh.exe wlan add profile filename="$path" user=all 2>&1 | Out-Null
            }
        }
    }
}

function Connect-Wifi {
    param([string]$Ssid)
    if (-not (Get-Service -Name WlanSvc -ErrorAction SilentlyContinue)) { return }
    foreach ($name in @($Ssid, "$Ssid-WPA3")) {
        & netsh.exe wlan connect name="$name" 2>$null | Out-Null
    }
}

function Wait-InternetConnection {
    param(
        [int]$TimeoutMin = 15,
        [string]$BaseDir = '',
        [scriptblock]$OnProgress = $null
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMin)
    while ((Get-Date) -lt $deadline) {
        if (Test-Internet) { return $true }
        if ($BaseDir) { Import-WifiProfiles -BaseDir $BaseDir }
        Connect-Wifi -Ssid $Config.Ssid
        if ($OnProgress) { & $OnProgress }
        Start-Sleep -Seconds 5
    }
    return (Test-Internet)
}

# ------------------------------------------------------------- Перезагрузка и CBS
function Test-PendingReboot {
    # 1. CBS (Component Based Servicing) reboot pending
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        return $true
    }
    # 2. Windows Update Auto Update reboot pending
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        return $true
    }
    # 3. COM API SystemInfo
    try {
        if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) {
            return $true
        }
    } catch { }
    return $false
}

# -------------------------------------------------------- Проверка связи с доменом
function Test-DomainHostReachability {
    param([string]$TargetHost)
    if (-not $TargetHost) { return $false }
    # 1. Ping
    try {
        if (Test-Connection -ComputerName $TargetHost -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            return $true
        }
    } catch { }
    # 2. DNS resolve
    try {
        if (Resolve-DnsName -Name $TargetHost -ErrorAction Stop) {
            return $true
        }
    } catch { }
    # 3. TCP LDAP (389)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($TargetHost, 389, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.Close()
            return $true
        }
        $tcp.Close()
    } catch { }
    return $false
}

function Sync-DomainTime {
    param([string]$TargetHost)
    try {
        Start-Service -Name W32Time -ErrorAction SilentlyContinue
        $serverList = "$TargetHost,0x8 ru.pool.ntp.org,0x8 ntp1.vniiftri.ru,0x8"
        & w32tm.exe /config /syncfromflags:manual "/manualpeerlist:$serverList" /update 2>$null | Out-Null
        & w32tm.exe /resync /force 2>$null | Out-Null
    } catch { }
}

# ----------------------------------------------------------------- Autologon
function Enable-Autologon {
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    try {
        $p = Get-ItemProperty -Path $winlogon -ErrorAction Stop
        if ($p.DefaultUserName) {
            Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '1' -Type String -Force -ErrorAction Stop
            Remove-ItemProperty -Path $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
            return $true
        }
    } catch { }
    return $false
}

function Disable-Autologon {
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    try {
        Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '0' -Type String -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $winlogon -Name 'DefaultPassword'  -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $winlogon -Name 'AutoLogonCount'   -ErrorAction SilentlyContinue
    } catch { }
}

# ---------------------------------------------------- Центр обновления Windows
function Ensure-WindowsUpdateServices {
    foreach ($name in @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc')) {
        try {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -eq 'Disabled') {
                Set-Service -Name $name -StartupType Manual -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    foreach ($name in @('bits', 'wuauserv', 'usosvc')) {
        try { Start-Service -Name $name -ErrorAction SilentlyContinue } catch { }
    }
}

function Register-MicrosoftUpdateCatalog {
    if (-not $Config.AddMicrosoftUpdate) { return }
    $sid = '7971f918-a847-4430-9279-4a52d1efe18d'
    try {
        $manager = New-Object -ComObject Microsoft.Update.ServiceManager
        $exists = $false
        foreach ($s in $manager.Services) {
            if ($s.ServiceId -eq $sid) { $exists = $true; break }
        }
        if (-not $exists) {
            $null = $manager.AddService2($sid, 7, '')
        }
    } catch { }
}

function Search-AllUpdatesAndDrivers {
    param($Session)

    $searcher = $Session.CreateUpdateSearcher()
    if ($Config.AddMicrosoftUpdate) {
        try {
            $searcher.ServerSelection = 3
            $searcher.ServiceID       = '7971f918-a847-4430-9279-4a52d1efe18d'
        } catch { }
    }

    $allUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
    $addedIds   = @{}

    # 1. Поиск обязательных обновлений (BrowseOnly=0)
    try {
        $resMandatory = $searcher.Search("IsInstalled=0 and IsHidden=0 and BrowseOnly=0")
        if ($resMandatory -and $resMandatory.Updates) {
            foreach ($u in $resMandatory.Updates) {
                $id = $u.Identity.UpdateID
                if (-not $addedIds.ContainsKey($id)) {
                    $addedIds[$id] = $true
                    [void]$allUpdates.Add($u)
                }
            }
        }
    } catch {
        # Резервный поиск без BrowseOnly
        try {
            $resFallback = $searcher.Search("IsInstalled=0 and IsHidden=0")
            if ($resFallback -and $resFallback.Updates) {
                foreach ($u in $resFallback.Updates) {
                    $id = $u.Identity.UpdateID
                    if (-not $addedIds.ContainsKey($id)) {
                        $addedIds[$id] = $true
                        [void]$allUpdates.Add($u)
                    }
                }
            }
        } catch { }
    }

    # 2. Поиск дополнительных обновлений и драйверов (BrowseOnly=1)
    if ($Config.IncludeOptionalUpdates -or $Config.IncludeDrivers) {
        try {
            $resOptional = $searcher.Search("IsInstalled=0 and IsHidden=0 and BrowseOnly=1")
            if ($resOptional -and $resOptional.Updates) {
                foreach ($u in $resOptional.Updates) {
                    $id = $u.Identity.UpdateID
                    if (-not $addedIds.ContainsKey($id)) {
                        $addedIds[$id] = $true
                        [void]$allUpdates.Add($u)
                    }
                }
            }
        } catch { }
    }

    # Фильтрация и принятие EULA
    $readyCollection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $allUpdates) {
        try {
            if ($u.InstallationBehavior.CanRequestUserInput) { continue }
        } catch { }

        if (-not $Config.IncludeDrivers -and $u.Type -eq 'Driver') {
            continue
        }

        try {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
        } catch { }

        [void]$readyCollection.Add($u)
    }

    return $readyCollection
}
