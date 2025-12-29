$musicFolder = "D:\Music"

# Get all Directory ojbects in Music folder
$folders = Get-Childitem $musicFolder  -Directory -Recurse

foreach ($folder in $folders) {

    # Count mp3old files in folder
    $mp3OldCount = (Get-ChildItem -Path $folder -Filter "*.mp3old" | Measure-Object).Count
    
    # If mpp3old count is greater than zero, proceed to check for flac files
    if ($mp3OldCount -gt 0) {

        # Count flac files in folder
        $flacCount = (Get-ChildItem -Path $folder -Filter "*.flac" | Measure-Object).Count

        # If flac count is greater than zero, remove mp3old files
        if ($flacCount -gt 0) {
            Get-ChildItem -Path $folder -Recurse -Filter "*.mp3old" | Remove-Item 
        }
        # If no flac files found, rename mp3old back to mp3
        else {
            Get-ChildItem -Path $folder -Recurse -Filter "*.mp3old" | Rename-Item -NewName { [io.path]::ChangeExtension($_.name, "mp3") } 
        } 
    }    
}