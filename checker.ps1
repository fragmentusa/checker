# Console checker for Minecraft screenshare (PowerShell, run as Administrator)
# Usage: .\checker.ps1 -Code ABC123 -Password mypass
param(
    [Parameter(Mandatory = $true)][string]$Code,      # код проверки (ID сессии модератора)
    [Parameter(Mandatory = $true)][string]$Password,  # пароль, чтобы скриптом не пользовались посторонние
    [string]$WebhookUrl = ""                          # необязательно: куда отправить отчёт
)

# ---------- Настройки ----------
# SHA256-хеш пароля. Получить: [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("твой_пароль"))).Replace("-","").ToLower()
$PasswordHash = "a862e4faf907500b42d12feea180f9dd194e80a7e3ac6b2bdc72b9dbbde27842"

$Keywords = @(
    "killaura","aimassist","autoclicker","triggerbot","reach","velocity","scaffold",
    "esp","xray","fly","nofall","bhop","wurst","meteor","impact","liquidbounce",
    "vape","rise","novoline","astolfo","akrien","celestial","expensive","nursultan","wexside"
)
# ---------------------------------

# Ссылки на zip-архивы инструментов (положи их, например, в GitHub Releases своего репозитория)
$EverythingZipUrl  = "https://www.voidtools.com/Everything-1.5.0.1409a.x64.zip"   # Everything 1.5a x64 portable
$JournalTraceUrl   = "https://github.com/ponei/JournalTrace/releases/latest/download/JournalTrace.exe"   # JournalTrace (ponei)
$ToolsDir = Join-Path $env:TEMP "checker_tools"

$ErrorActionPreference = "SilentlyContinue"
$report = New-Object System.Collections.Generic.List[string]
function Log($t) { $report.Add($t); Write-Host $t }

# 1. Проверка пароля
$hash = [BitConverter]::ToString(
    [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Password))
).Replace("-", "").ToLower()
if ($hash -ne $PasswordHash) { Write-Host "Неверный пароль." -ForegroundColor Red; return }

# 2. Проверка прав администратора
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "Запусти PowerShell от имени администратора." -ForegroundColor Red; return }

# 3. Согласие пользователя (прозрачность)
Write-Host "`nПроверка #$Code. Скрипт просматривает: папку .minecraft, Prefetch, Recent, запущенные процессы." -ForegroundColor Cyan
Write-Host "Файлы не изменяются и не удаляются. Отчёт сохраняется на рабочий стол." -ForegroundColor Cyan
if ($WebhookUrl) { Write-Host "Отчёт будет отправлен модератору." -ForegroundColor Yellow }
Write-Host "Запуск через 5 секунд. Закрой окно, чтобы отменить." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Log "=== ОТЧЁТ | Код: $Code | Игрок: $env:USERNAME | ПК: $env:COMPUTERNAME | $(Get-Date) ==="

function Match-Keyword($text) {
    $low = $text.ToLower()
    foreach ($k in $Keywords) { if ($low.Contains($k)) { return $k } }
    return $null
}

# 4. Запущенные процессы
Log "`n[1] Процессы"
Get-CimInstance Win32_Process | ForEach-Object {
    $line = "$($_.Name) $($_.CommandLine)"
    $m = Match-Keyword $line
    if ($m) { Log "  ПОДОЗРИТЕЛЬНО ($m): $($_.Name) PID=$($_.ProcessId)" }
}
$java = Get-CimInstance Win32_Process -Filter "Name='javaw.exe' OR Name='java.exe'"
foreach ($j in $java) {
    if ($j.CommandLine -match "-javaagent|-agentlib|-Xbootclasspath") {
        Log "  ВНИМАНИЕ: Java с агентом/инжектом PID=$($j.ProcessId): $($j.CommandLine)"
    }
}

# 5. Содержимое .minecraft (jar-файлы)
Log "`n[2] Файлы .jar в .minecraft"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$mc = Join-Path $env:APPDATA ".minecraft"
Get-ChildItem $mc -Recurse -Include *.jar -ErrorAction SilentlyContinue | ForEach-Object {
    $m = Match-Keyword $_.Name
    if ($m) { Log "  Имя файла ($m): $($_.FullName)" }
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($_.FullName)
        $hits = $zip.Entries | Where-Object { Match-Keyword $_.FullName } | Select-Object -First 5
        foreach ($h in $hits) { Log "  Внутри $($_.Name): $($h.FullName)" }
        $zip.Dispose()
    } catch {}
}

# 6. Prefetch (следы запуска программ)
Log "`n[3] Prefetch (за последние 7 дней)"
Get-ChildItem "C:\Windows\Prefetch\*.pf" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        $m = Match-Keyword $_.Name
        if ($m) { Log "  ($m) $($_.Name) — $($_.LastWriteTime)" }
    }

# 7. Recent (недавние файлы)
Log "`n[4] Недавние файлы"
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -Filter *.lnk | ForEach-Object {
    $m = Match-Keyword $_.Name
    if ($m) { Log "  ($m) $($_.Name) — $($_.LastWriteTime)" }
}

# 8. Загрузки и рабочий стол
Log "`n[5] Загрузки / Рабочий стол"
foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")) {
    Get-ChildItem $dir -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $m = Match-Keyword $_.Name
        if ($m) { Log "  ($m) $($_.FullName)" }
    }
}

# 9. Инжекты: подозрительные модули в процессах Java
Log "`n[6] Модули в javaw/java (неподписанные DLL вне системных папок)"
$skipName = '^(lwjgl|jna|glfw|OpenAL|jemalloc|zstd|opus|tinyfd|freetype|sqlite)'
foreach ($p in (Get-Process javaw, java -ErrorAction SilentlyContinue)) {
    try {
        foreach ($m in $p.Modules) {
            $f = $m.FileName
            if ($f -match '^C:\\Windows\\') { continue }
            if ($m.ModuleName -match $skipName) { continue }
            $kw = Match-Keyword $f
            if ($kw) { Log "  ВНИМАНИЕ (имя: $kw): $f [PID $($p.Id)]"; continue }
            if ($f -match '\.(dll)$') {
                $sig = Get-AuthenticodeSignature $f
                if ($sig.Status -ne "Valid" -and $f -notmatch '\\(Java|jdk|jre|runtime)[^\\]*\\') {
                    Log "  ВНИМАНИЕ (без подписи): $f [PID $($p.Id)]"
                }
            }
        }
    } catch { Log "  Не удалось прочитать модули PID $($p.Id)" }
}

# 10. Полное сканирование дисков по именам файлов
Log "`n[7] Все диски: файлы с подозрительными именами"
$exts = @("*.jar", "*.exe", "*.dll", "*.zip", "*.rar", "*.7z", "*.bat", "*.ps1", "*.cfg", "*.json")
$skipPath = '\\(Windows|Program Files|Program Files \(x86\)|ProgramData\\Microsoft|\$Recycle\.Bin|System Volume Information)\\'
foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
    Write-Host "  Сканирую $($drive.Root) ..." -ForegroundColor DarkGray
    Get-ChildItem $drive.Root -Recurse -Force -File -Include $exts -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skipPath } |
        ForEach-Object {
            $m = Match-Keyword $_.Name
            if ($m) { Log "  ($m) $($_.FullName)" }
        }
}

Log "`n=== Проверка завершена ==="

# Сохранение отчёта
$path = Join-Path ([Environment]::GetFolderPath("Desktop")) "check_$Code.txt"
$report | Out-File $path -Encoding utf8
Write-Host "`nОтчёт сохранён: $path" -ForegroundColor Green

# Отправка отчёта в Discord (только если указан webhook; игрок видел уведомление выше)
if ($WebhookUrl) {
    $hitCount = @($report | Where-Object { $_ -match '^\s+(ПОДОЗРИТЕЛЬНО|ВНИМАНИЕ|Имя файла|Внутри|\()' }).Count
    $color = if ($hitCount -gt 0) { 15158332 } else { 3066993 }   # красный / зелёный
    $verdict = if ($hitCount -gt 0) { "Найдено совпадений: $hitCount" } else { "Совпадений не найдено" }

    $payload = @{
        embeds = @(@{
            title  = "Проверка #$Code"
            color  = $color
            fields = @(
                @{ name = "Игрок";  value = "$env:USERNAME"; inline = $true },
                @{ name = "ПК";     value = "$env:COMPUTERNAME"; inline = $true },
                @{ name = "Итог";   value = $verdict; inline = $false }
            )
            footer    = @{ text = "Полный отчёт во вложении" }
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        })
    } | ConvertTo-Json -Depth 6 -Compress

    $tmp = Join-Path $env:TEMP "payload_$Code.json"
    [IO.File]::WriteAllText($tmp, $payload, (New-Object Text.UTF8Encoding $false))

    # curl.exe есть в Windows 10/11; отправляет embed + файл отчёта вложением
    curl.exe -s -X POST -F "payload_json=<$tmp" -F "file=@$path" $WebhookUrl | Out-Null
    Remove-Item $tmp -Force

    if ($LASTEXITCODE -eq 0) { Write-Host "Отчёт отправлен модератору." -ForegroundColor Green }
    else { Write-Host "Не удалось отправить отчёт. Покажи файл вручную: $path" -ForegroundColor Yellow }
}

# ---------- Запуск Everything 1.5a и JournalTrace ----------
function Get-Tool($url, $pattern) {
    $exe = Get-ChildItem $ToolsDir -Recurse -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe -or -not $url) { return $exe }
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
    $file = Join-Path $ToolsDir ([IO.Path]::GetFileName(([Uri]$url).AbsolutePath))
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
    if ($file -like "*.zip") { Expand-Archive $file -DestinationPath $ToolsDir -Force }
    return (Get-ChildItem $ToolsDir -Recurse -Filter $pattern | Select-Object -First 1)
}

$ev = Get-Tool $EverythingZipUrl "Everything*.exe"
if ($ev) {
    $query = ($Keywords -join "|")    # в Everything "|" означает ИЛИ
    Start-Process $ev.FullName -ArgumentList @("-search", $query)
    Write-Host "Everything запущен, строки поиска введены." -ForegroundColor Green
} else { Write-Host "Everything не найден: заполни `$EverythingZipUrl в скрипте." -ForegroundColor Yellow }

$jt = Get-Tool $JournalTraceUrl "JournalTrace*.exe"
if ($jt) {
    Start-Process $jt.FullName
    Write-Host "JournalTrace запущен." -ForegroundColor Green
} else { Write-Host "JournalTrace не найден: заполни `$JournalTraceUrl в скрипте." -ForegroundColor Yellow }
