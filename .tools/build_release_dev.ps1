[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+(?:\.\d+)?(?:-beta\d+)?$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref,

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
        throw "Refusing to write outside the intended directory: $Child"
    }
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& git -C $repoRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return $output
}

function Read-RefFile {
    param(
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$Path
    )

    return (Invoke-Git -Arguments @('show', "${Commit}:$Path")) -join "`n"
}

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

Assert-ChildPath -Child $outputRootFull -Parent $repoRoot

$commitOutput = @(Invoke-Git -Arguments @('rev-parse', '--verify', "$Ref^{commit}"))
$commit = ([string]$commitOutput[0]).Trim()
if ($commit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Ref '$Ref' did not resolve to a full commit ID."
}

foreach ($tocPath in @('ItemRack/ItemRack.toc', 'ItemRackOptions/ItemRackOptions.toc')) {
    $tocContent = Read-RefFile -Commit $commit -Path $tocPath
    $versionMatch = [regex]::Match($tocContent, '(?m)^## Version:\s*(\S+)\s*$')
    if (-not $versionMatch.Success -or $versionMatch.Groups[1].Value -ne $Version) {
        throw "$tocPath at $commit does not identify release version $Version."
    }
}

$releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $outputRootFull 'Release'))
$releasePath = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot "v$Version"))
$compressedPath = [System.IO.Path]::GetFullPath((Join-Path $outputRootFull 'Compressed'))
$zipPath = [System.IO.Path]::GetFullPath((Join-Path $compressedPath "ItemRack-anniversary-$Version.zip"))
$hashPath = "$zipPath.sha256"
$temporarySuffix = [Guid]::NewGuid().ToString('N')
$temporaryReleasePath = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot ".v$Version.$temporarySuffix.tmp"))
$temporaryZipPath = [System.IO.Path]::GetFullPath((Join-Path $compressedPath ".ItemRack-anniversary-$Version.$temporarySuffix.tmp.zip"))

foreach ($candidate in @($releasePath, $temporaryReleasePath)) {
    Assert-ChildPath -Child $candidate -Parent $releaseRoot
}
foreach ($candidate in @($zipPath, $hashPath, $temporaryZipPath)) {
    Assert-ChildPath -Child $candidate -Parent $compressedPath
}

New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
New-Item -ItemType Directory -Path $compressedPath -Force | Out-Null

try {
    Invoke-Git -Arguments @(
        '-c', 'core.autocrlf=false',
        'archive', '--format=zip', "--output=$temporaryZipPath", $commit, '--', 'ItemRack', 'ItemRackOptions'
    ) | Out-Null
    New-Item -ItemType Directory -Path $temporaryReleasePath -Force | Out-Null
    Expand-Archive -LiteralPath $temporaryZipPath -DestinationPath $temporaryReleasePath -Force

    $expectedFiles = @{}
    foreach ($line in (Invoke-Git -Arguments @('ls-tree', '-r', $commit, '--', 'ItemRack', 'ItemRackOptions'))) {
        if ($line -notmatch '^\d+\s+blob\s+([0-9a-fA-F]+)\t(.+)$') {
            throw "Unsupported entry in release tree: $line"
        }
        $expectedFiles[$Matches[2]] = $Matches[1].ToLowerInvariant()
    }
    if ($expectedFiles.Count -eq 0) {
        throw "Commit $commit contains no addon files."
    }

    $stagedFiles = @(
        Get-ChildItem -LiteralPath $temporaryReleasePath -Recurse -File | ForEach-Object {
            $_.FullName.Substring($temporaryReleasePath.Length + 1).Replace('\', '/')
        }
    )
    if ($stagedFiles.Count -ne $expectedFiles.Count) {
        throw "Archive file count $($stagedFiles.Count) does not match commit tree count $($expectedFiles.Count)."
    }

    foreach ($relativePath in $stagedFiles) {
        if (-not $expectedFiles.ContainsKey($relativePath)) {
            throw "Archive contains a file not present in commit $commit`: $relativePath"
        }
        $fullPath = Join-Path $temporaryReleasePath ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        # core.autocrlf is disabled for the archive, so compare its raw bytes
        # directly with the committed blob rather than with the mutable checkout.
        $blobHashOutput = @(Invoke-Git -Arguments @('hash-object', '--no-filters', '--', $fullPath))
        $blobHash = ([string]$blobHashOutput[0]).Trim().ToLowerInvariant()
        if ($blobHash -ne $expectedFiles[$relativePath]) {
            throw "Archive content differs from commit $commit`: $relativePath"
        }
    }

    if (Test-Path -LiteralPath $releasePath) {
        Remove-Item -LiteralPath $releasePath -Recurse -Force
    }
    Move-Item -LiteralPath $temporaryReleasePath -Destination $releasePath

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Move-Item -LiteralPath $temporaryZipPath -Destination $zipPath

    $treeManifest = $expectedFiles.GetEnumerator() |
        Sort-Object -Property Name |
        ForEach-Object { "$($_.Value)  $($_.Name)" }
    @(
        "ref=$Ref"
        "commit=$commit"
    ) | Set-Content -LiteralPath (Join-Path $releasePath 'SOURCE_COMMIT.txt') -Encoding ascii
    $treeManifest | Set-Content -LiteralPath (Join-Path $releasePath 'SOURCE_TREE.txt') -Encoding ascii

    $fileHashManifest = foreach ($relativePath in ($expectedFiles.Keys | Sort-Object)) {
        $fullPath = Join-Path $releasePath ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        "$(Get-SHA256 -Path $fullPath)  $relativePath"
    }
    $fileHashManifest | Set-Content -LiteralPath (Join-Path $releasePath 'SOURCE_FILES.sha256') -Encoding ascii

    $hash = Get-SHA256 -Path $zipPath
    "$hash  $(Split-Path -Leaf $zipPath)" | Set-Content -LiteralPath $hashPath -Encoding ascii

    Write-Host "Release source ref: $Ref"
    Write-Host "Release source commit: $commit"
    Write-Host "Verified addon files: $($expectedFiles.Count)"
    Write-Host "Release staging: $releasePath"
    Write-Host "Release archive: $zipPath"
    Write-Host "SHA-256 file: $hashPath"
} finally {
    if (Test-Path -LiteralPath $temporaryReleasePath) {
        Remove-Item -LiteralPath $temporaryReleasePath -Recurse -Force
    }
    if (Test-Path -LiteralPath $temporaryZipPath) {
        Remove-Item -LiteralPath $temporaryZipPath -Force
    }
}
