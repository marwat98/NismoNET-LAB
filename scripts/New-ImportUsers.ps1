$base = "OU=Uzytkownicy,OU=NismoNET,DC=nismonet,DC=local"

# function which generates a random password with 10 characters and adds #26 at the end
function New-TempPassword {
    $chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray()
    $pass  = -join (1..10 | ForEach-Object { $chars | Get-Random })
    return "$pass#26"
}

$logFile = ".\log-import-$(Get-Date -Format 'yyyy-MM-dd_HHmm').txt"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","OK","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $logFile -Value $line -Encoding UTF8

    $color = switch ($Level) {
        "OK"    { "Green"  }
        "WARN"  { "Yellow" }
        "ERROR" { "Red"    }
        default { "Gray"   }
    }
    Write-Host $line -ForegroundColor $color
}

$csvPath = Join-Path $PSScriptRoot "uzytkownicy.csv"
Import-Csv  $csvPath -Encoding UTF8 | ForEach-Object {
    $user = $_
    if (Get-ADUser -Filter "SamAccountName -eq '$($_.Login)'") {
        Write-Log "Konto $($user.Login) juz istnieje - pomijam" -Level WARN
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

        Write-Log "Utworzono $($user.Login) w OU=$($user.Dzial)" -Level OK
    }
    catch {
        Write-Log "Blad przy $($user.Login): $($_.Exception.Message)" -Level ERROR
    }
}
$utworzone = (Select-String -Path $logFile -Pattern "\[OK\]").Count
$bledy     = (Select-String -Path $logFile -Pattern "\[ERROR\]").Count
$pominiete = (Select-String -Path $logFile -Pattern "\[WARN\]").Count

Write-Log "Podsumowanie: utworzono $utworzone, pominieto $pominiete, bledow $bledy" -Level INFO
Write-Host "`nLog zapisany: $logFile" -ForegroundColor Cyan