# Praxis-Formularhelfer v0.9.4 - SVG-Vektor-Logo-Test (Basis: funktionierende v0.9)
# Druckt FO-5101 / FO-5103 direkt auf den Windows-Standarddrucker.

param(
    [ValidateSet("FO-5101","FO-5103")]
    [string]$DocumentId
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName ReachFramework
Add-Type -AssemblyName System.Printing

$BdtDatei = "C:\gdt\bdt\aktpatexp.bdt"
$LogoSvg  = "C:\Praxis-Formularhelfer\assets\praxis-logo.svg"

function Get-BdtField {
    param([string[]]$Zeilen,[string]$FieldId)
    foreach($Zeile in $Zeilen){
        if($Zeile.Length -ge 7 -and $Zeile.Substring(3,4) -eq $FieldId){
            return $Zeile.Substring(7).Trim()
        }
    }
    return ""
}

function Get-Patient {
    if(-not (Test-Path $BdtDatei)){
        throw "BDT-Datei nicht gefunden: $BdtDatei"
    }

    $Zeilen = Get-Content $BdtDatei -ErrorAction Stop

    $Nachname = Get-BdtField $Zeilen "3101"
    $Vorname  = Get-BdtField $Zeilen "3102"
    $Geb      = Get-BdtField $Zeilen "3103"
    $Strasse  = Get-BdtField $Zeilen "3107"
    $PlzOrt   = Get-BdtField $Zeilen "3106"
    $Telefon  = Get-BdtField $Zeilen "3626"
    $Email    = Get-BdtField $Zeilen "3619"

    if($Geb -match '^\d{8}$'){
        $GebAnzeige = $Geb.Substring(0,2)+"."+$Geb.Substring(2,2)+"."+$Geb.Substring(4,4)
    } else {
        $GebAnzeige = $Geb
    }

    return @{
        Nachname=$Nachname
        Vorname=$Vorname
        Name=("$Vorname $Nachname").Trim()
        Geburtsdatum=$GebAnzeige
        Strasse=$Strasse
        PlzOrt=$PlzOrt
        Telefon=$Telefon
        Email=$Email
    }
}

function New-Text {
    param(
        [string]$Text,
        [double]$Size = 11,
        [switch]$Bold,
        [double]$Bottom = 4
    )
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.FontSize = $Size
    $tb.TextWrapping = "Wrap"
    $tb.Margin = New-Object System.Windows.Thickness(0,0,0,$Bottom)
    if($Bold){ $tb.FontWeight = [System.Windows.FontWeights]::Bold }
    return $tb
}

function Add-Section {
    param($Panel,[string]$Text)
    $tb = New-Text -Text $Text -Size 12 -Bold -Bottom 5
    $tb.Margin = New-Object System.Windows.Thickness(0,10,0,5)
    $Panel.Children.Add($tb) | Out-Null
}

function Add-Line {
    param($Panel,[double]$Height = 18)
    $b = New-Object System.Windows.Controls.Border
    $b.BorderBrush = [System.Windows.Media.Brushes]::Gray
    $b.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
    $b.Height = $Height
    $b.Margin = New-Object System.Windows.Thickness(0,0,0,3)
    $Panel.Children.Add($b) | Out-Null
}

function New-Page {
    $page = New-Object System.Windows.Documents.FixedPage
    $page.Width = 793.7
    $page.Height = 1122.5

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Width = 670
    # v0.9.5: etwas breiterer linker Rand
    $panel.Margin = New-Object System.Windows.Thickness(65,45,55,45)

    $page.Children.Add($panel) | Out-Null
    return @{Page=$page;Panel=$panel}
}

function Add-Page {
    param($Doc,$Page)
    $pc = New-Object System.Windows.Documents.PageContent
    ([System.Windows.Markup.IAddChild]$pc).AddChild($Page)
    $Doc.Pages.Add($pc)
}


function New-VectorLogo {
    param(
        [string]$SvgPath = $LogoSvg,
        [double]$Width = 58
    )

    if(-not (Test-Path $SvgPath)){
        return $null
    }

    try {
        # SVG wird nur als Vektordatenquelle gelesen. Es wird KEIN WPF-Image/Bitmap erzeugt.
        [xml]$svg = Get-Content -LiteralPath $SvgPath -Raw -ErrorAction Stop
        $root = $svg.DocumentElement

        $viewX = 0.0; $viewY = 0.0; $viewW = 2000.0; $viewH = 2000.0
        $vb = $root.GetAttribute("viewBox")
        if($vb){
            $parts = ($vb -replace ',', ' ') -split '\s+' | Where-Object { $_ -ne '' }
            if($parts.Count -eq 4){
                $viewX = [double]::Parse($parts[0],[Globalization.CultureInfo]::InvariantCulture)
                $viewY = [double]::Parse($parts[1],[Globalization.CultureInfo]::InvariantCulture)
                $viewW = [double]::Parse($parts[2],[Globalization.CultureInfo]::InvariantCulture)
                $viewH = [double]::Parse($parts[3],[Globalization.CultureInfo]::InvariantCulture)
            }
        }

        if($viewW -le 0 -or $viewH -le 0){ throw "Ungültige SVG-viewBox." }

        $canvas = New-Object System.Windows.Controls.Canvas
        $canvas.Width  = $viewW
        $canvas.Height = $viewH
        $canvas.ClipToBounds = $true

        # viewBox-Ursprung berücksichtigen.
        if($viewX -ne 0 -or $viewY -ne 0){
            $canvas.RenderTransform = New-Object System.Windows.Media.TranslateTransform(-$viewX,-$viewY)
        }

        $brushConverter = New-Object System.Windows.Media.BrushConverter
        $pathNodes = $root.SelectNodes("//*[local-name()='path']")

        foreach($node in $pathNodes){
            $d = $node.GetAttribute("d")
            if([string]::IsNullOrWhiteSpace($d)){ continue }

            $shape = New-Object System.Windows.Shapes.Path
            $shape.Data = [System.Windows.Media.Geometry]::Parse($d)

            $fill = $node.GetAttribute("fill")
            if(-not [string]::IsNullOrWhiteSpace($fill) -and $fill -ne 'none'){
                $shape.Fill = $brushConverter.ConvertFromString($fill)
            }

            # Das vorliegende Praxislogo verwendet translate(x,y).
            $tr = $node.GetAttribute("transform")
            if($tr -match '^\s*translate\(\s*([-+0-9.eE]+)(?:[ ,]+([-+0-9.eE]+))?\s*\)\s*$'){
                $tx = [double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)
                $ty = 0.0
                if($Matches[2]){ $ty = [double]::Parse($Matches[2],[Globalization.CultureInfo]::InvariantCulture) }
                $shape.RenderTransform = New-Object System.Windows.Media.TranslateTransform($tx,$ty)
            }
            elseif(-not [string]::IsNullOrWhiteSpace($tr)){
                throw "Nicht unterstützte SVG-Transformation: $tr"
            }

            $canvas.Children.Add($shape) | Out-Null
        }

        if($canvas.Children.Count -eq 0){ throw "Keine druckbaren SVG-Pfade gefunden." }

        $view = New-Object System.Windows.Controls.Viewbox
        $view.Stretch = [System.Windows.Media.Stretch]::Uniform
        $view.StretchDirection = [System.Windows.Controls.StretchDirection]::DownOnly
        $view.Width = $Width
        $view.Height = $Width * ($viewH / $viewW)
        $view.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $view.Margin = New-Object System.Windows.Thickness(0,0,0,4)
        $view.Child = $canvas
        return $view
    }
    catch {
        throw "SVG-Logo konnte nicht als WPF-Vektor aufgebaut werden: $($_.Exception.Message)"
    }
}

function Add-Header {
    param($Panel,[string]$Title,[string]$Subtitle)

    # v0.9.5: kompakter gemeinsamer Praxis-Briefkopf. Der bewährte Druckkern und
    # die reine WPF-Vektorausgabe des Logos bleiben unverändert.
    $header = New-Object System.Windows.Controls.Grid
    $header.Width = 670
    $header.Margin = New-Object System.Windows.Thickness(0,0,0,3)

    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = New-Object System.Windows.GridLength(185)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = New-Object System.Windows.GridLength(250)
    $c3 = New-Object System.Windows.Controls.ColumnDefinition
    $c3.Width = New-Object System.Windows.GridLength(235)
    $header.ColumnDefinitions.Add($c1)
    $header.ColumnDefinitions.Add($c2)
    $header.ColumnDefinitions.Add($c3)

    # Links: Logo und Praxisname
    $left = New-Object System.Windows.Controls.StackPanel
    $logo = New-VectorLogo -Width 64
    if($null -ne $logo){
        $logo.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $left.Children.Add($logo) | Out-Null
    }
    $praxisName = New-Text -Text "Gemeinschaftspraxis Dres. Eckert" -Size 8.4 -Bold -Bottom 0
    $praxisName.TextAlignment = [System.Windows.TextAlignment]::Center
    $praxisName.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $left.Children.Add($praxisName) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($left,0)
    $header.Children.Add($left) | Out-Null

    # Mitte: Dr. med. Dagmar Eckert
    $dagmar = New-Object System.Windows.Controls.StackPanel
    $dagmar.Margin = New-Object System.Windows.Thickness(8,0,0,0)
    $dagmar.Children.Add((New-Text -Text "Dr. med. Dagmar Eckert" -Size 10.5 -Bold -Bottom 2)) | Out-Null
    $dagmar.Children.Add((New-Text -Text "Fachärztin für Allgemeinmedizin`nFachärztin für Anästhesie`nAkupunktur`nNaturheilverfahren`nRegulative Medizin" -Size 8.5 -Bottom 0)) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($dagmar,1)
    $header.Children.Add($dagmar) | Out-Null

    # Rechts: Dr. med. Thomas Eckert
    $thomas = New-Object System.Windows.Controls.StackPanel
    $thomas.Margin = New-Object System.Windows.Thickness(8,0,0,0)
    $thomas.Children.Add((New-Text -Text "Dr. med. Thomas Eckert" -Size 10.5 -Bold -Bottom 2)) | Out-Null
    $thomas.Children.Add((New-Text -Text "Facharzt für Allgemeinmedizin`nFacharzt für Anästhesie`nManuelle Medizin / Chirotherapie`nVerkehrsmedizin`nRegulative Medizin`nOsteopathie D.O. DAAO" -Size 8.5 -Bottom 0)) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($thomas,2)
    $header.Children.Add($thomas) | Out-Null

    $Panel.Children.Add($header) | Out-Null

    # Dezente Trennlinie zwischen Praxisbriefkopf und Formular.
    $sep = New-Object System.Windows.Controls.Border
    $sep.BorderBrush = [System.Windows.Media.Brushes]::Gray
    $sep.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
    $sep.Height = 1
    $sep.Margin = New-Object System.Windows.Thickness(0,0,0,5)
    $Panel.Children.Add($sep) | Out-Null

    $Panel.Children.Add((New-Text -Text $Title -Size 16 -Bold -Bottom 2)) | Out-Null
    $Panel.Children.Add((New-Text -Text $Subtitle -Size 9 -Bottom 8)) | Out-Null
}

function Add-Footer {
    param(
        $Page,
        [string]$DocumentId,
        [string]$Version,
        [int]$PageNumber,
        [int]$PageCount
    )

    # Gemeinsamer Praxis-Footer, direkt auf der FixedPage positioniert.
    # Dadurch bleiben Briefkopf und Formularinhalt unverändert.
    $footer = New-Object System.Windows.Controls.Grid
    $footer.Width = 670
    $footer.Height = 74

    [System.Windows.Documents.FixedPage]::SetLeft($footer,65)
    [System.Windows.Documents.FixedPage]::SetTop($footer,1028)

    $footerBorder = New-Object System.Windows.Controls.Border
    $footerBorder.BorderBrush = [System.Windows.Media.Brushes]::Gray
    $footerBorder.BorderThickness = New-Object System.Windows.Thickness(0,1,0,0)
    $footerBorder.Padding = New-Object System.Windows.Thickness(0,5,0,0)
    $footer.Children.Add($footerBorder) | Out-Null

    $body = New-Object System.Windows.Controls.Grid
    $footerBorder.Child = $body

    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = New-Object System.Windows.GridLength(50)
    $r2 = New-Object System.Windows.Controls.RowDefinition
    $r2.Height = New-Object System.Windows.GridLength(18)
    $body.RowDefinitions.Add($r1)
    $body.RowDefinitions.Add($r2)

    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = New-Object System.Windows.GridLength(250)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = New-Object System.Windows.GridLength(205)
    $c3 = New-Object System.Windows.Controls.ColumnDefinition
    $c3.Width = New-Object System.Windows.GridLength(215)
    $body.ColumnDefinitions.Add($c1)
    $body.ColumnDefinitions.Add($c2)
    $body.ColumnDefinitions.Add($c3)

    $left = New-Object System.Windows.Controls.StackPanel
    $left.Margin = New-Object System.Windows.Thickness(0,0,10,0)
    $left.Children.Add((New-Text -Text "Gemeinschaftspraxis Dres. Eckert" -Size 7.6 -Bold -Bottom 0)) | Out-Null
    $left.Children.Add((New-Text -Text "Am Ringpark 1A · 01640 Coswig" -Size 7.2 -Bottom 0)) | Out-Null
    $left.Children.Add((New-Text -Text "Tel. 03523 / 60403 · Fax 03523 / 530676" -Size 7.2 -Bottom 0)) | Out-Null
    $left.Children.Add((New-Text -Text "www.gemeinschaftspraxis-eckert.de" -Size 7.2 -Bottom 0)) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($left,0)
    [System.Windows.Controls.Grid]::SetRow($left,0)
    $body.Children.Add($left) | Out-Null

    $middle = New-Object System.Windows.Controls.StackPanel
    $middle.Margin = New-Object System.Windows.Thickness(8,0,8,0)
    $middle.Children.Add((New-Text -Text "Sprechzeiten" -Size 7.6 -Bold -Bottom 0)) | Out-Null
    $middle.Children.Add((New-Text -Text "Mo 08:00–12:00 · 14:30–18:00" -Size 7.0 -Bottom 0)) | Out-Null
    $middle.Children.Add((New-Text -Text "Di–Mi 08:00–12:00" -Size 7.0 -Bottom 0)) | Out-Null
    $middle.Children.Add((New-Text -Text "Do 08:00–12:00 · 14:30–18:00" -Size 7.0 -Bottom 0)) | Out-Null
    $middle.Children.Add((New-Text -Text "Fr 08:00–12:00" -Size 7.0 -Bottom 0)) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($middle,1)
    [System.Windows.Controls.Grid]::SetRow($middle,0)
    $body.Children.Add($middle) | Out-Null

    $right = New-Object System.Windows.Controls.StackPanel
    $right.Margin = New-Object System.Windows.Thickness(10,0,0,0)
    $right.Children.Add((New-Text -Text "Bankverbindung" -Size 7.6 -Bold -Bottom 0)) | Out-Null
    $right.Children.Add((New-Text -Text "Apo Bank Düsseldorf" -Size 7.2 -Bottom 0)) | Out-Null
    $right.Children.Add((New-Text -Text "IBAN: DE79 3006 0601 0307 2077 27" -Size 7.0 -Bottom 0)) | Out-Null
    $right.Children.Add((New-Text -Text "BIC: DAAEDEDDXXX" -Size 7.0 -Bottom 0)) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($right,2)
    [System.Windows.Controls.Grid]::SetRow($right,0)
    $body.Children.Add($right) | Out-Null

    $stand = (Get-Date).ToString("dd.MM.yyyy")
    $control = New-Text -Text ("{0} · Version {1} · Stand {2} · Seite {3} von {4}" -f $DocumentId,$Version,$stand,$PageNumber,$PageCount) -Size 6.8 -Bottom 0
    $control.TextAlignment = [System.Windows.TextAlignment]::Right
    $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $control.Margin = New-Object System.Windows.Thickness(0,3,0,0)
    [System.Windows.Controls.Grid]::SetColumnSpan($control,3)
    [System.Windows.Controls.Grid]::SetRow($control,1)
    $body.Children.Add($control) | Out-Null

    $Page.Children.Add($footer) | Out-Null
}

function Add-PatientData {
    param($Panel,$P)
    $text = "Name: $($P.Nachname), $($P.Vorname)    Geburtsdatum: $($P.Geburtsdatum)`n" +
            "Anschrift: $($P.Strasse), $($P.PlzOrt)"
    if($P.Telefon){ $text += "`nTelefon: $($P.Telefon)" }
    if($P.Email){ $text += "    E-Mail: $($P.Email)" }

    $border = New-Object System.Windows.Controls.Border
    $border.BorderBrush = [System.Windows.Media.Brushes]::Gray
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.Padding = New-Object System.Windows.Thickness(8)
    $border.Margin = New-Object System.Windows.Thickness(0,4,0,8)
    $border.Child = New-Text -Text $text -Size 10.5 -Bottom 0
    $Panel.Children.Add($border) | Out-Null
}

function Build-FO5103 {
    param($P)
    $doc = New-Object System.Windows.Documents.FixedDocument
    $pg = New-Page
    $panel = $pg.Panel

    Add-Header $panel "FO-5103 – Sportboottauglichkeit – Kostenübernahmevereinbarung" ("Version 1.0 · " + (Get-Date).ToString("dd.MM.yyyy"))
    Add-PatientData $panel $P

    Add-Section $panel "Vereinbarung"
    $panel.Children.Add((New-Text -Text "Ich wünsche die Durchführung einer ärztlichen Sportboottauglichkeitsuntersuchung einschließlich Ausstellung des ärztlichen Tauglichkeitsnachweises." -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Mir ist bekannt, dass es sich um eine privatärztliche Leistung handelt. Die Abrechnung erfolgt nach der Gebührenordnung für Ärzte (GOÄ)." -Size 10.5)) | Out-Null

    Add-Section $panel "Abrechnung"
    $panel.Children.Add((New-Text -Text "GOÄ 1 · Beratung · Faktor 3,387 · 15,79 €" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "GOÄ 8 · Ganzkörperstatus · Faktor 3,386 · 51,31 €" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "GOÄ 70 · Kurze Bescheinigung / kurzes Zeugnis · Faktor 3,388 · 7,90 €" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Gesamtbetrag: 75,00 €" -Size 11.5 -Bold -Bottom 8)) | Out-Null

    Add-Section $panel "Kostenübernahme und Zahlung"
    $panel.Children.Add((New-Text -Text "Ich wurde vor Beginn der Untersuchung über die Kosten informiert. Ich verpflichte mich, den Rechnungsbetrag von 75,00 € unmittelbar nach Abschluss der Untersuchung in der Praxis zu bezahlen." -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Die Zahlung ist per Barzahlung oder Kartenzahlung möglich." -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Eine mögliche Erstattung durch eine private Krankenversicherung, Beihilfestelle oder einen sonstigen Kostenträger ist von dieser Vereinbarung unabhängig. Eine vollständige oder teilweise Nichterstattung berührt meine Zahlungsverpflichtung nicht." -Size 10.5)) | Out-Null

    Add-Section $panel "Zusätzliche medizinische Leistungen"
    $panel.Children.Add((New-Text -Text "Zusätzliche Untersuchungen oder Leistungen aufgrund auffälliger Befunde oder besonderer medizinischer Umstände sind nicht Bestandteil des Betrages von 75,00 €. Über zusätzliche kostenpflichtige Leistungen werde ich vor deren Durchführung informiert." -Size 10.5)) | Out-Null

    Add-Section $panel "Bestätigung"
    $panel.Children.Add((New-Text -Text "Ich habe die vorstehenden Informationen gelesen und hatte Gelegenheit, Fragen zu stellen. Ich erkläre mich mit der Durchführung der Untersuchung und der Übernahme der genannten Kosten einverstanden." -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "`nCoswig, den __________________________" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "`nUnterschrift Patient/in __________________________________________" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "`nUnterschrift Praxis ______________________________________________" -Size 10.5)) | Out-Null

    Add-Footer $pg.Page "FO-5103" "1.0" 1 1
    Add-Page $doc $pg.Page
    return $doc
}

function Build-FO5101 {
    param($P)

    $doc = New-Object System.Windows.Documents.FixedDocument

    $pg1 = New-Page
    $panel = $pg1.Panel
    Add-Header $panel "FO-5101 – Sportboottauglichkeit – Anamnesebogen" ("Version 1.0 · " + (Get-Date).ToString("dd.MM.yyyy"))
    Add-PatientData $panel $P

    Add-Section $panel "Aktuelle gesundheitliche Situation"
    $panel.Children.Add((New-Text -Text "☐ Nein    ☐ Ja    Bestehen derzeit Erkrankungen oder Beschwerden?" -Size 10.5)) | Out-Null
    Add-Line $panel
    $panel.Children.Add((New-Text -Text "☐ Nein    ☐ Ja    Befinden Sie sich derzeit in regelmäßiger ärztlicher Behandlung?" -Size 10.5)) | Out-Null
    Add-Line $panel

    Add-Section $panel "Vorerkrankungen"
    foreach($q in @(
        "Herz-Kreislauf-Erkrankung",
        "Bluthochdruck",
        "Herzrhythmusstörungen",
        "Bewusstlosigkeit / Synkopen",
        "Schwindel / Gleichgewichtsstörungen",
        "Epilepsie / Krampfanfälle",
        "Schlaganfall / neurologische Erkrankung",
        "Diabetes mellitus",
        "Unterzuckerungen / Hypoglykämien",
        "Schlafapnoe",
        "Narkolepsie / ausgeprägte Tagesschläfrigkeit",
        "Asthma / chronische Atemwegserkrankung",
        "Psychische Erkrankung",
        "Sehbeeinträchtigung / Doppelbilder / Gesichtsfeld",
        "Hörminderung",
        "Erkrankung / Einschränkung des Bewegungsapparates"
    )){
        $panel.Children.Add((New-Text -Text ("☐ Nein    ☐ Ja    " + $q) -Size 10.2 -Bottom 3)) | Out-Null
    }
    Add-Footer $pg1.Page "FO-5101" "1.0" 1 2
    Add-Page $doc $pg1.Page

    $pg2 = New-Page
    $panel = $pg2.Panel
    Add-Header $panel "FO-5101 – Anamnesebogen – Fortsetzung" ("$($P.Name) · geb. $($P.Geburtsdatum)")

    Add-Section $panel "Medikamente"
    $panel.Children.Add((New-Text -Text "☐ Nein    ☐ Ja    Nehmen Sie regelmäßig oder bei Bedarf Medikamente ein?" -Size 10.5)) | Out-Null
    4 | ForEach-Object { Add-Line $panel 24 }
    $panel.Children.Add((New-Text -Text "Aktueller Medikamentenplan liegt vor:    ☐ Ja    ☐ Nein" -Size 10.5)) | Out-Null

    Add-Section $panel "Alkohol und andere Substanzen"
    $panel.Children.Add((New-Text -Text "☐ Nein    ☐ Ja    Besteht oder bestand eine Abhängigkeit von Alkohol, Medikamenten oder anderen Substanzen?" -Size 10.5)) | Out-Null
    Add-Line $panel 24

    Add-Section $panel "Krankenhausbehandlungen und Operationen"
    $panel.Children.Add((New-Text -Text "☐ Nein    ☐ Ja    Gab es relevante Krankenhausbehandlungen oder Operationen?" -Size 10.5)) | Out-Null
    Add-Line $panel 24
    Add-Line $panel 24

    Add-Section $panel "Sehvermögen"
    $panel.Children.Add((New-Text -Text "Sehhilfe:    ☐ keine    ☐ Brille    ☐ Kontaktlinsen" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Bekannte Augenerkrankung:    ☐ Nein    ☐ Ja" -Size 10.5)) | Out-Null
    Add-Line $panel
    $panel.Children.Add((New-Text -Text "Nachweis einer anerkannten Sehteststelle liegt vor:    ☐ Ja    ☐ Nein" -Size 10.5)) | Out-Null

    Add-Section $panel "Hörvermögen"
    $panel.Children.Add((New-Text -Text "Bekannte Hörminderung:    ☐ Nein    ☐ Ja" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Hörgerät:    ☐ Nein    ☐ Ja" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "Externer Hörnachweis liegt vor:    ☐ Ja    ☐ Nein" -Size 10.5)) | Out-Null

    Add-Section $panel "Weitere Angaben"
    $panel.Children.Add((New-Text -Text "Bestehen weitere gesundheitliche Einschränkungen, die Wahrnehmung, Reaktionsfähigkeit, Beweglichkeit oder die sichere Führung eines Sportbootes beeinträchtigen könnten?    ☐ Nein    ☐ Ja" -Size 10.5)) | Out-Null
    Add-Line $panel 24
    Add-Line $panel 24

    Add-Section $panel "Erklärung"
    $panel.Children.Add((New-Text -Text "Ich bestätige, dass ich die vorstehenden Fragen vollständig und nach bestem Wissen beantwortet habe. Mir ist bekannt, dass für die ärztliche Beurteilung vollständige und wahrheitsgemäße Angaben erforderlich sind." -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "`nCoswig, den __________________________" -Size 10.5)) | Out-Null
    $panel.Children.Add((New-Text -Text "`nUnterschrift Patient/in __________________________________________" -Size 10.5)) | Out-Null

    Add-Footer $pg2.Page "FO-5101" "1.0" 2 2
    Add-Page $doc $pg2.Page
    return $doc
}

try {
    $P = Get-Patient

    if($DocumentId -eq "FO-5103"){
        $Doc = Build-FO5103 $P
    } else {
        $Doc = Build-FO5101 $P
    }

    $Server = New-Object System.Printing.LocalPrintServer
    $Queue = $Server.DefaultPrintQueue

    if($null -eq $Queue){
        throw "Kein Windows-Standarddrucker eingerichtet."
    }

    $Writer = [System.Printing.PrintQueue]::CreateXpsDocumentWriter($Queue)
    if($null -eq $Writer){
        throw "Druckauftrag konnte nicht erstellt werden."
    }

    $Writer.Write($Doc.DocumentPaginator)

    [System.Windows.MessageBox]::Show(
        "Druckauftrag für $($P.Name) wurde an den Standarddrucker gesendet:`n`n$($Queue.FullName)",
        "Praxis-Formularhelfer",
        "OK",
        "Information"
    ) | Out-Null
}
catch {
    [System.Windows.MessageBox]::Show(
        "Direktdruck fehlgeschlagen:`n`n$($_.Exception.Message)",
        "Praxis-Formularhelfer",
        "OK",
        "Error"
    ) | Out-Null
    exit 1
}
