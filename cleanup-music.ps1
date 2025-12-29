# PowerShell script to delete specific file types recursively

# Define the directory to start the search
$directory = "D:\data\media\music"

# Define the file types to delete (e.g., .txt, .log)
$fileTypes = @("*.png", "*.nfo", "*.jpg", "*.lrc")

# Loop through each file type and delete the files
foreach ($fileType in $fileTypes) {
    Get-ChildItem -Path $directory -Recurse -Filter $fileType | Remove-Item -Force 
}

Write-Output "Specified file types have been deleted recursively."