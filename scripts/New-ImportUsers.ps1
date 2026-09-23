$base = "OU=Uzytkownicy,OU=NismoNET,DC=nismonet,DC=local"

# function which generates a random password with 10 characters and adds #26 at the end
function New-TempPassword {
    $chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray()
    $pass  = -join (1..10 | ForEach-Object { $chars | Get-Random })
    return "$pass#26"
}

Import-Csv .\uzytkownicy.csv -Encoding UTF8 | ForEach-Object {

    if (Get-ADUser -Filter "SamAccountName -eq '$($_.Login)'") {
        Write-Warning "Konto $($_.Login) juz istnieje - pomijam"
        return
    }

    # haslo generowane raz, uzywane w dwoch miejscach
    $tempPass   = New-TempPassword
    $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force

    New-ADUser `
        -Name              "$($_.Imie) $($_.Nazwisko)" `
        -GivenName         $_.Imie  -Surname $_.Nazwisko `
        -SamAccountName    $_.Login `
        -UserPrincipalName "$($_.Login)@nismonet.local" `
        -EmailAddress      "$($_.Login)@nismonet.local" `
        -Department        $_.Dzial -Title $_.Stanowisko `
        -Path              "OU=$($_.Dzial),$base" `
        -AccountPassword   $securePass `
        -ChangePasswordAtLogon $true -Enabled $true

    Add-ADGroupMember -Identity "GG_$($_.Dzial)" -Members $_.Login

    # Save the login and temporary password to a CSV file
    [PSCustomObject]@{
        Login = $_.Login
        Haslo = $tempPass
    } | Export-Csv .\starting-passwords.csv -Append -NoTypeInformation -Encoding UTF8

    Write-Host "Utworzono: $($_.Login)" -ForegroundColor Green
}