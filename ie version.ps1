Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Internet Explorer\' -Name svcVersion

(Get-Item 'C:\Program Files\internet explorer\iexplore.exe').VersionInfo | FL
(Get-Item 'C:\Program Files (x86)\internet explorer\iexplore.exe').VersionInfo | FL
