$dn   = "DC=nismoNET,DC=local"
$base = "OU=NismoNET,$dn"

# Helper - pomija jednostki, ktore juz istnieja, wiec skrypt mozna
# uruchomic ponownie bez bledow
function New-OU {
    param([string]$Name, [string]$Path)

    $full = "OU=$Name,$Path"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$full'") {
        Write-Host "Istnieje: $full" -ForegroundColor DarkGray
        return
    }

    New-ADOrganizationalUnit -Name $Name -Path $Path
    Write-Host "Utworzono: $full" -ForegroundColor Green
}

# Poziom 1 - kontener nadrzedny
New-OU "NismoNET" $dn

# Poziom 2 - glowne kategorie obiektow
"Uzytkownicy","Komputery","Grupy","KontaSerwisowe","Dostawcy","Klienci","Wylaczone" |
    ForEach-Object { New-OU $_ $base }

# Poziom 3 - dzialy firmy
"Zarzad","Ksiegowosc","Sprzedaz","Helpdesk","AdminSieci","CyberSecurity","AdminDomen" |
    ForEach-Object { New-OU $_ "OU=Uzytkownicy,$base" }

# Poziom 3 - podzial komputerow wedlug roli
"Stacje","Serwery" | ForEach-Object { New-OU $_ "OU=Komputery,$base" }

# Poziom 3 - typy klientow
"Indywidualni","Biznesowi" | ForEach-Object { New-OU $_ "OU=Klienci,$base" }