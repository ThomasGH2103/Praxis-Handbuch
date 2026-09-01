# Praxis-Formularhelfer v0.5
# Gemeinschaftspraxis Dres. Eckert
#
# Funktionen:
# - liest aktuellen PVS-Patienten aus C:\gdt\bdt\aktpatexp.bdt
# - zeigt GUI mit aktuellem Patienten
# - öffnet FO-5101 / FO-5103 als personalisierte HTML-Druckvorlage
# - kann vom lokalen HTTP-Listener direkt mit -OpenForm aufgerufen werden
#
# Windows PowerShell 5.1:
# Datei bitte als UTF-8 mit BOM speichern.

param(
    [ValidateSet("", "FO-5101", "FO-5103")]
    [string]$OpenForm = "",
    [switch]$NoConfirm
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$BdtDatei = "C:\gdt\bdt\aktpatexp.bdt"
$ProgrammOrdner = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateOrdner = Join-Path $ProgrammOrdner "templates"

function Get-BdtField {
    param(
        [string[]]$Zeilen,
        [string]$FieldId
    )

    foreach ($Zeile in $Zeilen) {
        if ($Zeile.Length -ge 7) {
            $Kennung = $Zeile.Substring(3,4)
            if ($Kennung -eq $FieldId) {
                return $Zeile.Substring(7).Trim()
            }
        }
    }

    return ""
}

function Get-AktuellerPatient {
    if (-not (Test-Path $BdtDatei)) {
        return @{ Fehler = "BDT-Datei wurde nicht gefunden:`n$BdtDatei" }
    }

    try {
        $Zeilen = Get-Content -Path $BdtDatei -ErrorAction Stop

        $Nachname     = Get-BdtField $Zeilen "3101"
        $Vorname      = Get-BdtField $Zeilen "3102"
        $Geburtsdatum = Get-BdtField $Zeilen "3103"
        $PlzOrt       = Get-BdtField $Zeilen "3106"
        $Strasse      = Get-BdtField $Zeilen "3107"
        $Geschlecht   = Get-BdtField $Zeilen "3108"
        $Email        = Get-BdtField $Zeilen "3619"
        $Telefon      = Get-BdtField $Zeilen "3626"

        if ($Geburtsdatum -match '^\d{8}$') {
            $GeburtsdatumAnzeige =
                $Geburtsdatum.Substring(0,2) + "." +
                $Geburtsdatum.Substring(2,2) + "." +
                $Geburtsdatum.Substring(4,4)
        } else {
            $GeburtsdatumAnzeige = $Geburtsdatum
        }

        $DateiInfo = Get-Item $BdtDatei
        $Alter = (Get-Date) - $DateiInfo.LastWriteTime

        return @{
            Fehler          = ""
            Nachname        = $Nachname
            Vorname         = $Vorname
            Geburtsdatum    = $GeburtsdatumAnzeige
            GeburtsdatumRoh = $Geburtsdatum
            Strasse         = $Strasse
            PlzOrt          = $PlzOrt
            Geschlecht      = $Geschlecht
            Email           = $Email
            Telefon         = $Telefon
            Aktualisiert    = $DateiInfo.LastWriteTime
            AlterMinuten    = $Alter.TotalMinutes
        }
    }
    catch {
        return @{
            Fehler = "Fehler beim Lesen der BDT-Datei:`n$($_.Exception.Message)"
        }
    }
}

function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-BrowserPath {
    $Kandidaten = @(
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )

    foreach ($Pfad in $Kandidaten) {
        if (Test-Path $Pfad) { return $Pfad }
    }

    return $null
}

function Open-PatientForm {
    param(
        [string]$TemplateDatei,
        [string]$DokumentId,
        [string]$Kurzname
    )

    $script:Patient = Get-AktuellerPatient

    if ($Patient.Fehler) {
        [System.Windows.MessageBox]::Show(
            $Patient.Fehler,
            "Praxis-Formularhelfer",
            "OK",
            "Error"
        )
        return
    }

    if (-not $NoConfirm) {
        $Bestaetigung = [System.Windows.MessageBox]::Show(
            "Aktueller Patient:`n`n$($Patient.Vorname) $($Patient.Nachname)`n$($Patient.Geburtsdatum)`n$($Patient.Strasse)`n$($Patient.PlzOrt)`n`nFormular:`n$DokumentId - $Kurzname`n`nFormular jetzt zur Vorschau / zum Drucken öffnen?",
            "Patient und Formular prüfen",
            "YesNo",
            "Question"
        )

        if ($Bestaetigung -ne "Yes") { return }
    }

    $TemplatePfad = Join-Path $TemplateOrdner $TemplateDatei

    if (-not (Test-Path $TemplatePfad)) {
        [System.Windows.MessageBox]::Show(
            "Vorlage nicht gefunden:`n$TemplatePfad",
            "Praxis-Formularhelfer",
            "OK",
            "Error"
        )
        return
    }

    $Html = Get-Content -Raw -Encoding UTF8 $TemplatePfad

    $Ersetzungen = @{
        "{{VORNAME}}"      = ConvertTo-HtmlSafe $Patient.Vorname
        "{{NACHNAME}}"     = ConvertTo-HtmlSafe $Patient.Nachname
        "{{GEBURTSDATUM}}" = ConvertTo-HtmlSafe $Patient.Geburtsdatum
        "{{STRASSE}}"      = ConvertTo-HtmlSafe $Patient.Strasse
        "{{PLZORT}}"       = ConvertTo-HtmlSafe $Patient.PlzOrt
        "{{TELEFON}}"      = ConvertTo-HtmlSafe $Patient.Telefon
        "{{EMAIL}}"        = ConvertTo-HtmlSafe $Patient.Email
        "{{DATUM}}"        = (Get-Date).ToString("dd.MM.yyyy")
    }

    foreach ($Schluessel in $Ersetzungen.Keys) {
        $Html = $Html.Replace($Schluessel, $Ersetzungen[$Schluessel])
    }

    $TempBasis = Join-Path $env:TEMP "Praxis-Formularhelfer"
    New-Item -ItemType Directory -Path $TempBasis -Force | Out-Null

    $Zeitstempel = Get-Date -Format "yyyyMMdd-HHmmss"
    $SichererName = (($Patient.Nachname + "-" + $Patient.Vorname) -replace '[^A-Za-z0-9_-]', '_')
    $HtmlDatei = Join-Path $TempBasis "$DokumentId-$SichererName-$Zeitstempel.html"

    [System.IO.File]::WriteAllText(
        $HtmlDatei,
        $Html,
        (New-Object System.Text.UTF8Encoding($true))
    )

    $Browser = Get-BrowserPath

    if ($Browser) {
        Start-Process -FilePath $Browser -ArgumentList "`"$HtmlDatei`""
    } else {
        Start-Process $HtmlDatei
    }
}

# Direkter Aufruf durch den lokalen Listener
if ($OpenForm) {
    if ($OpenForm -eq "FO-5101") {
        Open-PatientForm `
            -TemplateDatei "FO-5101-Sportboottauglichkeit-Anamnesebogen.html" `
            -DokumentId "FO-5101" `
            -Kurzname "Sportboottauglichkeit - Anamnesebogen"
        exit
    }

    if ($OpenForm -eq "FO-5103") {
        Open-PatientForm `
            -TemplateDatei "FO-5103-Sportboottauglichkeit-Kostenuebernahmevereinbarung.html" `
            -DokumentId "FO-5103" `
            -Kurzname "Sportboottauglichkeit - Kostenuebernahmevereinbarung"
        exit
    }
}

function Test-LocalListener {
    try {
        $Client = New-Object System.Net.Sockets.TcpClient
        $Async = $Client.BeginConnect("127.0.0.1", 8765, $null, $null)
        $Ok = $Async.AsyncWaitHandle.WaitOne(250, $false)

        if ($Ok -and $Client.Connected) {
            $Client.EndConnect($Async)
            $Client.Close()
            return $true
        }

        $Client.Close()
    }
    catch {}

    return $false
}

if (-not (Test-LocalListener)) {
    $ListenerScript = Join-Path $ProgrammOrdner "listener.ps1"

    if (Test-Path $ListenerScript) {
        Start-Process powershell.exe `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-WindowStyle", "Hidden",
                "-File", "`"$ListenerScript`""
            ) `
            -WindowStyle Hidden

        Start-Sleep -Milliseconds 400
    }
}

[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Praxis-Formularhelfer"
    Height="500"
    Width="720"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize">

    <Grid Margin="25">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="20"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="25"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
            <TextBlock Text="Praxis-Formularhelfer"
                       FontSize="26"
                       FontWeight="Bold"/>
            <TextBlock Text="Gemeinschaftspraxis Dres. Eckert"
                       FontSize="14"
                       Margin="0,5,0,0"/>
        </StackPanel>

        <Border Grid.Row="2"
                BorderBrush="Gray"
                BorderThickness="1"
                CornerRadius="5"
                Padding="16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="220"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0">
                    <TextBlock Text="Aktueller PVS-Patient"
                               FontSize="17"
                               FontWeight="Bold"
                               Margin="0,0,0,10"/>
                    <TextBlock x:Name="PatientName"
                               FontSize="20"
                               FontWeight="SemiBold"/>
                    <TextBlock x:Name="Geburtsdatum"
                               FontSize="14"
                               Margin="0,4,0,0"/>
                    <TextBlock x:Name="Adresse"
                               FontSize="14"
                               Margin="0,8,0,0"/>
                    <TextBlock x:Name="Kontakt"
                               FontSize="12"
                               Margin="0,8,0,0"/>
                    <TextBlock x:Name="Status"
                               FontSize="12"
                               FontWeight="Bold"
                               Margin="0,10,0,0"/>
                </StackPanel>

                <StackPanel Grid.Column="1"
                            Margin="18,0,0,0"
                            VerticalAlignment="Top">
                    <Button x:Name="ButtonAktualisieren"
                            Content="Patient neu einlesen"
                            Height="38"
                            Margin="0,0,0,10"/>
                    <Button x:Name="ButtonBeenden"
                            Content="Beenden"
                            Height="38"/>
                </StackPanel>
            </Grid>
        </Border>

        <StackPanel Grid.Row="4">
            <TextBlock Text="Sportboottauglichkeit"
                       FontSize="18"
                       FontWeight="Bold"
                       Margin="0,0,0,12"/>

            <Button x:Name="ButtonFO5101"
                    Content="FO-5101 - Anamnesebogen öffnen / drucken"
                    Height="38"
                    Margin="0,0,0,10"
                    FontSize="14"/>

            <Button x:Name="ButtonFO5103"
                    Content="FO-5103 - Kostenübernahmevereinbarung öffnen / drucken"
                    Height="38"
                    FontSize="14"/>
        </StackPanel>

        
    </Grid>
</Window>
"@

$Reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($Reader)

$PatientName         = $Window.FindName("PatientName")
$Geburtsdatum        = $Window.FindName("Geburtsdatum")
$Adresse             = $Window.FindName("Adresse")
$Kontakt             = $Window.FindName("Kontakt")
$Status              = $Window.FindName("Status")
$ButtonFO5101        = $Window.FindName("ButtonFO5101")
$ButtonFO5103        = $Window.FindName("ButtonFO5103")
$ButtonAktualisieren = $Window.FindName("ButtonAktualisieren")
$ButtonBeenden       = $Window.FindName("ButtonBeenden")

function Update-PatientAnzeige {
    $script:Patient = Get-AktuellerPatient

    if ($Patient.Fehler) {
        $PatientName.Text = "Kein Patient verfügbar"
        $Geburtsdatum.Text = ""
        $Adresse.Text = ""
        $Kontakt.Text = ""
        $Status.Text = $Patient.Fehler
        $Status.Foreground = "Red"
        $ButtonFO5101.IsEnabled = $false
        $ButtonFO5103.IsEnabled = $false
        return
    }

    $PatientName.Text = "$($Patient.Vorname) $($Patient.Nachname)"
    $Geburtsdatum.Text = "Geburtsdatum: $($Patient.Geburtsdatum)"
    $Adresse.Text = "$($Patient.Strasse)`n$($Patient.PlzOrt)"

    $KontaktText = ""

    if ($Patient.Telefon) {
        $KontaktText += "Telefon: $($Patient.Telefon)"
    }

    if ($Patient.Email) {
        if ($KontaktText) { $KontaktText += "`n" }
        $KontaktText += "E-Mail: $($Patient.Email)"
    }

    $Kontakt.Text = $KontaktText

    if ($Patient.AlterMinuten -le 10) {
        $Status.Text = "PVS-Daten aktuell | " + $Patient.Aktualisiert.ToString("dd.MM.yyyy HH:mm:ss")
        $Status.Foreground = "DarkGreen"
        $ButtonFO5101.IsEnabled = $true
        $ButtonFO5103.IsEnabled = $true
    } else {
        $Status.Text = "PVS-Daten älter als 10 Minuten - im Wiki kann der Patient manuell bestätigt werden"
        $Status.Foreground = "DarkRed"
        $ButtonFO5101.IsEnabled = $true
        $ButtonFO5103.IsEnabled = $true
    }
}

$ButtonFO5101.Add_Click({
    Open-PatientForm `
        -TemplateDatei "FO-5101-Sportboottauglichkeit-Anamnesebogen.html" `
        -DokumentId "FO-5101" `
        -Kurzname "Sportboottauglichkeit - Anamnesebogen"
})

$ButtonFO5103.Add_Click({
    Open-PatientForm `
        -TemplateDatei "FO-5103-Sportboottauglichkeit-Kostenuebernahmevereinbarung.html" `
        -DokumentId "FO-5103" `
        -Kurzname "Sportboottauglichkeit - Kostenuebernahmevereinbarung"
})

$ButtonAktualisieren.Add_Click({
    Update-PatientAnzeige
})

$ButtonBeenden.Add_Click({
    $Window.Close()
})

Update-PatientAnzeige
$Window.ShowDialog() | Out-Null
