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

    $tempPass   = New-TempPassword
    $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force

 try {
        New-ADUser `
            -Name              "$($user.Imie) $($user.Nazwisko)" `
            -GivenName         $user.Imie  -Surname $user.Nazwisko `
            -SamAccountName    $user.Login `
            -UserPrincipalName "$($user.Login)@nismonet.local" `
            -EmailAddress      "$($user.Login)@nismonet.local" `
            -Department        $user.Dzial `
            -Path              "OU=$($user.Dzial),$base" `
            -AccountPassword   $securePass `
            -ChangePasswordAtLogon $true -Enabled $true

        Add-ADGroupMember -Identity "GG_$($user.Dzial)" -Members $user.Login
        # Save the login and temporary password to a CSV file
        [PSCustomObject]@{
            Login = $user.Login
            Haslo = $tempPass
        } | Export-Csv .\starting-passwords.csv -Append -NoTypeInformation -Encoding UTF8

        Write-Host "Utworzono: $($user.Login)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Blad przy $($user.Login): $($_.Exception.Message)"
    }
}