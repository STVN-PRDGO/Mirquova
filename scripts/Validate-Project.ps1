$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$required = @('README.md', 'docs/project-analysis.md', 'docs/environment-check.md', 'docs/rea-findings.md', 'docs/implementation-roadmap.md', 'docs/acceptance.md', 'docs/source-manifest.json')
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
        throw "Missing preparation file: $relative"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'docs/source-manifest.json') -Raw | ConvertFrom-Json
if (@($manifest).Count -ne 5) { throw 'Expected exactly five source documents.' }
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'docs/source')) + [IO.Path]::DirectorySeparatorChar
$seen = @{}
foreach ($entry in $manifest) {
    $destination = [IO.Path]::GetFullPath((Join-Path $projectRoot $entry.projectPath))
    if (-not $destination.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Source path escapes docs/source.' }
    if ($seen.ContainsKey($destination)) { throw 'Duplicate source manifest entry.' }
    $seen[$destination] = $true
    $actual = Get-FileHash -LiteralPath $destination -Algorithm SHA256
    if ($actual.Hash -ne $entry.sha256) { throw "Source integrity failure: $($entry.projectPath)" }
    Write-Output "PASS source integrity: $($entry.projectPath)"
}
if (@(Get-ChildItem -LiteralPath $sourceRoot -File).Count -ne 5) { throw 'Unexpected source document count.' }
Write-Output 'PASS preparation files present; five source document hashes match. This check covers source-document integrity only.'
