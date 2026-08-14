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

if (-not (Test-Path -LiteralPath (Join-Path $itemRackSource 'ItemRack.toc'))) {
    throw "Release source is missing ItemRack/ItemRack.toc: $sourceRootFull"
}
if (-not (Test-Path -LiteralPath (Join-Path $optionsSource 'ItemRackOptions.toc'))) {
    throw "Release source is missing ItemRackOptions/ItemRackOptions.toc: $sourceRootFull"
}

foreach ($versionFolder in $gameVersions) {
    $addOnsPath = Join-Path $WowRoot (Join-Path $versionFolder 'Interface\AddOns')
    if (-not (Test-Path -LiteralPath $addOnsPath)) {
        continue
    }

    $targets = @(
        @{ Name = 'ItemRack'; Source = $itemRackSource },
        @{ Name = 'ItemRackOptions'; Source = $optionsSource }
    )

    foreach ($entry in $targets) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $addOnsPath $entry.Name))
        $addOnsPrefix = [System.IO.Path]::GetFullPath($addOnsPath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $target.StartsWith($addOnsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to deploy outside the AddOns directory: $target"
        }

        if ($PSCmdlet.ShouldProcess($target, "Replace with $($entry.Source)")) {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Copy-Item -LiteralPath $entry.Source -Destination $addOnsPath -Recurse -Force
            $expectedToc = Join-Path $target "$($entry.Name).toc"
            if (-not (Test-Path -LiteralPath $expectedToc)) {
                throw "Local deployment verification failed: $expectedToc was not created."
            }
        }
    }

    $verb = if ($WhatIfPreference) { 'Validated deployment of' } else { 'Deployed' }
    Write-Host "$verb ItemRack $((Get-Content -LiteralPath (Join-Path $itemRackSource 'ItemRack.toc') | Select-String '^## Version:').Line) to $versionFolder"
}
