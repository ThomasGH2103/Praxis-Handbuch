# Praxis-Formularhelfer v0.6 - lokaler HTTP-Listener
# Wiki -> neuer Tab -> direkt personalisiertes Formular
# Bindet ausschliesslich an 127.0.0.1:8765

$Prefix = "http://127.0.0.1:8765/"
$ProgrammOrdner = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateOrdner = Join-Path $ProgrammOrdner "templates"
$BdtDatei = "C:\gdt\bdt\aktpatexp.bdt"
$TempDir = Join-Path $env:TEMP "Praxis-Formularhelfer"
$ConfirmDatei = Join-Path $TempDir "confirmed-patient.txt"

function Get-BdtField {
    param([string[]]$Zeilen,[string]$FieldId)
    foreach ($Zeile in $Zeilen) {
        if ($Zeile.Length -ge 7 -and $Zeile.Substring(3,4) -eq $FieldId) {
            return $Zeile.Substring(7).Trim()
        }
    }
    return ""
}

function HtmlSafe {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-Patient {
    if (-not (Test-Path $BdtDatei)) {
        return @{Fehler="BDT-Datei nicht gefunden"; DruckFreigabe=$false}
    }

    try {
        $Zeilen = Get-Content $BdtDatei -ErrorAction Stop
        $Vorname = Get-BdtField $Zeilen "3102"
        $Nachname = Get-BdtField $Zeilen "3101"
        $Geb = Get-BdtField $Zeilen "3103"
        $Strasse = Get-BdtField $Zeilen "3107"
        $PlzOrt = Get-BdtField $Zeilen "3106"
        $Telefon = Get-BdtField $Zeilen "3626"
        $Email = Get-BdtField $Zeilen "3619"

        if ($Geb -match '^\d{8}$') {
            $GebAnzeige = $Geb.Substring(0,2)+"."+$Geb.Substring(2,2)+"."+$Geb.Substring(4,4)
        } else {
            $GebAnzeige = $Geb
        }

        $Info = Get-Item $BdtDatei
        $Alter = ((Get-Date) - $Info.LastWriteTime).TotalMinutes

        $Source = "$Vorname|$Nachname|$Geb|$($Info.LastWriteTimeUtc.Ticks)|$($Info.Length)"
        $Sha = [System.Security.Cryptography.SHA256]::Create()
        $Bytes = $Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Source))
        $Fingerprint = ([BitConverter]::ToString($Bytes)).Replace("-","").ToLowerInvariant()

        $Bestaetigt = $false
        if (Test-Path $ConfirmDatei) {
            $Saved = (Get-Content -Raw $ConfirmDatei -ErrorAction SilentlyContinue).Trim()
            $Bestaetigt = ($Saved -eq $Fingerprint)
        }

        return @{
            Fehler=""
            Name=("$Vorname $Nachname").Trim()
            Vorname=$Vorname
            Nachname=$Nachname
            Geburtsdatum=$GebAnzeige
            Strasse=$Strasse
            PlzOrt=$PlzOrt
            Telefon=$Telefon
            Email=$Email
            Aktualisiert=$Info.LastWriteTime.ToString("dd.MM.yyyy HH:mm:ss")
            AlterMinuten=[math]::Round($Alter,1)
            Fingerprint=$Fingerprint
            BdtAktuell=($Alter -le 10)
            Bestaetigt=$Bestaetigt
            DruckFreigabe=(($Alter -le 10) -or $Bestaetigt)
        }
    } catch {
        return @{Fehler=$_.Exception.Message; DruckFreigabe=$false}
    }
}

function Add-CorsHeaders {
    param($Response)
    $Response.Headers["Access-Control-Allow-Origin"] = "*"
    $Response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    $Response.Headers["Access-Control-Allow-Headers"] = "Content-Type"
    $Response.Headers["Cache-Control"] = "no-store"
}

function Send-Text {
    param($Response,[int]$Code,[string]$Type,[string]$Body)
    Add-CorsHeaders $Response
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $Code
    $Response.ContentType = $Type
    $Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes,0,$Bytes.Length)
    $Response.OutputStream.Close()
}

function Send-Json {
    param($Response,[int]$Code,$Object)
    Send-Text $Response $Code "application/json; charset=utf-8" ($Object | ConvertTo-Json -Compress)
}

function Render-Form {
    param([string]$TemplateName,$Patient)

    $Pfad = Join-Path $TemplateOrdner $TemplateName
    if (-not (Test-Path $Pfad)) { return $null }

    $Html = Get-Content -Raw -Encoding UTF8 $Pfad
    $Map = @{
        "{{VORNAME}}"      = HtmlSafe $Patient.Vorname
        "{{NACHNAME}}"     = HtmlSafe $Patient.Nachname
        "{{GEBURTSDATUM}}" = HtmlSafe $Patient.Geburtsdatum
        "{{STRASSE}}"      = HtmlSafe $Patient.Strasse
        "{{PLZORT}}"       = HtmlSafe $Patient.PlzOrt
        "{{TELEFON}}"      = HtmlSafe $Patient.Telefon
        "{{EMAIL}}"        = HtmlSafe $Patient.Email
        "{{DATUM}}"        = (Get-Date).ToString("dd.MM.yyyy")
    }

    foreach ($K in $Map.Keys) {
        $Html = $Html.Replace($K,$Map[$K])
    }

    return $Html
}

$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add($Prefix)

try { $Listener.Start() } catch { exit 1 }

while ($Listener.IsListening) {
    $Context = $null

    try {
        $Context = $Listener.GetContext()
        $Req = $Context.Request
        $Res = $Context.Response

        $Remote = $Req.RemoteEndPoint.Address.ToString()
        if ($Remote -ne "127.0.0.1" -and $Remote -ne "::1") {
            Send-Text $Res 403 "text/plain; charset=utf-8" "Zugriff verweigert."
            continue
        }

        if ($Req.HttpMethod -eq "OPTIONS") {
            Add-CorsHeaders $Res
            $Res.StatusCode = 204
            $Res.Close()
            continue
        }

        $Path = $Req.Url.AbsolutePath.TrimEnd("/")
        if (-not $Path) { $Path = "/" }

        if ($Path -ieq "/api/patient") {
            $P = Get-Patient
            Send-Json $Res 200 @{
                ok=(-not [bool]$P.Fehler)
                name=$P.Name
                vorname=$P.Vorname
                nachname=$P.Nachname
                geburtsdatum=$P.Geburtsdatum
                aktualisiert=$P.Aktualisiert
                alterMinuten=$P.AlterMinuten
                bdtAktuell=$P.BdtAktuell
                bestaetigt=$P.Bestaetigt
                druckFreigabe=$P.DruckFreigabe
                fehler=$P.Fehler
            }
            continue
        }

        if ($Path -ieq "/api/confirm") {
            $P = Get-Patient
            if ($P.Fehler) {
                Send-Json $Res 409 @{ok=$false;fehler=$P.Fehler}
                continue
            }
            New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
            [System.IO.File]::WriteAllText(
                $ConfirmDatei,
                $P.Fingerprint,
                (New-Object System.Text.UTF8Encoding($false))
            )
            Send-Json $Res 200 @{ok=$true;name=$P.Name}
            continue
        }

        if ($Path -ieq "/status" -or $Path -eq "/") {
            $P = Get-Patient

            if ($P.BdtAktuell) {
                $Text = "PVS-Daten aktuell"
                $Class = "ok"
            } elseif ($P.Bestaetigt) {
                $Text = "Patient manuell bestätigt"
                $Class = "ok"
            } else {
                $Text = "PVS-Daten abgelaufen - bitte Patient bestätigen"
                $Class = "warn"
            }

            $Confirm = if (-not $P.DruckFreigabe) {
                '<button onclick="confirmPatient()">Dieser Patient ist korrekt</button>'
            } else { '' }

            $Buttons = if ($P.DruckFreigabe) {
                $N = HtmlSafe $P.Name
                '<p><a target="_blank" rel="noopener" href="/FO-5101">Anamnesebogen für '+$N+' öffnen</a></p><p><a target="_blank" rel="noopener" href="/FO-5103">Kostenübernahme für '+$N+' öffnen</a></p>'
            } else {
                '<p>Drucken derzeit gesperrt.</p>'
            }

            $Body = @"
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>Praxis-Formularhelfer</title>
<style>
body{font-family:Arial;margin:32px}
.card{max-width:650px;border:1px solid #bbb;border-radius:8px;padding:22px}
.ok{color:#176b32;font-weight:bold}
.warn{color:#a12622;font-weight:bold}
a,button{display:inline-block;padding:10px 14px;margin:5px 0;border:1px solid #777;border-radius:5px;background:#fff;color:#111;text-decoration:none;cursor:pointer}
</style>
<script>
async function confirmPatient(){
    await fetch('/api/confirm',{method:'POST'});
    location.reload();
}
</script>
</head>
<body>
<div class="card">
<h2>Praxis-Formularhelfer v0.6</h2>
<p><strong>Aktueller Patient:</strong><br>$(HtmlSafe $P.Name)<br>$(HtmlSafe $P.Geburtsdatum)</p>
<p>BDT aktualisiert: $($P.Aktualisiert)</p>
<p class="$Class">$Text</p>
$Confirm
$Buttons
</div>
</body>
</html>
"@

            Send-Text $Res 200 "text/html; charset=utf-8" $Body
            continue
        }

        if ($Path -ieq "/FO-5101" -or $Path -ieq "/FO-5103") {
            $P = Get-Patient

            if (-not $P.DruckFreigabe) {
                Send-Text $Res 409 "text/html; charset=utf-8" '<!doctype html><meta charset="utf-8"><body style="font-family:Arial;margin:32px"><h2>Drucken gesperrt</h2><p>Bitte zuerst den aktuellen Patienten bestätigen.</p><p><a href="/status">Zum Formularhelfer</a></p></body>'
                continue
            }

            $Template = if ($Path -ieq "/FO-5101") {
                "FO-5101-Sportboottauglichkeit-Anamnesebogen.html"
            } else {
                "FO-5103-Sportboottauglichkeit-Kostenuebernahmevereinbarung.html"
            }

            $Html = Render-Form $Template $P

            if ($null -eq $Html) {
                Send-Text $Res 500 "text/plain; charset=utf-8" "Druckvorlage nicht gefunden."
                continue
            }

            # Direkt das personalisierte Formular ausliefern.
            # Danach automatisch den normalen Browser-Druckdialog öffnen.
            $PrintScript = @"
<script>
window.addEventListener("load", function () {
    setTimeout(function () {
        window.print();
    }, 300);
});
</script>
"@

            if ($Html -match "</body>") {
                $Html = $Html.Replace("</body>", $PrintScript + "</body>")
            }
            else {
                $Html += $PrintScript
            }

            Send-Text $Res 200 "text/html; charset=utf-8" $Html
            continue
        }

        Send-Text $Res 404 "text/plain; charset=utf-8" "Nicht gefunden."
    }
    catch {
        try {
            if ($Context -and $Context.Response) {
                $Context.Response.OutputStream.Close()
            }
        } catch {}
    }
}
