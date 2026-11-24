param(
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$repo = 'Aaditya-kumar-singh/web-check'
$displayName = 'Web-Check'
$mutex = New-Object System.Threading.Mutex($false, 'Local\AadityaWebCheckStart')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Invoke-Gh {
  param([string[]]$Arguments)
  $result = & gh @Arguments
  if ($LASTEXITCODE -ne 0) { throw "GitHub CLI failed: $($Arguments -join ' ')" }
  return $result
}

try {
  Get-Command gh -ErrorAction Stop | Out-Null
  Write-Host 'Connecting to GitHub Codespaces...'
  # The first run needs the user's approval for the Codespaces OAuth scope.
  $ErrorActionPreference = 'Continue'
  & gh api user/codespaces --jq '.total_count' 2>$null | Out-Null
  $hasAccess = $LASTEXITCODE -eq 0
  $ErrorActionPreference = 'Stop'
  if (-not $hasAccess) {
    if ($NoBrowser) { throw 'Authorize Codespaces with: gh auth refresh -h github.com -s codespace' }
    Write-Host 'Authorize GitHub Codespaces in the browser to continue.'
    & gh auth refresh -h github.com -s codespace
    if ($LASTEXITCODE -ne 0) { throw 'Codespaces authorization was not completed.' }
  }

  $spaces = Invoke-Gh -Arguments @('api','--paginate','user/codespaces','--jq','.codespaces[] | [.repository.full_name,.display_name,.name] | @tsv')
  $name = $spaces | ForEach-Object { $fields = $_ -split "`t"; if ($fields[0] -eq $repo -and $fields[1] -eq $displayName) { $fields[2] } } | Select-Object -First 1
  if (-not $name) {
    if ($NoBrowser) { throw 'No Web-Check Codespace exists yet.' }
    Write-Host 'Creating a Codespace uses your GitHub compute and storage quota.'
    if ((Read-Host 'Create one remote machine now? [y/N]') -ne 'y') { exit 0 }
    $repoId = Invoke-Gh -Arguments @('api',"repos/$repo",'--jq','.id')
    $machine = Invoke-Gh -Arguments @('api',"repos/$repo/codespaces/machines",'--jq','.machines | sort_by(.cpus, .memory_in_bytes) | .[0].name')
    if (-not $machine -or $machine -eq 'null') { throw 'No Codespaces machine is available for this repository.' }
    $name = Invoke-Gh -Arguments @('api','--method','POST','user/codespaces','-F',"repository_id=$repoId",'-f','ref=master','-f',"machine=$machine",'-f',"display_name=$displayName",'-F','idle_timeout_minutes=10','--jq','.name')
  }

  $state = Invoke-Gh -Arguments @('api',"user/codespaces/$name",'--jq','.state')
  if ($state -eq 'Shutdown') {
    Invoke-Gh -Arguments @('api','--method','POST',"user/codespaces/$name/start",'--jq','.state') | Out-Null
  }
  for ($i=0; $i -lt 120; $i++) {
    $state = Invoke-Gh -Arguments @('api',"user/codespaces/$name",'--jq','.state')
    if ($state -eq 'Available') { break }
    if ($state -in @('Failed','Deleted','Archived','Unavailable')) { throw "Codespace is $state." }
    Start-Sleep -Seconds 5
  }
  if ($state -ne 'Available') { throw "Codespace is not ready: $state." }

  # Resolve the private origin first: SSH does not inherit Codespaces metadata.
  $port = (Invoke-Gh -Arguments @('codespace','ports','-c',$name,'--json','sourcePort,browseUrl,visibility') | ConvertFrom-Json) | Where-Object sourcePort -eq 3000 | Select-Object -First 1
  if (-not $port -or $port.visibility -ne 'private') { throw 'GitHub did not return a private port 3000.' }
  $uri = [uri]$port.browseUrl
  $prefix = $name + '-3000.'
  if ($name -notmatch '^[a-z0-9-]+$' -or $uri.Scheme -ne 'https' -or -not $uri.Host.StartsWith($prefix)) { throw 'Invalid Codespaces port URL.' }
  $domain = $uri.Host.Substring($prefix.Length)
  if ($domain -notmatch '^[a-z0-9.-]+$') { throw 'Invalid forwarding domain.' }

  Write-Host 'Building or starting Web-Check on the GitHub machine...'
  & gh codespace ssh -c $name -- "CODESPACE_NAME=$name GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=$domain bash /workspaces/web-check/.devcontainer/start.sh"
  if ($LASTEXITCODE -ne 0) { throw 'Remote Web-Check did not start.' }
  $url = $uri.GetLeftPart([UriPartial]::Authority) + '/check'
  Write-Host "Web-Check ready: $url"
  if (-not $NoBrowser) { Start-Process $url }
} catch {
  Write-Host "Web-Check launcher error: $($_.Exception.Message)" -ForegroundColor Red
  if (-not $NoBrowser) { Read-Host 'Press Enter to close this window' | Out-Null }
  exit 1
} finally {
  $mutex.ReleaseMutex()
  $mutex.Dispose()
}
