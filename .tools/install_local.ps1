[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..'),
    [string]$WowRoot = 'C:\Program Files (x86)\World of Warcraft'
)

$ErrorActionPreference = 'Stop'
$gameVersions = @('_anniversary_', '_classic_', '_classic_era_', '_classic_era_ptr_')
$sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
$itemRackSource = Join-Path $sourceRootFull 'ItemRack'
$optionsSource = Join-Path $sourceRootFull 'ItemRackOptions'

function Get-SHA256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($algorithm.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Assert-DirectoryMirror {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $sourceFiles = @(
        Get-ChildItem -LiteralPath $Source -Recurse -File | ForEach-Object {
            $_.FullName.Substring($Source.Length + 1).Replace('\', '/')
        }
    )
    $targetFiles = @(
        Get-ChildItem -LiteralPath $Target -Recurse -File | ForEach-Object {
            $_.FullName.Substring($Target.Length + 1).Replace('\', '/')
        }
    )
    $difference = @(Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $targetFiles)
    if ($difference.Count -ne 0) {
        throw "Local deployment file manifest differs from its staged source: $Target"
    }
    foreach ($relativePath in $sourceFiles) {
        $sourcePath = Join-Path $Source ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        $targetPath = Join-Path $Target ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if ((Get-SHA256 -Path $sourcePath) -ne (Get-SHA256 -Path $targetPath)) {
            throw "Local deployment content differs from its staged source: $targetPath"
        }
    }
}

function Assert-ReleaseSourceManifest {
    param([Parameter(Mandatory = $true)][string]$Root)

    $commitManifest = Join-Path $Root 'SOURCE_COMMIT.txt'
    $fileManifest = Join-Path $Root 'SOURCE_FILES.sha256'
    if (-not (Test-Path -LiteralPath $commitManifest) -and -not (Test-Path -LiteralPath $fileManifest)) {
        return
    }
    if (-not (Test-Path -LiteralPath $commitManifest) -or -not (Test-Path -LiteralPath $fileManifest)) {
        throw "Release staging provenance is incomplete: $Root"
    }

    $expected = @{}
    foreach ($line in (Get-Content -LiteralPath $fileManifest)) {
        if ($line -notmatch '^([0-9a-fA-F]{64})  ((?:ItemRack|ItemRackOptions)/.+)$') {
            throw "Invalid release source manifest entry: $line"
        }
        $relativePath = $Matches[2]
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $Root ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))))
        $rootPrefix = $Root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Release source manifest escapes its staging directory: $relativePath"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Release source manifest references a missing file: $relativePath"
        }
        if ((Get-SHA256 -Path $fullPath) -ne $Matches[1].ToLowerInvariant()) {
            throw "Release staging content no longer matches its source manifest: $relativePath"
        }
        $expected[$relativePath] = $true
    }

    $actual = @(
        foreach ($addonPath in @((Join-Path $Root 'ItemRack'), (Join-Path $Root 'ItemRackOptions'))) {
            Get-ChildItem -LiteralPath $addonPath -Recurse -File | ForEach-Object {
                $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
            }
        }
    )
    if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { -not $expected.ContainsKey($_) }).Count -ne 0) {
        throw "Release staging file set no longer matches its source manifest: $Root"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $itemRackSource 'ItemRack.toc'))) {
    throw "Release source is missing ItemRack/ItemRack.toc: $sourceRootFull"
}
if (-not (Test-Path -LiteralPath (Join-Path $optionsSource 'ItemRackOptions.toc'))) {
    throw "Release source is missing ItemRackOptions/ItemRackOptions.toc: $sourceRootFull"
}
Assert-ReleaseSourceManifest -Root $sourceRootFull

$destinations = @(
    foreach ($versionFolder in $gameVersions) {
        $addOnsPath = [System.IO.Path]::GetFullPath((Join-Path $WowRoot (Join-Path $versionFolder 'Interface\AddOns')))
        if (Test-Path -LiteralPath $addOnsPath -PathType Container) {
            [pscustomobject]@{ VersionFolder = $versionFolder; AddOnsPath = $addOnsPath }
        }
    }
)

if ($destinations.Count -eq 0) {
    $checked = ($gameVersions | ForEach-Object {
        [System.IO.Path]::GetFullPath((Join-Path $WowRoot (Join-Path $_ 'Interface\AddOns')))
    }) -join ', '
    throw "No supported local WoW AddOns folders were found. Checked: $checked"
}

$completedDestinations = @()
$tocVersion = (Get-Content -LiteralPath (Join-Path $itemRackSource 'ItemRack.toc') |
    Select-String '^## Version:\s*(\S+)\s*$').Matches[0].Groups[1].Value

foreach ($destination in $destinations) {
    $addOnsPath = $destination.AddOnsPath

    $targets = @(
        @{ Name = 'ItemRack'; Source = $itemRackSource },
        @{ Name = 'ItemRackOptions'; Source = $optionsSource }
    )

    if ($PSCmdlet.ShouldProcess($addOnsPath, "Replace ItemRack and ItemRackOptions from $sourceRootFull")) {
        foreach ($entry in $targets) {
            $target = [System.IO.Path]::GetFullPath((Join-Path $addOnsPath $entry.Name))
            $addOnsPrefix = $addOnsPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
            if (-not $target.StartsWith($addOnsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to deploy outside the AddOns directory: $target"
            }

            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Copy-Item -LiteralPath $entry.Source -Destination $addOnsPath -Recurse -Force
            $expectedToc = Join-Path $target "$($entry.Name).toc"
            if (-not (Test-Path -LiteralPath $expectedToc)) {
                throw "Local deployment verification failed: $expectedToc was not created."
            }
            Assert-DirectoryMirror -Source $entry.Source -Target $target
        }
        $completedDestinations += $addOnsPath
    }
}

if (-not $WhatIfPreference -and $completedDestinations.Count -eq 0) {
    throw 'No local addon folders were deployed.'
}

$verb = if ($WhatIfPreference) { 'Would deploy' } else { 'Deployed' }
$reportedDestinations = if ($WhatIfPreference) { $destinations.AddOnsPath } else { $completedDestinations }
Write-Host "$verb ItemRack $tocVersion to:"
foreach ($destinationPath in $reportedDestinations) {
    Write-Host "  $destinationPath"
}
