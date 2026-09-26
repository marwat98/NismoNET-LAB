<#
.SYNOPSIS
    Nadanie uprawnien grupom zabezpieczen w domenie NismoNET.

.DESCRIPTION
    Skrypt realizuje model uprawnien oparty na zasadzie najmniejszych uprawnien.
    Kazda grupa otrzymuje wylacznie te prawa, ktore wynikaja z zakresu obowiazkow
    dzialu.

    Zakres:
      GG_AdminDomeny    - pelna kontrola nad domena (Domain Admins)
      GG_AdminSieci     - zarzadzanie kontami uzytkownikow, administracja serwerami
      GG_CyberSecurity  - odczyt dziennikow zdarzen, odczyt obiektow katalogu
      GG_Helpdesk       - reset hasel, odblokowanie, wlaczanie i wylaczanie kont
      GG_Zarzad         - dostep zdalny (VPN)
      GG_Ksiegowosc     - dostep zdalny (VPN)
      GG_Sprzedaz       - dostep zdalny (VPN)

    Uprawnienia w katalogu nadawane sa jako wpisy na liscie kontroli dostepu
    jednostki organizacyjnej OU=Uzytkownicy, z dziedziczeniem na obiekty
    klasy user. Identyfikatory GUID odczytywane sa ze schematu w czasie
    dzialania skryptu, dzieki czemu skrypt dziala niezaleznie od wersji
    jezykowej systemu.

.NOTES
    Uruchamiac na kontrolerze domeny w konsoli podniesionej do uprawnien
    administratora, na koncie nalezacym do Domain Admins.

    Czego skrypt NIE robi - to nalezy do etapu zasad grupy:
      - prawa logowania lokalnego i zdalnego na serwerach
      - uprawnienia NTFS do udzialow sieciowych
      - polityki hasel i blokady kont
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- konfiguracja

$BaseOU  = "OU=NismoNET,DC=nismoNET,DC=local"
$UsersOU = "OU=Uzytkownicy,$BaseOU"

$GroupAdminDomain = "GG_AdminDomeny"
$GroupNetAdmins   = "GG_AdminSieci"
$GroupSecurity    = "GG_CyberSecurity"
$GroupHelpdesk    = "GG_Helpdesk"

# Dzialy z dostepem zdalnym
$VpnGroups = @("GG_Zarzad", "GG_Ksiegowosc", "GG_Sprzedaz")

# ------------------------------------------------------------------- funkcje

# funkcja pomocnicza do wypisywania naglowkow poszczegolnych etapow
function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("-" * $Text.Length) -ForegroundColor DarkGray
}

function Get-GroupSid {
    param([string]$Name)

    $group = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Warning "Nie znaleziono grupy $Name - pomijam zwiazane z nia uprawnienia"
        return $null
    }
    return [System.Security.Principal.SecurityIdentifier]$group.SID
}

# funkcja pomocnicza do dodawania wpisow kontroli dostepu na OU
function Add-DelegationRule {
    <#
        Dodaje wpis kontroli dostepu do jednostki organizacyjnej.

        Rights     - rodzaj uprawnienia (ExtendedRight, WriteProperty, GenericAll...)
        ObjectGuid - konkretne prawo rozszerzone lub atrybut, ktorego wpis dotyczy
        ClassGuid  - klasa obiektow potomnych, na ktore wpis sie rozciaga
    #>
    param(
        [string] $OuPath,
        [System.Security.Principal.SecurityIdentifier] $Sid,
        [System.DirectoryServices.ActiveDirectoryRights] $Rights,
        [guid] $ObjectGuid,
        [guid] $ClassGuid,
        [string] $Label
    )

    $acl = Get-Acl -Path "AD:\$OuPath"

    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $Sid,
        $Rights,
        [System.Security.AccessControl.AccessControlType]::Allow,
        $ObjectGuid,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents,
        $ClassGuid
    )

    $acl.AddAccessRule($rule)
    Set-Acl -Path "AD:\$OuPath" -AclObject $acl

    Write-Host "  $Label" -ForegroundColor Green
}

# -------------------------------------------------------- warunki poczatkowe

Import-Module ActiveDirectory

Write-Step "Odczyt identyfikatorow ze schematu katalogu"

# Nazwy wyswietlane praw rozszerzonych sa tlumaczone na jezyk systemu, 
# natomiast nazwy wyrozniajace (CN) pozostaja stale - dlatego filtr po CN
$rootDSE  = Get-ADRootDSE
$schemaNC = $rootDSE.schemaNamingContext
$configNC = $rootDSE.configurationNamingContext

# funkcja pomocnicza do odczytu identyfikatorow GUID z katalogu
function Get-SchemaGuid {
    param([string]$LdapName)
    $obj = Get-ADObject -SearchBase $schemaNC `
        -Filter "lDAPDisplayName -eq '$LdapName'" -Properties schemaIDGUID
    return [guid]$obj.schemaIDGUID
}

# funkcja pomocnicza do odczytu identyfikatorow GUID praw rozszerzonych
function Get-ExtendedRightGuid {
    param([string]$Cn)
    $obj = Get-ADObject -SearchBase "CN=Extended-Rights,$configNC" `
        -Filter "cn -eq '$Cn'" -Properties rightsGuid
    return [guid]$obj.rightsGuid
}

# Klasa obiektow, ktorych dotycza delegacje
$GuidUserClass = Get-SchemaGuid "user"

# Atrybuty sterujace stanem konta
$GuidUserAccountControl = Get-SchemaGuid "userAccountControl"   # wlaczenie / wylaczenie konta
$GuidLockoutTime        = Get-SchemaGuid "lockoutTime"          # odblokowanie po nieudanych probach
$GuidPwdLastSet         = Get-SchemaGuid "pwdLastSet"           # wymuszenie zmiany hasla

# Prawo rozszerzone resetu hasla
$GuidResetPassword = Get-ExtendedRightGuid "User-Force-Change-Password"

Write-Host "  Klasa user                  $GuidUserClass"
Write-Host "  Reset hasla                 $GuidResetPassword"
Write-Host "  userAccountControl          $GuidUserAccountControl"
Write-Host "  lockoutTime                 $GuidLockoutTime"
Write-Host "  pwdLastSet                  $GuidPwdLastSet"

# ================================================================ ADMINDOMENY

Write-Step "$GroupAdminDomain - pelna kontrola nad domena"

if (Get-ADGroup -Filter "Name -eq '$GroupAdminDomain'" -ErrorAction SilentlyContinue) {

    # Zagniezdzenie w grupie wbudowanej zamiast kopiowania jej uprawnien.
    # Domain Admins ma juz nadane wszystkie prawa w domenie, wiec czlonkostwo
    # jest jedynym poprawnym sposobem nadania pelnej kontroli
    Add-ADGroupMember -Identity "Domain Admins" -Members $GroupAdminDomain
    Write-Host "  Dodano do Domain Admins" -ForegroundColor Green

    Write-Host ""
    Write-Warning "Domain Admins to najwyzszy poziom uprawnien w domenie."
    Write-Host "  Grupy Enterprise Admins i Schema Admins celowo pominieto -" -ForegroundColor DarkGray
    Write-Host "  sluza do operacji obejmujacych caly las, nie do administracji" -ForegroundColor DarkGray
    Write-Host "  pojedyncza domena." -ForegroundColor DarkGray
} else {
    Write-Warning "Nie znaleziono grupy $GroupAdminDomain"
}

# ================================================================= ADMINSIECI

Write-Step "$GroupNetAdmins - zarzadzanie kontami i serwerami"

$sidNetAdmins = Get-GroupSid $GroupNetAdmins

if ($sidNetAdmins) {

    # Pelna kontrola nad obiektami uzytkownikow w calej galezi Uzytkownicy.
    # Obejmuje tworzenie, usuwanie, modyfikacje atrybutow i nadawanie uprawnien
    Add-DelegationRule -OuPath $UsersOU -Sid $sidNetAdmins `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericAll) `
        -ObjectGuid ([guid]::Empty) -ClassGuid $GuidUserClass `
        -Label "Pelna kontrola nad kontami uzytkownikow w OU=Uzytkownicy"

    # Prawo tworzenia i usuwania obiektow uzytkownikow w samej jednostce
    $acl = Get-Acl -Path "AD:\$UsersOU"
    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sidNetAdmins,
        ([System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor
         [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild),
        [System.Security.AccessControl.AccessControlType]::Allow,
        $GuidUserClass,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path "AD:\$UsersOU" -AclObject $acl
    Write-Host "  Tworzenie i usuwanie kont" -ForegroundColor Green

    # Administracja serwerami. Server Operators pozwala na zarzadzanie
    # uslugami, udzialami i kopiami zapasowymi bez uprawnien Domain Admin
    Add-ADGroupMember -Identity "Server Operators"     -Members $GroupNetAdmins
    Add-ADGroupMember -Identity "Remote Desktop Users" -Members $GroupNetAdmins
    Write-Host "  Dodano do Server Operators i Remote Desktop Users" -ForegroundColor Green

    Write-Host ""
    Write-Host "  Uwaga: prawo logowania lokalnego na serwerach nadaje sie" -ForegroundColor DarkGray
    Write-Host "  przez zasady grupy, nie przez czlonkostwo - etap zasad grupy." -ForegroundColor DarkGray
}

# ============================================================== CYBERSECURITY

Write-Step "$GroupSecurity - audyt i odczyt dziennikow"

$sidSecurity = Get-GroupSid $GroupSecurity

if ($sidSecurity) {

    # Wbudowana grupa przeznaczona do odczytu dziennikow zdarzen,
    # rowniez zdalnego, bez jakichkolwiek uprawnien do zmian
    Add-ADGroupMember -Identity "Event Log Readers" -Members $GroupSecurity
    Write-Host "  Dodano do Event Log Readers" -ForegroundColor Green

    # Odczyt wszystkich wlasciwosci kont w galezi Uzytkownikow.
    # Swiadomie bez prawa zapisu - audyt obserwuje, nie modyfikuje
    Add-DelegationRule -OuPath $UsersOU -Sid $sidSecurity `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::ReadProperty) `
        -ObjectGuid ([guid]::Empty) -ClassGuid $GuidUserClass `
        -Label "Odczyt wlasciwosci kont uzytkownikow (bez prawa zapisu)"

    Write-Host ""
    Write-Host "  Uwaga: wlaczenie szczegolowego audytu logowan i zmian w katalogu" -ForegroundColor DarkGray
    Write-Host "  nastepuje przez zasady grupy - bez tego dzienniki beda ubogie." -ForegroundColor DarkGray
}

# =================================================================== HELPDESK

Write-Step "$GroupHelpdesk - obsluga kont uzytkownikow"

$sidHelpdesk = Get-GroupSid $GroupHelpdesk

if ($sidHelpdesk) {

    # Reset hasla jako prawo rozszerzone - nie wymaga znajomosci starego hasla
    Add-DelegationRule -OuPath $UsersOU -Sid $sidHelpdesk `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight) `
        -ObjectGuid $GuidResetPassword -ClassGuid $GuidUserClass `
        -Label "Reset hasla uzytkownika"

    # Wymuszenie zmiany hasla przy nastepnym logowaniu
    Add-DelegationRule -OuPath $UsersOU -Sid $sidHelpdesk `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::WriteProperty) `
        -ObjectGuid $GuidPwdLastSet -ClassGuid $GuidUserClass `
        -Label "Wymuszenie zmiany hasla przy logowaniu"

    # Wlaczanie i wylaczanie konta - oba stany zapisane sa w tym samym atrybucie
    Add-DelegationRule -OuPath $UsersOU -Sid $sidHelpdesk `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::WriteProperty) `
        -ObjectGuid $GuidUserAccountControl -ClassGuid $GuidUserClass `
        -Label "Wlaczanie i wylaczanie kont"

    # Odblokowanie konta po przekroczeniu liczby nieudanych prob logowania
    Add-DelegationRule -OuPath $UsersOU -Sid $sidHelpdesk `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::WriteProperty) `
        -ObjectGuid $GuidLockoutTime -ClassGuid $GuidUserClass `
        -Label "Odblokowanie zablokowanych kont"

    # Odczyt danych konta - bez tego technik nie odnajdzie uzytkownika w konsoli
    Add-DelegationRule -OuPath $UsersOU -Sid $sidHelpdesk `
        -Rights ([System.DirectoryServices.ActiveDirectoryRights]::ReadProperty) `
        -ObjectGuid ([guid]::Empty) -ClassGuid $GuidUserClass `
        -Label "Odczyt wlasciwosci kont"

    Write-Host ""
    Write-Host "  Swiadomie nieprzyznane: tworzenie i usuwanie kont, zmiana" -ForegroundColor DarkGray
    Write-Host "  czlonkostwa w grupach, dostep do kontrolerow domeny." -ForegroundColor DarkGray
}

# ======================================================================== VPN

Write-Step "Dostep zdalny - $($VpnGroups -join ', ')"

foreach ($groupName in $VpnGroups) {

    $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Warning "  Nie znaleziono grupy $groupName"
        continue
    }

    $members = Get-ADGroupMember -Identity $groupName | Where-Object objectClass -eq "user"

    foreach ($member in $members) {
        # Atrybut zezwalajacy na polaczenie przychodzace. Serwer zasad sieciowych
        # odczytuje go przy probie zestawienia tunelu
        Set-ADUser -Identity $member.SamAccountName -Replace @{ msNPAllowDialin = $true }
    }

    Write-Host ("  {0,-20} kont z dostepem zdalnym: {1}" -f $groupName, @($members).Count) -ForegroundColor Green
}

Write-Host ""
Write-Host "  Uwaga: atrybut sam w sobie niczego nie udostepnia. Realna kontrola" -ForegroundColor DarkGray
Write-Host "  wymaga serwera VPN z rola RRAS oraz zasad na serwerze NPS," -ForegroundColor DarkGray
Write-Host "  ktore odwoluja sie do czlonkostwa w powyzszych grupach." -ForegroundColor DarkGray

# ============================================================== DOMAIN USERS

Write-Step "Domain Users"

# Grupa podstawowa przypisywana automatycznie przy tworzeniu konta.
# Dotyczy rowniez kont administracyjnych - nie da sie jej usunac wybiorczo,
# bo kazde konto musi miec grupe podstawowa
$total = (Get-ADUser -Filter * -SearchBase $UsersOU).Count
Write-Host "  Kont w OU=Uzytkownicy: $total" -ForegroundColor Green
Write-Host "  Wszystkie naleza do Domain Users - przypisanie automatyczne." -ForegroundColor DarkGray

# ================================================================ WERYFIKACJA

Write-Step "Weryfikacja - wpisy kontroli dostepu na OU=Uzytkownicy"

(Get-Acl -Path "AD:\$UsersOU").Access |
    Where-Object { $_.IdentityReference -like "*GG_*" } |
    Select-Object `
        @{n='Grupa';      e={ ($_.IdentityReference -split '\\')[-1] }},
        @{n='Uprawnienie'; e={ $_.ActiveDirectoryRights }},
        AccessControlType |
    Sort-Object Grupa |
    Format-Table -AutoSize

Write-Step "Weryfikacja - czlonkostwo w grupach wbudowanych"

"Domain Admins","Server Operators","Event Log Readers","Remote Desktop Users" |
ForEach-Object {
    $members = (Get-ADGroupMember $_ -ErrorAction SilentlyContinue).Name -join ", "
    Write-Host ("  {0,-22} {1}" -f $_, $members)
}

Write-Host ""
Write-Host "Zalecany test: zaloguj sie kontem z $GroupHelpdesk i sprawdz," -ForegroundColor Yellow
Write-Host "czy reset hasla dziala, a proba usuniecia konta konczy sie odmowa." -ForegroundColor Yellow
Write-Host "Zrzut ekranu z odmowy jest lepszym dowodem niz zrzut z sukcesu." -ForegroundColor DarkGray
Write-Host ""