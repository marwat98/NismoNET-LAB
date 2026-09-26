<#
.SYNOPSIS
    Wspolne funkcje pomocnicze dla skryptow administracyjnych NismoNET.

.DESCRIPTION
    Plik nie jest uruchamiany samodzielnie. Dolacza sie go na poczatku skryptu
    operatorem kropki, ktory wykonuje zawartosc w biezacym zakresie - dzieki temu
    funkcje staja sie dostepne tak, jakby byly zdefiniowane w samym skrypcie.

        . (Join-Path $PSScriptRoot "NismoLib.ps1")

    Zwykle wywolanie (bez kropki) uruchomiloby plik w osobnym zakresie
    i funkcje zniknelyby natychmiast po jego zakonczeniu.

.EXAMPLE
    . (Join-Path $PSScriptRoot "NismoLib.ps1")

    Start-Log -Name "uprawnienia"

    Write-Log "Poczatek nadawania uprawnien"
    Write-Log "Delegacja dla GG_Helpdesk" -Level OK
    Add-Problem -Item "GG_AdminSieci" -Reason "grupa nie istnieje"

    Stop-Log
#>

# Stan dziennika. Prefiks script: sprawia, ze zmienne naleza do zakresu
# skryptu dolaczajacego, a nie do zakresu globalnego
$script:LogFile     = $null
$script:LogProblems = @()
$script:LogCounters = @{ OK = 0; WARN = 0; ERROR = 0; INFO = 0 }
$script:LogStart    = $null

function Start-Log {
    <#
        Otwiera nowy dziennik. Nazwa pliku zawiera date i godzine, wiec kazde
        uruchomienie ma wlasny plik i historia nie jest nadpisywana.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        # Katalog dziennikow. Domyslnie podkatalog logs obok skryptu
        [string]$Path
    )

    if (-not $Path) {
        $Path = Join-Path $PSScriptRoot "logs"
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }

    $script:LogFile     = Join-Path $Path "$Name-$(Get-Date -Format 'yyyy-MM-dd_HHmm').log"
    $script:LogProblems = @()
    $script:LogCounters = @{ OK = 0; WARN = 0; ERROR = 0; INFO = 0 }
    $script:LogStart    = Get-Date

    Write-Log "=== $Name ===" -Level INFO
    Write-Log "Uzytkownik: $env:USERNAME na $env:COMPUTERNAME" -Level INFO
}

function Write-Log {
    <#
        Zapisuje komunikat jednoczesnie do pliku i na ekran. Bez tego trzeba
        by dublowac kazda linie - raz dla operatora, raz dla dziennika.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","OK","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1,-5}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
        $script:LogCounters[$Level]++
    }

    $color = switch ($Level) {
        "OK"    { "Green"  }
        "WARN"  { "Yellow" }
        "ERROR" { "Red"    }
        default { "Gray"   }
    }

    Write-Host $line -ForegroundColor $color
}

function Add-Problem {
    <#
        Odnotowuje rzecz, ktora sie nie udala. Zapis trafia do dziennika
        i jednoczesnie do kolekcji, z ktorej Stop-Log buduje raport koncowy.

        Item to identyfikator obiektu, ktorego dotyczy problem - login, nazwa
        grupy, numer wiersza w pliku wejsciowym. Bez niego dziennik mowi,
        ze cos padlo, ale nie mowi co.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Item,

        [Parameter(Mandatory)]
        [string]$Reason,

        [ValidateSet("WARN","ERROR")]
        [string]$Level = "WARN",

        # Dodatkowy kontekst, np. numer wiersza CSV albo nazwa etapu
        [string]$Context
    )

    $text = if ($Context) { "$Item ($Context): $Reason" } else { "$Item : $Reason" }
    Write-Log $text -Level $Level

    $script:LogProblems += [PSCustomObject]@{
        Czas    = Get-Date -Format "HH:mm:ss"
        Poziom  = $Level
        Obiekt  = $Item
        Kontekst = $Context
        Powod   = $Reason
    }
}

function Stop-Log {
    <#
        Zamyka dziennik: wypisuje podsumowanie, a przy wykrytych problemach
        zestawienie na ekranie oraz raport w formacie CSV.

        Dziennik jest chronologiczny i sluzy do odtworzenia przebiegu.
        Raport jest zestawieniem i sluzy do poprawienia danych wejsciowych.
    #>
    param(
        # Pomija zapis raportu CSV, gdy wystarczy samo podsumowanie na ekranie
        [switch]$NoReport
    )

    if (-not $script:LogFile) {
        Write-Warning "Dziennik nie zostal otwarty - wywolaj najpierw Start-Log"
        return
    }

    $duration = (Get-Date) - $script:LogStart

    Write-Log ("Podsumowanie: sukcesow {0}, ostrzezen {1}, bledow {2}, czas {3:mm\:ss}" -f `
        $script:LogCounters.OK,
        $script:LogCounters.WARN,
        $script:LogCounters.ERROR,
        $duration) -Level INFO

    if ($script:LogProblems.Count -gt 0) {

        Write-Host ""
        Write-Host "Nie powiodlo sie:" -ForegroundColor Yellow
        $script:LogProblems |
            Format-Table Poziom, Obiekt, Kontekst, Powod -AutoSize -Wrap

        if (-not $NoReport) {
            $reportFile = [System.IO.Path]::ChangeExtension($script:LogFile, "csv")
            $script:LogProblems | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
            Write-Host "Raport:   $reportFile" -ForegroundColor Cyan
        }
    }

    Write-Host "Dziennik: $script:LogFile" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-Step {
    <#
        Wykonuje blok kodu, zapisujac wynik do dziennika. Zdejmuje ze skryptu
        powtarzalna konstrukcje try/catch przy kazdej operacji.

        Zwraca wartosc logiczna, dzieki czemu mozna uzaleznic kolejne kroki
        od powodzenia poprzedniego.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        # Identyfikator obiektu trafiajacy do raportu przy niepowodzeniu
        [string]$Item
    )

    if (-not $Item) { $Item = $Description }

    try {
        & $Action
        Write-Log $Description -Level OK
        return $true
    }
    catch {
        Add-Problem -Item $Item -Reason $_.Exception.Message -Level ERROR -Context $Description
        return $false
    }
}
