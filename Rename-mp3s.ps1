$musicFolder = "D:\Videos\Movies"

# Get all directories in Music folder
# Consider adding the -Filter option to perform the rename in small batches.
# -Filter a* would return all folders that start with the letter A.
$folders = Get-Childitem $musicFolder -Directory

foreach ($folder in $folders) {
    Get-ChildItem -Path $folder -Recurse -Filter "*remux*" | Rename-Item -NewName { [io.path]::ChangeExtension($_.name, "remux") } -WhatIf
}