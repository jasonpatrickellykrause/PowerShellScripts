# This script deletes all empty folders in the specified directory and its subdirectories

$targetDirectory = "D:\data\media\music\"

# Get all directories recursively
$directories = Get-ChildItem -Path $targetDirectory -Directory -Recurse

foreach ($directory in $directories) {
    # Check if the directory is empty
    if (-Not (Get-ChildItem -Path $directory.FullName)) {
        # Delete the empty directory
        Remove-Item -Path $directory.FullName -Force
        Write-Output "Deleted empty folder: $($directory.FullName)"
    }
}