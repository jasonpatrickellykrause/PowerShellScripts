<#
.SYNOPSIS
	Uninstall and clean up Windows Admin Center (safe, interactive with -Force for unattended).

.DESCRIPTION
	This script attempts to uninstall Windows Admin Center by locating the registered
	uninstaller, running it (interactive or silent if -Force), and then removing
	common leftovers: files, services, scheduled tasks, firewall rules, SSL bindings
	and certificates. Operations support -WhatIf and are logged to a temp file.

.PARAMETER Force
	Run unattended where possible (silently pass /qn to msiexec and skip confirmations).

.NOTES
	- Run as Administrator.
	- The script uses conservative pattern matching (DisplayName/FriendlyName) for safety.
	- Review the log in the temp folder after running.

#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
	[switch]$Force
)

function Write-Log {
	param(
		[string]$Message
	)
	$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
	$line = "$timestamp`t$Message"
	Add-Content -Path $Script:LogFile -Value $line -ErrorAction SilentlyContinue
	Write-Host $Message
}

function Ensure-Admin {
	$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	if (-not $isAdmin) {
		Write-Error "This script must be run as Administrator. Exiting."
		Exit 1
	}
}

function Find-UninstallEntries {
	# Look in 64-bit and 32-bit uninstall registry paths
	$hives = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
	$matches = @()
	foreach ($hive in $hives) {
		if (Test-Path $hive) {
			Get-ChildItem -Path $hive -ErrorAction SilentlyContinue | ForEach-Object {
				$props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
				if ($props -and $props.DisplayName -and ($props.DisplayName -match 'Windows Admin Center')) {
					$matches += [PSCustomObject]@{
						DisplayName = $props.DisplayName
						UninstallString = $props.UninstallString
						RegistryPath = $_.PSPath
					}
				}
			}
		}
	}
	return $matches
}

function Run-UninstallString {
	param(
		[string]$UninstallString
	)
	if (-not $UninstallString) { return }

	# Typical format: "MsiExec.exe /I{GUID}" or "msiexec /x {GUID} /qn"
	if ($UninstallString -match 'msi?exec' -or $UninstallString -match 'MsiExec') {
		# Extract the GUID or product code portion
		$args = $UninstallString -replace '"',''
		# If installer used /I (install) convert to /x (uninstall)
		if ($args -match '/I' -and -not ($args -match '/x')) {
			$args = $args -replace '/I','/x'
		}
		if ($Force) {
			if ($args -notmatch '/qn') { $args += ' /qn' }
			Write-Log "Starting silent uninstall: msiexec $args"
			Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -NoNewWindow -ErrorAction SilentlyContinue
		}
		else {
			Write-Log "Starting interactive uninstall: msiexec $args"
			Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -NoNewWindow
		}
	}
	else {
		# Fall back: run the uninstall string as a command
		Write-Log "Running uninstall command: $UninstallString"
		try {
			Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $UninstallString" -Wait -NoNewWindow -ErrorAction SilentlyContinue
		}
		catch {
			Write-Log "Failed to run uninstall command: $_"
		}
	}
}

function Remove-Leftovers {
	# Common install paths used by Windows Admin Center
	$paths = @(
		"$env:ProgramFiles\Windows Admin Center",
		"$env:ProgramFiles(x86)\Windows Admin Center",
		"$env:ProgramData\Windows Admin Center",
		"C:\Program Files\Windows Admin Center"
	) | Where-Object { $_ -ne $null } | Get-Unique

	foreach ($p in $paths) {
		if (Test-Path $p) {
			if ($PSCmdlet.ShouldProcess($p, 'Remove directory')) {
				try {
					if ($Force) { Remove-Item -Path $p -Recurse -Force -ErrorAction Stop }
					else { Remove-Item -Path $p -Recurse -Confirm }
					Write-Log "Removed folder: $p"
				}
				catch {
					Write-Log "Failed to remove folder $($p): $($_)"
				}
			}
		}
	}

	# Services
	try {
		$svcCandidates = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Windows Admin Center' -or $_.Name -match 'WindowsAdminCenter' }
		foreach ($s in $svcCandidates) {
			if ($PSCmdlet.ShouldProcess($s.Name, 'Stop and delete service')) {
				try { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue } catch {}
				try { sc.exe delete $s.Name | Out-Null } catch { Write-Log "Failed to delete service $($s.Name): $($_)" }
				Write-Log "Removed service: $($s.Name)"
			}
		}
	}
	catch { }

	# Scheduled tasks
	try {
		Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Windows Admin Center' -or $_.TaskPath -match 'Windows Admin Center' } | ForEach-Object {
			if ($PSCmdlet.ShouldProcess($_.TaskName, 'Unregister scheduled task')) {
				Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
				Write-Log "Unregistered scheduled task: $($_.TaskName)"
			}
		}
	}
	catch { }

	# Firewall rules
	try {
		Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Windows Admin Center' -or $_.Name -match 'WindowsAdminCenter' } | ForEach-Object {
			if ($PSCmdlet.ShouldProcess($_.DisplayName, 'Remove firewall rule')) {
				Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
				Write-Log "Removed firewall rule: $($_.DisplayName)"
			}
		}
	}
	catch { }

	# Remove HTTP.SYS SSL bindings commonly used by WAC (default port 6516)
	try {
		$portsToTry = @('0.0.0.0:6516','[::]:6516')
		foreach ($ipport in $portsToTry) {
			if ($PSCmdlet.ShouldProcess($ipport, 'Delete SSL binding')) {
				try {
					netsh http delete sslcert ipport=$ipport 2>$null
					Write-Log "Deleted SSL binding on $ipport (if it existed)"
				}
				catch { Write-Log "Failed deleting ssl binding $($ipport): $($_)" }
			}
		}
	}
	catch { }

	# Certificates
	try {
		$certs = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'Windows Admin Center' -or $_.FriendlyName -match 'Windows Admin Center' }
		foreach ($c in $certs) {
			if ($PSCmdlet.ShouldProcess($c.Thumbprint, 'Remove certificate')) {
				try {
					if ($Force) { Remove-Item -Path ("Cert:\LocalMachine\My\" + $c.Thumbprint) -Force -ErrorAction Stop }
					else { Remove-Item -Path ("Cert:\LocalMachine\My\" + $c.Thumbprint) -Confirm }
					Write-Log "Removed certificate: $($c.Subject) [$($c.Thumbprint)]"
				}
				catch { Write-Log "Failed to remove certificate $($c.Thumbprint): $($_)" }
			}
		}
	}
	catch { }

	# IIS site (if any)
	try {
		Import-Module WebAdministration -ErrorAction SilentlyContinue
		if (Get-Website -Name 'Windows Admin Center' -ErrorAction SilentlyContinue) {
			if ($PSCmdlet.ShouldProcess('Windows Admin Center', 'Remove IIS site')) {
				Remove-Website -Name 'Windows Admin Center' -ErrorAction SilentlyContinue
				Write-Log "Removed IIS website: Windows Admin Center"
			}
		}
	}
	catch { }
}

### Main
Ensure-Admin

$timeStamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$Script:LogFile = Join-Path -Path $env:TEMP -ChildPath "WAC-uninstall-$timeStamp.log"
Write-Log "Starting Windows Admin Center cleanup"

# 1) Find uninstall entries
$entries = Find-UninstallEntries
if ($entries.Count -eq 0) {
	Write-Log "No registered 'Windows Admin Center' uninstall entries found. Continuing with cleanup of leftovers."
}
else {
	foreach ($e in $entries) {
		Write-Log "Found installer entry: $($e.DisplayName) -> $($e.UninstallString)"
		if ($PSCmdlet.ShouldProcess($e.DisplayName, 'Uninstall')) {
			if ($e.UninstallString) { Run-UninstallString -UninstallString $e.UninstallString }
		}
	}
}

# 2) Remove leftovers (files, services, tasks, firewall, bindings, certs)
Remove-Leftovers

Write-Log "Windows Admin Center cleanup finished. Review log: $Script:LogFile"

Write-Host "Done. Log: $Script:LogFile"

