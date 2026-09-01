// Praxis-Formularhelfer v0.9 - Direktdruck-Erweiterung
(function(){
  const API="http://127.0.0.1:8765";

  async function pfhDirectPrint(documentId, patientName){
    try{
      const r=await fetch(`${API}/print/${documentId}`,{cache:"no-store"});
      const data=await r.json();

      if(!r.ok || !data.ok){
        throw new Error(data.fehler || "Druckauftrag konnte nicht gestartet werden");
      }

      const root=document.getElementById("praxis-formularhelfer");
      if(root){
        const notice=document.createElement("div");
        notice.className="pfh-ok";
        notice.textContent=`Druckauftrag für ${patientName} gestartet`;
        root.appendChild(notice);
        setTimeout(()=>notice.remove(),3500);
      }
    }catch(e){
      alert("Druckauftrag fehlgeschlagen: "+e.message);
    }
  }

  window.pfhDirectPrint=pfhDirectPrint;
})();
