param(
  [switch]$Once,
  [switch]$Clean,
  [int]$Port = 9666
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadPath = Join-Path $Root "codex_payload.js"
$LogPath = Join-Path $Root "watcher.log"

function Write-Log([string]$Message) {
  try {
    if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 200000)) {
      Set-Content -Path $LogPath -Value "" -Encoding UTF8
    }
    $line = "[{0}] {1}" -f (Get-Date).ToString("s"), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
  } catch { }
}

function Get-CodexTarget {
  try {
    $json = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json" -f $Port) -TimeoutSec 2
    return @($json) | Where-Object { $_.type -eq "page" -and $_.url -eq "app://-/index.html" } | Select-Object -First 1
  } catch {
    return $null
  }
}

function Invoke-CdpEvaluate {
  param(
    [string]$WsUrl,
    [string]$Expression
  )
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ct = [System.Threading.CancellationToken]::None
  try {
    [void]$ws.ConnectAsync([Uri]$WsUrl, $ct).GetAwaiter().GetResult()
    $msg = @{
      id = 1
      method = "Runtime.evaluate"
      params = @{
        expression = $Expression
        returnByValue = $true
        awaitPromise = $true
      }
    } | ConvertTo-Json -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    [void]$ws.SendAsync(
      [ArraySegment[byte]]::new($bytes),
      [System.Net.WebSockets.WebSocketMessageType]::Text,
      $true,
      $ct
    ).GetAwaiter().GetResult()

    $buffer = New-Object byte[] 65536
    $sb = [System.Text.StringBuilder]::new()
    do {
      $result = $ws.ReceiveAsync([ArraySegment[byte]]::new($buffer), $ct).GetAwaiter().GetResult()
      if ($result.Count -gt 0) {
        [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
      }
    } until ($result.EndOfMessage)

    $response = $sb.ToString() | ConvertFrom-Json
    if ($response.result -and $response.result.result) {
      return $response.result.result.value
    }
    return $null
  } finally {
    try { $ws.Dispose() } catch { }
  }
}

function Invoke-Tick {
  $target = Get-CodexTarget
  if (-not $target -or -not $target.webSocketDebuggerUrl) { return }
  $state = Invoke-CdpEvaluate -WsUrl $target.webSocketDebuggerUrl -Expression "localStorage.getItem('sv-codex-disabled')==='1'?'disabled':(document.querySelector('#sv-codex-theme')?'present':'missing')"
  if ($state -eq "missing") {
    $payload = Get-Content -Path $PayloadPath -Raw -Encoding UTF8
    [void](Invoke-CdpEvaluate -WsUrl $target.webSocketDebuggerUrl -Expression $payload)
    Write-Log "theme injected"
  }
}

if ($Clean) {
  try {
    $target = Get-CodexTarget
    if ($target) {
      $cleanup = "(()=>{for(const id of ['sv-codex-theme','sv-codex-toggle','sv-codex-style','sv-codex-winctl']){const e=document.getElementById(id);if(e)e.remove();}document.documentElement.classList.remove('sv-codex-on');document.querySelectorAll('canvas[data-sv-hidden]').forEach(c=>{c.style.display='';c.removeAttribute('data-sv-hidden')});return 'cleared';})()"
      [void](Invoke-CdpEvaluate -WsUrl $target.webSocketDebuggerUrl -Expression $cleanup)
    }
  } catch { }
  exit 0
}

if ($Once) {
  try {
    Invoke-Tick
    $target = Get-CodexTarget
    if ($target) {
      $state = Invoke-CdpEvaluate -WsUrl $target.webSocketDebuggerUrl -Expression "localStorage.getItem('sv-codex-disabled')==='1'?'disabled':(document.querySelector('#sv-codex-theme')?'present':'missing')"
      Write-Output ("target=ok state=" + $state)
    } else {
      Write-Output "target=missing"
    }
  } catch {
    Write-Output ("error=" + $_.Exception.Message)
    Write-Log ("once error: " + $_.Exception.Message)
  }
  exit 0
}

Write-Log "watcher started"
while ($true) {
  try { Invoke-Tick } catch {
    $msg = $_.Exception.Message
    if ($msg -notmatch "Unable to connect|connection|timed out|refused|remote party|0x") {
      Write-Log ("error: " + $msg)
    }
  }
  Start-Sleep -Seconds 5
}
