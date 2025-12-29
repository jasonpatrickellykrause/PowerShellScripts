# Define the root directory to scan
$rootPath = "D:\data\media\music"

# Define audio file extensions
$audioExtensions = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a")

# Get all bottom-level subfolders (folders with no subdirectories)
$bottomFolders = Get-ChildItem -Path $rootPath -Directory -Recurse | Where-Object {
    (Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue).Count -eq 0
}

foreach ($folder in $bottomFolders) {
    $audioFiles = Get-ChildItem -Path $folder.FullName -File -ErrorAction SilentlyContinue | Where-Object {
        $audioExtensions -contains $_.Extension.ToLower()
    }
    if ($audioFiles.Count -eq 0) {
        Write-Output "Deleting folder '$($folder.FullName)' because it contains no audio files."
        Remove-Item -Path $folder.FullName -Recurse -Force -Confirm:$false
    }
}


