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
    "vape","rise","novoline","astolfo","akrien","celestial","expensive","nursultan","wexside",
    "systemdlc","system-dlc","doomsday","aristois","sigma","wolfram","future","rusherhack",
    "huzuni","salhack","kamiblue","inertia","pyro","wolfvorlem","kiiro","needle","moon",
    "nofx","aristois2","cinnamon","anarchy","pandora","onehandclick","jigsaw","blatant",
    "watermark","injection","injector","loader","cracked","cheatclient","cheatgui","hvh"
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
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Кастомный прогресс-бар без системной темы (рисуем сами) ---
Add-Type @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class FlatProgress : Control {
    private int _value = 0;
    private int _max   = 100;
    public Color BarColor  = Color.FromArgb(80, 190, 255);
    public Color BackFill  = Color.FromArgb(40, 42, 50);
    public int   Value { get { return _value; }
        set { _value = Math.Max(0, Math.Min(_max, value)); Invalidate(); } }
    public int   Maximum { get { return _max; }
        set { _max = value; Invalidate(); } }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int r = Height / 2;
        // фон
        using (var b = new SolidBrush(BackFill)) g.FillRoundedRect(b, 0, 0, Width, Height, r);
        // заполнение
        if (_value > 0) {
            int w = (int)((double)_value / _max * Width);
            w = Math.Max(w, Height);
            var rect = new Rectangle(0, 0, w, Height);
            using (var gb = new LinearGradientBrush(rect, Color.FromArgb(60,160,255), Color.FromArgb(110,220,255), 0f))
                g.FillRoundedRect(gb, 0, 0, w, Height, r);
        }
    }
}

public static class GfxExt {
    public static void FillRoundedRect(this Graphics g, Brush b, int x, int y, int w, int h, int r) {
        var path = new System.Drawing.Drawing2D.GraphicsPath();
        path.AddArc(x, y, 2*r, 2*r, 180, 90);
        path.AddArc(x+w-2*r, y, 2*r, 2*r, 270, 90);
        path.AddArc(x+w-2*r, y+h-2*r, 2*r, 2*r, 0, 90);
        path.AddArc(x, y+h-2*r, 2*r, 2*r, 90, 90);
        path.CloseAllFigures();
        g.FillPath(b, path);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing"

$Global:AkilyaForm = New-Object System.Windows.Forms.Form
$Global:AkilyaForm.Text            = "AKILYA"
$Global:AkilyaForm.Size            = New-Object System.Drawing.Size(460, 310)
$Global:AkilyaForm.StartPosition   = "CenterScreen"
$Global:AkilyaForm.FormBorderStyle = "None"
$Global:AkilyaForm.TopMost         = $true
$Global:AkilyaForm.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)

# Перетаскивание окна мышью (без рамки)
$drag = $false; $dragPt = [System.Drawing.Point]::Empty
$Global:AkilyaForm.Add_MouseDown({ param($s,$e); if($e.Button -eq 'Left'){$script:drag=$true;$script:dragPt=$e.Location} })
$Global:AkilyaForm.Add_MouseMove({ param($s,$e); if($script:drag){$Global:AkilyaForm.Left+=$e.X-$script:dragPt.X;$Global:AkilyaForm.Top+=$e.Y-$script:dragPt.Y} })
$Global:AkilyaForm.Add_MouseUp({   $script:drag=$false })

# Тонкая рамка
$Global:AkilyaForm.Add_Paint({
    param($s,$e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50,52,65), 1)
    $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width-1, $s.Height-1)
    $pen.Dispose()
})

# Кнопка X
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = "×"
$btnClose.Size      = New-Object System.Drawing.Size(28, 28)
$btnClose.Location  = New-Object System.Drawing.Point(424, 6)
$btnClose.FlatStyle = "Flat"
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Font      = New-Object System.Drawing.Font("Segoe UI", 13)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(120,120,140)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
$btnClose.Cursor    = "Hand"
$btnClose.Add_Click({ $Global:AkilyaForm.Close() })
$Global:AkilyaForm.Controls.Add($btnClose)

# Иконка-кружок
$circle = New-Object System.Windows.Forms.Panel
$circle.Size     = New-Object System.Drawing.Size(70, 70)
$circle.Location = New-Object System.Drawing.Point(195, 28)
$circle.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
$circle.Add_Paint({
    param($s,$e)
    $g = $e.Graphics; $g.SmoothingMode = "AntiAlias"
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80,190,255), 2)
    $g.DrawEllipse($pen, 2, 2, 64, 64)
    $pen.Dispose()
    $inner = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40,100,180), 1)
    $g.DrawEllipse($inner, 8, 8, 52, 52)
    $inner.Dispose()
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = "Center"; $sf.LineAlignment = "Center"
    $f = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80,190,255))
    $g.DrawString("A", $f, $b, (New-Object System.Drawing.RectangleF(0,0,70,70)), $sf)
    $f.Dispose(); $b.Dispose(); $sf.Dispose()
})
$Global:AkilyaForm.Controls.Add($circle)

# Заголовок
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text      = "AKILYA"
$titleLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.AutoSize  = $false
$titleLabel.TextAlign = "MiddleCenter"
$titleLabel.Size      = New-Object System.Drawing.Size(460, 34)
$titleLabel.Location  = New-Object System.Drawing.Point(0, 108)
$Global:AkilyaForm.Controls.Add($titleLabel)

# Подзаголовок
$subLabel = New-Object System.Windows.Forms.Label
$subLabel.Text      = "Screenshare Checker"
$subLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$subLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 120)
$subLabel.AutoSize  = $false
$subLabel.TextAlign = "MiddleCenter"
$subLabel.Size      = New-Object System.Drawing.Size(460, 20)
$subLabel.Location  = New-Object System.Drawing.Point(0, 144)
$Global:AkilyaForm.Controls.Add($subLabel)

# Статус
$Global:AkilyaStatus = New-Object System.Windows.Forms.Label
$Global:AkilyaStatus.Text      = "Инициализация..."
$Global:AkilyaStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$Global:AkilyaStatus.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 180)
$Global:AkilyaStatus.AutoSize  = $false
$Global:AkilyaStatus.TextAlign = "MiddleCenter"
$Global:AkilyaStatus.Size      = New-Object System.Drawing.Size(460, 20)
$Global:AkilyaStatus.Location  = New-Object System.Drawing.Point(0, 190)
$Global:AkilyaForm.Controls.Add($Global:AkilyaStatus)

# Кастомный прогресс-бар
$Global:AkilyaBar          = New-Object FlatProgress
$Global:AkilyaBar.Location = New-Object System.Drawing.Point(40, 218)
$Global:AkilyaBar.Size     = New-Object System.Drawing.Size(380, 8)
$Global:AkilyaBar.Maximum  = 100
$Global:AkilyaBar.Value    = 0
$Global:AkilyaForm.Controls.Add($Global:AkilyaBar)

# Нижняя подпись
$footLabel = New-Object System.Windows.Forms.Label
$footLabel.Text      = "Код: $Code  |  $env:USERNAME"
$footLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$footLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 62, 75)
$footLabel.AutoSize  = $false
$footLabel.TextAlign = "MiddleCenter"
$footLabel.Size      = New-Object System.Drawing.Size(460, 18)
$footLabel.Location  = New-Object System.Drawing.Point(0, 274)
$Global:AkilyaForm.Controls.Add($footLabel)

$Global:AkilyaForm.Show()
$Global:AkilyaForm.Refresh()

function Show-Progress($percent, $label) {
    $Global:AkilyaStatus.Text  = $label
    $Global:AkilyaBar.Value    = [Math]::Min(100, [Math]::Max(0, $percent))
    $Global:AkilyaForm.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

Show-Progress 2 "Инициализация проверки..."
Write-Host "  Код проверки : $Code" -ForegroundColor White
Write-Host "  Код проверки : $Code" -ForegroundColor White
Write-Host "  Игрок        : $env:USERNAME" -ForegroundColor White
Write-Host "  Внимание: проверяются папка .minecraft, Prefetch, Recent," -ForegroundColor Yellow
Write-Host "  запущенные процессы и все диски. Отчёт уйдёт модератору." -ForegroundColor Yellow
Write-Host ""
Show-Progress 5 "Подготовка к сканированию..."
Start-Sleep -Seconds 2
Write-Host ""

Log "=== ОТЧЁТ | Код: $Code | Игрок: $env:USERNAME | ПК: $env:COMPUTERNAME | $(Get-Date) ==="

function Match-Keyword($text) {
    $low = $text.ToLower()
    foreach ($k in $Keywords) { if ($low.Contains($k)) { return $k } }
    return $null
}

# 4. Запущенные процессы
Show-Progress 10 "Проверка процессов"
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
Show-Progress 25 "Проверка .minecraft"
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
Show-Progress 40 "Проверка Prefetch"
Log "`n[3] Prefetch (за последние 7 дней)"
Get-ChildItem "C:\Windows\Prefetch\*.pf" | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        $m = Match-Keyword $_.Name
        if ($m) { Log "  ($m) $($_.Name) — $($_.LastWriteTime)" }
    }

# 7. Recent (недавние файлы)
Show-Progress 50 "Проверка недавних файлов"
Log "`n[4] Недавние файлы"
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -Filter *.lnk | ForEach-Object {
    $m = Match-Keyword $_.Name
    if ($m) { Log "  ($m) $($_.Name) — $($_.LastWriteTime)" }
}

# 8. Загрузки и рабочий стол
Show-Progress 60 "Проверка загрузок и рабочего стола"
Log "`n[5] Загрузки / Рабочий стол"
foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")) {
    Get-ChildItem $dir -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $m = Match-Keyword $_.Name
        if ($m) { Log "  ($m) $($_.FullName)" }
    }
}

# 9. Инжекты: подозрительные модули в процессах Java
Show-Progress 70 "Проверка инжектов в Java"
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
Show-Progress 80 "Сканирование всех дисков"
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

Show-Progress 95 "Формирование отчёта..."
Write-Host ""
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

    $tmp  = Join-Path $env:TEMP "payload_$Code.json"
    $resp = Join-Path $env:TEMP "resp_$Code.txt"
    [IO.File]::WriteAllText($tmp, $payload, (New-Object Text.UTF8Encoding $false))

    $sent = $false
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        # -w выводит HTTP-код, чтобы видеть реальный результат отправки
        $http = curl.exe -s -o $resp -w "%{http_code}" -X POST -F "payload_json=<$tmp" -F "file=@$path" $WebhookUrl
        Write-Host "Discord ответил кодом: $http" -ForegroundColor DarkGray
        if ($http -match '^2\d\d$') { $sent = $true }
        else { Write-Host "Ответ Discord: $(Get-Content $resp -Raw)" -ForegroundColor Yellow }
    } else {
        Write-Host "curl.exe не найден, отправляю без файла." -ForegroundColor Yellow
        try { Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json; charset=utf-8" -Body $payload | Out-Null; $sent = $true }
        catch { Write-Host "Ошибка отправки: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    Remove-Item $tmp, $resp -Force -ErrorAction SilentlyContinue

    if ($sent) { Write-Host "Отчёт отправлен модератору." -ForegroundColor Green }
    else { Write-Host "Не удалось отправить отчёт. Покажи файл вручную: $path" -ForegroundColor Red }
}

$hitTotal = @($report | Where-Object { $_ -match '^\s+(ПОДОЗРИТЕЛЬНО|ВНИМАНИЕ|Имя файла|Внутри|\()' }).Count
if ($hitTotal -gt 0) {
    $Global:AkilyaStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 90, 90)
    $Global:AkilyaStatus.Text = "Готово: найдено совпадений — $hitTotal"
} else {
    $Global:AkilyaStatus.ForeColor = [System.Drawing.Color]::FromArgb(90, 220, 130)
    $Global:AkilyaStatus.Text = "Готово: совпадений не найдено"
}
$Global:AkilyaBar.Value = 100
$Global:AkilyaForm.Refresh()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Seconds 4
$Global:AkilyaForm.Close()


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
