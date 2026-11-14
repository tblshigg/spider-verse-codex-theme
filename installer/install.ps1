param(
  [switch]$NoShortcuts,
  [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"
$Source = $PSScriptRoot
$InstallDir = Join-Path $env:LOCALAPPDATA "SpiderVerseCodexTheme"
$Port = 9666
$PsExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Startup = [Environment]::GetFolderPath("Startup")
$Desktop = [Environment]::GetFolderPath("Desktop")
$Programs = [Environment]::GetFolderPath("Programs")

function Write-Step([string]$Text) { Write-Host "  $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  $Text" -ForegroundColor Yellow }

function Get-CodexExe {
  $pkg = Get-AppxPackage -Name "OpenAI.Codex" | Select-Object -First 1
  if ($pkg) {
    foreach ($name in @("ChatGPT.exe", "Codex.exe")) {
      $p = Join-Path (Join-Path $pkg.InstallLocation "app") $name
      if (Test-Path $p) { return $p }
    }
  }
  $hit = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter "ChatGPT.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return $null
}

function Test-Port {
  try {
    $null = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 1
    return $true
  } catch { return $false }
}

function New-Shortcut([string]$Path, [string]$Script, [string]$Description) {
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut($Path)
  $lnk.TargetPath = $PsExe
  $lnk.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Script + '"'
  $lnk.WorkingDirectory = $InstallDir
  $lnk.IconLocation = (Join-Path $InstallDir "spiderverse.ico")
  $lnk.Description = $Description
  $lnk.WindowStyle = 7
  $lnk.Save()
}

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Magenta
Write-Host "     SPIDER-VERSE THEME  /  CHATGPT + CODEX" -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor Magenta
Write-Host ""

$exe = Get-CodexExe
if (-not $exe) {
  Write-Warn "没有找到 ChatGPT / Codex 桌面应用。"
  Write-Host "  请先安装桌面版，再运行本安装器。" -ForegroundColor Gray
  Read-Host "  按 Enter 退出"
  exit 1
}

Write-Step "检查安装目录..."
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item (Join-Path $Source "payload\codex_payload.js") (Join-Path $InstallDir "codex_payload.js") -Force
Copy-Item (Join-Path $Source "watcher\watcher.ps1") (Join-Path $InstallDir "watcher.ps1") -Force
Copy-Item (Join-Path $Source "launch.ps1") (Join-Path $InstallDir "launch.ps1") -Force
Copy-Item (Join-Path $Source "spiderverse.ico") (Join-Path $InstallDir "spiderverse.ico") -Force
Write-Ok "主题文件已复制到 $InstallDir"

Write-Step "停止旧版后台进程..."
Get-CimInstance Win32_Process | Where-Object {
  ($_.Name -eq "node.exe" -and $_.CommandLine -like "*codex_watcher.js*") -or
  ($_.Name -eq "powershell.exe" -and $_.CommandLine -like "*SpiderVerseCodexTheme*watcher.ps1*")
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
try { Unregister-ScheduledTask -TaskName "SpiderVerse Codex Theme" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
Write-Ok "旧版进程已清理"

Write-Step "注册开机自动恢复..."
$startupLnk = Join-Path $Startup "SpiderVerse Codex Theme.lnk"
New-Shortcut -Path $startupLnk -Script (Join-Path $InstallDir "watcher.ps1") -Description "Keep the Spider-Verse theme applied to ChatGPT / Codex"
Write-Ok "已加入启动项"

if (-not $NoShortcuts) {
  Write-Step "创建主题启动快捷方式..."
  $desktopLnk = Join-Path $Desktop "ChatGPT · Spider-Verse.lnk"
  $startLnk = Join-Path $Programs "ChatGPT · Spider-Verse.lnk"
  New-Shortcut -Path $desktopLnk -Script (Join-Path $InstallDir "launch.ps1") -Description "Open ChatGPT with the Spider-Verse theme"
  New-Shortcut -Path $startLnk -Script (Join-Path $InstallDir "launch.ps1") -Description "Open ChatGPT with the Spider-Verse theme"
  Write-Ok "桌面和开始菜单快捷方式已创建"
}

Write-Step "启动后台守护..."
Start-Process -FilePath $PsExe -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $InstallDir "watcher.ps1")) -WindowStyle Hidden
Start-Sleep -Milliseconds 800

if (-not (Test-Port)) {
  Write-Step "需要让 ChatGPT 以主题模式启动..."
  $proc = Get-Process ChatGPT, Codex -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  $restart = $true
  if ($proc) {
    if ($SkipRestart) {
      $restart = $false
    } else {
      Write-Host ""
      Write-Warn "ChatGPT 正在运行，需要重启一次才能应用主题。"
      $ans = Read-Host "  现在重启？输入 Y 继续，其他键跳过 (Y/n)"
      if ($ans -and $ans -notmatch "^[Yy]") { $restart = $false }
    }
    if ($restart) {
      Write-Step "正在重启 ChatGPT..."
      try { $proc.CloseMainWindow() | Out-Null } catch { }
      Start-Sleep -Seconds 2
      Get-Process ChatGPT, Codex -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 1
    }
  }
  if ($restart) {
    Start-Process -FilePath $exe -ArgumentList @("--remote-debugging-port=9666", "--remote-allow-origins=http://127.0.0.1:9666")
    Write-Step "等待 ChatGPT 启动..."
    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
      Start-Sleep -Milliseconds 500
      if (Test-Port) { $ok = $true; break }
    }
    if (-not $ok) {
      Write-Warn "等待超时。请从桌面/开始菜单打开 “ChatGPT · Spider-Verse” 再试。"
    }
  }
}

if (Test-Port) {
  Write-Step "应用主题..."
  try {
    & $PsExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallDir "watcher.ps1") -Once | Out-Null
    Start-Sleep -Seconds 2
    Write-Ok "主题已应用"
  } catch {
    Write-Warn "主题注入未确认，请打开主题快捷方式后等待几秒。"
  }
} else {
  Write-Warn "ChatGPT 还没有以主题模式运行。"
  Write-Host "  请从桌面或开始菜单打开 “ChatGPT · Spider-Verse”。" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "     安装完成" -ForegroundColor White
Write-Host "     以后从 “ChatGPT · Spider-Verse” 打开即可" -ForegroundColor Gray
Write-Host "     右下角 SV THEME / Alt+Shift+S 可开关主题" -ForegroundColor Gray
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Read-Host "  按 Enter 退出"
