$musicPath = "D:\Music"

Get-ChildItem $musicPath -Recurse -ReadOnly | 

ForEach-Object { 
    if ($_.IsReadOnly) { 
        Write-Host $_.FullName
        $_.IsReadOnly = $false 
    } 
}