Praxis-Formularhelfer v0.9 - Direktdruck

Diese Version fuegt den Direktdruck auf den Windows-Standarddrucker hinzu.

Dateien:
- print-form.ps1
- listener-v0.9-snippet.ps1
- mkdocs/praxis-formularhelfer-v0.9-print.js

Wichtig:
Diese ZIP ist als Update fuer Ihren funktionierenden v0.8.1/v0.7-Stand gedacht.

Windows:
1. print-form.ps1 nach C:\Praxis-Formularhelfer kopieren.
2. Den Inhalt aus listener-v0.9-snippet.ps1 in listener.ps1 direkt vor den
   bestehenden /FO-5101-/FO-5103-Endpunkten einfuegen.
3. Alten Listener beenden und Praxis-Formularhelfer neu starten.

Danach sind lokal erreichbar:
http://127.0.0.1:8765/print/FO-5101
http://127.0.0.1:8765/print/FO-5103

MkDocs:
Der vorhandene JS-Code muss die Druckbuttons auf diese /print/-Endpunkte legen.
Die beigefuegte JS-Datei stellt die Hilfsfunktion pfhDirectPrint() bereit.

Hinweis:
Der Direktdruck verwendet WPF/FixedDocument und den Windows-Standarddrucker.
Der Browser wird fuer den eigentlichen Druckauftrag nicht verwendet.
