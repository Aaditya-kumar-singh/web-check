param(
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$healthUrl = 'http://127.0.0.1:3000/healthz'
$appUrl = 'http://127.0.0.1:3000/check'

function Test-WebCheckReady {
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    return $health.status -eq 'ok' -and $health.ready -eq $true
  } catch {
    return $false
  }
}

try {
  Set-Location $repo
  if (Test-WebCheckReady) {
    Write-Host 'Web-Check is already running.'
    if (-not $NoBrowser) { Start-Process $appUrl }
    exit 0
  }

  if (Get-NetTCPConnection -State Listen -LocalPort 3000 -ErrorAction SilentlyContinue) {
    throw 'Port 3000 is in use. Close the other app before starting Web-Check.'
  }

  $node = (Get-Command node.exe -ErrorAction Stop).Source
  $corepack = (Get-Command corepack -ErrorAction Stop).Source
  if (-not (Test-Path (Join-Path $repo 'public\favicon.ico'))) {
    throw 'Web-Check source files are missing.'
  }

  # Get upstream updates from your fork without overriding uncommitted work.
  if (-not (git status --porcelain)) {
    Write-Host 'Checking your GitHub fork for updates...'
    $env:GIT_TERMINAL_PROMPT = '0'
    git pull --ff-only origin master
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not update; using the existing local code.' }
  } else {
    Write-Warning 'Local changes found; skipping automatic Git update.'
  }

  $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
  if (-not (Test-Path $chrome)) { $chrome = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
  if (-not (Test-Path $chrome)) { throw 'Chrome or Edge is needed for browser-based checks.' }

  $env:CHROME_PATH = $chrome
  $env:CHROMIUM_BIN = $chrome
  $env:PUPPETEER_EXECUTABLE_PATH = $chrome
  $env:PUPPETEER_SKIP_DOWNLOAD = 'true'
  $env:HOST = '127.0.0.1'
  $env:PORT = '3000'
  $env:TRUST_PROXY = 'false'
  $env:API_ENABLE_RATE_LIMIT = 'true'
  $env:API_DISABLED_CHECKS = 'ports,trace-route'
  $env:API_CORS_ORIGIN = 'http://127.0.0.1:3000'

  $revision = (git rev-parse HEAD).Trim()
  $stamp = Join-Path $repo '.git\web-check-last-built'
  $builtRevision = if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { '' }
  if (-not (Test-Path 'node_modules') -or -not (Test-Path 'dist') -or $builtRevision -ne $revision) {
    Write-Host 'Installing dependencies and building Web-Check. The first start may take longer...'
    & $corepack yarn install --frozen-lockfile --non-interactive --network-timeout 120000
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    & $corepack yarn build
    if ($LASTEXITCODE -ne 0) { throw 'Web-Check build failed.' }
    Set-Content -Path $stamp -Value $revision -NoNewline
  }

  $logDir = Join-Path $repo 'logs'
  [void](New-Item -ItemType Directory -Path $logDir -Force)
  Write-Host 'Starting Web-Check locally on port 3000...'
  $process = Start-Process -FilePath $node -ArgumentList @('server.js') -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'web-check.out.log') -RedirectStandardError (Join-Path $logDir 'web-check.err.log')
  for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-WebCheckReady) {
      Write-Host 'Web-Check ready at' $appUrl -ForegroundColor Green
      if (-not $NoBrowser) { Start-Process $appUrl }
      exit 0
    }
    if ($process.HasExited) { break }
  }
  throw "Web-Check did not become ready. See $logDir for details."
} catch {
  Write-Host "Web-Check launcher error: $($_.Exception.Message)" -ForegroundColor Red
  if (-not $NoBrowser) { Read-Host 'Press Enter to close this window' | Out-Null }
  exit 1
}
