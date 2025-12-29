# Helper: list most recent WAC uninstall logs
Get-ChildItem -Path $env:TEMP -Filter 'WAC-uninstall-*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        Write-Host $_.FullName
        Write-Host $_.LastWriteTime
        Write-Host '-'*40
    }
