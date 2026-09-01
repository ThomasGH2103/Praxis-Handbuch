// Praxis-Formularhelfer v0.8.1 - MkDocs Integration
// Fix: Patient wird auf ALLEN Wiki-Seiten geladen.
// Dadurch werden auch Links auf FO-Seiten personalisiert,
// selbst wenn dort kein <div id="praxis-formularhelfer"></div> vorhanden ist.

(function(){
  const API="http://127.0.0.1:8765";

  function esc(s){
    return String(s||"").replace(/[&<>"']/g,c=>({
      "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
    }[c]));
  }

  function markExternalLinks(){
    document.querySelectorAll('a[href]').forEach(a=>{
      const href=a.getAttribute('href')||'';

      // PDF-Dateien immer extern/neuer Tab
      if(/\.pdf(?:$|[?#])/i.test(href)){
        a.setAttribute('target','_blank');
        a.setAttribute('rel','noopener');
      }

      // Lokale Formularhelfer-Links immer extern/neuer Tab
      if(/^http:\/\/127\.0\.0\.1:8765\//i.test(href)){
        a.setAttribute('target','_blank');
        a.setAttribute('rel','noopener');
      }
    });
  }

  function personalizeFormLinks(patient){
    if(!patient || !patient.name)return;

    document.querySelectorAll('a[href]').forEach(a=>{
      const href=a.getAttribute('href')||'';

      if(/\/FO-5101(?:$|[?#])/i.test(href)){
        a.textContent=`Anamnesebogen für ${patient.name} öffnen`;
        a.setAttribute('target','_blank');
        a.setAttribute('rel','noopener');
      }

      if(/\/FO-5103(?:$|[?#])/i.test(href)){
        a.textContent=`Kostenübernahme für ${patient.name} öffnen`;
        a.setAttribute('target','_blank');
        a.setAttribute('rel','noopener');
      }
    });
  }

  function renderPatientCard(root,p){
    if(!root)return;

    const status=p.bdtAktuell
      ?"PVS-Daten aktuell"
      :p.bestaetigt
        ?"Patient manuell bestätigt"
        :"PVS-Daten abgelaufen";

    let html=`<div class="pfh-card">
      <div class="pfh-title">Aktueller PVS-Patient</div>
      <div class="pfh-patient">${esc(p.name)}</div>
      <div>geb. ${esc(p.geburtsdatum)}</div>
      <div class="${p.druckFreigabe?"pfh-ok":"pfh-warn"}">${esc(status)}</div>`;

    if(!p.druckFreigabe){
      html+=`<button id="pfh-confirm" class="md-button md-button--primary">Dieser Patient ist korrekt</button>`;
    }else{
      html+=`<div class="pfh-actions">
        <a class="md-button md-button--primary"
           target="_blank"
           rel="noopener"
           href="${API}/FO-5101">
           Anamnesebogen für ${esc(p.name)} öffnen
        </a>

        <a class="md-button md-button--primary"
           target="_blank"
           rel="noopener"
           href="${API}/FO-5103">
           Kostenübernahme für ${esc(p.name)} öffnen
        </a>
      </div>`;
    }

    html+=`<div class="pfh-small">BDT aktualisiert: ${esc(p.aktualisiert)}</div></div>`;

    root.innerHTML=html;

    const b=document.getElementById("pfh-confirm");
    if(b){
      b.addEventListener("click",async()=>{
        await fetch(API+"/api/confirm",{method:"POST"});
        await updatePage();
      });
    }
  }

  async function updatePage(){
    const root=document.getElementById("praxis-formularhelfer");

    // Externe Links funktionieren auch, wenn der lokale Helfer nicht erreichbar ist.
    markExternalLinks();

    try{
      const r=await fetch(API+"/api/patient",{cache:"no-store"});
      const p=await r.json();

      if(!p.ok){
        throw new Error(p.fehler||"Keine Patientendaten");
      }

      // WICHTIG: läuft auf jeder Wiki-Seite.
      personalizeFormLinks(p);

      // Nur auf Seiten mit Platzhalter wird zusätzlich die Patientenkachel angezeigt.
      renderPatientCard(root,p);

    }catch(e){
      // Auf Seiten ohne Patientenkachel nichts störendes anzeigen.
      if(root){
        root.innerHTML=`<div class="pfh-card pfh-warn">
          Lokaler Praxis-Formularhelfer nicht erreichbar.
          <br><br>
          <a target="_blank" rel="noopener" href="${API}/status">Status prüfen</a>
        </div>`;
      }
    }
  }

  document.addEventListener("DOMContentLoaded",updatePage);

  // MkDocs Material: bei navigation.instant nach jedem Seitenwechsel erneut anwenden.
  if(typeof document$!=="undefined"){
    document$.subscribe(updatePage);
  }
})();
