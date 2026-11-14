$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = 9666

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

# make sure the background watcher is alive
$watcher = Join-Path $InstallDir "watcher.ps1"
$running = $false
try {
  $running = [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$watcher*" } | Select-Object -First 1)
} catch { }
if (-not $running -and (Test-Path $watcher)) {
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", $watcher) `
    -WindowStyle Hidden
}

$exe = Get-CodexExe
if (-not $exe) {
  [System.Windows.Forms.MessageBox]::Show("没有找到 ChatGPT / Codex 桌面应用。请先安装桌面版。", "Spider-Verse Theme") | Out-Null
  exit 1
}

Start-Process -FilePath $exe -ArgumentList @(
  "--remote-debugging-port=9666",
  "--remote-allow-origins=http://127.0.0.1:9666"
)
