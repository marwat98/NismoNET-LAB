$BaseOU   = "OU=NismoNET,DC=nismoNET,DC=local"
$UsersOU  = "OU=Uzytkownicy,$BaseOU"
$GroupsOU = "OU=Grupy,$BaseOU"

# Lista dzialow pobierana z samej struktury AD, nie wpisywana recznie -
# dodanie nowego OU wystarczy, zeby skrypt utworzyl dla niego grupe
Get-ADOrganizationalUnit -Filter * -SearchBase $UsersOU -SearchScope OneLevel |
ForEach-Object {

    $groupName = "GG_$($_.Name)"

    if (Get-ADGroup -Filter "Name -eq '$groupName'") {
        Write-Host "Istnieje, pomijam: $groupName" -ForegroundColor Yellow
        return
    }

    New-ADGroup -Name $groupName `
        -SamAccountName $groupName `
        -GroupScope Global `
        -GroupCategory Security `
        -Path $GroupsOU `
        -Description "Grupa dzialowa - $($_.Name)"

    Write-Host "Utworzono: $groupName" -ForegroundColor Green
}