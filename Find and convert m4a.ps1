<#
.SYNOPSIS
Search for .m4a files and report whether the primary audio stream is AAC, ALAC, or Other.

.REQUIREMENTS
ffprobe (from ffmpeg) must be available in PATH.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = '.',

    [switch]$Recurse,

    [switch]$CsvOutput,

    [string]$OutFile
    ,
    [switch]$Convert,
    [switch]$KeepOriginal,
    [string]$OutputDir,
    [ValidateSet('aac', 'alac', 'same')]
    [string]$Target = 'same',
    [switch]$Force,
    [switch]$DryRun
)



# Ensure ffprobe is available
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Error "ffprobe not found. Install ffmpeg and ensure ffprobe is in PATH."
    exit 2
}

# Collect files
$searchParams = @{
    Path   = $Path
    Filter = '*.m4a'
    File   = $true
}
if ($Recurse) { $searchParams.Recurse = $true }

$files = Get-ChildItem @searchParams

if (-not $files) {
    Write-Output "No .m4a files found in '$Path'."
    exit 0
}

$results = foreach ($f in $files) {
    # Get codec of the first audio stream
    $codec = (& ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 -- "$($f.FullName)" ) 2>$null

    if ($null -eq $codec -or $codec -eq '') {
        $codec = 'Unknown'
        $type = 'No audio / Unknown'
    }
    else {
        $codec = $codec.Trim()
        if ($codec -match 'alac') { $type = 'ALAC' }
        elseif ($codec -match 'aac') { $type = 'AAC' }
        else { $type = 'Other' }
    }

    [PSCustomObject]@{
        File  = $f.FullName
        Codec = $codec
        Type  = $type
    }
}

# If conversion requested, perform re-encoding based on detected codec
if ($Convert) {
    if ($OutputDir) {
        if (-not (Test-Path -Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir | Out-Null
        }
        $outRoot = (Get-Item -LiteralPath $OutputDir).FullName
    }
    else {
        $outRoot = $Path
    }

    foreach ($row in $results) {
        $src = $row.File
        $detected = ($row.Codec -as [string])
        if ($detected) { $detected = $detected.ToLower() } else { $detected = 'unknown' }

        # Decide effective target (either explicit or same-as-detected)
        switch ($Target) {
            'aac' { $effective = 'aac' }
            'alac' { $effective = 'alac' }
            'same' {
                if ($detected -match 'alac') { $effective = 'alac' }
                elseif ($detected -match 'aac') { $effective = 'aac' }
                else { $effective = 'aac' }
            }
        }

        # Skip conversion if same as detected and not forced
        if (-not $Force -and ($detected -ne 'unknown') -and (($effective -eq 'aac' -and $detected -match 'aac') -or ($effective -eq 'alac' -and $detected -match 'alac'))) {
            Write-Verbose "Skipping $src because detected codec '$detected' matches target '$effective' (use -Force to override)"
            continue
        }

        $srcFile = Get-Item -LiteralPath $src
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcFile.Name)
        $outFile = Join-Path $outRoot ($baseName + '.m4a')

        # Manage collisions / in-place overwrite
        $useTemp = $false
        if ((Get-Item -LiteralPath $outFile -ErrorAction SilentlyContinue) -and ($srcFile.FullName -eq (Get-Item -LiteralPath $outFile).FullName) -and $KeepOriginal) {
            $outFile = Join-Path $outRoot ($baseName + '_converted.m4a')
        }
        elseif ($srcFile.FullName -eq $outFile -and -not $KeepOriginal) {
            $useTemp = $true
            $outFile = Join-Path $srcFile.DirectoryName ([System.IO.Path]::GetRandomFileName() + '.m4a')
        }

        # Build ffmpeg args
        if ($effective -eq 'aac') {
            # Prefer libfdk_aac if available
            $ffmpegEnc = 'aac'
            try {
                $encList = (& ffmpeg -hide_banner -encoders 2>&1) -join "`n"
                if ($encList -match 'libfdk_aac') { $ffmpegEnc = 'libfdk_aac' }
            }
            catch {
                $ffmpegEnc = 'aac'
            }
            $audioArgs = @('-c:a', $ffmpegEnc, '-b:a', '256k')
        }
        else {
            $audioArgs = @('-c:a', 'alac')
        }

        $ffmpegArgs = @('-y', '-i', $src, '-vn') + $audioArgs + @('-movflags', 'use_metadata_tags', $outFile)

        Write-Output "Converting:`n  Source: $src`n  Detected codec: $detected -> target: $effective`n  Output: $outFile"

        if ($DryRun) {
            $quotedArgs = $ffmpegArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
            Write-Output "DRY RUN: ffmpeg " + ($quotedArgs -join ' ')
            continue
        }
        else {
            try {
                & ffmpeg @ffmpegArgs
                $code = $LASTEXITCODE
            }
            catch {
                Write-Warning "ffmpeg invocation failed for $src: $($_)"
                continue
            }

            if ($code -ne 0) {
                Write-Warning "ffmpeg failed for $src (exit $code). Skipping."
                continue
            }
        }

        if ($useTemp) {
            try {
                Move-Item -LiteralPath $outFile -Destination $src -Force
            }
            catch {
                Write-Warning "Failed to replace original file for $($src): $($_)"
            }
        }
    }
}

# Output
if ($CsvOutput) {
    if ($OutFile) {
        $results | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
        Write-Output "CSV written to $OutFile"
    }
    else {
        $results | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ }
    }
}
else {
    $results | Format-List
}