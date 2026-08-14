[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+(?:\.\d+)?(?:-beta\d+)?$')]
    [string]$Version,

    [string]$OutputRoot = '.versions'
)

$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRootFull = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Child,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $parentPrefix = $Parent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Child.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside the repository: $Child"
    }
}

Assert-ChildPath -Child $outputRootFull -Parent $repoRoot

$itemRackSource = Join-Path $repoRoot 'ItemRack'
$optionsSource = Join-Path $repoRoot 'ItemRackOptions'
if (-not (Test-Path -LiteralPath (Join-Path $itemRackSource 'ItemRack.toc'))) {
    throw 'ItemRack/ItemRack.toc was not found. Run this script from the repository checkout.'
}
if (-not (Test-Path -LiteralPath (Join-Path $optionsSource 'ItemRackOptions.toc'))) {
    throw 'ItemRackOptions/ItemRackOptions.toc was not found.'
}

foreach ($tocPath in @(
    (Join-Path $itemRackSource 'ItemRack.toc'),
    (Join-Path $optionsSource 'ItemRackOptions.toc')
)) {
    $versionLine = Get-Content -LiteralPath $tocPath | Select-String '^## Version:\s*(\S+)\s*$'
    if (-not $versionLine -or $versionLine.Matches[0].Groups[1].Value -ne $Version) {
        throw "$tocPath does not identify release version $Version."
    }
}

$releaseRoot = Join-Path $outputRootFull 'Release'
$releasePath = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot "v$Version"))
$compressedPath = Join-Path $outputRootFull 'Compressed'
$zipPath = Join-Path $compressedPath "ItemRack-anniversary-$Version.zip"
$hashPath = "$zipPath.sha256"

Assert-ChildPath -Child $releasePath -Parent $releaseRoot
Assert-ChildPath -Child $zipPath -Parent $compressedPath

if (Test-Path -LiteralPath $releasePath) {
    Remove-Item -LiteralPath $releasePath -Recurse -Force
}
New-Item -ItemType Directory -Path $releasePath -Force | Out-Null
New-Item -ItemType Directory -Path $compressedPath -Force | Out-Null

Copy-Item -LiteralPath $itemRackSource -Destination $releasePath -Recurse -Force
Copy-Item -LiteralPath $optionsSource -Destination $releasePath -Recurse -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
if (Test-Path -LiteralPath $hashPath) {
    Remove-Item -LiteralPath $hashPath -Force
}

$pathsToCompress = @(
    (Join-Path $releasePath 'ItemRack'),
    (Join-Path $releasePath 'ItemRackOptions')
)
Compress-Archive -LiteralPath $pathsToCompress -DestinationPath $zipPath -CompressionLevel Optimal

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
"$hash  $(Split-Path -Leaf $zipPath)" | Set-Content -LiteralPath $hashPath -Encoding ascii

Write-Host "Release staging: $releasePath"
Write-Host "Release archive: $zipPath"
Write-Host "SHA-256 file: $hashPath"
