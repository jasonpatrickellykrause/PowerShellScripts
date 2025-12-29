Import-Module ActiveDirectory

# Get all domains in forest
$Domains = (Get-ADForest).Domains

foreach ($Domain in $Domains) {
    # Get all DCs in Domain
    $DCs = Get-ADDomainController -filter * -Server $Domain

    foreach ($DC in $DCs) {
        $DomainController_fqdn = $DC.HostName
        $DomainDN = $dc.DefaultPartition
        Get-ADobject -Server $DomainController_fqdn -Filter { objectclass -eq "DNSZone" } | 
        Set-ADObject -ProtectedFromAccidentalDeletion $true
        Get-ADobject -Server $DomainController_fqdn -Filter { objectclass -eq "DNSZone" } -SearchBase "DC=DomainDNSZones,$DomainDN" | 
        Set-ADObject -ProtectedFromAccidentalDeletion $true
        Get-ADobject -Server $DomainController_fqdn -Filter { objectclass -eq "DNSZone" } -SearchBase "DC=ForestDNSZones,$DomainDN" | 
        Set-ADObject -ProtectedFromAccidentalDeletion $true
    }
} 
