// B07-QA: Bedienungshilfen des Bild-in-Bild-Systemfensters (nur dieser eine Prozess, per PID).
// osascript -l JavaScript pipax.js <pid> list            – Elemente auflisten
// osascript -l JavaScript pipax.js <pid> press <text>    – ersten Knopf, dessen Beschreibung/Titel/Hilfe <text> enthält, per AXPress
// osascript -l JavaScript pipax.js <pid> hover           – nichts (Platzhalter)
function run(argv) {
  const se = Application("System Events");
  const procs = se.processes.whose({unixId: parseInt(argv[0])});
  if (procs.length === 0) return "kein Prozess";
  const p = procs[0];
  const name = "" + p.name();
  if (!/bild-in-bild|picture in picture|pip/i.test(name)) return "abgelehnt: " + name;
  const act = argv[1];
  let out = ["Prozess: " + name + " Fenster=" + p.windows.length];
  const attr = (e, a) => { try { const v = e.attributes.byName(a).value(); return v === null || v === undefined ? "" : "" + v; } catch (x) { return ""; } };
  const els = [];
  for (let wi = 0; wi < p.windows.length; wi++) {
    const w = p.windows[wi];
    let all = [];
    try { all = w.entireContents(); } catch (x) {}
    els.push(w);
    all.forEach(e => els.push(e));
  }
  const info = (e) => {
    let r = "?"; try { r = e.role(); } catch (x) {}
    let acts = ""; try { acts = e.actions().map(a => a.name()).join(","); } catch (x) {}
    return r + " desc='" + attr(e, "AXDescription") + "' title='" + attr(e, "AXTitle") + "' help='" + attr(e, "AXHelp") + "' id='" + attr(e, "AXIdentifier") + "' value='" + attr(e, "AXValue") + "' actions=" + acts;
  };
  if (act === "list") { els.forEach((e, i) => out.push(i + " " + info(e))); return out.join("\n"); }
  if (act === "press") {
    const needle = ("" + argv[2]).toLowerCase();
    for (const e of els) {
      let r = ""; try { r = e.role(); } catch (x) {}
      if (r !== "AXButton" && r !== "AXCheckBox") continue;
      const t = (attr(e, "AXDescription") + " " + attr(e, "AXTitle") + " " + attr(e, "AXHelp") + " " + attr(e, "AXIdentifier")).toLowerCase();
      if (t.indexOf(needle) >= 0) {
        try { e.actions.byName("AXPress").perform(); return "gedrückt: " + info(e); } catch (x) { return "Fehler: " + x + " bei " + info(e); }
      }
    }
    return "nicht gefunden: " + argv[2];
  }
  return "unbekannt";
}
