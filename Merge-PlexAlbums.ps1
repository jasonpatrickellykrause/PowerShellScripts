# Plex Album Merger
# Scans for duplicate albums with the same name and merges them if all files are in the same folder.

# Configuration
$PLEX_URL = "http://localhost:32400"  # Change to your Plex server URL
$PLEX_TOKEN = "KA72SDXHmJQVi-Xrtn1-"  # Get from Plex settings
$MUSIC_LIBRARY_NAME = "Music"  # Change to your music library name


function Get-PlexHeaders {
    return @{
        "X-Plex-Token" = $PLEX_TOKEN
        "Accept"       = "application/json"
    }
}

function Get-MusicLibrary {
    $headers = Get-PlexHeaders
    $response = Invoke-RestMethod -Uri "$PLEX_URL/library/sections" -Headers $headers
    
    foreach ($library in $response.MediaContainer.Directory) {
        if ($library.title -eq $MUSIC_LIBRARY_NAME -and $library.type -eq "artist") {
            return $library.key
        }
    }
    
    throw "Music library '$MUSIC_LIBRARY_NAME' not found"
}

function Get-AllAlbums {
    param([string]$LibraryKey)
    
    $headers = Get-PlexHeaders
    
    try {
        Write-Host "Fetching all albums (this may take a moment)..." -ForegroundColor Gray
        $response = Invoke-RestMethod -Uri "$PLEX_URL/library/sections/$LibraryKey/all?type=9" -Headers $headers -TimeoutSec 60
        return $response.MediaContainer.Metadata
    }
    catch {
        Write-Host "Error fetching albums: $_" -ForegroundColor Red
        throw
    }
}

function Get-AlbumTracks {
    param([string]$AlbumKey)
    
    $headers = Get-PlexHeaders
    
    # Add retry logic and rate limiting
    $maxRetries = 3
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            Start-Sleep -Milliseconds 100  # Rate limiting
            $response = Invoke-RestMethod -Uri "$PLEX_URL$AlbumKey" -Headers $headers -TimeoutSec 30
            return $response.MediaContainer.Metadata
        }
        catch {
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Host "  Warning: Failed to get tracks for album after $maxRetries attempts" -ForegroundColor Yellow
                return @()
            }
            Start-Sleep -Seconds 1
        }
    }
}

function Get-FolderPath {
    param($Track)
    
    if ($Track.Media -and $Track.Media[0].Part) {
        $filePath = $Track.Media[0].Part[0].file
        return Split-Path -Parent $filePath
    }
    
    return $null
}

function Get-AlbumFolder {
    param($Album)
    
    try {
        $tracks = Get-AlbumTracks -AlbumKey $Album.key
        
        if ($tracks -and $tracks.Count -gt 0) {
            return Get-FolderPath -Track $tracks[0]
        }
    }
    catch {
        Write-Host "  Warning: Could not get folder for album '$($Album.title)'" -ForegroundColor Yellow
    }
    
    return $null
}

function Find-DuplicateAlbums {
    param($Albums)
    
    # Group albums by BOTH title AND folder
    $albumGroups = @{}
    $processedCount = 0
    
    Write-Host "Processing albums to find duplicates..." -ForegroundColor Gray
    
    foreach ($album in $Albums) {
        $processedCount++
        if ($processedCount % 50 -eq 0) {
            Write-Progress -Activity "Finding duplicates" -Status "Processed $processedCount of $($Albums.Count) albums" -PercentComplete (($processedCount / $Albums.Count) * 100)
        }
        
        $folder = Get-AlbumFolder -Album $album
        
        if ($folder) {
            # Create a unique key combining folder and title
            $key = "$folder|$($album.title)"
            
            if (-not $albumGroups.ContainsKey($key)) {
                $albumGroups[$key] = @()
            }
            $albumGroups[$key] += $album
        }
    }
    Write-Progress -Activity "Finding duplicates" -Completed
    
    # Filter to only duplicates (same folder AND same title)
    $duplicates = @{}
    foreach ($key in $albumGroups.Keys) {
        if ($albumGroups[$key].Count -gt 1) {
            # Extract just the title for display
            $title = $key.Split('|')[1]
            $duplicates[$key] = $albumGroups[$key]
        }
    }
    
    return $duplicates
}

function Test-SameFolder {
    param($Albums)
    
    $folders = @{}
    
    foreach ($album in $Albums) {
        $tracks = Get-AlbumTracks -AlbumKey $album.key
        
        foreach ($track in $tracks) {
            $folder = Get-FolderPath -Track $track
            if ($folder) {
                $folders[$folder] = $true
            }
        }
    }
    
    # Should always be true now since we're pre-filtering by folder
    # But this is a safety check in case tracks span multiple folders
    $isSameFolder = ($folders.Count -eq 1)
    
    return @{
        IsSameFolder = $isSameFolder
        Folders      = $folders.Keys
    }
}

function Remove-Album {
    param([string]$RatingKey)
    
    # This function is no longer used but kept for reference
    $headers = Get-PlexHeaders
    
    $maxRetries = 3
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            Start-Sleep -Milliseconds 200
            Invoke-RestMethod -Uri "$PLEX_URL/library/metadata/$RatingKey" -Method Delete -Headers $headers -TimeoutSec 30 | Out-Null
            return $true
        }
        catch {
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Host "    Error deleting album: $_" -ForegroundColor Red
                return $false
            }
            Write-Host "    Retry $retryCount of $maxRetries..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
}

function Merge-Albums {
    param($Albums)
    
    if ($Albums.Count -le 1) {
        return $false
    }
    
    # Keep the first album as the primary, merge others into it
    $primary = $Albums[0]
    $toMerge = $Albums[1..($Albums.Count - 1)]
    
    Write-Host "  Primary: $($primary.title) (ID: $($primary.ratingKey))" -ForegroundColor Green
    
    # Build the merge URL - merge all duplicates into the primary
    $mergeIds = ($toMerge | ForEach-Object { $_.ratingKey }) -join ","
    
    Write-Host "  Merging IDs: $mergeIds into primary" -ForegroundColor Yellow
    
    $headers = Get-PlexHeaders
    
    $maxRetries = 3
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            Start-Sleep -Milliseconds 200  # Rate limiting
            # PUT request to merge endpoint
            $mergeUrl = "$PLEX_URL/library/metadata/$($primary.ratingKey)/merge?ids=$mergeIds"
            Invoke-RestMethod -Uri $mergeUrl -Method Put -Headers $headers -TimeoutSec 30 | Out-Null
            Write-Host "  ✅ Merge successful!" -ForegroundColor Green
            return $true
        }
        catch {
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Host "    Error merging albums: $_" -ForegroundColor Red
                return $false
            }
            Write-Host "    Retry $retryCount of $maxRetries..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
}

# Main Script
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Plex Album Merger" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

try {
    # Connect to Plex
    Write-Host "`nConnecting to Plex server at $PLEX_URL"
    $libraryKey = Get-MusicLibrary
    Write-Host "Connected! Found music library." -ForegroundColor Green
    
    # Get all albums
    Write-Host "`nScanning albums..."
    $albums = Get-AllAlbums -LibraryKey $libraryKey
    Write-Host "Found $($albums.Count) total albums" -ForegroundColor Green
    
    # Find duplicates
    Write-Host "`nSearching for duplicate album names..."
    $duplicates = Find-DuplicateAlbums -Albums $albums
    
    if ($duplicates.Count -eq 0) {
        Write-Host "No duplicate albums found!" -ForegroundColor Green
        exit
    }
    
    Write-Host "Found $($duplicates.Count) album titles with duplicates" -ForegroundColor Yellow
    
    # Analyze duplicates
    Write-Host "`nAnalyzing duplicate albums..."
    $mergeable = @()
    $notMergeable = @()
    
    $progress = 0
    foreach ($key in $duplicates.Keys) {
        $progress++
        $title = $key.Split('|')[1]
        $folder = $key.Split('|')[0]
        Write-Progress -Activity "Analyzing duplicates" -Status "Processing $title" -PercentComplete (($progress / $duplicates.Count) * 100)
        
        $albumGroup = $duplicates[$key]
        $folderCheck = Test-SameFolder -Albums $albumGroup
        
        if ($folderCheck.IsSameFolder) {
            $mergeable += @{
                Title  = $title
                Albums = $albumGroup
                Folder = $folder
            }
        }
        else {
            # This shouldn't happen with the new filtering, but keeping as safety check
            $notMergeable += @{
                Title   = $title
                Albums  = $albumGroup
                Folders = $folderCheck.Folders
            }
        }
    }
    Write-Progress -Activity "Analyzing duplicates" -Completed
    
    # Display summary
    Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
    Write-Host "SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "Albums that CAN be merged (same folder): $($mergeable.Count)" -ForegroundColor Green
    Write-Host "Albums that CANNOT be merged (different folders): $($notMergeable.Count)" -ForegroundColor Yellow
    
    # Show mergeable albums
    if ($mergeable.Count -gt 0) {
        Write-Host "`n" + ("=" * 80) -ForegroundColor Green
        Write-Host "ALBUMS READY TO MERGE:" -ForegroundColor Green
        Write-Host ("=" * 80) -ForegroundColor Green
        
        foreach ($item in $mergeable) {
            Write-Host "`n'$($item.Title)' ($($item.Albums.Count) duplicates)" -ForegroundColor White
            Write-Host "  Folder: $($item.Folder)" -ForegroundColor Gray
            
            $i = 1
            foreach ($album in $item.Albums) {
                $trackCount = (Get-AlbumTracks -AlbumKey $album.key).Count
                Write-Host "  [$i] Tracks: $trackCount | ID: $($album.ratingKey)" -ForegroundColor Gray
                $i++
            }
        }
    }
    
    # Show non-mergeable albums
    if ($notMergeable.Count -gt 0) {
        Write-Host "`n" + ("=" * 80) -ForegroundColor Yellow
        Write-Host "ALBUMS IN DIFFERENT FOLDERS (NOT MERGING):" -ForegroundColor Yellow
        Write-Host ("=" * 80) -ForegroundColor Yellow
        
        foreach ($item in $notMergeable) {
            Write-Host "`n'$($item.Title)' ($($item.Albums.Count) duplicates)" -ForegroundColor White
            Write-Host "  Found in $($item.Folders.Count) different folders:" -ForegroundColor Gray
            foreach ($folder in $item.Folders) {
                Write-Host "    - $folder" -ForegroundColor Gray
            }
        }
    }
    
    # Ask for confirmation
    if ($mergeable.Count -gt 0) {
        Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
        $response = Read-Host "`nMerge $($mergeable.Count) duplicate album(s)? (yes/no)"
        
        if ($response -eq "yes") {
            Write-Host "`nMerging albums..." -ForegroundColor Cyan
            $mergedCount = 0
            
            foreach ($item in $mergeable) {
                Write-Host "`nMerging '$($item.Title)'..." -ForegroundColor Cyan
                if (Merge-Albums -Albums $item.Albums) {
                    $mergedCount++
                }
            }
            
            Write-Host "`n" + ("=" * 80) -ForegroundColor Green
            Write-Host "Successfully merged $mergedCount album(s)!" -ForegroundColor Green
            Write-Host "Refreshing library metadata..." -ForegroundColor Cyan
            
            $headers = Get-PlexHeaders
            Invoke-RestMethod -Uri "$PLEX_URL/library/sections/$libraryKey/refresh" -Headers $headers | Out-Null
            
            Write-Host "Done! Library refresh initiated." -ForegroundColor Green
        }
        else {
            Write-Host "`nMerge cancelled." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Make sure your PLEX_TOKEN is correct"
    Write-Host "2. Verify the PLEX_URL is accessible"
    Write-Host "3. Check that the library name matches exactly"
    Write-Host "`nTo find your Plex token:"
    Write-Host "https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/"
}