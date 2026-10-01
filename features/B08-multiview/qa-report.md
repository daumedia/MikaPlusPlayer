# B08 · Multiview — Testbericht

Durchlauf 1 · Stand: 2026-09-26 · Geprüft gegen `spec.md` vom 2026-09-16 (Status `rekonstruiert`, Stand `c01f1cf` + Reparatur B01)
· Geprüfter Code: **aktueller Arbeitsbaum** (`c01f1cf` + Reparaturen B01, B09, B10 Teil 1, Branch `sdd/rueckerfassung`, nicht committet).
Die B08-Dateien `MultiviewScreen.swift`, `MultiviewTile.swift` und `ChannelRowView.swift` (⊞) sind gegenüber `c01f1cf` unverändert,
`MultiviewSession.swift` trägt nur die Resolver-Anbindung aus B01. `MultiviewScreen.swift` ist auch gegenüber dem ausgelieferten Tag
`v1.1` unverändert (`git diff v1.1 -- Sources/Views/MultiviewScreen.swift` leer). Die Fundstellen der Spec stimmen.

Dieser Durchlauf setzt einen abgebrochenen Durchlauf (API-Limit) fort. Übernommen wurden dessen Tests (`Tests/B08/`, 42 Fälle), die
Absturznachstellungen in Debug und Release mit Absturzberichten, die Neustartprüfung und die Nachweisbilder. Ergänzt wurden echte
Mausklicks bei aktiver App (Fokuswechsel, verdecktes X, VLC-Hauptbild), der ⊞-Weg ohne Zugangsdaten und mit Dublette über die
Oberfläche, die Wiederholung von BF-101/BF-97 mit vier VLC-Kacheln und die Nachprüfung der Code-Review-Funde (davon einer neu
ausgeführt: schwarzes VLC-Bild im Raster nach dem Entfernen).

## Fazit

**Production-ready: nein** · höchster Schweregrad: **kritisch** (BUG-01)

Die Grundfunktion trägt und ist jetzt ausgeführt belegt: ⊞ in Senderliste, Favoriten-Tab und im echten Hauptfenster fügt hinzu und holt
das Fenster „Multiview“ (1280 × 720 pt, Größe über den Neustart gemerkt) nach vorn, ohne einen Player zu öffnen; höchstens vier Streams,
der fünfte erzeugt keine Verbindung; der erste hat Ton, jeder weitere ist stumm – am `AVPlayer` bzw. am VLC-Audiokanal gemessen; ein
echter Mausklick auf eine Kachel verlegt Ton, Etikett und Rahmen (Fokus und Raster); Entfernen und Schließen im Fokus-Layout geben jede
Engine frei und schließen die Stream-Verbindungen nach 0,0–0,8 s, auch bei ladenden Kacheln; Belegung, Fokus und Layout werden nirgends
gespeichert; Kacheln zeigen weder Adresse noch Zugangsdaten; AVKit-Fehler erscheinen je Kachel, die anderen laufen weiter.

Durchgefallen sind alle zwölf ⚠-Kriterien. Schwer wiegen drei Funde. **BUG-01 (kritisch)**: Im Raster-Layout stürzt die App ab
(„Index out of range“, `MultiviewScreen.swift:79`) – beim Schließen des Fensters mit einem wie mit vier Streams und beim Entfernen per X
von 3 auf 2 und von 1 auf 0 Streams, in Debug **und Release** mit Absturzbericht; mit einem Stream ist der Umschalter zurück zu „Fokus“
gesperrt, der Nutzer sitzt in der Falle. Der Code steckt unverändert im ausgelieferten `v1.1`. **BUG-02 (hoch)**: Nach einem echten Klick
auf eine VLC-Kachel – jeder Xtream-Sender im Standardformat MPEG-TS – bleibt das große Bild schwarz (100 % nach 1–15 s und nach
Größenänderung), während genau dieser Stream Ton hat; die Website verspricht, dass das große Bild mitwandert. Dieselbe Ursache lässt im
Raster nach dem Entfernen der ersten Kachel die nachrückende, fokussierte Kachel schwarz (Fund des Code-Reviews, ausgeführt). **BUG-04 (hoch)**: Das X des
großen Streams liegt unter der ersten kleinen Kachel; sechs echte Klicks darauf verlegten den Fokus hin und her (2 → 0 → 1 → 0 → 1 → 0 → 1)
und entfernten nichts. Da im Raster das Entfernen bei 3 → 2 abstürzt, gibt es für den fokussierten Stream keinen sicheren Mausweg.

Hoch ist außerdem die Kachel-Ausprägung von BF-96 (BUG-07): VLC-Kacheln mit 404, geschlossenem Port, Abbruch oder Hänger zeigen endlos die
Ladeanzeige, Schwarz oder ein Standbild, nie eine Meldung. Mittel sind der Klick auf den abgeblendeten ⊞, der den Player mit Ton und
fünfter Verbindung öffnet (BUG-03), die Kacheln, die nach dem Löschen der Playlist mit Zugangsdaten weiterlaufen (BUG-05 = BF-56), und die
fehlende Rückmeldung beim Anbieterlimit (BUG-06: Limit 1 → eine Kachel spielt, drei laden endlos). Niedrig: Dublette ohne Hinweis
(BUG-08, wartet auf OF-01), ⊞ ohne Zugangsdaten öffnet ein leeres Fenster ohne Meldung (BUG-09, wartet auf OF-02) und das bis 105 × 106 pt
verkleinerbare Fenster, in dem die kleinen Kacheln über den Rand laufen (BUG-10).

BF-101 (libVLC-Hänger beim Erzeugen neuer Player während des Abbaus) wurde mit vier VLC-Kacheln im echten Fenster in 26 Runden
(104 Player abgebaut, 104 sofort neu erzeugt, 1,5 s bzw. 10 s Spielzeit) **nicht** reproduziert; BF-97 trifft Multiview nicht, alle
Player waren nach 0,1–0,6 s frei. Nicht prüfbar blieben EC-08 (natives Vollbild) und EC-09 (Fensterwiederherstellung nach Neustart).

Nächster Schritt: `/sdd-build B08` mit BUG-01 bis BUG-10 (BUG-05 gemeinsam mit B03 BF-56, BUG-07 gemeinsam mit B06 BF-96), danach
`/sdd-qa B08` (Durchlauf 2). Wegen BUG-01 (kritisch, Code läuft in `v1.1`) **pausiert die Erfassung der weiteren Bestandsfeatures**.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 34 von 34 |
| davon bestanden | 22 |
| davon durchgefallen | 12 (alle zwölf ⚠-Kriterien) |
| **nicht prüfbar** | 0 |
| Edge Cases belegt | 13 von 15 ausgeführt, davon 1 abweichend (EC-10); EC-08, EC-09 nicht prüfbar |
| Tests neu geschrieben | 46 in `Tests/B08/` (42 aus dem abgebrochenen Teil übernommen, davon AK-29 angepasst; 4 neu) |
| Tests grün | 35 von 35 ausgeführten im Gesamtlauf (46 Fälle, davon 11 nur mit Umgebungsvariable – separat ausgeführt, siehe *Neue Tests*) |

## Prüfumgebung

| Was | Wie |
|---|---|
| Kopie | `scratchpad/qa1-b08/` (am Ende gelöscht; rsync ohne `build`, `.git`, `.xcodeproj`, `web/node_modules`, `web/.next`), mit dem Repo abgeglichen (`diff -rq Sources`: nur `Info.plist` der Kopie), `xcodegen generate`, eigene DerivedData `dd/` (Debug) und `dd-release/` (Release). **Eigene Bundle-IDs** `lu.daumedia.MikaPlusPlayer.b08qa` (Test-Host) und `…b08qatests`; Sparkle-Feed der Kopie auf `http://127.0.0.1:9`, automatische Prüfung aus |
| Datenbank, Schlüsselbund | Test-Host ⇒ `AppEnvironment.isRunningTests`: Datenbank in-memory, Schlüsselbund nur im Dienst `lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>` (im `tearDown` geleert). Die App wurde **nie regulär gestartet**; `default.store` und der Ordner der installierten App wurden weder gelesen noch beschrieben |
| Build/Test | `xcodebuild build-for-testing` / `test-without-building -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -only-testing:MikaPlusPlayerTests/B08…` (ohne `-collect-test-diagnostics`) |
| Absturzfälle | je Fall ein eigener Test-Host-Prozess (`TEST_RUNNER_B08_ABSTURZ=<fall>`), Debug und Release (`-configuration Release`, `-O`); Absturzberichte aus `~/Library/Logs/DiagnosticReports` nur mit Bundle-ID `…b08qa`, im Repo nur als Auszug (`qa/AK-23-absturz-protokoll.txt`) |
| Oberfläche | echte Szenen der App im Test-Host: Fenster „Multiview“ (`Window`), Hauptfenster (`WindowGroup`, Import über das echte Sheet), dazu Senderlisten-/Favoritenfenster mit derselben Session. Klicks als synthetische Mausereignisse; Tipp-Gesten der Kacheln reagieren nur bei **aktiver** App mit Ereignissen über die Warteschlange (`NSApp.postEvent`) – dafür holt ein Helfer der Kopie (`tools/front`, setzt `AXFrontmost` für die PID des Test-Hosts, am Ende beendet) den Test-Host auf Anforderung nach vorn |
| Streams | `B08StreamServer` im Prozess auf 127.0.0.1 (zufälliger Port): `player_api.php`, M3U, roher TS in Echtzeit, Live-HLS, 404, Hänger, Abbruch, Segment-404, Verbindungslimit je Benutzer mit 403 |
| Ton | keiner: alle Medien mit `ffmpeg -an` erzeugt und vor dem ersten Abspielen mit `ffprobe` geprüft (0 Audiospuren in 11 Dateien); jede Engine sofort auf Lautstärke 0 (`isMuted` bleibt prüfbar), jeder `AVPlayer` beim Anhängen an eine Videofläche auf 0. **Keine Tasten** in der Fortsetzung (siehe AK-29) |
| Zugangsdaten | nur erfunden: `qa-user` / `qa-pass-123` |
| Rechner | Apple Silicon, macOS 27.0 (26A428). Parallel liefen QA-Läufe anderer Features (Aktivierung wurde mehrfach übernommen und je Klick erneuert) |

## Akzeptanzkriterien im Einzelnen

Testnamen ohne Klasse: `B08SessionTests` (S), `B08OberflaecheTests` (O), `B08HauptfensterTests` (H), `B08NeustartTests` (R),
`B08AbsturzTests` (A), `B08NachtragTests` (N). Bilder und Protokolle unter `features/B08-multiview/qa/`, Testprotokoll `qa/testlauf.log`
(Fortsetzung) und `qa/testlauf-teil1-abgebrochen.log` (abgebrochener Teil). `<pass>` steht für das erfundene Passwort.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | O `testAK01_AK02_AK09_…`: Karten mit Tooltip „Zu Multiview hinzufügen“ in Senderliste und Favoriten-Tab (`AK-01-senderliste-plus.png`, `AK-01-favoriten-plus.png`); Klick auf ⊞ → `slots=["Alpha HLS"]`, Fenster „Multiview“ 1280 × 720, Titel der Liste vorher/nachher „QA Liste“ (kein Player); zweiter ⊞ → vorderstes Fenster „Multiview“. H `testAK01_AK21_…`: **echtes Hauptfenster** (`WindowGroup`), Playlist über das echte Import-Sheet, Senderliste → ⊞ → `slots=["Echt 1"]` (`AK-01-echtes-hauptfenster-senderliste.png`) |
| AK-02 | ✅ bestanden | H: erstes Öffnen ohne gespeicherte Größe → Titel „Multiview“, 1280 × 720 pt. R `testAK02_AK24_EC09_…` in zwei Prozessen: Phase 1 setzt (200, 150, 960 × 600), Autosave `NSWindow Frame multiview` = `200 150 960 600 …`; Phase 2 (neuer Prozess) öffnet mit (200, 150, 960 × 600) |
| AK-03 | ✅ bestanden | S `testAK03_EC01_EC03_…`: nach dem ersten `A HLS` `muted=false`, `AVPlayer.isMuted=false`; B (VLC), C (AVKit), D (VLC) je `muted=true`, VLC `audio.muted=1`; Fokus bleibt 0 |
| AK-04 | ✅ bestanden | S `testAK04_…`: 4 Slots, fünfter `add` → 0 Anfragen, 4 offene Verbindungen. O `testAK04_AK05_AK21_EC06_…`: Tooltip „Multiview voll (max. 4)“ in Liste **und** Favoritenfenster; Kontrast des ⊞ von 25,06 auf 3,85 (15 %) (`AK-04-liste-voll.png`, `AK-04-favoriten-voll.png`, `AK-04-multiview-vier.png`) |
| AK-05 ⚠ | ❌ durchgefallen | O `testAK04_AK05_…`: Klick auf den abgeblendeten ⊞ von „Kanal 5 HLS“ → Fenstertitel „QA Voll“ → „Kanal 5 HLS“ (Player), neuer `AVPlayer` mit `isMuted=false`, 7 Anfragen für Kanal 5 zusätzlich zu 4 offenen TS-Verbindungen; im Multiview hat der fokussierte Stream weiter Ton (`AK-05-klick-auf-grauen-plus-oeffnet-player.png`). Stumm geprüft: Medium ohne Tonspur, Lautstärke 0 → **BUG-03** |
| AK-06 ⚠ | ❌ durchgefallen | S `testAK06_…`: zwei Kacheln „Doppelt“, verschiedene IDs und Engines, 2 Verbindungen auf denselben Pfad. N `testAK06_AK07_…` über die Oberfläche: zweimal ⊞ auf „Doppel TS“ → `["Doppel TS", "Doppel TS"]`, 2 Verbindungen, Tooltip danach weiter „Zu Multiview hinzufügen“, kein Hinweis (`AK-06-derselbe-sender-zweimal.png`) → **BUG-08** (wartet auf OF-01) |
| AK-07 ⚠ | ❌ durchgefallen | S `testAK07_…`: Xtream-Sender ohne Schlüsselbund-Eintrag → 0 Kacheln, 0 Anfragen, Resolver wirft. N `testAK06_AK07_…`: Multiview geschlossen, ⊞ in der Senderliste → Fenster „Multiview“ öffnet sich mit Leerzustand, kein Sheet, kein Hinweisfenster, 0 Anfragen (`AK-07-plus-ohne-zugangsdaten-leeres-fenster.png`) → **BUG-09** (wartet auf OF-02 = B01 OF-11) |
| AK-08 | ✅ bestanden | O `testAK08_AK19_…`: Symbol, „Kein Stream im Multiview“ und der Hinweistext wörtlich, Schwarzanteil > 95 % (`AK-08-leerzustand.png`); nach dem X der letzten Kachel bleibt das Fenster sichtbar, wieder mit Leerzustand |
| AK-09 | ✅ bestanden | O `testAK01_AK02_AK09_…`: Menü „Window“ = `Minimize, Zoom, —, Multiview, —, Bring All to Front, —, …`, Tastenkürzel leer; zweimal über das Menü geöffnet → genau **ein** Multiview-Fenster mit Leerzustand |
| AK-10 | ✅ bestanden | O `testAK10_…` (Fenster 1280 × 720 bei x 320): Inhalt 1280 × 668, großes Bild füllt ihn, Akzentrahmen links gemessen (Rotanteil 0,94); kleine Kacheln 240 × 135 bei x 1344 (= 16 pt vom rechten Rand), y-Abstand 143 (8 pt), obere Kante 16 pt unter dem Inhaltsrand, Reihenfolge des Hinzufügens; Etiketten „Volume High“ (fokussiert) und „Mute“; X mit Tooltip „Stream entfernen“ (`AK-10-fokus-vier.png`) |
| AK-11 | ✅ bestanden | O `testAK11_AK12_AK13_…`: Kachel 638 × 332 (4 pt Abstand), X-Lagen bei 2 → zwei nebeneinander, bei 3 → zwei oben, eines unten links (unten rechts leer), bei 4 → 2 × 2 (`AK-11-raster-vier.png`); ein Stream füllt das Fenster (`AK-13-raster-ein-stream-umschalter-gesperrt.png`); Akzentrahmen am fokussierten (`AK-14-raster-klick-unten-links-aktive-app.png`) |
| AK-12 | ✅ bestanden | O: Umschalter bei 0/1 Streams `aktiv=false`, ab 2 `aktiv=true`; Klick auf „Raster“ wirkt. O `testAK12_…`: nach Schließen und Öffnen `layout=grid`. R Phase 2: nach Neustart `layout=focus` |
| AK-13 ⚠ | ❌ durchgefallen | O `testAK11_AK12_AK13_…`: Raster auf einen Stream reduziert → `Fokus|Raster gewählt=1 aktiv=false`, kein Weg zurück zu „Fokus“; Schließen in diesem Zustand stürzt ab (A `testAK23_RasterMitEinemFensterSchliessen`, Debug und Release) → **BUG-01** |
| AK-14 | ✅ bestanden | N `testAK14_AK15_AK16_…` mit **echten Klicks bei aktiver App**: Fokus-Layout, Klick auf die zweite kleine Kachel → `fokus=2`, nur sie `muted=false` (auch `AVPlayer.isMuted`), Etiketten oben→unten „Drei HLS, Eins HLS, Zwei TS“ (Tausch mit dem großen Bild, `AK-14-fokus-klick-kleine-kachel.png`); Klick auf das große Bild → Fokus bleibt 2. Raster: Klick unten links → `fokus=2`, `muted=[t, t, f, t]` (`AK-14-raster-klick-unten-links-aktive-app.png`). S `testAK14_AK17_…`: erneuter Fokus auf den fokussierten und ungültige Indizes ändern nichts |
| AK-15 ⚠ | ❌ durchgefallen | O `testAK14_AK15_…`: VLC-Paar, Fokuswechsel → Schwarzanteil des großen Bildes vorher 0,00, nach 1/5/10/15 s und nach Größenänderung je **1,00**, nach Raster ↔ Fokus 0,00; HLS-Paar durchgehend 0,00 (`AK-15-vlc-nach-fokuswechsel-*.png`, `AK-15-hls-*.png`). N mit echtem Klick: 0,00 → 1,00 (2 s) → 1,00 (10 s), `VLC B` hat Ton (`AK-15-vlc-echter-klick-10s.png`) → **BUG-02** |
| AK-16 ⚠ | ❌ durchgefallen | O `testAK16_…`: großes X (1562, 795, 30 × 30) liegt mit seiner Mitte in der ersten kleinen Kachel (1344, 682, 240 × 135). N, aktive App: 6 echte Klicks auf das große X → Fokus `[2, 0, 1, 0, 1, 0, 1]`, 3 Slots bleiben (`AK-16-klicks-aufs-grosse-x-aktive-app.png`); per Bedienungshilfe (`AXPress`) entfernt dasselbe X den Stream → **BUG-04** |
| AK-17 | ✅ bestanden | S `testAK14_AK17_EC02_…`: vor dem Fokus entfernt → Fokus bleibt bei R3; den fokussierten entfernt → Nachfolger R4 `muted=false`; letzter in der Reihe fokussiert und entfernt → Vorgänger R2; nach dem Fokus entfernt → nichts ändert sich; immer genau einer mit Ton; nach `clear` hat der nächste Ton; jeweils auch am eigentlichen Player |
| AK-18 | ✅ bestanden | O `testAK18_…`: Player im Hauptfenster `AVPlayer.isMuted=false`, Multiview-Fokus (VLC) `muted=false` – beide „mit Ton“ (Zustand; hörbar nichts) (`AK-18-player-neben-multiview.png`). Ob das gewollt ist → OF-05 |
| AK-19 | ✅ bestanden | O `testAK08_AK19_…`: X per Mausklick → Engine frei und Verbindung zu nach 0,8 s ab Klick. S `testAK19_EC05_…`: VLC spielt/lädt (Hänger), AVKit spielt/lädt (Hänger) → alle Engines sofort frei, alle Stream-Verbindungen nach **0,0 s** zu, keine HLS-Abrufe nach 1 s. Hinweis H-1 (leere Keep-alive-Verbindungen) |
| AK-20 | ✅ bestanden | O `testAK20_AK21_…`: roter Knopf (`performClose`) im Fokus mit 4 → `slots=0`, Engines 4/4 frei, Verbindungen nach 0,2 s zu, Tooltip in beiden Fenstern wieder „Zu Multiview hinzufügen“; nächster ⊞ → Fenster offen mit `["S5"]`. S `testAK20_…`: `clear` → Stream-Verbindungen nach 0,0 s zu |
| AK-21 | ✅ bestanden | H: zwei echte Hauptfenster; drei ⊞ im zweiten → Tooltip „Multiview voll (max. 4)“ in **beiden** (`AK-21-erstes-hauptfenster-voll.png`, `AK-21-zweites-…`), Schließen des Multiview leert für beide. O: Liste und Favoritenfenster ebenso |
| AK-22 | ✅ bestanden | O `testAK22_EC07_…`: minimiert → +421.120 B in 3 s (2 Streams); alle Listenfenster zu → +644.840 B in 3 s (3 Streams), Verbindungen offen |
| AK-23 ⚠ | ❌ durchgefallen | A, je Fall eigener Prozess, **Debug und Release**: Raster + Schließen mit 4 → Absturz; mit 1 → Absturz; X 3 → 2 → Absturz; X 1 → 0 → Absturz. Absturzbericht jeweils `EXC_BREAKPOINT`, „Swift runtime failure: Index out of range“ ← `Array.subscript.getter` ← `MultiviewScreen.gridLayout.getter` `MultiviewScreen.swift:79` ← `ForEachChild.updateValue()`. Gegenproben ohne Absturz: X 4 → 3 (Debug, Release), X 2 → 1 (Debug), Fokus + Schließen mit 4 (Debug, Release), Beenden bei offenem Raster (EC-15) (`qa/AK-23-absturz-protokoll.txt`, `AK-23-vorher-raster-*.png`; die acht Rohberichte der Bundle-ID `…b08qa` liegen in `~/Library/Logs/DiagnosticReports/`) → **BUG-01** |
| AK-24 | ✅ bestanden | R Phase 2 (neuer Prozess): `slots=0`, `layout=focus`, `fokus=0`; S `testAK24_AK34_…` |
| AK-25 | ✅ bestanden | S `testAK25_AK26_…` und O `testAK25_AK26_AK32_…`: 404 → „Wiedergabe fehlgeschlagen“ + „The requested URL was not found on this server.“, Port zu → „Could not connect to the server.“, je nach 0,1 s; kein „Erneut versuchen“ in der Kachel; die anderen Kacheln spielen weiter (`AK-25-26-fehler-je-kachel.png`). Englische Systemtexte → B01 OF-06 |
| AK-26 ⚠ | ❌ durchgefallen | S `testAK25_AK26_…`: VLC 404 und Port zu → `idle` (Ladeanzeige) bei 3, 8, 16, 25 s; Abbruch nach Start → `playing` (Standbild); Hänger → `playing` (Schwarz ohne Ladeanzeige); HLS mit Segment-404 ab 6 s → 20 s lang `playing`, 7 Segment-404, keine Meldung. O: Kachel „404 TS“ zeigt nur die Ladeanzeige → **BUG-07** (= BF-96) |
| AK-27 ⚠ | ❌ durchgefallen | S `testAK27_EC14_Angriff8_…` (Datenbank auf Datei): Playlist gelöscht → SQLite `ZPLAYLIST=0`, `ZCHANNEL=0`, Schlüsselbund-Eintrag weg; **2 von 2** Verbindungen `/live/qa-user/<pass>/…` offen, +289.520 B in 2 s; kein Absturz, Namen lesbar → **BUG-05** (= BF-56) |
| AK-28 ⚠ | ❌ durchgefallen | S `testAK28_…`: nach dem Aktualisieren mit neuen `stream_id`s spielt die Kachel weiter `/live/qa-user/<pass>/101.ts`; derselbe Sender kommt ein zweites Mal mit `…/201.ts` hinzu → `["QA Kanal 1", "QA Kanal 1"]` → **BUG-05** (= BF-56) |
| AK-29 | ✅ bestanden | O `testAK29_…`, ausgeführt **einmal im abgebrochenen Teil** (16:34, `testlauf-teil1-abgebrochen.log`) mit Beep-Wächter (ersetzt `noResponderFor:`): Leertaste, M, F, P, ↑, ↓, Esc, 1, Tab → Zustand vorher = nachher, **7 von 9** Tasten erreichten das Ende der Responder-Kette (`AppDelegate keyDown:`, abgefangen), `firstResponder=VLCVideoLayerView`; Menüeintrag ohne Kürzel. In der Fortsetzung auf Anweisung „ohne Ton“ nicht wiederholt, Test jetzt nur mit `B08_TASTEN=1`. Abweichung → siehe unten |
| AK-30 ⚠ | ❌ durchgefallen | S `testAK30_…`: offene Verbindungen nach 1…4 Xtream-Kacheln = 1, 2, 3, 4, je `/live/qa-user/<pass>/10x.ts`, UA `VLC/3.0.21 LibVLC/3.0.21`; O AK-05: Player als fünfte; keine Prüfung, kein Hinweis → **BUG-06** |
| AK-31 ⚠ | ❌ durchgefallen | S `testAK31_…`: Limit 1 → Kanal 1 `playing`, Kanäle 2–4 je `[403, 403, 403, 403]` in 2–4 ms, dann `idle`; O: 3 Ladeanzeigen, 0 Fehlermeldungen nach 10 s (`AK-31-anbieterlimit-eine-verbindung.png`) → **BUG-06** |
| AK-32 | ✅ bestanden | O `testAK25_AK26_AK32_…`: alle Accessibility-Texte der vier Kacheln (2 M3U-AVKit-Fehler, VLC-404, Xtream-Kachel) enthalten nur Namen, „Wiedergabe fehlgeschlagen“ und Engine-Text; Suche nach `qa-user`, Passwort, `127.0.0.1`, `/live/` → 0 Treffer (`lecks=[]`) |
| AK-33 | ✅ bestanden | App-Subsystem `lu.daumedia` im Unified Log des Test-Hosts: **0** Zeilen; `grep -rnE 'print\(|Logger|os_log|NSLog' Sources/` → 0. Regulär gestarteter Ersatzprozess (AVPlayer wie eine HLS-Kachel, Xtream-Adresse mit Passwort): 470 Zeilen, 0 × Passwort, 0 × `/live/`, Adresse nur als `url hash` (`qa/AK-33-ersatzprozess-log.txt`). Im **Test-Host** schreibt das Network-Framework die volle Adresse samt Passwort (6 Zeilen, `qa/angriff4-log-auszug.txt`) – wie B06 EC-10/BF-43, nicht die App |
| AK-34 | ✅ bestanden | S `testAK24_AK34_…` (Datenbank auf Datei): nach Hinzufügen, Fokus, Entfernen `hasChanges=false`, Store- und WAL-Datei byte-gleich, keine neuen Einstellungsschlüssel außer dem Fenster-Autosave von macOS (AK-02), kein Schlüsselbund-Eintrag |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | S `testAK03_…` und N: AVKit- und VLC-Kacheln gemischt, Ton-Fokus wirkt auf beide gleich |
| EC-02 | ✅ belegt | S: fokussierter Stream ohne Tonspur `muted=false`, der andere `muted=true` (Medien ohne Tonspur, Lautstärke 0) |
| EC-03 | ✅ belegt | S: VLC direkt nach `add` (Zustand `loading`) → `audio.muted=true` sofort |
| EC-04 | ✅ belegt | S `testEC04_…`: 8 s pausiert, Engine gehalten → VLC-Verbindung offen, AVKit ruft die HLS-Playlist 4 × ab |
| EC-05 | ✅ belegt | S `testAK19_EC05_…`: Kachel mit nie antwortendem Server (VLC und AVKit) entfernt → Engine frei, Verbindung nach 0,0 s zu |
| EC-06 | ✅ belegt | O `testAK04_…`: Tooltip im Favoritenfenster nach 1, 2, 3 „Zu Multiview hinzufügen“, nach 4 „Multiview voll (max. 4)“, ohne Neuladen |
| EC-07 | ✅ belegt | O `testAK22_EC07_…`: ⊞ bei minimiertem Multiview → Fenster wiederhergestellt und sichtbar, 3 Slots (Spec: gelesen) |
| EC-08 | ⚠️ nicht prüfbar | Natives Vollbild wechselt den Space des gemeinsamen Bildschirms; parallel liefen Fensteraufnahmen anderer QA-Läufe. Nicht ausgelöst |
| EC-09 | ⚠️ nicht prüfbar | `xcodebuild` startet den Test-Host mit `-ApplePersistenceIgnoreState YES` (R Phase 2: 0 Multiview-Fenster beim Start); ein regulärer App-Start ist wegen `AppPersistence.prepareStore` ausgeschlossen |
| EC-10 | ❌ weicht ab | O `testEC10_EC11_…`: `minSize` = `contentMinSize` = 105 × 106 pt; auf die kleinste Größe gezogen → Inhalt 105 × 54, unterste kleine Kachel endet 383 pt **unter** dem Fensterboden, Umschalter und Kacheln nicht sichtbar (`EC-10-kleinstes-fenster.png`) → **BUG-10** |
| EC-11 | ✅ belegt | O: Name mit 460 Zeichen → einzeilig „Sehr langer Sendername Sehr la…“ |
| EC-12 | ✅ belegt | O `testAK10_…`: Bild-in-Bild-Controller je Kachel `AVKit: angelegt`, `VLC: –` |
| EC-13 | ✅ belegt | O `testAK10_…`: Test-Host mit 4 Streams (2 HLS, 2 TS, Debug), je 3 Proben in zwei Läufen: CPU 8,4–17,5 %, RSS 184–255 MB |
| EC-14 | ✅ belegt | S `testAK27_EC14_…`: nach dem Löschen `setFocus(1)` und `remove` ohne Absturz, `modelContext == nil`, `isDeleted=false`, Namen lesbar (Session-Ebene; die Kachel liest nur `name`) |
| EC-15 | ✅ belegt | A `testEC15_…`: `NSApp.terminate` bei offenem Raster mit 2 → Prozess endet, **kein** Absturzbericht (`qa/AK-23-absturz-protokoll.txt`) |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf eine lokale App ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | bestanden | S `testAngriff1_…`: Slot-ID einer anderen Session entfernen, Fokus-Index 5, erfundene UUID → beide Sessions unverändert (1/1); Xtream-Sender auf eine fremde Playlist ohne Schlüsselbund-Eintrag umgehängt → 0 Kacheln, **0** Anfragen, keine fremden Zugangsdaten |
| 2 · Zugriffsregeln (Betriebssystem) | = BF-98, BF-09 | Release-Entitlements der Kopie `app-sandbox=false`, `disable-library-validation=true`; im Multiview parsen bis zu vier libVLC-Instanzen gleichzeitig unvertraute Streams im Prozess, der die Xtream-Zugangsdaten lesen darf. Kein neuer Befund |
| 3 · Rate Limit / Wiederholversuche | teils, **BUG-06** | S `testAngriff3_…`: 10 × `add` desselben Senders → 4 Slots, 4 Verbindungen (Grenze greift); 5 Zyklen Leeren/Füllen → nach jedem Leeren 0 offen, insgesamt 24 Verbindungen, nichts sammelt sich an. Ein Anbieterlimit kennt die App nicht (AK-30, AK-31) |
| 4 · PII in Protokollen | bestanden (Hinweis) | App schreibt nichts (AK-33). Test-Host: Network-Framework mit Adresse samt Passwort (6 Zeilen, nur Entwicklerkontext, = BF-43); regulärer Prozess: `url hash`, 0 Treffer (`qa/angriff4-log-auszug.txt`, `qa/AK-33-ersatzprozess-log.txt`) |
| 5 · PII an externe Dienste | bestanden | S `testAngriff5_…`, tatsächlicher Payload am Mock: VLC `GET /live/qa-user/<pass>/101.ts` mit `accept`, `accept-language: en_US`, `host`, `range: bytes=0-`, `user-agent: VLC/3.0.21 LibVLC/3.0.21`; AVKit `GET /live/qa-user/<pass>/102.m3u8` und Segmente mit `AppleCoreMedia/1.0.0.26A428 (Macintosh; U; Intel Mac OS X 27_0; de_de)`, `x-playback-session-id`. Kein Cookie, keine `Authorization`, nur der Host der Playlist (`qa/angriff5-payload.txt`) – wie in Spec 2.2 |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` über `MultiviewScreen.swift`, `MultiviewTile.swift`, `MultiviewSession.swift` (Commits `d5c5e58`, `54550b2`): 0 Treffer für `password=`, `token=`, `sk_live`, `service_role`, `api_key`, fremde Hosts; `Tests/B08`: nur `127.0.0.1` und `qa-user`/`qa-pass-123`; `strings` über das Release-Binary der Kopie: 0 Treffer |
| 7 · Eingaben | bestanden | S `testAngriff7_…`: Sendernamen leer, 1 Zeichen, 10.000 × „Ä“, Emoji, `'; drop table ZCHANNEL; --`, `<script>alert(1)</script>`, `../../etc/passwd` → als Text angezeigt, kein Absturz; Adresse `file:///etc/passwd` → AVKit „Cannot Open“, Pfad nicht angezeigt (`angriff7-namen-raster.png`, `angriff7-sonderzeichen-dateiadresse.png`). `file://…ts` über libVLC → B06 BF-98 |
| 8 · Löschen | **BUG-05** (= BF-56) | S `testAK27_…`: nach dem Löschen der Playlist 0 Zeilen in `ZPLAYLIST`/`ZCHANNEL`, Schlüsselbund-Eintrag weg – die Kacheln senden Benutzername und Passwort weiter an den Anbieter (2 Verbindungen, +289.520 B in 2 s), bis X oder Schließen |

## Fehler

### BUG-01 · Absturz im Raster beim Schließen des Fensters und beim Entfernen per X — kritisch

**Betrifft:** AK-13, AK-23 (FB-01); US-04
**Reproduktion:**
1. Zwei bis vier Sender per ⊞ ins Multiview, Layout „Raster“
2. Fenster über den roten Knopf schließen – **oder** bei drei Streams ein X klicken (3 → 2) – **oder** auf einen Stream reduzieren und dessen X klicken (1 → 0)
3. Zusatz: Bei einem Stream im Raster ist der Umschalter „Fokus | Raster“ gesperrt; zurück zu „Fokus“ geht nicht
**Erwartet:** Fenster schließt, Kachel verschwindet; nie ein Absturz
**Tatsächlich:** Die App beendet sich mit „Swift runtime failure: Index out of range“ (`EXC_BREAKPOINT`), alle Fenster und ein laufender
Player enden mit. Belegt je Fall in eigenem Prozess, **Debug und Release**, acht Absturzberichte mit identischem Stapel
`MultiviewScreen.gridLayout.getter` `MultiviewScreen.swift:79` ← `ForEachChild.updateValue()` ← `ViewGraphRootValueUpdater`. Ohne Absturz:
4 → 3, 2 → 1, Fokus-Layout, Beenden der App. Wer das Raster benutzt, verliert die App beim Schließen **immer**; mit einem Stream gibt es
keinen Weg hinaus. Der Code ist seit `d5c5e58` unverändert und damit in `v1.1`
**Ort:** `Sources/Views/MultiviewScreen.swift:69-93` (`count`, `columns`, `rows` einmal berechnet, `ForEach(0..<rows, id: \.self)`,
`session.slots[index]` live gelesen, `:79`); Auslöser `:26` (`onDisappear { session.clear() }`) und `MultiviewTile.swift:62` (X);
Sperre `:116` (`.disabled(session.slots.count < 2)`)
**Vorschlag:** Raster über die Slots selbst aufbauen (`ForEach(session.slots)` mit Slot-Identität, z. B. `LazyVGrid`) statt über
Indizes, und das Layout beim Unterschreiten von zwei Streams auf „Fokus“ zurücksetzen.
**Test:** A `testAK23_RasterMitVierFensterSchliessen`, `…MitEinemFensterSchliessen`, `…XVonDreiAufZwei`, `…XVonEinsAufNull` (nur mit
`TEST_RUNNER_B08_ABSTURZ=<fall>`, beenden den Test-Host), Gegenproben ebenda; O `testAK11_AK12_AK13_…` (`XCTExpectFailure("BUG-01 …")`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — In eigener Kopie (eigene Bundle-ID, Test-Host mit Datenbank im Speicher, Sender ohne Mediendaten und Ton) endete jeder Prozess mit „Index out of range“ in `MultiviewScreen.gridLayout` `:79` ← `ForEachChild.updateValue()`: roter Knopf des echten Fensters mit 4 und 1 Stream sowie X per `AXPress` 3 → 2 und 1 → 0, in Debug **und** Release (`-O`), dazu die vier Beleg-Tests der QA in Debug und ein eigenes Fenster ohne QA-Hilfen (`clear()` im Raster stürzt bei jeder Anzahl 1–4 ab), während 4 → 3, 2 → 1 und Fokus + Schließen ohne Absturz blieben und der Umschalter bei einem Stream `aktiv=false` zeigte (nur „kein Weg hinaus“ ist überzeichnet: ein zweiter Stream per ⊞ gibt ihn frei, ⌘Q beendet ohne Absturz); Grad angemessen (kritisch: Absturz im Hauptweg „Multiview schließen“, `MultiviewScreen.swift` seit `v1.1` unverändert).

**Behoben 2026-09-28:** Raster und Fokus-Layout bauen die Kacheln über `ForEach(session.slots)` auf, gebunden an `Slot.id`;
Lage und Größe bestimmt die neue Anordnung `MultiviewArrangement` (`MultiviewScreen.swift`) – kein Index-Zugriff auf
`session.slots` mehr, der beim Schrumpfen veralten kann. Mit einem Stream im Raster bleibt der Umschalter aktiv und führt
zurück zu „Fokus“ (spec OF-09). Vor der Reparatur reproduziert (Debug, je eigener Prozess): alle vier Fälle enden mit
„Fatal error: Index out of range“ ← `MultiviewScreen.gridLayout` `:79`. Danach bestanden, in Debug **und Release** (`-O`):
`B08AbsturzTests` (vier Fälle und drei Gegenproben, jetzt im Gesamtlauf statt opt-in; nur EC-15 bleibt opt-in, ohne
Absturzbericht), `B08ReparaturTests.testBUG01_RasterLeerenUndEntfernen…` (`clear()` im Raster mit 1–4 Streams, Entfernen
von vorn, hinten und aus der Mitte bis 0), `testBUG01_EinStreamImRasterZurueckZuFokus`; O `testAK11_AK12_AK13_…` ohne
`XCTExpectFailure` (X im Raster 4 → 3 → 2 → 1, dann Klick auf „Fokus“).

### BUG-02 · VLC-Bild bleibt schwarz, sobald eine Kachel ihren Stream wechselt: nach dem Fokuswechsel und im Raster nach dem Entfernen — hoch

**Betrifft:** AK-15 (FB-02), AK-11/AK-19 (Raster nach dem Entfernen, Fund des Code-Reviews); Website-Versprechen
**Reproduktion:**
1. Zwei `.ts`-Sender (VLC, z. B. Xtream im Standardformat) ins Multiview, Layout „Fokus“
2. Auf die kleine Kachel klicken
3. 15 s warten, Fenstergröße ändern; dann Raster und zurück
4. Zweiter Fall: vier `.ts`-Sender im Raster, X der Kachel oben links klicken (4 → 3, stürzt nicht ab)
**Erwartet:** Der angeklickte Stream erscheint groß (`web/content/changelog-overrides.ts:11` „Clicking a tile moves both the sound and the
large picture“, `web/app/page.tsx:44-45`)
**Tatsächlich:** Ton und Etikett wandern, das große Bild ist zu **100 % schwarz** (1, 5, 10, 15 s, nach Größenänderung); erst Raster ↔ Fokus
bringt das Bild zurück. Mit echtem Mausklick bei aktiver App ebenso (0,00 → 1,00 → 1,00). Bei HLS (AVKit) 0 % Schwarz. Im Raster rückt
nach dem X auf die erste Kachel „V2“ (fokussiert, mit Ton) nach oben links – die Zelle ist zu 100 % schwarz, weil die Zellen ihre Identität
über den Index behalten (`CR-raster-nach-x-vorne-vlc.png`)
**Ort:** `Sources/Views/MultiviewScreen.swift:40-46` (große Kachel ohne `.id(slot.id)`), `:74-85` (Rasterzellen mit Index-Identität), `Sources/Services/VLCPlaybackEngine.swift:121-129`
(`VLCPlayerSurface.makeNSView` gibt die eine Zeichenfläche zurück, `updateNSView` leer); Gegenstück `PlayerLayerView.swift:63-65`
**Vorschlag:** Kacheln mit `.id(slot.id)` an ihren Slot binden (Raster als `ForEach(session.slots)`, zugleich Abhilfe für BUG-01) und/oder die
Zeichenfläche in `updateNSView` neu einhängen, wie es `PlayerLayerView` für AVKit tut.
**Test:** O `testAK14_AK15_…`, N `testAK14_AK15_AK16_KlicksBeiAktiverApp`, N `testCR_AK11_AK19_RasterVorneEntfernenVLCBilder` (je `XCTExpectFailure("BUG-02 …")`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — In einer eigenen Kopie (Test-Host, Datenbank im Speicher, Medien ohne Tonspur, Lautstärke 0) ergaben die drei Beleg-Tests erneut einen Schwarzanteil des großen Bildes von 0,00 → 1,00 (1, 5, 10, 15 s, nach Größenänderung, echter Klick 2/10 s) bei HLS 0,00 und im Raster nach dem X auf V1 `[1,00; 0,00; 0,00; 1,00]`; eine zusätzliche Strukturprüfung zeigt die Ursache: Nach `setFocus(1)` hängt die Zeichenfläche des fokussierten VLC-Streams mit Ton in keinem Fenster (`superview = nil`), die des alten Streams sitzt in der kleinen Kachel, auch nach dem Zurückwechseln bleibt es schwarz, und im Raster steckt die Fläche von V2 unter dem Etikett „V3“ und die von V3 unter „V4“, die von V4 fehlt (Bild und Etikett passen also zusätzlich nicht zusammen). Im AK-14-Teil von `testAK14_AK15_AK16_…` blieb der erste Klick ohne Wirkung (Aktivierung), mit BUG-02 hat das nichts zu tun. Grad angemessen.

**Behoben 2026-09-28:** Jede Kachel ist an ihren Slot gebunden (siehe BUG-01) und bleibt bei Fokuswechsel, Layoutwechsel
und Entfernen dieselbe Ansicht. Zusätzlich steckt die VLC-Zeichenfläche in einem Behälter je Einbettung
(`VLCSurfaceHostView`, `VLCPlaybackEngine.swift`), der sie in `updateNSView` und beim Einfügen ins Fenster wieder einhängt
und beim Abbau an eine andere Einbettung derselben Engine weitergibt. Vor der Reparatur reproduziert: N
`testAK14_AK15_AK16_…` mit echtem Klick bei aktiver App → Schwarzanteil 1,00. Danach: O `testAK14_AK15_…VLCUndHLSHauptbildSichtbar`
VLC 0,00 bei 1/5/10/15 s, nach Größenänderung und nach Raster ↔ Fokus; N echter Klick 0,00/0,00; N `testCR_…` drei Bilder;
`testBUG02_VLCZeichenflaecheFolgtIhremStream` (Fläche jedes Streams an seiner Stelle, kleine über der großen, Raster nach
dem Entfernen der ersten Kachel; auch Release).

### BUG-03 · Klick auf den abgeblendeten ⊞ öffnet den Player mit Ton und fünfter Verbindung — mittel

**Betrifft:** AK-05 (FB-03); Sicherheitskatalog 4.2
**Reproduktion:**
1. Vier Sender per ⊞ ins Multiview (⊞ überall abgeblendet, Tooltip „Multiview voll (max. 4)“)
2. In der Senderliste auf den abgeblendeten ⊞ eines fünften Senders klicken
**Erwartet:** Nichts passiert („voll“)
**Tatsächlich:** Der Klick geht an die Karte: Der Player dieses Senders öffnet sich im Hauptfenster (Titel „Kanal 5 HLS“) mit
`isMuted=false`, 7 Anfragen an den Anbieter zusätzlich zu 4 offenen Verbindungen; im Multiview hat der fokussierte Stream weiter Ton – zwei
Streams mit Ton, fünf Verbindungen. Bei einem Abo mit Verbindungslimit scheitert der Player oder verdrängt eine Kachel
**Ort:** `Sources/Views/ChannelRowView.swift:73-85` (`.disabled(!multiview.canAddMore)` `:83`) innerhalb `NavigationLink`
(`ChannelListView.swift:111`, `FavoritesView.swift:24`)
**Vorschlag:** Den Button nicht deaktivieren, sondern bei vollem Multiview wirkungslos machen (Aktion prüft `canAddMore`) bzw. den Klick
mit `.allowsHitTesting`/eigener Geste abfangen, damit er nie die Karte erreicht.
**Test:** O `testAK04_AK05_AK21_EC06_…` (`XCTExpectFailure("BUG-03 …")`)

**Behoben 2026-09-28:** Der ⊞ ist bei vollem Multiview abgeblendet (30 % Deckkraft), aber nicht mehr deaktiviert; seine
Aktion prüft `canAddMore` und tut dann nichts, der Klick erreicht die Karte nicht mehr (`ChannelRowView.swift`). O
`testAK04_AK05_AK21_EC06_…KlickAufGrauBewirktNichts`: Titel bleibt „QA Voll“, 0 Anfragen für Kanal 5, kein neuer Player;
`testBUG03_…` ebenso im Favoriten-Tab. Folge für Bedienungshilfen → spec OF-12.

### BUG-04 · Das X des großen Streams ist im Fokus-Layout nicht erreichbar — hoch

**Betrifft:** AK-16 (FB-04); US-04
**Reproduktion:**
1. Zwei oder mehr Streams, Layout „Fokus“
2. Auf das X oben rechts im großen Bild klicken, mehrmals
**Erwartet:** Der große (fokussierte) Stream wird entfernt
**Tatsächlich:** Die Mitte des X (1562, 795) liegt in der ersten kleinen Kachel (1344–1584, 682–817). Sechs echte Klicks bei aktiver App
verlegten den Fokus `2 → 0 → 1 → 0 → 1 → 0 → 1` und entfernten nichts; per Bedienungshilfe entfernt dasselbe X den Stream. Ausweg nur,
alle anderen zuerst zu entfernen – im Raster stürzt das Entfernen aber bei 3 → 2 ab (BUG-01)
**Ort:** `Sources/Views/MultiviewScreen.swift:41-46` (große Kachel mit X oben rechts, `MultiviewTile.swift:53-75`, 8 pt Innenabstand) und
`:47-64` (kleine Kacheln als Overlay oben rechts, `padding(16)`)
**Vorschlag:** Kleine Kacheln unterhalb der Chrome-Leiste der großen Kachel beginnen lassen (oberen Abstand ≥ X-Höhe + Innenabstand) oder
das X der großen Kachel links bzw. unten platzieren.
**Test:** O `testAK16_…`, N `testAK14_AK15_AK16_KlicksBeiAktiverApp` (je `XCTExpectFailure("BUG-04 …")`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ (mit Einschränkung) — In einer eigenen Kopie (Test-Host, Datenbank im Speicher, HLS ohne Tonspur, Lautstärke 0, App aktiv) verlegten sechs Klicks auf die Mitte des großen X (1577, 810) den Fokus `0 → 1 → 0 → 1 → 0 → 1 → 0` ohne etwas zu entfernen, und beide Beleg-Tests ergaben erneut `[2, 0, 1, 0, 1, 0, 1]` bzw. Entfernen per `AXPress`. Überzeichnet sind aber „nicht erreichbar“ und „Ausweg nur … Raster“: Der nicht verdeckte Rand des X (rechts 1584–1592, oben 817–825, 46 % des X-Rechtecks, sichtbar als dunkle Sichel ohne Kreuz) ist klickbar, denn je ein Klick bei (1589, 810) und bei (1577, 822) entfernte den großen Stream. Außerdem entfernt der Umweg „kleine Kachel anklicken, dann das X des vorher großen, jetzt kleinen Streams“ ihn mit zwei Klicks im Fokus-Layout, ohne Raster und ohne Absturz. Grad angemessen (hoch: Das Kriterium bleibt an der sichtbaren Stelle unerfüllt, im Standard-Layout bei jedem Versuch, und der Fehlklick verlegt den Ton). Die Begründung mit dem Raster-Absturz als einzigem Ausweg sollte entfallen.

**Behoben 2026-09-28:** Die kleinen Kacheln beginnen unterhalb der Leiste des großen Streams, 46 pt unter dem oberen
Inhaltsrand statt 16 pt (8 pt Innenabstand + X fest 30 × 30 pt + 8 pt, `MultiviewMetrics`; spec OF-08). O
`testAK16_XDesGrossenStreamsErreichbar`: großes X (1562, 795, 30 × 30) von keiner Kachel verdeckt, ein Mausklick entfernt
den großen Stream, der nachrückende hat Ton; N mit echtem Klick bei aktiver App ebenso; `testBUG04_…`: von vier auf einen
Stream nur über das große X, je Klick genau einer mit Ton. O `testAK10_…` prüft die neue Lage (46 pt).

### BUG-05 · Kacheln überleben Löschen und Aktualisieren ihrer Playlist, samt Verbindung mit Zugangsdaten — mittel (= BF-56)

**Betrifft:** AK-27, AK-28 (FB-05); Sicherheitskatalog 5.2; B03 BUG-05
**Reproduktion:**
1. Zwei Sender einer Xtream-Playlist (MPEG-TS) ins Multiview
2. Playlist löschen (B03) – bzw. aktualisieren, während der Anbieter neue `stream_id`s liefert
**Erwartet:** Kacheln der gelöschten Playlist enden; nach dem Aktualisieren gilt die neue Adresse
**Tatsächlich:** Nach dem Löschen (Datenbank 0 Zeilen, Schlüsselbund-Eintrag weg) bleiben beide Verbindungen `/live/qa-user/<pass>/…`
offen und streamen (+289.520 B in 2 s); nach dem Aktualisieren spielt die Kachel weiter `101.ts`, ⊞ fügt denselben Sender ein zweites Mal
mit `201.ts` hinzu
**Ort:** `Sources/Services/MultiviewSession.swift:37-41, 54-67`; `Sources/Services/PlaylistImporter.swift:220, 270` (keine Benachrichtigung)
**Vorschlag:** Beim Löschen/Aktualisieren die Slots der Playlist entfernen bzw. neu auflösen (gemeinsam mit B03 BF-56).
**Test:** S `testAK27_EC14_Angriff8_…`, `testAK28_…` (je `XCTExpectFailure("BUG-05 …")`)

**Teil Löschen behoben (durch die B02+B03-Reparatur, zentraler Löschweg):** `PlaylistEvents.willDelete` →
`MultiviewSession.removeSlots(ofPlaylists:)` beendet die Kacheln der gelöschten Playlist samt Verbindung. S
`testAK27_EC14_Angriff8_…` bestand im Ausgangslauf dieses Builds und danach (0 offene Verbindungen mit Zugangsdaten, keine
weiteren Bytes, Session leer, kein Absturz). **Nicht behoben: Teil Aktualisieren** – ob laufende Kacheln umschalten, enden
oder bleiben, ist Produktverhalten (B03 OF-09), die Dublette hängt an OF-01 (spec OF-14); S `testAK28_…` behält sein
`XCTExpectFailure`.

### BUG-06 · N Kacheln = N Verbindungen ohne Rücksicht auf das Anbieterlimit; Kacheln über dem Limit scheitern ohne Meldung — mittel

**Betrifft:** AK-30, AK-31 (FB-06); Sicherheitskatalog 4.2, 4.5
**Reproduktion:**
1. Anbieter (Mock) erlaubt eine Verbindung je Benutzer und antwortet danach mit 403
2. Vier Xtream-Sender (MPEG-TS) per ⊞ hinzufügen, 10 s warten
**Erwartet:** Ein Hinweis, dass das Abo weitere Verbindungen ablehnt (ob die App das Limit vorab kennen soll: OF-03)
**Tatsächlich:** Kachel 1 spielt, Kacheln 2–4 zeigen endlos die Ladeanzeige, 0 Meldungen; VLC fragt je Kachel 4 × in 2–4 ms und gibt still
auf. Ohne Limit hält die App 1…4 Verbindungen mit Benutzername und Passwort im Pfad, ein Player im Hauptfenster (auch über BUG-03)
kommt hinzu; `max_connections` aus `user_info` wird nicht gelesen
**Ort:** `Sources/Services/MultiviewSession.swift:54-67` (einzige Grenze `maxSlots = 4`, `:34`), `Sources/Services/XtreamClient.swift:167-170`
(nur `auth` dekodiert), `Sources/Views/MultiviewTile.swift:35-39`; stille VLC-Fehler = BF-96
**Vorschlag:** Mit BF-96 VLC-Fehler an die Kachel durchreichen (403 → verständliche Meldung „Anbieter lehnt weitere Verbindung ab“) und
`max_connections` beim Hinzufügen berücksichtigen bzw. anzeigen (nach Entscheidung OF-03).
**Test:** S `testAK30_…`, `testAK31_…`, O `testAK25_AK26_AK32_…` (UI-Teil AK-31) (`XCTExpectFailure("BUG-06 …")`)

**Teil Meldung behoben 2026-09-28:** Seit B06 BUG-01 melden sich die abgelehnten VLC-Kacheln („Der Sender konnte nicht
geöffnet werden …“); jetzt steht darunter, solange ein anderer Stream desselben Anbieters (Host und Port) läuft,
„Möglicherweise erlaubt dein Abo nicht so viele Streams gleichzeitig.“ (`MultiviewTile`, `MultiviewSession.otherStreamIsPlaying`).
`testBUG06_…`: Limit 1 → eine Kachel spielt, drei zeigen Meldung und Hinweis; eine allein gescheiterte Kachel ohne Hinweis;
O AK-31-Teil ebenso. **Nicht behoben:** die Rücksicht auf das Limit (`max_connections` auswerten, Kacheln begrenzen, vorab
warnen) – Produktentscheidung spec OF-03; S `testAK30_…` behält sein `XCTExpectFailure`.

### BUG-07 · Kacheln zeigen VLC-Fehler nie, abgebrochene HLS-Segmente 20 s lang nicht — hoch (= BF-96)

**Betrifft:** AK-26; B06 BUG-01 (FB-01)
**Reproduktion:**
1. Kacheln mit `.ts`-Adressen: HTTP 404, geschlossener Port, Abbruch nach dem Start, nie antwortender Server; dazu eine Live-HLS-Kachel,
   deren Segmente ab 6 s mit 404 enden
2. 25 s beobachten
**Erwartet:** Fehlermeldung in der Kachel wie bei AVKit (AK-25)
**Tatsächlich:** 404 und Port zu → Ladeanzeige ohne Ende (Zustand `idle`), Abbruch → Standbild (`playing`), Hänger → Schwarz ohne Ladeanzeige
(`playing`); HLS mit Segment-404 → 20 s `playing` ohne Meldung (danach nicht weiter beobachtet)
**Ort:** `Sources/Services/VLCPlaybackEngine.swift:80-99` (B06), `Sources/Views/MultiviewTile.swift:35-49`
**Vorschlag:** Mit der Reparatur von BF-96 beheben; die Kachel braucht keinen eigenen Code, sobald die Engine `failed` meldet.
**Test:** S `testAK25_AK26_FehlerJeKachel` (`XCTExpectFailure("BUG-07 …")`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — in eigener Kopie lief `testAK25_AK26_FehlerJeKachel` mit den erwarteten Fehlschlägen (VLC 404/Port zu `idle` bei 3/8/16/25 s, Abbruch und Hänger `playing`, HLS nach 20 s `playing` bei 7 Segment-404), und die zusätzlich einzeln gerenderte echte `MultiviewTile` zeigte nach 3, 10, 25 und 45 s in keinem Fall „Wiedergabe fehlgeschlagen“: 404/Port zu Ladeanzeige (libVLC `stopped`, nie `error`), Abbruch Standbild bei 00:00:05.720 (libVLC `paused`), Hänger schwarz ohne Ladeanzeige (`buffering`), HLS nach 45 s mit 21 Segment-404 weiter `playing`; Grad angemessen

**Behoben 2026-09-28:** VLC-Teil durch die B06-Reparatur (BF-96): S `testAK25_AK26_FehlerJeKachel` war im Ausgangslauf
dieses Builds für 404, Port zu und Abbruch grün, der Hänger lädt bis zur Frist. HLS-Teil hier: AVKit gibt bei Live-HLS mit
Segment-404 nie auf (Messung 120 s: Wiedergabezeit steht bei 15,9 s, 57 × 404, Zustand „spielt“). AVKit-Kacheln haben jetzt
eine Frist von 30 s ohne Fortschritt (`AVKitPlaybackEngine.limitStalls(to:)`, gesetzt von `MultiviewSession`; spec OF-11)
→ „Die Verbindung zum Sender wurde unterbrochen.“, danach keine Anfrage mehr. `testBUG07_…`: Meldung 30,2 s nach dem
Stillstand, eine gesunde HLS-Kachel spielt weiter; S `testAK25_AK26_…` (Frist dort 5 s) ohne `XCTExpectFailure`. Der
Player (B06) behält das Verhalten von AVKit.

### BUG-08 · Derselbe Sender kommt ohne Hinweis zweimal ins Multiview — niedrig (wartet auf OF-01)

**Betrifft:** AK-06
**Reproduktion:** ⊞ zweimal auf denselben Sender
**Erwartet:** je nach Entscheidung OF-01: kein zweites Mal bzw. ein Hinweis
**Tatsächlich:** zwei Kacheln gleichen Namens, zwei Engines, zwei Verbindungen auf denselben Pfad; Tooltip bleibt „Zu Multiview hinzufügen“
**Ort:** `Sources/Services/MultiviewSession.swift:54-67` (keine Dublettenprüfung), `Sources/Views/ChannelRowView.swift:74-77`
**Vorschlag:** Nach OF-01 in `add` prüfen (z. B. über `Channel.persistentModelID` bzw. die Adresse) und den ⊞ für laufende Sender kennzeichnen.
**Test:** S `testAK06_…`, N `testAK06_AK07_…` (`XCTExpectFailure("BUG-08 …")`)

**Nicht behoben:** wartet auf OF-01 (Produktentscheidung: Dubletten zulassen, verhindern oder melden). S `testAK06_…`,
N `testAK06_AK07_…` behalten ihr `XCTExpectFailure`.

### BUG-09 · ⊞ ohne Zugangsdaten öffnet ein leeres Multiview ohne Meldung — niedrig (wartet auf OF-02)

**Betrifft:** AK-07; B01 OF-11
**Reproduktion:** Xtream-Playlist, deren Schlüsselbund-Eintrag fehlt; in der Senderliste ⊞ klicken
**Erwartet:** je nach OF-02 eine Meldung („Zugangsdaten fehlen“) statt eines leeren Fensters
**Tatsächlich:** Fenster „Multiview“ öffnet sich mit „Kein Stream im Multiview“, kein Sheet, keine Anfrage an den Anbieter
**Ort:** `Sources/Services/MultiviewSession.swift:57` (`try?` verschluckt `missingCredentials`), `Sources/Views/ChannelRowView.swift:75-76`
(`openWindow` unbedingt)
**Vorschlag:** `add` einen Fehler bzw. ein Ergebnis zurückgeben lassen und das Fenster nur bei Erfolg öffnen, sonst Meldung wie im Player.
**Test:** S `testAK07_…`, N `testAK06_AK07_…` (`XCTExpectFailure("BUG-09 …")`)

**Nicht behoben:** wartet auf OF-02 (= B01 OF-11, Produktentscheidung). S `testAK07_…`, N `testAK06_AK07_…` behalten ihr
`XCTExpectFailure`.

### BUG-10 · Das Multiview lässt sich bis 105 × 106 pt verkleinern; kleine Kacheln laufen über den Rand, Umschalter und X verschwinden — niedrig

**Betrifft:** EC-10; `design.md` („Größe durch Inhalt nach unten begrenzt“)
**Reproduktion:** Vier Streams im Fokus-Layout, Fenster auf die kleinste Größe ziehen
**Erwartet:** Eine Mindestgröße, in die die kleinen Kacheln (240 × 135 pt, bis zu drei übereinander) und die Titelleiste passen
**Tatsächlich:** `minSize` 105 × 106 pt, Inhalt 105 × 54; die unterste kleine Kachel endet 383 pt unter dem Fensterboden, Umschalter und
Kacheln sind nicht zu sehen (`EC-10-kleinstes-fenster.png`)
**Ort:** `Sources/App/MikaPlusPlayerApp.swift:58` (`.windowResizability(.contentMinSize)` ohne Mindestrahmen), `Sources/Views/MultiviewScreen.swift:13-27`
**Vorschlag:** `.frame(minWidth:minHeight:)` am `MultiviewScreen` (z. B. 640 × 480) setzen.
**Test:** O `testEC10_EC11_…` (`XCTExpectFailure("BUG-10 …")`)

**Behoben 2026-09-28:** Mindestinhalt 640 × 483 pt (`MultiviewScreen.minimumContentSize` mit
`.windowResizability(.contentMinSize)`; spec OF-10): drei kleine Kacheln passen samt Abständen unter die Leiste des großen
Streams. O `testEC10_EC11_KleinstesFensterUndLangerName`: kleinstes Fenster 640 × 535 pt, Inhalt 640 × 483, unterste kleine
Kachel endet 16 pt über dem Fensterboden, Umschalter sichtbar; `testBUG10_…` ebenso mit allen vier X im Fenster.

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · Leere Keep-alive-Verbindungen nach dem Entfernen.** Nach dem Entfernen einer HLS-Kachel sind alle Stream-Verbindungen sofort zu,
  AVFoundation hält aber zwei leere HTTP-Verbindungen (keine Anfrage, keine Daten) noch über 46 s offen (S `testAK19_…`, `testAK20_…`).
  Deckt sich mit B03 H-7; kein Datenfluss, kein Befund.
- **H-2 · Tipp-Gesten im Test-Host.** Die Kacheln reagieren auf synthetische Klicks nur bei aktiver App und über die Ereigniswarteschlange;
  der abgebrochene Teil hatte „Mausklick wirkt=false“ gemessen und den Fokus über `setFocus` gesetzt. Das war eine Messbedingung, kein
  Verhalten der App (mit echten Klicks bestanden, AK-14).
- **H-3 · BF-101 und BF-97 im Multiview.** N `testBF101_…` (nur mit `B08_HAENGER=1`, Wachhund 60 s): 16 Runden mit 1,5 s und 10 Runden mit
  10 s Spielzeit, je vier VLC-Kacheln im echten Fenster, abwechselnd Fenster schließen bzw. vier X in Folge, **sofort** vier neue Kacheln
  (0,03–0,06 s nach dem Abbau) → kein Hänger; nach jeder Runde alle VLC-Player frei und alle Verbindungen zu nach 0,1–0,6 s. Der
  B06-Hänger ist damit für Multiview nicht belegt, BF-101 bleibt in B06 offen.
- **H-4 · Etiketten kleiner Kacheln auf hellem Bild.** Das graue Etikett nicht fokussierter Kacheln ist auf hellen Bildern kaum lesbar
  (`AK-14-fokus-klick-kleine-kachel.png`); so im Design-System vorgesehen, für die Reparatur als Hinweis.
- **H-5 · Release-Build der Kopie.** Die Absturzfälle liefen im Release-Build **als Test-Host** (`build-for-testing`); `xcodebuild` ergänzt dort
  Test-Entitlements (`get-task-allow`, `testmanagerd`). Für die Grenzprüfung (`-O`, keine `-Ounchecked`) ist das unerheblich; die
  ausgelieferte Signatur ist nicht Gegenstand von B08.

## Code-Review

Der `code-reviewer`-Lauf (Skill `code-review`, Stufe mittel, nur berichten) über `MultiviewScreen.swift`, `MultiviewTile.swift`,
`MultiviewSession.swift`, `ChannelRowView.swift` und `MikaPlusPlayerApp.swift` lieferte sieben Funde (1 kritisch, 1 hoch, 3 mittel,
2 niedrig). Alle wurden nachgeprüft; einer brachte eine neue Ausprägung zutage.

| Fund des Reviews | Nachprüfung | Ergebnis |
|---|---|---|
| Raster: `ForEach(0..<rows)` mit altem `count`, `session.slots[index]` live → Index außerhalb | ausgeführt (AK-23, Debug und Release) | bestätigt → BUG-01 |
| Kachel-Identität nicht an den Slot gebunden, `VLCPlayerSurface.updateNSView` leer → schwarzes VLC-Bild nach Fokuswechsel **und im Raster nach dem Entfernen einer vorderen Kachel** | ausgeführt: Fokus (AK-15) und neu N `testCR_AK11_AK19_…`: Raster mit vier VLC-Kacheln, X auf die erste (4 → 3) → Zelle oben links („V2“, **mit Ton**) zu 100 % schwarz, die beiden anderen Zellen mit Bild, die vierte leer (`CR-raster-nach-x-vorne-vlc.png`) | bestätigt → BUG-02 erweitert |
| X des großen Streams unter der ersten kleinen Kachel (Review: mittel) | ausgeführt mit echten Klicks (AK-16) | bestätigt → BUG-04 (hier hoch, weil Standard-Layout und der Ausweg über das Raster bei 3 → 2 abstürzt) |
| Abgeblendeter ⊞: Klick fällt auf den `NavigationLink` durch | ausgeführt (AK-05) | bestätigt → BUG-03 |
| `try?` in `add`, `openWindow` unbedingt (Review: mittel) | ausgeführt (AK-07 über die Oberfläche) | bestätigt → BUG-09 (niedrig, wartet auf OF-02) |
| Slots halten `Channel` über Löschen/Aktualisieren | ausgeführt (AK-27, AK-28) | bestätigt → BUG-05 (= BF-56) |
| Raster mit einem Stream: Umschalter gesperrt, `layout` bleibt `.grid` | ausgeführt (AK-13) | bestätigt, Teil von BUG-01 |

Vom Review ausdrücklich verworfen und hier bestätigt: Ein gelöschtes `Channel`-Objekt in einer Kachel führt nicht zum Absturz (EC-14).

## Abweichung Spec ↔ Code

Rückmeldung an die Spezifikation (Stand `c01f1cf` + Reparatur B01); geprüft wurde der Arbeitsbaum vom 2026-09-26.

| Stelle | Spec sagt | Code tut (ausgeführt) |
|---|---|---|
| AK-04 | ⊞ mit 30 % Deckkraft | `opacity(0.3)` plus Abblenden durch `.disabled`: gemessener Kontrast 15 % des aktiven Zustands |
| AK-11, AK-14 | 2 und 3 Streams bzw. Raster-Klick gelesen | ausgeführt und bestanden |
| AK-16 | Klicks schalten den Fokus 0 ↔ 1 | bei drei Streams wandert der Fokus jeweils zur ersten kleinen Kachel: 2 → 0 → 1 → 0 → 1 … |
| AK-19 | MPEG-TS nach 2 s, HLS innerhalb 5 s geschlossen | Stream-Verbindungen nach 0,0–0,8 s zu; leere Keep-alive-Verbindungen von AVFoundation > 46 s (H-1) |
| AK-20 | Verbindungen nach spätestens 3 s zu | 0,2–0,3 s |
| AK-29 | Warnton bei **jeder** der neun Tasten | 7 von 9 erreichten das Ende der Responder-Kette; welche zwei das Fenster selbst verarbeitet, wurde ohne Ton nicht einzeln ermittelt |
| AK-31 | vier Versuche in rund 20 ms | vier Versuche in 2–4 ms |
| AK-33 | `log show` fand das Passwort nicht | im Test-Host protokolliert das Network-Framework die volle Adresse samt Passwort (6 Zeilen); im regulären Prozess nur `url hash` |
| EC-07 | gelesen | ausgeführt: Fenster wird wiederhergestellt |
| EC-10 | nicht geprüft, „Größe durch Inhalt nach unten begrenzt“ (`design.md`) | Mindestgröße 105 × 106 pt, Kacheln laufen über (BUG-10) |
| EC-12, EC-13 | gelesen bzw. nicht gemessen | ausgeführt: PiP-Controller je AVKit-Kachel; CPU 8–18 %, RSS 184–255 MB mit vier Streams |
| EC-14 | ausgeführt mit Fenster (S5, S6) | hier auf Session-Ebene ausgeführt |
| FB-01 | Grenzprüfung im Release aktiv (gelesen) | ausgeführt: Absturz in Release in allen vier Fällen |
| `docs/app-shell.md` AS-05 | Spec: widerspricht AS-05 | AS-05 ist inzwischen korrigiert („… über das System-Menü „Window › Multiview““) |

## Neue Tests

Alle unter `Tests/B08/`, Testnamen mit AK-/EC-Nummer. Belege für Fehler mit `XCTExpectFailure("BUG-NN …")`.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B08Support.swift` | — | stumme Testmedien (ffmpeg `-an`, ffprobe-Prüfung), Stream-Mock mit Verbindungs-/Byte-/Kopfzeilenprotokoll und Verbindungslimit, Registratur aller `AVPlayer`/`VLCMediaPlayer` (Lautstärke 0), Beep-Wächter, Accessibility-/Bild-Hilfen, Basisklasse mit Aufräumen |
| `B08UITestCase.swift` | — | echte Szenen im Test-Host, ⊞-Klick, Kachelgeometrie, Umschalter, Tasten nur mit Wächter |
| `B08SessionTests.swift` | 18 | AK-03, AK-04, AK-06, AK-07, AK-14, AK-17, AK-19, AK-20, AK-24–AK-28, AK-30, AK-31, AK-34, EC-01–EC-05, EC-14, Angriff 1, 3, 5, 7, 8 |
| `B08OberflaecheTests.swift` | 14 (AK-29 nur mit `B08_TASTEN=1`) | AK-01, AK-02, AK-04, AK-05, AK-08–AK-16, AK-18–AK-22, AK-25, AK-26, AK-29, AK-31, AK-32, EC-06, EC-07, EC-10–EC-13 |
| `B08HauptfensterTests.swift` | 1 | AK-01, AK-02, AK-21 im echten Hauptfenster (Import über das echte Sheet) |
| `B08NeustartTests.swift` | 1 (zwei Prozesse, `B08_NEUSTART=1/2`) | AK-02, AK-24, EC-09 |
| `B08AbsturzTests.swift` | 8 (je Prozess, `B08_ABSTURZ=<fall>`) | AK-23 (4 Absturzfälle, 3 Gegenproben), EC-15 |
| `B08NachtragTests.swift` (neu) | 4 (BF-101 nur mit `B08_HAENGER=1`) | AK-14, AK-15, AK-16 mit echten Klicks bei aktiver App (`B08_AKTIVIEREN=<Anforderungsdatei>`); AK-06, AK-07 über die Oberfläche; Code-Review-Fund Raster/VLC (BUG-02); BF-101/BF-97 mit vier VLC-Kacheln |

**Letzter Gesamtlauf** (Kopie, Debug, `dd/`, 2026-09-26):

```
B08AbsturzTests         8 skipped  (nur mit TEST_RUNNER_B08_ABSTURZ=<fall>, je eigener Prozess, separat ausgeführt)
B08HauptfensterTests    1 passed
B08NachtragTests        3 passed, 1 skipped (BF-101, nur mit B08_HAENGER=1, separat ausgeführt)
B08NeustartTests        1 skipped  (zwei Prozesse, B08_NEUSTART=1/2, separat ausgeführt)
B08OberflaecheTests    13 passed, 1 skipped (AK-29, nur mit B08_TASTEN=1)
B08SessionTests        18 passed
Executed 46 tests, with 11 tests skipped and 0 failures (0 unexpected) in 440.609 (440.641) seconds
** TEST EXECUTE SUCCEEDED **
```

Vollständige gefilterte Ausgabe: `qa/testlauf-ausgabe.txt`; Protokollzeilen der Tests: `qa/testlauf.log`.

Separat ausgeführt (nur mit Umgebungsvariable): Absturzfälle 8 × Debug und 6 × Release (je eigener Prozess, 8 Absturzberichte, 6 Läufe
ohne Absturz, `qa/AK-23-absturz-protokoll.txt`); Neustart Phase 1 und 2 → je `passed`; `B08_HAENGER=1` mit 16 Runden/1,5 s
(`passed`, 47,4 s) und 10 Runden/10 s (`passed`, 114,9 s); `B08_TASTEN=1` einmal im abgebrochenen Teil (damals noch mit der
Erwartung „9 von 9“, daher `failed`; die Beobachtung steht unter AK-29). Build-Warnungen aus `Tests/B08`: drei Veraltungshinweise
(`CGWindowListCreateImage` in `B08Support.swift` für Fensteraufnahmen), sonst keine.

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Absturz („Index out of range“) im Raster beim Schließen des Multiview-Fensters (1 und 4 Streams) und beim Entfernen per X (3 → 2, 1 → 0), Debug und Release; mit einem Stream ist „Fokus“ gesperrt; seit `v1.1` ausgeliefert | kritisch | `Views/MultiviewScreen.swift:69-93, 79, 26, 116`, `Views/MultiviewTile.swift:62` | BUG-01 |
| VLC-Stream (Xtream-Standardformat) nach Fokuswechsel im großen Bild schwarz, Ton läuft (Website verspricht das Gegenteil); im Raster nach dem Entfernen der ersten Kachel ebenso | hoch | `Views/MultiviewScreen.swift:40-46, 74-85`, `Services/VLCPlaybackEngine.swift:121-129` | BUG-02 |
| X des großen Streams unter der ersten kleinen Kachel: Klick verlegt den Fokus, entfernt nichts | hoch | `Views/MultiviewScreen.swift:41-64`, `Views/MultiviewTile.swift:53-75` | BUG-04 |
| Kacheln zeigen VLC-Fehler nie (404, Port zu, Abbruch, Hänger), HLS-Segment-404 20 s ohne Meldung — **= BF-96, nicht neu zählen** | hoch | `Services/VLCPlaybackEngine.swift:80-99`, `Views/MultiviewTile.swift:35-49` | BUG-07 |
| Klick auf den abgeblendeten ⊞ öffnet den Player mit Ton und fünfter Verbindung | mittel | `Views/ChannelRowView.swift:73-85`, `ChannelListView.swift:111`, `FavoritesView.swift:24` | BUG-03 |
| Kacheln laufen nach Löschen/Aktualisieren der Playlist mit Zugangsdaten bzw. alter Adresse weiter — **= BF-56, nicht neu zählen** | mittel | `Services/MultiviewSession.swift:37-41, 54-67`, `Services/PlaylistImporter.swift:220, 270` | BUG-05 |
| N Kacheln = N Verbindungen ohne Rücksicht auf das Anbieterlimit; über dem Limit endlose Ladeanzeige ohne Meldung | mittel | `Services/MultiviewSession.swift:34, 54-67`, `Services/XtreamClient.swift:167-170` | BUG-06 |
| Derselbe Sender ohne Hinweis zweimal im Multiview — wartet auf OF-01 | niedrig | `Services/MultiviewSession.swift:54-67` | BUG-08 |
| ⊞ ohne Zugangsdaten öffnet leeres Multiview ohne Meldung — wartet auf OF-02 (= B01 OF-11) | niedrig | `Services/MultiviewSession.swift:57`, `Views/ChannelRowView.swift:75-76` | BUG-09 |
| Multiview bis 105 × 106 pt verkleinerbar, kleine Kacheln laufen über, Umschalter verschwindet | niedrig | `App/MikaPlusPlayerApp.swift:58`, `Views/MultiviewScreen.swift:13-27` | BUG-10 |

## Nächster Schritt

`/sdd-build B08` mit dem Auftrag, BUG-01 bis BUG-10 zu beheben – BUG-01 zuerst (Absturz im ausgelieferten Code), BUG-05 gemeinsam mit
B03 BF-56, BUG-07 gemeinsam mit B06 BF-96, BUG-08 und BUG-09 erst nach den Entscheidungen OF-01 und OF-02 –, danach erneut `/sdd-qa B08`
(Durchlauf 2). Wegen BUG-01 (kritisch) und BUG-02, BUG-04 (hoch) **pausiert die Erfassung der weiteren Bestandsfeatures**. Die offenen
Produktfragen OF-03 (Anbieterlimit), OF-04 (Tasten), OF-05 (Ton-Fokus mit Player), OF-06 („Erneut versuchen“ je Kachel) und OF-07
(Layout über Neustart) sind keine Befunde, gehören aber vor die Reparatur entschieden. Für B06: BF-101 ließ sich mit vier VLC-Kacheln nicht
reproduzieren (H-3).
