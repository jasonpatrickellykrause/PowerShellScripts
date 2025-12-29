# This script finds the longest file paths in all subdirectories
# and outputs the results.

# Define the root directory to search
$rootDirectory = "D:\data\media\music"

# Get all files in subdirectories and calculate their path lengths
$files = Get-ChildItem -Path $rootDirectory -Recurse -File | 
Select-Object FullName, @{Name = "PathLength"; Expression = { $_.FullName.Length } }

# Find the maximum path length
$maxLength = ($files | Measure-Object -Property PathLength -Maximum).Maximum

# Get the files with the longest paths
$longestPaths = $files | Where-Object { $_.PathLength -eq $maxLength }

# Output the results
$longestPaths | ForEach-Object {
    Write-Output "Path: $($_.FullName)"
    Write-Output "Length: $($_.PathLength)"
    Write-Output ""
}