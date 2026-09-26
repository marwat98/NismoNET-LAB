<#
.SYNOPSIS
    Masowe zakladanie kont uzytkownikow w domenie NismoNET na podstawie pliku CSV.

.DESCRIPTION
    Skrypt wczytuje plik uzytkownicy.csv, weryfikuje kazdy wiersz, tworzy konto
    w jednostce organizacyjnej odpowiadajacej dzialowi i dodaje uzytkownika
    do grupy dzialowej.

    Kazde konto otrzymuje losowe haslo startowe z wymuszona zmiana przy pierwszym
    logowaniu. Pary login-haslo zapisywane sa do osobnego pliku CSV.

    Skrypt mozna uruchamiac wielokrotnie - konta juz istniejace sa pomijane.

.NOTES
    Uruchamiac na kontrolerze domeny lub stacji z narzedziami RSAT,
    w konsoli PowerShell podniesionej do uprawnien administratora.

    Plik z haslami zawiera dane poufne - usunac po przekazaniu hasel uzytkownikom.
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- konfiguracja

$Domain = "nismonet.local"
$BaseOU = "OU=Uzytkownicy,OU=NismoNET,DC=nismonet,DC=local"

# Wszystkie sciezki liczone wzgledem lokalizacji skryptu, a nie katalogu
# biezacego konsoli - inaczej pliki laduja tam, skad skrypt zostal wywolany
$CsvPath  = Join-Path $PSScriptRoot "uzytkownicy.csv"
$PassFile = Join-Path $PSScriptRoot "starting-passwords.csv"
$LogFile  = Join-Path $PSScriptRoot "log-import-$(Get-Date -Format 'yyyy-MM-dd_HHmm').txt"

# Maksymalna dlugosc atrybutu SamAccountName w Active Directory
$MaxLoginLength = 20

# ------------------------------------------------------------------- funkcje pomocnicze

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","OK","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8

    $color = switch ($Level) {
        "OK"    { "Green"  }
        "WARN"  { "Yellow" }
        "ERROR" { "Red"    }
        default { "Gray"   }
    }
    Write-Host $line -ForegroundColor $color
}

function New-TempPassword {
    # Zestaw znakow bez l, I, O, 0 i 1 - latwe do pomylenia przy przepisywaniu
    $chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray()
    $pass  = -join (1..10 | ForEach-Object { $chars | Get-Random })
    return "$pass#26"
}

function Test-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "Brak modulu ActiveDirectory. Zainstaluj: Install-WindowsFeature RSAT-AD-PowerShell"
    }
    Import-Module ActiveDirectory
}
# ------------------------------------------------------------- raport problemow
function Add-Problem {
    param(
        [int]$Row,
        [string]$Label,
        [string]$Reason,
        [ValidateSet("WARN","ERROR")]
        [string]$Level = "WARN"
    )

    Write-Log "$Label (wiersz $Row): $Reason" -Level $Level

    # Zwracany obiekt trafia do kolekcji w petli glownej
    return [PSCustomObject]@{
        Wiersz = $Row
        Login  = $Label
        Powod  = $Reason
    }
}

# -------------------------------------------------------- warunki poczatkowe

Write-Log "Start importu z pliku $CsvPath"

Test-ADModule

if (-not (Test-Path $CsvPath)) {
    Write-Log "Nie znaleziono pliku $CsvPath - przerywam" -Level ERROR
    return
}

# Stary plik z haslami usuwany, zeby Export-Csv z parametrem -Append
# nie dopisywal wpisow z poprzedniego uruchomienia
if (Test-Path $PassFile) {
    Remove-Item $PassFile
    Write-Log "Usunieto poprzedni plik $PassFile"
}

$rows = Import-Csv $CsvPath -Encoding UTF8
Write-Log "Wczytano wierszy: $($rows.Count)"

# Duplikat loginu w samym pliku CSV. Sprawdzany przed petla, bo w jej trakcie
# drugie wystapienie zostaloby zgloszone jako "konto juz istnieje" - czyli
# blad w danych wygladalby jak ponowne uruchomienie skryptu
$duplicates = $rows | Group-Object Login | Where-Object { $_.Count -gt 1 }

if ($duplicates) {
    $duplicates | ForEach-Object {
        Write-Log "Login $($_.Name) wystepuje w pliku $($_.Count) razy" -Level ERROR
    }
    Write-Log "Przerwano - popraw plik wejsciowy" -Level ERROR
    return
}

# Pamiec podreczna wynikow sprawdzen. Przy szesciu dzialach i 35 wierszach
# oszczedza okolo 60 zapytan do katalogu
$ouCache    = @{}
$groupCache = @{}

$created = 0
$skipped = 0
$failed  = 0

# Lista wierszy, ktore nie trafily do katalogu - raport na koniec
$problems = @()

# ------------------------------------------------------------- petla glowna
# Zmienna $rowNumber uzywana w logach do okreslenia, ktory wiersz z pliku CSV
$rowNumber = 1

foreach ($row in $rows) {
    $rowNumber++

    #------------------------------------------------------------- etykieta wiersza
    $label = if    ($row.Login)    { $row.Login.Trim() }
             elseif ($row.Nazwisko) { "$($row.Imie) $($row.Nazwisko)".Trim() }
             else                   { "wiersz $rowNumber" }

    # --- weryfikacja kompletnosci wiersza ---

    $required = @("Imie","Nazwisko","Login","Dzial")
    $missing  = $required | Where-Object { [string]::IsNullOrWhiteSpace($row.$_) }

    if ($missing) {
        $problems += Add-Problem $rowNumber $label "brak wartosci w polach: $($missing -join ', ')"
        $skipped++
        continue
    }

    # Biale znaki z pliku CSV rozbijaja sciezke LDAP i nazwe konta
    $firstName = $row.Imie.Trim()
    $lastName  = $row.Nazwisko.Trim()
    $login     = $row.Login.Trim().ToLower()
    $dept      = $row.Dzial.Trim()
    $title     = if ($row.PSObject.Properties.Name -contains "Stanowisko") {
                     $row.Stanowisko.Trim()
                 } else { "" }

    # --- weryfikacja formatu loginu ---
    if ($login.Length -gt $MaxLoginLength) {
        $problems += Add-Problem $rowNumber $label "login dluzszy niz $MaxLoginLength znakow"
        $skipped++; continue
    }

    if ($login -notmatch '^[a-z0-9.\-]+$') {
        $problems += Add-Problem $rowNumber $label "niedozwolone znaki w loginie"
        $skipped++; continue
    }

    # --- weryfikacja stanu w katalogu ---
    if (Get-ADUser -Filter "SamAccountName -eq '$login'") {
        $problems += Add-Problem $rowNumber $label "konto juz istnieje w katalogu"
        $skipped++; continue
    }

    $ouPath    = "OU=$dept,$BaseOU"
    $groupName = "GG_$dept"

    if (-not $ouCache.ContainsKey($dept)) {
        $ouCache[$dept] = [bool](Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'")
    }

    if (-not $ouCache[$dept]) {
        $problems += Add-Problem $rowNumber $label "nie znaleziono jednostki $ouPath"
        $skipped++; continue
    }

    if (-not $groupCache.ContainsKey($groupName)) {
        $groupCache[$groupName] = [bool](Get-ADGroup -Filter "Name -eq '$groupName'")
    }

    if (-not $groupCache[$groupName]) {
        $problems += Add-Problem $rowNumber $label "nie znaleziono grupy $groupName"
        $skipped++; continue
    }

    # --- utworzenie konta ---
    $tempPass   = New-TempPassword
    $securePass = ConvertTo-SecureString $tempPass -AsPlainText -Force

    $upn = "$login@$Domain"

    try {
        $params = @{
            Name                  = "$firstName $lastName"
            GivenName             = $firstName
            Surname               = $lastName
            DisplayName           = "$firstName $lastName"
            SamAccountName        = $login
            UserPrincipalName     = $upn
            EmailAddress          = $upn
            Department            = $dept
            Path                  = $ouPath
            AccountPassword       = $securePass
            ChangePasswordAtLogon = $true
            Enabled               = $true
            Description           = "Utworzono $(Get-Date -Format 'yyyy-MM-dd') skryptem importu"
        }

        # Pusta wartosc parametru Title jest odrzucana przez New-ADUser,
        if ($title) { $params.Title = $title }

        New-ADUser @params

        # Czlonkostwo w grupie dzialowej decyduje o dostepie do zasobow
        Add-ADGroupMember -Identity $groupName -Members $login

        # Zapisanie loginu i hasla startowego do pliku CSV. Plik zawiera dane poufne
        [PSCustomObject]@{
            Login = $login
            Haslo = $tempPass
        } | Export-Csv -Path $PassFile -Append -NoTypeInformation -Encoding UTF8

        Write-Log "Utworzono $login w OU=$dept" -Level OK
        $created++
    }
    catch {
        $problems += Add-Problem $rowNumber $login $_.Exception.Message -Level ERROR
        $failed++
    }
}

# ---------------------------------------------------------------- zakonczenie

Write-Log "Podsumowanie: utworzono $created, pominieto $skipped, bledow $failed"

if ($problems.Count -gt 0) {
    Write-Host ""
    Write-Host "Konta, ktore nie zostaly utworzone:" -ForegroundColor Yellow
    $problems | Format-Table Wiersz, Login, Powod -AutoSize -Wrap

    # Raport w formacie CSV - latwiej poprawic plik wejsciowy majac liste
    $reportFile = Join-Path $PSScriptRoot "raport-pominietych-$(Get-Date -Format 'yyyy-MM-dd_HHmm').csv"
    $problems | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
    Write-Host "Raport zapisany: $reportFile" -ForegroundColor Cyan
}

Write-Host ""