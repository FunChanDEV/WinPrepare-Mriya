# ============================================================================
#  WinPrepare - Главное интерактивное UI-приложение
#  Запускается на рабочем столе от имени Администратора.
#  Выполняет: Wi-Fi -> Обновления и драйверы -> Ожидание сети -> Ввод в домен.
# ============================================================================

$ErrorActionPreference = 'Continue'
$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Base 'Config.ps1')
. (Join-Path $Base 'Common.ps1')

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    exit 1
}

# ============================================================================
#  Создание графического интерфейса WinForms
# ============================================================================

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'WinPrepare — Автоматическая настройка Windows 11'
$form.Size            = New-Object System.Drawing.Size(700, 560)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.TopMost         = $true

# Панель заголовка
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location  = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size      = New-Object System.Drawing.Size(700, 65)
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(24, 76, 120)

$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text      = 'WinPrepare'
$lblAppTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblAppTitle.ForeColor = [System.Drawing.Color]::White
$lblAppTitle.Location  = New-Object System.Drawing.Point(18, 10)
$lblAppTitle.Size      = New-Object System.Drawing.Size(400, 26)

$lblAppSub = New-Object System.Windows.Forms.Label
$lblAppSub.Text      = 'Автоматическое обновление Windows, установка всех драйверов и ввод в домен'
$lblAppSub.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$lblAppSub.ForeColor = [System.Drawing.Color]::FromArgb(210, 230, 250)
$lblAppSub.Location  = New-Object System.Drawing.Point(19, 36)
$lblAppSub.Size      = New-Object System.Drawing.Size(650, 20)

$pnlHeader.Controls.Add($lblAppTitle)
$pnlHeader.Controls.Add($lblAppSub)
$form.Controls.Add($pnlHeader)

# Индикатор шагов
$lblSteps = New-Object System.Windows.Forms.Label
$lblSteps.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblSteps.Location = New-Object System.Drawing.Point(18, 75)
$lblSteps.Size     = New-Object System.Drawing.Size(650, 22)
$lblSteps.Text     = 'Шаги: [1] Wi-Fi   -->   [2] Обновления и драйверы   -->   [3] Корпоративная сеть   -->   [4] Домен'
$lblSteps.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$form.Controls.Add($lblSteps)

# Блок статуса текущей операции
$lblCurrentTask = New-Object System.Windows.Forms.Label
$lblCurrentTask.Font     = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblCurrentTask.ForeColor = [System.Drawing.Color]::FromArgb(20, 60, 100)
$lblCurrentTask.Location = New-Object System.Drawing.Point(18, 105)
$lblCurrentTask.Size     = New-Object System.Drawing.Size(650, 26)
$lblCurrentTask.Text     = 'Инициализация...'
$form.Controls.Add($lblCurrentTask)

$lblDetail = New-Object System.Windows.Forms.Label
$lblDetail.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
$lblDetail.Location = New-Object System.Drawing.Point(19, 133)
$lblDetail.Size     = New-Object System.Drawing.Size(650, 48)
$lblDetail.Text     = 'Пожалуйста, подождите...'
$form.Controls.Add($lblDetail)

# Прогресс-бар
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 185)
$progressBar.Size     = New-Object System.Drawing.Size(645, 20)
$progressBar.Style    = [System.Windows.Forms.ProgressBarStyle]::Marquee
$form.Controls.Add($progressBar)

# Журнал действий
$lblLogTitle = New-Object System.Windows.Forms.Label
$lblLogTitle.Font     = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$lblLogTitle.ForeColor = [System.Drawing.Color]::Gray
$lblLogTitle.Location = New-Object System.Drawing.Point(18, 215)
$lblLogTitle.Size     = New-Object System.Drawing.Size(200, 18)
$lblLogTitle.Text     = 'ЖУРНАЛ ОПЕРАЦИЙ:'
$form.Controls.Add($lblLogTitle)

$lstLog = New-Object System.Windows.Forms.ListBox
$lstLog.Location = New-Object System.Drawing.Point(20, 235)
$lstLog.Size     = New-Object System.Drawing.Size(645, 220)
$lstLog.Font     = New-Object System.Drawing.Font('Consolas', 8.5)
$form.Controls.Add($lstLog)

# Нижняя панель с кнопками
$btnAction = New-Object System.Windows.Forms.Button
$btnAction.Text     = 'Ввести в домен...'
$btnAction.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnAction.Location = New-Object System.Drawing.Point(20, 468)
$btnAction.Size     = New-Object System.Drawing.Size(180, 38)
$btnAction.Visible  = $false
$form.Controls.Add($btnAction)

$btnCheckReachability = New-Object System.Windows.Forms.Button
$btnCheckReachability.Text     = 'Проверить связь'
$btnCheckReachability.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
$btnCheckReachability.Location = New-Object System.Drawing.Point(210, 468)
$btnCheckReachability.Size     = New-Object System.Drawing.Size(140, 38)
$btnCheckReachability.Visible  = $false
$form.Controls.Add($btnCheckReachability)

function UI-Log {
    param([string]$Msg)
    Add-LogLine -Tag 'UI' -Message $Msg
    $ts = Get-Date -Format 'HH:mm:ss'
    $item = "[{0}] {1}" -f $ts, $Msg
    $lstLog.Items.Add($item) | Out-Null
    $lstLog.TopIndex = [Math]::Max(0, $lstLog.Items.Count - 1)
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-TaskStatus {
    param(
        [string]$Title,
        [string]$Detail,
        [string]$StepHighlight = ''
    )
    $lblCurrentTask.Text = $Title
    $lblDetail.Text      = $Detail
    if ($StepHighlight) {
        $lblSteps.Text   = $StepHighlight
    }
    [System.Windows.Forms.Application]::DoEvents()
}

# ============================================================================
#  Логика выполнения автоматизации
# ============================================================================

$script:WorkerRunning = $false

function Run-AutomationWorkflow {
    if ($script:WorkerRunning) { return }
    $script:WorkerRunning = $true

    $state = Get-WinPrepareState
    if (-not $state) {
        $state = [pscustomobject]@{ phase = 'wifi'; cycles = 0; noChange = 0 }
    }

    # ------------------------------------------------------------- 1. Wi-Fi
    if ($state.phase -eq 'start' -or $state.phase -eq 'wifi') {
        Set-TaskStatus -Title "Шаг 1: Подключение к Wi-Fi сети '$($Config.Ssid)'" `
                       -Detail "Импорт профилей Wi-Fi и ожидание выхода в интернет..." `
                       -StepHighlight "Шаги: >>> [1] Wi-Fi <<<   -->   [2] Обновления и драйверы   -->   [3] Корпоративная сеть   -->   [4] Домен"
        
        UI-Log "Проверка сетевого подключения..."

        if (Test-Internet) {
            UI-Log "Интернет уже доступен (Ethernet или активный Wi-Fi)."
        } else {
            UI-Log "Импорт профилей Wi-Fi для SSID '$($Config.Ssid)'..."
            Import-WifiProfiles -BaseDir $Base
            Connect-Wifi -Ssid $Config.Ssid

            $deadline = (Get-Date).AddMinutes($Config.WifiTimeoutMin)
            while ((Get-Date) -lt $deadline -and -not (Test-Internet)) {
                Import-WifiProfiles -BaseDir $Base
                Connect-Wifi -Ssid $Config.Ssid
                Set-TaskStatus -Title "Шаг 1: Подключение к Wi-Fi '$($Config.Ssid)'" `
                               -Detail "Ожидание установления соединения и доступа в интернет..."
                [System.Threading.Thread]::Sleep(4000)
            }
        }

        if (-not (Test-Internet)) {
            UI-Log "ОШИБКА: Не удалось получить доступ к интернету через Wi-Fi '$($Config.Ssid)'."
            Set-TaskStatus -Title "Сбой подключения к сети" `
                           -Detail "Проверьте точку доступа '$($Config.Ssid)' или подключите сетевой кабель."
            [System.Windows.Forms.MessageBox]::Show(
                "Не удалось подключиться к интернету через Wi-Fi '$($Config.Ssid)'.`n`nПроверьте хотспот или подключите сетевой провод, затем перезапустите ПК.",
                'WinPrepare',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $script:WorkerRunning = $false
            return
        }

        UI-Log "Интернет подтверждён. Переход к этапу установки обновлений и драйверов."
        $state.phase = 'updates'
        Save-WinPrepareState $state
    }

    # ---------------------------------------------- 2. Обновления и драйверы
    if ($state.phase -eq 'updates') {
        Set-TaskStatus -Title "Шаг 2: Центр обновления Windows и драйверы" `
                       -Detail "Инициализация службы Windows Update..." `
                       -StepHighlight "Шаги: [1] Wi-Fi   -->   >>> [2] Обновления и драйверы <<<   -->   [3] Корпоративная сеть   -->   [4] Домен"

        Ensure-WindowsUpdateServices
        Register-MicrosoftUpdateCatalog

        while ($true) {
            $state.cycles = [int]$state.cycles + 1
            Save-WinPrepareState $state
            UI-Log ("--- Цикл обновления {0} из макс. {1} ---" -f $state.cycles, $Config.MaxUpdateCycles)

            if ([int]$state.cycles -gt [int]$Config.MaxUpdateCycles) {
                UI-Log "Достигнут максимальный лимит циклов обновлений. Переход к этапу домена."
                break
            }

            Set-TaskStatus -Title "Поиск обновлений Windows и драйверов (Цикл $($state.cycles))..." `
                           -Detail "Запрос обязательных и дополнительных компонентов к серверам Microsoft..."
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee

            $session = New-Object -ComObject Microsoft.Update.Session
            $updateColl = Search-AllUpdatesAndDrivers -Session $session

            $count = if ($updateColl) { $updateColl.Count } else { 0 }
            UI-Log ("Найдено применимых обновлений и драйверов: {0}" -f $count)

            if ($count -eq 0) {
                if (Test-PendingReboot) {
                    UI-Log "Новых обновлений нет, но система ожидает перезагрузки после предыдущих пакетов."
                    Set-TaskStatus -Title "Перезагрузка для применения обновлений..." `
                                   -Detail "Компьютер перезагрузится через 10 секунд и автоматически вернется на рабочий стол."
                    for ($s = 10; $s -gt 0; $s--) {
                        UI-Log ("Перезагрузка через {0} сек..." -f $s)
                        [System.Threading.Thread]::Sleep(1000)
                    }
                    & shutdown.exe /r /f /t 2 /c 'WinPrepare: перезагрузка для завершения обновлений'
                    exit 0
                }
                UI-Log "Все обновления Windows и все драйверы успешно установлены!"
                break
            }

            # Вывод списка обновлений
            for ($i = 0; $i -lt $count; $i++) {
                $u = $updateColl.Item($i)
                UI-Log ("  • [{0}] {1}" -f $u.Type, $u.Title)
            }

            # Скачивание
            Set-TaskStatus -Title "Скачивание обновлений и драйверов ($count шт.)..." `
                           -Detail "Идёт загрузка компонентов из Центра обновления..."
            UI-Log "Запуск скачивания пакетов..."
            
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $updateColl
            $downloadResult = $downloader.Download()
            UI-Log ("Скачивание завершено (ResultCode={0})." -f $downloadResult.ResultCode)

            # Отбор успешно скачанных
            $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
            for ($i = 0; $i -lt $count; $i++) {
                $u = $updateColl.Item($i)
                if ($u.IsDownloaded) { [void]$toInstall.Add($u) }
            }

            if ($toInstall.Count -eq 0) {
                UI-Log "Не удалось скачать обновления (возможен сбой связи). Повтор попытки..."
                [System.Threading.Thread]::Sleep(15000)
                continue
            }

            # Установка
            Set-TaskStatus -Title "Установка обновлений и драйверов ($($toInstall.Count) шт.)..." `
                           -Detail "Применение драйверов и системных компонентов..."
            UI-Log ("Запуск установки {0} пакетов..." -f $toInstall.Count)

            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $toInstall
            $installResult = $installer.Install()

            UI-Log ("Установка завершена (ResultCode={0}, RebootRequired={1})." -f $installResult.ResultCode, $installResult.RebootRequired)

            $rebootNeeded = ($installResult.RebootRequired -or (Test-PendingReboot))

            if ($rebootNeeded) {
                UI-Log "Требуется перезагрузка системы для применения обновлений и драйверов."
                Set-TaskStatus -Title "Перезагрузка компьютера..." `
                               -Detail "Ноутбук перезагружается для применения драйверов/обновлений и продолжит настройку."
                for ($s = 10; $s -gt 0; $s--) {
                    UI-Log ("Перезагрузка через {0} сек..." -f $s)
                    [System.Threading.Thread]::Sleep(1000)
                }
                & shutdown.exe /r /f /t 2 /c 'WinPrepare: перезагрузка для завершения установки драйверов'
                exit 0
            }

            UI-Log "Перезагрузка не потребовалась. Повторная проверка оставшихся обновлений..."
            [System.Threading.Thread]::Sleep(10000)
        }

        $state.phase = 'domain'
        Save-WinPrepareState $state
    }

    # ------------------------------------------------ 3 & 4. Корпоративная сеть и Домен
    if ($state.phase -eq 'domain') {
        Enter-DomainPhaseUI
    }
}

function Enter-DomainPhaseUI {
    $progressBar.Style   = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $progressBar.Value   = 100
    $btnAction.Visible   = $true
    $btnAction.Enabled   = $false
    $btnCheckReachability.Visible = $true

    $wifiHint = if ($Config.CorporateWifiHint) { $Config.CorporateWifiHint } else { 'Mrs.team' }
    $targetHost = if ($Config.DomainTargetHost) { $Config.DomainTargetHost } else { $Config.Domain }

    Set-TaskStatus -Title "Шаг 3: Требуется подключение к корпоративной сети" `
                   -Detail "Подключите Wi-Fi '$wifiHint' (значок сети в трее) или вставьте сетевой провод.`nИмя ПК: $env:COMPUTERNAME (будет сохранено без изменений)." `
                   -StepHighlight "Шаги: [1] Wi-Fi   -->   [2] Обновления и драйверы   -->   >>> [3] Корпоративная сеть <<<   -->   [4] Домен"

    UI-Log "================================================================"
    UI-Log "Все обновления и драйверы успешно установлены!"
    UI-Log "Для ввода в домен подключите ноутбук к корпоративной сети:"
    UI-Log ("  1. Подключите Wi-Fi '{0}' (через значок сети в трее)" -f $wifiHint)
    UI-Log "     ИЛИ"
    UI-Log "  2. Вставьте сетевой кабель."
    UI-Log ("Ожидание доступности контроллера домена '{0}'..." -f $targetHost)
    UI-Log "================================================================"

    $checkConnection = {
        $ok = Test-DomainHostReachability -TargetHost $targetHost

        if (-not $ok -and @($Config.DomainDnsServers).Count -gt 0) {
            try {
                Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } |
                    Set-DnsClientServerAddress -ServerAddresses @($Config.DomainDnsServers) -ErrorAction SilentlyContinue
                Clear-DnsClientCache -ErrorAction SilentlyContinue
                $ok = Test-DomainHostReachability -TargetHost $targetHost
            } catch { }
        }

        if ($ok) {
            $lblDetail.ForeColor = [System.Drawing.Color]::DarkGreen
            $lblDetail.Text      = "Связь с контроллером домена ($targetHost) установлена!`nИмя компьютера: $env:COMPUTERNAME (сохраняется).`nНажмите кнопку 'Ввести в домен...' ниже."
            $btnAction.Enabled   = $true
            $lblSteps.Text       = "Шаги: [1] Wi-Fi   -->   [2] Обновления и драйверы   -->   [3] Сеть OK   -->   >>> [4] Ввод в домен <<<"
            return $true
        } else {
            $lblDetail.ForeColor = [System.Drawing.Color]::DarkRed
            $lblDetail.Text      = "Ожидание подключения к корпоративной сети... Контроллер '$targetHost' пока недоступен.`nПодключите Wi-Fi '$wifiHint' или кабель."
            $btnAction.Enabled   = $false
            return $false
        }
    }

    # Таймер непрерывного опроса rixos.rus каждые 3 секунды
    $timerDomain = New-Object System.Windows.Forms.Timer
    $timerDomain.Interval = 3000
    $timerDomain.Add_Tick({ & $checkConnection })
    $timerDomain.Start()

    $btnCheckReachability.Add_Click({
        UI-Log ("Ручная проверка связи с {0}..." -f $targetHost)
        if (& $checkConnection) {
            UI-Log "Контроллер домена доступен!"
        } else {
            UI-Log "Контроллер домена пока недоступен."
        }
    })

    $btnAction.Add_Click({
        $timerDomain.Stop()
        $form.TopMost = $false

        while ($true) {
            $cred = $null
            if ($Config.DomainUser -and $Config.DomainPass) {
                try {
                    $sec  = ConvertTo-SecureString -String $Config.DomainPass -AsPlainText -Force
                    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Config.DomainUser, $sec
                } catch { }
            }
            if (-not $cred) {
                try {
                    $prefix = if ($Config.NetbiosDomain) { '{0}\' -f $Config.NetbiosDomain } else { '' }
                    $cred = Get-Credential -UserName $prefix -Message ("Введите доменные учётные данные для ввода ПК '{0}' в домен {1}:" -f $env:COMPUTERNAME, $Config.Domain)
                } catch { }
            }

            if (-not $cred) {
                $ans = [System.Windows.Forms.MessageBox]::Show(
                    "Ввод учётных данных был отменён.`n`nПопробовать ввести снова?",
                    'WinPrepare',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { continue }
                else {
                    $timerDomain.Start()
                    $form.TopMost = $true
                    return
                }
            }

            UI-Log "Синхронизация времени с контроллером домена..."
            Sync-DomainTime -TargetHost $targetHost

            UI-Log ("Выполняется присоединение компьютера '{0}' к домену {1}..." -f $env:COMPUTERNAME, $Config.Domain)
            try {
                $joinParams = @{
                    DomainName  = $Config.Domain
                    Credential  = $cred
                    Force       = $true
                    ErrorAction = 'Stop'
                }
                if ($Config.OuPath) { $joinParams['OUPath'] = $Config.OuPath }

                Add-Computer @joinParams
                UI-Log "Компьютер успешно введён в домен!"

                # Очистка
                $state = Get-WinPrepareState
                if ($state) { $state.phase = 'done'; Save-WinPrepareState $state }

                Disable-Autologon
                try { Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                UI-Log "Автозапуск очищен, AutoAdminLogon отключен."

                [System.Windows.Forms.MessageBox]::Show(
                    "Компьютер '$env:COMPUTERNAME' успешно введён в домен $($Config.Domain)!`n`nСейчас компьютер перезагрузится.",
                    'WinPrepare — Готово',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null

                UI-Log "Финальная перезагрузка..."
                & shutdown.exe /r /f /t 5 /c 'WinPrepare: ввод в домен завершен, перезагрузка'
                $form.Close()
                exit 0
            } catch {
                $err = $_.Exception.Message
                UI-Log ("ОШИБКА ввода в домен: {0}" -f $err)

                $ans = [System.Windows.Forms.MessageBox]::Show(
                    "Не удалось ввести компьютер в домен:`n$err`n`nПовторить ввод учётных данных?",
                    'Ошибка ввода в домен',
                    [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                if ($ans -ne [System.Windows.Forms.DialogResult]::Retry) {
                    $timerDomain.Start()
                    $form.TopMost = $true
                    return
                }
            }
        }
    })

    & $checkConnection
}

# Запуск рабочего процесса при открытии окна
$form.Add_Shown({
    $timerStart = New-Object System.Windows.Forms.Timer
    $timerStart.Interval = 500
    $timerStart.Add_Tick({
        $timerStart.Stop()
        Run-AutomationWorkflow
    })
    $timerStart.Start()
})

[void][System.Windows.Forms.Application]::Run($form)
