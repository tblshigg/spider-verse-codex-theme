$ErrorActionPreference = "SilentlyContinue"
$InstallDir = Join-Path $env:LOCALAPPDATA "SpiderVerseCodexTheme"
$Startup = [Environment]::GetFolderPath("Startup")
$Desktop = [Environment]::GetFolderPath("Desktop")
$Programs = [Environment]::GetFolderPath("Programs")
$PsExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

Clear-Host
Write-Host ""
Write-Host "  Spider-Verse Theme - 卸载" -ForegroundColor Magenta
Write-Host ""

# remove theme from the running app first
$watcher = Join-Path $InstallDir "watcher.ps1"
if ((Test-Path $watcher) -and (Test-Path $InstallDir)) {
  & $PsExe -NoProfile -ExecutionPolicy Bypass -File $watcher -Clean | Out-Null
}

# stop watchers
Get-CimInstance Win32_Process | Where-Object {
  ($_.Name -eq "node.exe" -and $_.CommandLine -like "*codex_watcher.js*") -or
  ($_.Name -eq "powershell.exe" -and $_.CommandLine -like "*SpiderVerseCodexTheme*watcher.ps1*")
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# remove startup / shortcuts / task
Remove-Item (Join-Path $Startup "SpiderVerse Codex Theme.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Desktop "ChatGPT · Spider-Verse.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Programs "ChatGPT · Spider-Verse.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Desktop "Spider-Verse ChatGPT.lnk") -Force -ErrorAction SilentlyContinue
try { Unregister-ScheduledTask -TaskName "SpiderVerse Codex Theme" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }

# remove installed files
Start-Sleep -Milliseconds 300
Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "  已卸载。ChatGPT 重启后会恢复原来的界面。" -ForegroundColor Green
Write-Host ""
Read-Host "  按 Enter 退出"
