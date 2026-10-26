$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $projectRoot '.toolchains')) { . "$PSScriptRoot/Use-Toolchains.ps1" }
$binary = Join-Path $projectRoot 'target/debug/discovery-spike.exe'
if (-not (Test-Path -LiteralPath $binary)) { throw 'Build the discovery-spike binary first.' }
$logs = Join-Path $projectRoot 'local-evidence'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$advertiser = Start-Process -FilePath $binary -ArgumentList 'advertise' -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'advertiser.log') -RedirectStandardError (Join-Path $logs 'advertiser-error.log')
try {
    Start-Sleep -Seconds 1
    $raw = & $binary browse | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Real multicast browse failed.' }
    $snapshot = $raw | ConvertFrom-Json
    if ($snapshot.status -ne 'complete') { throw "Unexpected scan status: $($snapshot.status)" }
    $peers = @($snapshot.peers.PSObject.Properties | ForEach-Object { $_.Value })
    $testPeer = @($peers | Where-Object { $_.id -like "Mirquova-spike-$($advertiser.Id).*" })
    if ($testPeer.Count -eq 0) { throw 'No same-host announcement observed. Multicast may be blocked; this smoke test did not pass.' }
    if (@($testPeer | Where-Object { $_.verified -ne $false }).Count -gt 0) { throw 'Discovery incorrectly established trust.' }
    Write-Output "PASS real same-host mDNS: $($testPeer.Count) test candidate(s), all unverified. This is not a two-device test."
} finally {
    if (-not $advertiser.HasExited) { $advertiser.WaitForExit(17000) | Out-Null }
}
