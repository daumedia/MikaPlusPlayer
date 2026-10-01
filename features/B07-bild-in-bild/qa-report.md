# B07 · Bild-in-Bild — Testbericht

Durchlauf 1 · Stand: 2026-09-26 · Geprüft gegen `spec.md` vom 2026-09-15 (Status `rekonstruiert`, Stand `c01f1cf`)
· Geprüfter Code: **aktueller Arbeitsbaum** (`c01f1cf` + Reparaturen B01, B09, B10-Teil-1, Branch `sdd/rueckerfassung`, nicht committet).
`AVKitPlaybackEngine.swift`, `PlaybackEngine.swift` und `PlayerLayerView.swift` sind gegenüber `c01f1cf` unverändert. `PlayerView.swift`
trägt die Resolver-Anbindung aus B01 (+32 Zeilen); dadurch sind die Zeilennummern der Spec verschoben (siehe *Abweichung Spec ↔ Code*).
Seit B09 läuft der Release-Build mit Hardened Runtime; Bild-in-Bild wurde darunter geprüft.

Dieser Durchlauf setzt einen an einem API-Limit abgebrochenen Durchlauf fort. Übernommen und in einem Gesamtlauf neu ausgeführt wurden
dessen Tests (`Tests/B07/`, 28 Fälle), die iOS-Simulator-Läufe (Protokoll, Bilder) und der Release-Lauf. Neu hinzu kamen sieben Tests,
die die **echten Knöpfe des Bild-in-Bild-Systemfensters** am Mac bedienen (Pause, Schließen, Zurück zur App), der Mac-Teil von AK-10,
Bild-in-Bild im Vollbild (EC-09) und am iPad die Bildschirmsperre (AK-22) sowie ein zweiter Lauf von AK-14.

## Fazit

**Production-ready: nein** · höchster Schweregrad: **hoch** (BUG-01)

Die Grundfunktion trägt auf beiden Plattformen: Knopf und Taste P öffnen und schließen das Systemfenster (Mac per Klick, Taste klein
und groß; iPad per Tipp und Hardware-Tastatur), der Knopf fehlt beim Laden, in der Fehleransicht, bei ausgeblendeter Steuerung, im
Multiview und bei VLC. Auf dem iPad startet Bild-in-Bild beim App-Wechsel von selbst und bleibt bei der Rückkehr offen; am Mac nicht.
Das Fenster zeigt nur das Bild, keinen Namen, keine Adresse. Im Release-Build unter Hardened Runtime läuft Bild-in-Bild, und im
Systemprotokoll der normal gestarteten App stehen weder Passwort noch Adresse (13.799 Zeilen, 0 Treffer). Bild-in-Bild schreibt
nichts in Datenbank, Einstellungen oder Dateien und löst keine zusätzlichen Anfragen aus.

Durchgefallen sind die vier ⚠-Kriterien (AK-14 bis AK-17) sowie AK-04 (iPad) und AK-09. Schwer wiegt **BUG-01**: Verlässt man am
Mac den Player mit aktivem Bild-in-Bild, spielt das schwebende Fenster weiter, und die App kann es nicht mehr steuern. Öffnet man
dann einen Sender, laufen **zwei Streams gleichzeitig**, in drei Läufen 42 s, 45 s und 60 s lang bis zum Ende der Beobachtung (die
Spec hatte 4,6 s gemessen). Drückt man im verwaisten Fenster „Zurück zur App“, verschwindet es, und der Stream spielt **unsichtbar**
weiter: 50 s beobachtet, auch während ein anderer Sender offen ist. Mit Tonspur wäre er zu hören, und es gibt weder Fenster noch
Knopf noch Taste, um ihn anzuhalten. Die Ursache ist dieselbe wie bei BF-97 (Engines überleben den Player, B06), die zusätzliche Verbindung ist dort gezählt.
Mittel sind der gegenteilige Abbruch auf iOS/iPadOS (**BUG-02**, Zielverhalten wartet auf OF-04), der App-Zustand, der dem Player
nach Pause, Schließen oder zweitem Bild-in-Bild nicht folgt (**BUG-03**, jetzt mit den echten Systemknöpfen belegt), das fehlende
Bild-in-Bild im Xtream-Standardformat ohne Hinweis in App und Website (**BUG-04**) und das iPad-Fenster, das den eigenen
„Schließen“-Knopf verdeckt (**BUG-05**). Niedrig: englische Systemtexte (**BUG-06**, wartet auf OF-03).

FB-01 (Bild-in-Bild in keinem Release, Website bewirbt es) ist nachgeprüft und deckt sich mit **BF-25**. Es wird dort gezählt, nicht
hier. Nicht ausgeführt ist nur EC-12 (echtes iPhone). Bildschirmfreigabe und -aufnahme (Teil von AK-20) wurden nicht gestartet.

Nächster Schritt: `/sdd-build B07` mit BUG-01 bis BUG-06, vorher OF-04 entscheiden. BUG-01 gehört zusammen mit B06 BUG-02 (BF-97)
repariert, BUG-04 (Website-Teil) in die B10-Reparatur Teil 2. Wegen BUG-01 (hoch) **wartet die Erfassung**.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 24 von 24 |
| davon bestanden | 18 |
| davon durchgefallen | 6 (AK-04, AK-09, AK-14, AK-15, AK-16, AK-17) |
| **nicht prüfbar** | 0 |
| Edge Cases belegt | 11 von 12 (EC-12 nicht: kein echtes iPhone) |
| Tests neu geschrieben | 35 in `Tests/B07/` (28 aus dem abgebrochenen Teil übernommen, 7 neu) |
| Tests grün | 41 von 41 (35 aus `Tests/B07`, 6 `PlaybackEngineTests`), 0 unerwartete Fehlschläge; 11 Tests belegen Fehler mit 19 erwarteten Fehlschlägen (`XCTExpectFailure`: BUG-01, BUG-03, BUG-04) |

## Prüfumgebung

| Was | Wie |
|---|---|
| Kopie | `scratchpad/qa1-b07/` (rsync ohne `build`, `.git`, `.xcodeproj`, `web/node_modules`, `web/.next`), vor der Fortsetzung mit dem Repo abgeglichen (`Sources/`, `Tests/Support/` – ohne Unterschied), `xcodegen generate`, eigene DerivedData in der Kopie. **Eigene Bundle-IDs** `lu.daumedia.qa1b07.MikaPlusPlayer` / `…Tests`; Sparkle-Feed auf `http://127.0.0.1:9/`, automatische Prüfung aus. Datenbank des Nutzers, Cache und Einstellungsdomäne der installierten App weder gelesen noch beschrieben |
| macOS-Tests | `xcodebuild test -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -only-testing:MikaPlusPlayerTests/B07…` (Test-Host: Datenbank im Speicher, Schlüsselbund nur mit Test-Dienstnamen). `PlayerView` echt, im `NavigationStack` bzw. Tab-Stapel wie in der App; AK-15c in der echten `ContentView`. Knöpfe per Klick bzw. Bedienungshilfen-Aktion, Tasten als `keyDown` |
| Systemfenster (Mac) | Ein Helfer außerhalb des Test-Hosts (`bridge2.sh`) nimmt nur drei Aufträge an: Aufnahme **eines** Fensters (`screencapture -l`), Test-Host nach vorn, und `pipax` – Bedienungshilfen des Bild-in-Bild-Fensters, nur wenn es dem Systemprozess `PIPAgent` gehört. Das Fenster bietet drei Knöpfe: `close`, `restore` („Zurück zur App“), `pause`/`play`. Kein Mauszeiger, keine anderen Apps |
| Release-Lauf | Release-Build der Kopie (`flags=0x10002(adhoc,runtime)`, `app-sandbox=false`, `disable-library-validation=true`, wie ausgeliefert), direkt gestartet mit `XCTestBundlePath=<nicht vorhanden>` (→ Datenbank nur im Speicher, `prepareStore` wird nicht aufgerufen – `AppPersistence.swift:183-185` –, eigener Schlüsselbund-Dienst) und `HOME`/`CFFIXED_USER_HOME` in einem leeren QA-Ordner; bedient per JXA/System Events nur dieses Prozesses. Protokoll `qa/release-protokoll.txt` |
| iOS | zwei **eigens angelegte** Simulatoren „QA-B07 iPad Pro 11“ (M4, iOS 26.5) und „QA-B07 iPhone 17“ (iOS 27.0), am Ende gelöscht; Debug-Build der Kopie; Bedienung mit AXe (Tippen, HID-Tasten, Home, Sperre). Protokoll `qa/ios-protokoll.txt` |
| Streams | Test-Host: `B07StreamServer` im Prozess (127.0.0.1, zufälliger Port; Live-HLS mit 2-s-Segmenten, roher TS in Echtzeit, 404, Verzögerung, Abbruch, Xtream-Form). iOS/Release: Python-Mock auf 127.0.0.1:18917. **Alle Medien ohne Tonspur** (`ffmpeg -an`, `ffprobe`: 0 Audiospuren), selbst erzeugte Engines vor dem Laden stumm |
| Zugangsdaten | nur erfunden (`qa-user` / `qa-pass-123`); Xtream-Panel nur als lokaler Mock (`MockXtreamServer`) |
| Ton | kein Ton: Medien ohne Tonspur, Beep-Wächter ersetzt `noResponderFor:` (unbelegte Tasten erzeugen eine Protokollzeile statt eines Warntons) |
| Rechner | Apple Silicon, macOS 27 (Darwin 27.0.0). Parallel liefen Gegenprüfungen anderer Features und Builds fremder Projekte (Lastmittel zeitweise über 700) |

## Akzeptanzkriterien im Einzelnen

Testnamen ohne Klasse: `B07KnopfTests` (K), `B07ImportHinweisTests` (I), `B07VerlassenTests` (V), `B07AppOberflaecheTests` (O),
`B07DatenschutzTests` (D), `B07AngriffTests` (A), `B07SystemfensterTests` (S). Bilder und Protokolle unter
`features/B07-bild-in-bild/qa/`. `<pass>` steht für das erfundene Passwort.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | K `testAK01_…`: Knopf „Minimise Video“ (`pip.enter`) bei (608, 465, 43 × 43) links neben „Enter Full Screen“ (666, 465,5) in derselben Zeile, obere rechte Hälfte des Fensters, Tooltip/Hilfe „Bild-in-Bild“ (`AK-01-knopf-mac.png`). iPad: Bedienungshilfen-Baum `Button 'Minimise Video' id='pip.enter' (710,152,48x48)` links neben `'Enter Full Screen' (775,153)` (`AK-01-ipad-knopf.png`, `ios-protokoll.txt`). Beschriftung englisch → BUG-06 (OF-03) |
| AK-02 | ✅ bestanden | K `testAK02_…`: beim Laden (Playlist 8 s verzögert) keine Knöpfe, Ladekreis (`AK-02-laedt-kein-knopf.png`); 404 → nach 0,1 s nur „Erneut versuchen“ (`AK-02-fehler-kein-knopf.png`); Steuerung samt Knopf nach 3,5 s ausgeblendet, Klick aufs Bild → nach 0,1 s wieder da |
| AK-03 | ✅ bestanden | K `testAK03_AK04_…` (Klick auf den Knopf): Systemfenster „Bild-in-Bild“ (Prozess `PIPAgent`, Ebene 19) nach 0,0 s, ohne Titel; nach 2 s Rate 1,0; Knopf wechselt auf „Maximise Video“ (`pip.exit`) (`AK-03-pip-fenster-mac.png`, `AK-03-platzhalter-app-mac.png`). Größe und Lage wählt das System (erster Start je Lauf 670–682 × 358–364 an der Stelle des Videos, spätere 514 × 270 oben rechts). iPad (Tipp): Fenster oben rechts, Platzhalter mit Symbol und „This video is playing in picture in picture.“, Knopf `pip.exit` (`AK-03-ipad-pip-aktiv.png`); Systemknöpfe Schließen, 10 s zurück, Pause, 10 s vor, Zurück zur App, bei Live mit „LIVE“ (`AK-04-ipad-tipp-auf-knopf-unter-pip.png`) |
| AK-04 | ❌ durchgefallen | Mac bestanden: K `testAK03_AK04_…` erneuter Klick → nach 0,0 s beendet, Video im Player, Rate 1,0, `isPaused=false`, Knopf wieder `pip.enter` (`AK-04-nach-schliessen-app-mac.png`). **iPad:** Das Systemfenster liegt über dem eigenen Knopf (Knopf 710,152 48 × 48 pt, Fenster ≈ 475–809 × 32–219 pt); der Tipp auf „Maximise Video“ trifft das Fenster und blendet nur dessen Knöpfe ein, Bild-in-Bild bleibt (`AK-04-ipad-tipp-auf-knopf-unter-pip.png`). Erst nach Verschieben des Fensters beendet der Knopf (`AK-04-ipad-knopf-nach-verschieben-beendet.png`) → **BUG-05** |
| AK-05 | ✅ bestanden | K `testAK05_…`: `p` bei ausgeblendeter Steuerung → nach 0,0 s aktiv, Steuerung eingeblendet, kein HUD-Bild, Steuerung nach 3,2 s wieder weg; Umschalt+P → nach 0,3 s beendet, Rate 1,0; Beep-Wächter leer (kein Warnton). iPad mit Hardware-Tastatur: Tab, dann `p` → startet (`AK-05-ipad-tab-dann-p-startet.png`), Umschalt+P → beendet (`AK-05-ipad-shift-p-beendet.png`). **Ohne** vorheriges Tab erreicht keine Taste den Player (`AK-05-ipad-taste-p-ohne-tab-ohne-wirkung.png`) – das ist der fehlende Tastaturfokus aus B06 (**BF-102**), nicht hier gezählt |
| AK-06 | ✅ bestanden | K `testAK06_…`: P bei Zustand `loading` (`isPictureInPicturePossible=false`); Stream spielt nach 3,9 s; 4 s später kein Bild-in-Bild, kein Fenster, keine Meldung, kein Sheet. Rückmeldung → OF-02 |
| AK-07 | ✅ bestanden | K `testAK07_…`: 404 → „The requested URL was not found on this server.“; P → kein Fenster, Fehleransicht bleibt (`AK-07-fehler-nach-p.png`) |
| AK-08 | ✅ bestanden | iPhone-Simulator (iOS 27.0): Knöpfe nur Zurück, „Enter Full Screen“, Pause, Lautstärke – kein Bild-in-Bild-Knopf (`AK-08-iphone-kein-pip-knopf.png`); Tab + P → kein Bild-in-Bild; Home → kein Fenster (`AK-08-AK-21-iphone-hintergrund-kein-pip.jpg`) |
| AK-09 | ❌ durchgefallen | K `testAK09_TSUeberVLC_…`: `.ts` → VLC, Knöpfe nur Vollbild, Pause, Lautstärke, **0** PiP-Controller; P blendet nur die Steuerung ein, kein Fenster, kein Warnton, kein Hinweis (`AK-09-ts-vlc-ohne-knopf-mac.png`). K `testAK09_Xtream…`: Xtream-Import (lokaler Mock) → alle Sender `…/<id>.ts` → `VLCPlaybackEngine`, `supportsPiP=false`. I `testAK09_…`: Import-Sheet mit Standard „MPEG-TS“ und Hinweis „Originalformat des Anbieters – benötigt VLCKit.“, kein Wort zu Bild-in-Bild (`AK-09-import-standard-mpegts.png`). iPad: `.ts` ohne Knopf, App-Wechsel ohne Bild-in-Bild (`AK-09-ipad-ts-vlc-ohne-pip-knopf.png`, `AK-09-ipad-ts-app-wechsel-kein-pip.jpg`). Verhalten wie beschrieben, in der Spec aber als Fehler eingestuft (FB-02) → **BUG-04** |
| AK-10 | ✅ bestanden | iPad: HLS spielt, Home → Bild-in-Bild-Fenster über dem Home-Bildschirm, spielt weiter (3 Segmente in 6 s) (`AK-10-ipad-auto-pip-nach-home.jpg`). Mac: S `testAK10_Mac_…`: Test-Host ausgeblendet (⌘H-gleich, `isActive=false`), 5 s später kein Fenster, `pipActive=false`, Wiedergabe läuft (Rate 1,0), obwohl Bild-in-Bild möglich gewesen wäre. Eine Einstellung gibt es nicht (Bedienungshilfen-Baum Mac und iPad: nur Playlists, Favoriten, Import). Abschaltbarkeit → OF-01 |
| AK-11 | ✅ bestanden | iPad: Rückkehr in die App → Fenster bleibt, Player zeigt den Platzhalter, 10 s später weiter `pip.exit` (`AK-11-ipad-rueckkehr-pip-bleibt.png`) |
| AK-12 | ✅ bestanden | D `testAK12_EC11_…`: Multiview mit 2 HLS- und 1 TS-Kachel: Knöpfe nur 3 × „Close“; P → kein Bild-in-Bild (P ist dort unbelegt, der Beep-Wächter fing den Warnton ab, siehe H-3) (`AK-12-multiview-ohne-pip-knopf.png`). Automatischer Start ist iOS-only, Multiview macOS-only |
| AK-13 | ✅ bestanden | V `testAK13_…`: „Zurück“ über den Zurück-Knopf der Fenster-Toolbar → `isPaused=true`, Rate 0; Tabwechsel → pausiert, Rückkehr → Rate 1,0 |
| AK-14 ⚠ | ❌ durchgefallen | iPad, zwei Läufe: „Zurück“ bei aktivem Bild-in-Bild → Fenster sofort weg, Senderliste (`AK-14-ipad-nach-zurueck.png`, `AK-14-ipad-nach-zurueck-lauf2.png`); Systemprotokoll `stopPictureInPictureAndRestoreUserInterface: shouldRestore NO` um 16:20:18.614, `AVPlayerController dealloc` 18.617, `AVPlayer dealloc` 18.633 (`AK-14-ipad-systemprotokoll-auszug.txt`); danach **0** Abrufe (20 in den 20 s davor). Lauf 2: letzter Abruf 17:14:35.947, danach keiner → **BUG-02** |
| AK-15 ⚠ | ❌ durchgefallen | V `testAK15a_…` (derselbe Sender), `testAK15b_…` (anderer Sender): nach „Zurück“ Fenster weiter mit Rate 1,0 (2–3 Segmente je 5 s), kein Knopf, P in der Liste ohne Wirkung, `stopPictureInPicture()` an der verwaisten Engine wirkungslos (Fenster bleibt); anderer Sender → **beide laden parallel bis zum Ende der Beobachtung (60 s)**, das alte Fenster verschwand nicht (`AK-15b-nach-zurueck-pip-fenster-mac.png`, `AK-15b-neuer-sender-app-mac.png`). O `testAK15c_…` (echte `ContentView`): parallel 45 s, auch nach Rückkehr zur Übersicht lädt A weiter. Release (Hardened Runtime): Fenster 20 s nach „Zurück“ weiter, 5–6 Abrufe je 5 s (`REL-02-nach-zurueck-liste-release.png`, `release-protokoll.txt`). S `testAK15e_…`: „Zurück zur App“ im verwaisten Fenster → Fenster weg, Stream spielt **unsichtbar** weiter (Rate 1,0, 50 s, 20 Segmente in 40 s), auch bei offenem anderem Sender; S `testAK15d_…`: „Schließen“ → Rate 0, lädt aber weiter (10 Segmente in 20 s) → **BUG-01** (Bezug BF-97) |
| AK-16 ⚠ | ❌ durchgefallen | S `testAK16_PauseKnopfDesSystemfensters_…`: Knopf `pause` des echten Systemfensters → Rate 0, Fensterknopf wird `play`, App `isPaused=false`, Knopf der App zeigt weiter „Pause“ (`AK-16-app-nach-pause-im-systemfenster.png`, `AK-16-systemfenster-nach-pause.png`); Leertaste 1 → Rate bleibt 0 (Knopf springt auf ▶), Leertaste 2 → Rate 1,0. V `testAK16_…` (Pause am Player) ebenso → **BUG-03** |
| AK-17 ⚠ | ❌ durchgefallen | V `testAK17_EC10_…`: zwei Player-Fenster; zweites Bild-in-Bild → Fenster des ersten schließt (Animation, danach 1 Fenster), erster Player Rate 0, `isPaused=false`, Knopf „Pause“ (`AK-17-erster-player-zeigt-pause-knopf.png`) → **BUG-03** |
| AK-18 | ✅ bestanden | D `testAK18_…`: Ablehnung über den Delegate-Aufruf gemeldet, wie ihn das System sendet (`failedToStartPictureInPictureWithError` am echten Controller): kein Fenster, keine Meldung, kein Sheet, Knopf weiter „Minimise Video“. Eine echte Ablehnung durch das System ließ sich nicht auslösen: Auch bei verkleinertem Fenster blieb `isPictureInPicturePossible=true` und Bild-in-Bild startete (H-4). Rückmeldung → OF-02 |
| AK-19 | ✅ bestanden | D `testAK19_AK20_AK22_…`: Sender „QA Geheimsender“ unter `/live/qa-user/<pass>/201.m3u8`: Fenster ohne Titel, keine Metadaten am Asset, Platzhalter nur mit den Knöpfen (`AK-19-20-pip-fenster-ohne-metadaten.png`, `AK-19-platzhalter-app.png`). A `testAngriff7_…`: sechs Namen (10.000 Zeichen, Emoji, SQL, Skript, Pfad, leer) erscheinen weder im Fenster noch im Platzhalter. Release: Fenster „Bild-in-Bild“, nur Bild (`REL-01-pip-fenster-release-hardened-runtime.png`, `REL-01-app-platzhalter-release.png`). iPad: Fenster über den Einstellungen bzw. dem Home-Bildschirm nur Bild (`AK-10-…`, `AK-03-ipad-…`) |
| AK-20 | ✅ bestanden | Fenster auf Ebene 19 über allen normalen Fenstern (Ebene 0); `screencapture -l` nimmt es auf (1028 × 540 px, `AK-19-20-…png`, `REL-01-pip-fenster-release-hardened-runtime.png`); iPad: automatischer Start über dem Home-Bildschirm, im Bildschirmfoto sichtbar (`AK-10-…`). Bildschirmfreigabe bzw. -aufnahme selbst wurde nicht gestartet; sie folgt aus beidem (OF-01) |
| AK-21 | ✅ bestanden | iPhone (ohne PiP), Home: Segmentabrufe je 30 s 14 / 14 / 18 / 16 über zwei Minuten, keine Zeitgrenze; iPad mit Bild-in-Bild: 3 in 6 s; gesperrt 16 in 33 s. Stumm geprüft (Medien ohne Tonspur); echtes Gerät nicht geprüft |
| AK-22 | ✅ bestanden | Mac: `MPNowPlayingInfoCenter.nowPlayingInfo = nil`, `playbackState=0` während Bild-in-Bild (D `testAK19_AK20_AK22_…`). iPad gesperrt mit aktivem Bild-in-Bild: Bedienungshilfen-Baum des Sperrbildschirms nur Uhrzeit, Datum, eine Systemmitteilung, Statusleiste – **kein** „Jetzt läuft“, kein Sendername; Wiedergabe lief gesperrt weiter; nach dem Entsperren Fenster weiter offen (`AK-22-ipad-nach-entsperren.png`). Bildschirmfotos des gesperrten Simulators sind schwarz (`AK-22-ipad-gesperrt-mit-pip.png`), die Sichtprüfung am Gerät steht aus |
| AK-23 | ✅ bestanden | Release (normal gestartet): `log show --predicate processID==…` 13.799 Zeilen, **0** Treffer für Passwort, `qa-user`, `/live/`, Sendername, `127.0.0.1:18917`; Netzwerkzeilen nur mit „url hash“, 475 × `<private>`. Test-Host (D `testAK23_…`, `OSLogStore`): 20.725 Einträge, 0 aus dem App-Subsystem, 0 in AVKit-/PiP-Zeilen (2.889); 8 Netzwerkzeilen von `com.apple.network` mit der vollen Adresse samt Zugangsdaten – nur am Test-Host (Schwärzung aus), wie **BF-43** |
| AK-24 | ✅ bestanden | D `testAK24_…`: nach Start und Ende von Bild-in-Bild keine neuen Einstellungen in der Domäne `lu.daumedia.qa1b07.MikaPlusPlayer`, keine geänderten Dateien in Application Support, Caches, Preferences, Saved Application State; `hasChanges=false`; neue Ansicht → neue Engine mit `pipActive=false` |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | K `testEC01_…`: `/live/qa-user/<pass>/101` (ohne Endung, roher TS) → AVKit, nach 0,1 s „Operation Stopped“, nur „Erneut versuchen“, kein Knopf (`EC-01-ohne-endung.png`) |
| EC-02 | ✅ belegt | K `testEC02_…`: `…/index.m3u` → AVKit, Knopf da, Bild-in-Bild aktiv nach 0,0 s |
| EC-03 | ✅ belegt | V `testEC03_…`: Tabwechsel bei aktivem Bild-in-Bild → keine Pause, Engine lebt, 1 Fenster; zurück im Tab dieselbe Engine, weiter aktiv (Spec: „vermutlich“) |
| EC-04 | ✅ belegt | K `testEC04_EC05_…`: Abbruch nach 14 s → nach 44,1 s „The network connection was lost.“, Knopf weg, Systemfenster bleibt (`EC-04-abbruch-waehrend-pip-app.png`, `EC-04-abbruch-waehrend-pip-fenster.png`); P beendet es nach 0,3 s |
| EC-05 | ✅ belegt | ebenda: „Erneut versuchen“ nach der Störung → spielt nach 0,1 s, **dieselbe** Engine, Bild-in-Bild weiter aktiv, 1 Fenster |
| EC-06 | ✅ belegt | iPad: pausiert (Leertaste nach Tab), dann Home → kein Fenster (`EC-06-ipad-pausiert-app-wechsel-kein-pip.jpg`). Der pausierte Live-Stream lud im Hintergrund weiter: 152 Segmente in 303 s (H-2) |
| EC-07 | ✅ belegt | S `testEC07_…`: Knopf `close` des Systemfensters → App merkt es nach 0,1–0,2 s, Knopf wieder `pip.enter`. **Das System pausiert dabei** (Rate 0), die App zeigt weiter „Pause“ (`EC-07-nach-schliessen-im-systemfenster.png`) – wie in der Spec vorhergesagt gilt dann AK-16 → BUG-03 |
| EC-08 | ✅ belegt | S `testEC08_…`: `restore` bei offenem Player → nach 0,1–0,3 s beendet, Bild im Player, Rate 1,0, Player-Fenster ist Schlüsselfenster (`EC-08-mac-zurueck-zur-app.png`); iPad ebenso (`EC-08-ipad-zurueck-zur-app-im-fenster.png`). Nach „Zurück“ (Mac): Fenster weg, Stream läuft unsichtbar weiter (S `testAK15e_…`) → BUG-01 |
| EC-09 | ✅ belegt | S `testEC09_…`: F → natives Vollbild 1920 × 1080, dann P → Bild-in-Bild aktiv, Fenster bleibt im Vollbild, der Platzhalter füllt die Vollbildfläche (`EC-09-pip-im-vollbild-platzhalter.png`); P beendet, Vollbild bleibt, F verlässt es, Rate 1,0 |
| EC-10 | ✅ belegt | V `testAK17_EC10_…`: immer nur ein Fenster, das zuletzt gestartete gewinnt |
| EC-11 | ✅ belegt | D `testAK12_EC11_…`: 2 PiP-Controller für 2 AVKit-Kacheln, keiner aktiv; TS-Kachel ohne Controller |
| EC-12 | ⚠️ nicht belegt | kein echtes iPhone verfügbar; die iPhone-Simulatoren melden keine Unterstützung (AK-08) |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf eine lokale App ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | bestanden | Keine per ID abrufbaren Ressourcen. Übertragen auf „fremde Wiedergabe übernehmen“: Ein zweiter Player kann das Fenster nur über denselben Systemweg übernehmen (V `testAK17_EC10_…`, das System schließt und pausiert den ersten, BUG-03). Die Knöpfe des Systemfensters sind per Bedienungshilfen steuerbar (`pipax`, S-Tests) – eine Eigenschaft von macOS für Prozesse mit Bedienungshilfen-Recht, nicht der App |
| 2 · Zugriffsregeln (Betriebssystem) | bestanden (Hinweis) | Release: Hardened Runtime aktiv (`flags=0x10002(adhoc,runtime)`), Bild-in-Bild läuft darunter ohne eigenes Entitlement (`REL-01-pip-fenster-release-hardened-runtime.png`); `app-sandbox=false`, `disable-library-validation=true` gehören zu B09 (BF-09) und B06 (BF-98). Das Systemfenster liegt auf Ebene 19 und ist für Bildschirmaufnahmen sichtbar (AK-20, gewollt, OF-01) |
| 3 · Rate Limit / Wiederholversuche | bestanden | A `testAngriff3_…`: 20 × P in 6 s → nie mehr als **1** Fenster, kein Abbruch, App-Zustand und Fenster stimmen überein, Verbindungen vorher 1 / nachher 1. Parallele Verbindungen nach „Zurück“ dagegen → BUG-01 (gezählt bei BF-97) |
| 4 · PII in Protokollen | bestanden | Release: 0 Treffer in 13.799 Zeilen (AK-23). Test-Host: App und AVKit schreiben nichts davon; nur `com.apple.network` schreibt am Test-Host die Adresse samt Zugangsdaten (8 Zeilen) – das ist BF-43, nicht B07 |
| 5 · PII an externe Dienste | bestanden | A `testAngriff5_…`: Tatsächliche Anfragen während Bild-in-Bild an/aus: 6, nur `/live/qa-user/<pass>/501.m3u8` und Segmente, Kopfzeilen `accept, accept-encoding, accept-language, connection, host, user-agent, x-playback-session-id`, UA `AppleCoreMedia/1.0.0.26A428 (Macintosh; …; de_de)`; entfernte TCP-Endpunkte des Prozesses nur `127.0.0.1`. Bild-in-Bild selbst fragt nichts an |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` über die vier B07-Dateien (4 Commits, darunter `54550b2`): 0 Treffer für `password=`, `token=`, `sk_live`, `service_role`, `api_key`, `/live/<u>/<p>/<id>`; `strings` über das Release-Binary (4,1 MB): 0; `Tests/B07` nur `qa-pass-123` und `127.0.0.1` |
| 7 · Eingaben | bestanden | A `testAngriff7_…`: Sendernamen mit 10.000 Zeichen, Emoji, `'; drop table ZCHANNEL; '`, `<script>alert(1)</script>`, `../../etc/passwd`, leer → Bild-in-Bild startet jeweils, Fenster ohne Namen, Platzhalter ohne Text (`Angriff7-emoji-name-platzhalter.png`), kein Absturz |
| 8 · Löschen | teils – **BF-56** | A `testAngriff8_…`: Playlist während Bild-in-Bild gelöscht (0 Sender in der DB) → Fenster spielt 10 s später weiter (Rate 1,0, 5 Segmente). Das ist BF-56 (B03), hier nicht neu gezählt. Bild-in-Bild selbst speichert nichts (AK-24) |

## Fehler

### BUG-01 · Mac: Nach „Zurück“ spielt Bild-in-Bild verwaist weiter; die App kann es nicht beenden, der nächste Sender läuft parallel, „Zurück zur App“ lässt den Stream unsichtbar weiterlaufen — hoch

**Betrifft:** AK-15 (FB-03), EC-08; Sicherheitskatalog 2.1, 4.2, 4.3 · **Bezug:** BF-97 (B06 BUG-02) – dieselbe Ursache, die
zusätzliche Verbindung ist dort gezählt; hier geht es um die Wiedergabe, die weiterläuft und nicht mehr zu steuern ist
**Reproduktion:**
1. Mac, HLS-Sender aus der Senderliste öffnen, Knopf „Bild-in-Bild“
2. „Zurück“ in der Fenster-Toolbar, 15 s warten
3. Einen anderen Sender öffnen, 60 s beobachten; danach zurück in die Übersicht
4. Variante: nach Schritt 2 im schwebenden Fenster „Zurück zur App“ bzw. „Schließen“
**Erwartet:** Nach „Zurück“ entweder sauberes Ende (Fenster zu, Verbindung zu) oder Weiterlaufen mit einer Steuerung in der App
(Zielverhalten OF-04). Nie zwei Streams zugleich, nie eine Wiedergabe ohne sichtbares Fenster
**Tatsächlich:** Das Fenster spielt weiter (Rate 1,0), die App zeigt die Liste ohne Knopf, P bleibt dort ohne Wirkung, und
`stopPictureInPicture()` an der verwaisten Engine bewirkt nichts. Mit einem neuen Sender laden beide Streams parallel, im Test-Host
60 s und in der echten Oberfläche 45 s lang, auch nach der Rückkehr zur Übersicht. Im Release-Build spielte das Fenster nach „Zurück“
ebenso weiter (20 s beobachtet, danach wurde die App beendet). Das alte Fenster verschwand in keinem Lauf, die Spec hatte 4,6 s gemessen. „Zurück zur App“ im verwaisten Fenster
schließt das Fenster, der Stream spielt aber **unsichtbar** weiter: Rate 1,0 über 50 s, 20 Segmente in 40 s, auch während ein anderer
Sender offen ist. Mit Tonspur wäre er zu hören, und es gibt kein Bedienelement mehr, das ihn anhält; im Test hielt ihn erst das
Aufräumen am Testende an. „Schließen“ pausiert (Rate 0), die Verbindung bleibt aber offen und lädt weiter (10 Segmente in 20 s)
**Ort:** `Sources/Views/PlayerView.swift:17` (Engine nur als `@State`), `:83-92` (Wache `:89` verhindert nur die Pause);
`Sources/Services/AVKitPlaybackEngine.swift:76-78` (Stopp am Controller, dessen Layer nicht mehr im Fenster hängt), `:153-172` (kein
`restoreUserInterfaceForPictureInPictureStop`, Engine nur schwach, `:154`); es gibt keine App-weite Stelle, die eine laufende
Bild-in-Bild-Wiedergabe kennt
**Vorschlag:** Nach OF-04 entscheiden. Entweder die Bild-in-Bild-Wiedergabe außerhalb der Ansicht halten (App-weite Sitzung wie
`MultiviewSession`) und mit `restoreUserInterfaceForPictureInPictureStop` den Player wieder öffnen, oder beim Verlassen Bild-in-Bild
beenden und die Engine stoppen. Die Reparatur gehört zu BF-97 (`stop()` im Protokoll).
**Test:** V `testAK15a_…`, `testAK15b_…`, O `testAK15c_…`, S `testAK15d_…`, `testAK15e_EC08_…` (je `XCTExpectFailure("BUG-01 …")`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — In einer eigenen Kopie (Test-Host, Datenbank im Speicher, Medien ohne Tonspur, nur 127.0.0.1) traten alle fünf Beleg-Tests wie beschrieben ein (Fenster nach „Zurück“ mit Rate 1,0, `stopPictureInPicture()` wirkungslos, 42/60/45 s parallel, nach „Zurück zur App“ unsichtbar Rate 1,0 mit 20 Segmenten in 40 s, nach „Schließen“ Rate 0 und trotzdem 10 Segmente in 20 s), und eine eigene Gegenprobe ohne starke Testreferenz auf die Engine (die QA-Tests halten `eA` bis zum Testende) zeigte dasselbe: in der echten `ContentView` 30 von 30 s parallel, nach „Zurück zur App“ 30 s unsichtbar weiter (15 Segmente), im Stapel in 2 von 3 Läufen 30 s parallel (im dritten blieb das Fenster pausiert stehen, ebenfalls ohne Steuerung in der App); Grad angemessen

**Behoben 2026-09-27:** Zuerst die ursprüngliche Reproduktion auf dem B06-Stand (Arbeitsbaum, Test-Host mit Helfer für
das Systemfenster): „Schließen“ und „Zurück zur App“ im verwaisten Fenster beendeten die Wiedergabe schon (S AK-15d/e:
Rate 0, 0 Segmente in 8 s bzw. 40 s – `DetachedPlayback` stoppt beim Ende von Bild-in-Bild), offen blieben die zwei
Streams (V AK-15b 60 s, O AK-15c 45 s parallel, altes Fenster blieb) und das wirkungslose `stopPictureInPicture()`.
Behoben: (1) Startet oder setzt ein Player eine Wiedergabe fort, endet die verwaiste samt Fenster
(`DetachedPlayback.stopAll()` in `PlayerView.startIfNeeded`). (2) `stop()` gibt den Bild-in-Bild-Controller ab – am Mac
schließt das Fenster sonst nicht, weil die Videofläche in keinem Fenster mehr hängt; an einer übernommenen Engine wirkt
auch `stopPictureInPicture()` so. (3) `restoreUserInterfaceForPictureInPictureStop` ist implementiert: offener Player →
Bild kehrt zurück (EC-08 unverändert), verlassener Player → kein Wiederherstellen, die Wiedergabe endet (Player
wiederherstellen → `spec.md` OF-05). (4) In der echten Oberfläche erkannte der Player am Mac „Zurück“ aus der
Senderliste nicht (`isPresented` beim Verschwinden noch wahr) – dort griff weder B06 noch (1); `ContentView` führt jetzt
den sichtbaren Tab (`ShellTabs`), der Player unterscheidet damit „Zurück“ vom Tabwechsel. Reproduktion greift nicht mehr:
Mock-Protokoll (Anfragen je Sekunde ab 6 s vor dem Öffnen von B) A=[2,0,2,0,2,0,0,0,…], B=[0,0,0,0,0,0,5,0,2,0,2,…]; altes
Fenster nach 0,2 s zu, nach der ersten Anfrage von B **0** Anfragen an A, **0** Sekunden mit zwei Streams; nach dem Ende
0 Anfragen (R `testBUG01_ZurueckMitPiP_AndererSender_AltesEndetNieZweiStreams`); ebenso in der echten `ContentView`
(R `testBUG01_EchteOberflaeche_…`, Fenster nach 0,2 s zu; O AK-15c jetzt „parallel ≈ 0 s“, Fenster nach 3,1 s – Messraster
3 s); `stopPictureInPicture()` ohne Player: Fenster nach 0,3 s zu, 0 Anfragen (R `testBUG01_BeendenOhnePlayer_…`,
V AK-15a/b); Delegate mit/ohne Player true/false (R `testBUG01_ZurueckZurApp_…`); Tabwechsel pausiert weiter nur,
„Zurück“ beendet (R `testBUG01_EchteOberflaeche_TabwechselPausiert_ZurueckBeendet`). iPad (eigener Simulator): nach
„Zurück“ läuft das Fenster weiter; „QA HLS Zwei“ öffnen → letzte Anfrage an den alten Sender 1,3 s vor der ersten des
neuen, danach keine, Fenster weg; „Zurück zur App“ im verwaisten Fenster → Delegate aufgerufen, Fenster weg, 0 Anfragen
(`qa/BUILD-IOS-sonde-protokoll.txt`, Bilder `qa/BUILD-IOS-ipad-04/05/06-…`). V AK-15a/b, O AK-15c, S AK-15d/e ohne
`XCTExpectFailure`. In der App selbst gibt es nach „Zurück“ weiterhin keinen Knopf für das schwebende Fenster (OF-04).

### BUG-02 · iOS/iPadOS: „Zurück“ beendet Bild-in-Bild sofort und ohne Rückmeldung, entgegen der Absicht im Code — mittel

**Betrifft:** AK-14 (FB-03) · Zielverhalten wartet auf **OF-04**
**Reproduktion:**
1. iPad (Simulator iPad Pro 11, iOS 26.5), HLS-Sender, Knopf „Minimise Video“ (oder Home und zurück)
2. Im Player „Zurück“
**Erwartet:** Laut Kommentar `PlayerView.swift:87-88` und Commit `54550b2` („onDisappear-Guard, damit PiP nicht abgewürgt wird“) soll
ein Ansichtswechsel die schwebende Wiedergabe nicht abwürgen; zumindest dasselbe Verhalten wie am Mac bzw. eine bewusste,
angekündigte Beendigung
**Tatsächlich:** Das Fenster verschwindet sofort, die Wiedergabe endet, es gibt keinen Hinweis. Systemprotokoll: `stopPictureInPicture…
shouldRestore NO` 16:20:18.614, `AVPlayerController dealloc` 18.617, `AVPlayer dealloc` 18.633; danach keine Abrufe mehr (zweiter
Lauf ebenso). Der Mac verhält sich gegenteilig (BUG-01)
**Ort:** `Sources/Views/PlayerView.swift:17, 83-92`; `Sources/Services/AVKitPlaybackEngine.swift:154` (schwache Referenz), kein
Wiederherstellungs-Delegate
**Vorschlag:** Mit BUG-01 gemeinsam lösen (eine Lebensdauer für beide Plattformen); wird „beenden“ gewählt, den Kommentar anpassen
und das Ende sichtbar machen.
**Test:** keiner im Test-Target (nur im iOS-Simulator bedienbar); Protokoll `qa/ios-protokoll.txt`, `qa/AK-14-ipad-systemprotokoll-auszug.txt`

**Nicht behoben:** Das Zielverhalten wartet auf **OF-04** (weiterlaufen mit Steuerung oder sauber beenden) – nicht Teil
dieses Fehlerauftrags. Stand nach den Reparaturen B06 und B07 siehe `build-bericht.md`, Abschnitt 2 (iPad-Sonde).

### BUG-03 · Der Wiedergabezustand der App folgt dem Player nicht, wenn das System ihn anhält — mittel

**Betrifft:** AK-16, AK-17 (FB-04), EC-07, EC-10
**Reproduktion:**
1. Mac, HLS-Sender, Bild-in-Bild per Knopf
2. Im schwebenden Fenster auf Pause
3. Im Player Leertaste, dann noch einmal
4. Varianten: „Schließen“ im schwebenden Fenster; in einem zweiten Player-Fenster Bild-in-Bild starten
**Erwartet:** Knopf und HUD zeigen „angehalten“, der erste Druck setzt fort
**Tatsächlich:** Nach der Pause im Fenster (echter Systemknopf) steht der Player (Rate 0), die App meldet `isPaused=false`, ihr Knopf
zeigt „Pause“. Der erste Druck auf die Leertaste setzt nicht fort, der Knopf springt nur auf ▶, erst der zweite spielt ab. Beim
„Schließen“ pausiert das System ebenfalls (Rate 0), die App zeigt weiter „läuft“. Startet ein zweiter Player Bild-in-Bild, pausiert
das System den ersten, dessen Knopf zeigt weiter „Pause“
**Ort:** `Sources/Services/AVKitPlaybackEngine.swift:13, 45-47` (`isPaused` nur aus eigenen Aufrufen, `togglePlayPause` danach);
`Sources/Views/PlayerView.swift:146, 348-353`
**Vorschlag:** `isPaused` aus `AVPlayer.timeControlStatus`/`rate` ableiten (Beobachtung), `togglePlayPause` nach dem tatsächlichen
Zustand entscheiden.
**Test:** S `testAK16_PauseKnopfDesSystemfensters_…`, `testEC07_…`, V `testAK16_…`, `testAK17_EC10_…` (je `XCTExpectFailure("BUG-03 …")`)

**Behoben 2026-09-27:** `AVKitPlaybackEngine` beobachtet `timeControlStatus` des `AVPlayer` und führt `isPaused` nach:
Hält das System an (Pause oder Schließen im schwebenden Fenster, zweites Bild-in-Bild), zeigt der Knopf ▶; setzt es fort,
❚❚. `togglePlayPause()` gleicht vorher mit dem Player ab, der erste Druck setzt also fort. Ausnahmen: ohne Element (vor
`load`, nach `stop`) gilt der eigene Zustand; am natürlichen Ende einer Datei bleibt die Anzeige „läuft“ (B06 EC-04,
`testEC04_MP4BisZumEndeBleibtLaeuft` weiter grün). Reproduktion greift nicht mehr: Pause von außen → `isPaused` nach
0,05 s, Fortsetzen von außen → nach 0,05 s, erster Druck spielt sofort (R `testBUG03_…`); echter Pause-Knopf des
Systemfensters (S `testAK16_PauseKnopfDesSystemfensters_AppZeigtAngehalten`), Pause am Player (V
`testAK16_PauseImPiPFenster_AppZeigtAngehalten_ErsterDruckSetztFort`), zweites Bild-in-Bild (V
`testAK17_EC10_ZweiterPlayerStartetPiP_ErsterPausiertUndZeigtEs`) und Schließen im Fenster (S `testEC07_…`, jetzt
`isPaused == (rate == 0)`) ohne `XCTExpectFailure`. iPad: Pause im schwebenden Fenster → App zeigt ▶, erster Tipp spielt
(`qa/BUILD-IOS-ipad-08-…`, `-09-…`, `qa/BUILD-IOS-sonde-protokoll.txt`).

### BUG-04 · Im Xtream-Standardformat (MPEG-TS/VLC) gibt es kein Bild-in-Bild, und weder App noch Website sagen es — mittel

**Betrifft:** AK-09 (FB-02); Website (B10)
**Reproduktion:**
1. Import-Sheet öffnen: Reiter Xtream, Format vorausgewählt „MPEG-TS“, Hinweis „Originalformat des Anbieters – benötigt VLCKit.“
2. Xtream-Playlist importieren, Sender öffnen
3. Knopf suchen, P drücken; am iPad die App wechseln
4. `web/content/features.ts:31-33, 38` und `web/app/support/page.tsx:70` lesen
**Erwartet:** Die Einschränkung ist erkennbar: ein Hinweis beim Format bzw. im Player, und die Website nennt „nur HLS“
**Tatsächlich:** Alle Sender enden auf `.ts` und laufen über VLC. Es gibt keinen Knopf, P blendet nur die Steuerung ein, am iPad
startet beim App-Wechsel nichts, und nirgends steht eine Erklärung. Die Website verspricht „Send the stream into the system PiP
window … On iPhone and iPad it starts on its own“ und „P opens Picture in Picture“ ohne Einschränkung. Für die Hauptzielgruppe
(Xtream-Abos) fehlt die Funktion damit im Normalfall
**Ort:** `Sources/Views/ImportPlaylistView.swift:33` (Standard `.mpegts`), `Sources/Services/XtreamCodes.swift:20` (Hinweistext),
`Sources/Services/PlaybackEngine.swift:85-94, 99-108`, `Sources/Views/PlayerView.swift:118, 337-338`; `web/content/features.ts:31-33, 38`,
`web/app/support/page.tsx:70`
**Vorschlag:** Hinweis „kein Bild-in-Bild“ am MPEG-TS-Format und P bei VLC mit kurzer Meldung; Website-Text auf HLS einschränken
(mit der B10-Reparatur Teil 2). Überschneidet sich mit BF-25 (Release) und BF-103 (P ohne Rückmeldung), die dort gezählt sind.
**Test:** K `testAK09_TSUeberVLC_…`, I `testAK09_ImportSheet…` (je `XCTExpectFailure("BUG-04 …")`), K `testAK09_XtreamStandardformatLandetBeiVLC`

**Behoben 2026-09-27 (App-Teil):** Import-Sheet: Der Hinweis zum Format MPEG-TS lautet jetzt „Originalformat des
Anbieters – benötigt VLCKit. Bild-in-Bild gibt es nur mit HLS.“ (`XtreamOutput.hint`; der HLS-Hinweis ist unverändert).
Player: P bei einem Sender über VLC blendet auf Geräten mit Bild-in-Bild 3 s lang „Bild-in-Bild gibt es nur mit HLS,
nicht mit MPEG-TS.“ ein (HUD mit Symbol; Geräte ohne Bild-in-Bild wie bisher ohne Meldung, AK-08). Einen Knopf gibt es
bei VLC weiter nicht (AK-09). Belegt: I `testAK09_ImportSheetStandardMPEGTS_MitHinweisBildInBildNurHLS`, K
`testAK09_TSUeberVLC_KeinKnopf_PZeigtHinweisNurHLS` (Hinweis erscheint, verschwindet nach wenigen Sekunden, kein Warnton)
ohne `XCTExpectFailure`; iPad: Hinweis im Sheet und nach Tab + p im Player (`qa/BUILD-IOS-ipad-01-…`, `-07-…`).
**Nicht behoben (Website-Teil):** `web/content/features.ts`, `web/app/support/page.tsx` gehören zur B10-Reparatur Teil 2.
Offen: Wer am iPad ohne Tastatur schaut, sieht den Player-Hinweis nie → `spec.md` OF-06.

### BUG-05 · iPad: Das Bild-in-Bild-Fenster verdeckt den eigenen Knopf „Bild-in-Bild schließen“ — mittel

**Betrifft:** AK-04 (iPad-Teil)
**Reproduktion:**
1. iPad (Simulator iPad Pro 11, iOS 26.5), HLS-Sender, Tipp auf „Minimise Video“
2. Steuerung einblenden, auf „Maximise Video“ tippen
**Erwartet:** Der zweite Tipp schließt das schwebende Fenster, das Video kehrt in den Player zurück
**Tatsächlich:** Das Systemfenster erscheint oben rechts (≈ 475–809 × 32–219 pt) genau über dem Knopf (710,152, 48 × 48 pt) und dem
Vollbild-Knopf. Der Tipp trifft das Fenster und blendet nur dessen eigene Knöpfe ein, Bild-in-Bild bleibt aktiv. Erst wenn man das
Fenster wegschiebt, beendet der Knopf. Beenden lässt es sich sonst über „Zurück zur App“ im Fenster oder mit P über die Tastatur,
die aber erst nach einem Tab ankommt (BF-102)
**Ort:** `Sources/Views/PlayerView.swift:113-133` (Knöpfe oben rechts); Lage des Fensters bestimmt das System
**Vorschlag:** Auf dem iPad den Knopf dort platzieren, wo das Fenster ihn nicht verdeckt (z. B. in der unteren Leiste), oder den
Platzhalter selbst antippbar machen.
**Test:** keiner im Test-Target; Bilder `AK-04-ipad-tipp-auf-knopf-unter-pip.png`, `AK-04-ipad-knopf-nach-verschieben-beendet.png`

**Behoben 2026-09-27:** Auf iOS/iPadOS zeigt die untere Leiste des Players, solange Bild-in-Bild läuft, zusätzlich den
Knopf „Bild-in-Bild beenden“ (Symbol `pip.exit` mit deutschem Text) neben Pause und Ton. Liegt das schwebende Fenster
oben (Standard), bleibt er frei; liegt es unten links, bleibt der Knopf oben rechts frei (nicht nachgestellt). Nachgestellt im eigenen
iPad-Simulator (iPad Pro 11, iOS 26.5): Fenster oben rechts über „Maximise Video“ (710,152), neuer Knopf bei
(148,1134, 207 × 43 pt) frei; ein Tipp darauf beendet Bild-in-Bild, das Video kehrt in den Player zurück, der obere
Knopf zeigt wieder „Minimise Video“ (`qa/BUILD-IOS-ipad-02-…`, `-03-…`, `qa/BUILD-IOS-sonde-protokoll.txt`). Kein Test
im Test-Target (macOS-only; der Knopf ist iOS-only).

### BUG-06 · Englische Systemtexte in der deutschen Oberfläche: „Minimise Video“, „Maximise Video“, „This video is playing in picture in picture.“ — niedrig

**Betrifft:** AK-01, AK-03 · wartet auf **OF-03**
**Reproduktion:** Mac oder iPad, HLS-Sender, Bedienungshilfen-Baum bzw. VoiceOver auf dem Knopf; Bild-in-Bild starten und den
Platzhalter lesen
**Erwartet:** deutsche Beschriftung wie im Rest der App (Tooltip „Bild-in-Bild“)
**Tatsächlich:** Die VoiceOver-Beschriftung kommt vom SF-Symbol und lautet englisch „Minimise Video“ bzw. „Maximise Video“, der
Platzhalter des Systems „This video is playing in picture in picture.“, weil das Bundle keine deutsche Lokalisierung hat
**Ort:** `Sources/Views/PlayerView.swift:119-124` (Knopf ohne `accessibilityLabel`); keine `de.lproj` bzw. `.xcstrings` unter `Sources/`
**Vorschlag:** Nach OF-03 `accessibilityLabel("Bild-in-Bild öffnen/schließen")` setzen und Deutsch als Lokalisierung aufnehmen.
**Test:** K `testAK01_…`, `testAK03_AK04_…` (Ist-Werte im Protokoll)

**Nicht behoben:** wartet auf **OF-03** (eigene deutsche Beschriftung bzw. Lokalisierung) – nicht Teil dieses
Fehlerauftrags. Die Beschriftungen des Knopfs und der Platzhalter des Systems sind unverändert englisch.

## Bestätigte Befunde anderer Features (nicht neu gezählt)

| Befund | Was B07 dazu gezeigt hat |
|---|---|
| **BF-25** (B10) · Werbeaussagen, die Release v1.1 nicht erfüllt | = FB-01: `git merge-base --is-ancestor 54550b2 v1.1` → nein; `v1.1:PlayerView.swift` ohne Fall `"p"`, `v1.1:PlaybackEngine.swift` ohne `PictureInPicture`; `appcast.xml` nur 1.1, `MARKETING_VERSION` 1.1 (`CURRENT_PROJECT_VERSION` 3); die Website bewirbt Bild-in-Bild weiter (`web/content/features.ts:31-33, 38`, `web/app/support/page.tsx:70`) |
| **BF-97** (B06) · Engines überleben den Player | Grundlage von BUG-01: Die verwaiste Engine lebt nach „Zurück“ weiter, zusätzlich zu der neuen des nächsten Senders |
| **BF-102** (B06) · iPad-Tastatur erreicht den Player nicht | P wirkt am iPad erst nach einem Tab (AK-05) |
| **BF-56** (B03) · gelöschte Sender spielen weiter | Playlist während Bild-in-Bild gelöscht → Fenster spielt weiter (Angriff 8) |
| **BF-43** (B01) · Adressen samt Zugangsdaten im Systemprotokoll (Test-Host/Private Data) | 8 Netzwerkzeilen am Test-Host; im Release 0 (AK-23) |

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · Laufzeitwarnung von SwiftUI bei jedem Start von Bild-in-Bild am Mac.** Im Debug-Build meldet SwiftUI 58-mal „Adding
  'AVPictureInPicturePlayerLayerView' as a subview of NSHostingView is not supported and may result in a broken view hierarchy“, dazu
  „NSHostingView is being laid out reentrantly“. AVKit hängt seinen Platzhalter in die SwiftUI-Hierarchie, weil der Layer in
  `PlayerLayerHostView` direkt im `NSViewRepresentable` sitzt (`PlayerLayerView.swift:56-96`). Im Release-Protokoll erscheint die
  Warnung nicht. Eine sichtbare Folge ist nicht belegt; ob sie zum wirkungslosen `stopPictureInPicture()` nach „Zurück“ beiträgt
  (BUG-01), ist offen.
- **H-2 · Ein pausierter Live-Stream lädt weiter (für B06).** Am iPad lud der pausierte Player im Hintergrund 152 Segmente in 303 s
  (≈ Echtzeit, EC-06); am Mac lud der nach „Schließen“ pausierte verwaiste Player weiter (BUG-01). `pause()` setzt nur die Rate auf 0.
  Das ist dieselbe Wurzel wie BF-97; Datenvolumen im Hintergrund ohne Wiedergabe.
- **H-3 · P im Multiview (für B08).** Im Multiview ist P nicht belegt; das Ereignis läuft ins Leere und würde einen Warnton auslösen
  (hier vom Beep-Wächter abgefangen: `SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:`). Außerdem legt jede AVKit-Kachel einen ungenutzten
  Bild-in-Bild-Controller an (EC-11).
- **H-4 · Verkleinertes Fenster verhindert Bild-in-Bild nicht.** Liegt das Player-Fenster im Dock, meldet der Controller weiter
  „möglich“, und Bild-in-Bild startet (AK-18b). Eine Ablehnung durch das System ließ sich so nicht herstellen.
- **H-5 · iPhone.** Die iPhone-Simulatoren (iOS 26.5, 27.0) melden keine Unterstützung; ob echte iPhones Bild-in-Bild anbieten und wie
  der automatische Start im Hochformat aussieht (EC-12), bleibt für eine Prüfung am Gerät.

## Code-Review

Der `code-reviewer`-Lauf (Skill `code-review`, mittlere Stufe, über `AVKitPlaybackEngine.swift`, `PlaybackEngine.swift`,
`PlayerLayerView.swift`, `PlayerView.swift`, Verweis auf `design.md`) lief im ersten Teil dieses Durchlaufs (2026-09-26, 16:28) und
lieferte drei Funde; der Code ist seitdem unverändert. Alle drei sind nachgeprüft:

| Fund | Nachprüfung | Ergebnis |
|---|---|---|
| `PlayerView.swift:89`: Bild-in-Bild hängt an der `@State`-Engine; „Zurück“ bricht auf iOS ab, auf dem Mac verwaiste Wiedergabe und zweite Verbindung | ausgeführt (AK-14 iPad, AK-15a–e Mac, Release) | bestätigt → BUG-01, BUG-02 |
| `AVKitPlaybackEngine.swift:47`: `isPaused` nur von der App geführt; Pause im Fenster bzw. zweites Bild-in-Bild → falscher Knopf, erster Druck verpufft | ausgeführt (AK-16 mit echtem Systemknopf, AK-17, EC-07) | bestätigt → BUG-03 |
| `PlayerView.swift:250`: `retry()` setzt bei vorhandener Engine `resolveError`, die Ansicht zeigt ihn nicht | in B06 ausgeführt (EC-11) | bestätigt, = BF-56, hier nicht gezählt |
| `PlayerLayerView.swift`, Standardwerte in `PlaybackEngine.swift` | – | keine Funde |

## Abweichung Spec ↔ Code

Rückmeldung an die Spezifikation (Stand `c01f1cf`); geprüft wurde der Arbeitsbaum vom 2026-09-26.

| Stelle | Spec sagt | Code tut (ausgeführt) |
|---|---|---|
| Fundstellen `PlayerView.swift` | `onDisappear :79-88`, Knopf `:114-121`, Taste `:312-313`, `togglePiP :337-340`, `startIfNeeded :398-408` | durch die Resolver-Anbindung (B01) verschoben: `:83-92` (Wache `:89`), `:118-125`, `:337-338`, `:362-365`, `:423-437` |
| AK-03 | Fenster beobachtet 514 × 270 pt oben rechts | Größe und Lage wählt das System: erster Start 670–682 × 358–364 an der Stelle des Videos, in der echten Oberfläche 934 × 508, danach 514 × 270 oben rechts |
| AK-04, AK-05 (iPad) | gelesen | ausgeführt: Knopf vom Fenster verdeckt (BUG-05); P nur nach Tab (BF-102) |
| AK-14 | Engine etwa 10 ms nach dem Verlassen frei | 3 ms bis `AVPlayerController dealloc`, 19 ms bis `AVPlayer dealloc` nach dem Stopp |
| AK-15 | altes Fenster verschwindet nach einigen Sekunden (4,6 s); Knöpfe des Fensters nicht bedient | in keinem Lauf verschwunden (42 s, 45 s, 60 s bis Beobachtungsende; Release 20 s); „Zurück zur App“ → unsichtbare Wiedergabe, „Schließen“ → pausiert, lädt weiter |
| AK-16 | Pause über den Player ausgelöst | mit dem echten Pause-Knopf des Systemfensters ausgeführt, gleiches Ergebnis |
| AK-22 | Sperre nicht auslösbar, nicht geprüft | am iPad-Simulator gesperrt: kein „Jetzt läuft“, Wiedergabe läuft gesperrt weiter; Bildschirmfotos gesperrt schwarz |
| EC-03 | „vermutlich“ Engine und Fenster bleiben | bestätigt |
| EC-07 | ob das System pausiert, nicht geprüft | es pausiert → BUG-03 |
| EC-08 | nach „Zurück“ kein Player, in den das Bild zurück kann | „Zurück zur App“ schließt das Fenster, der Stream läuft unsichtbar weiter (BUG-01) |
| design.md, Kommentar `PlaybackEngine.swift:73` | `stopPictureInPicture` „holt die Wiedergabe zurück in die App“ | nach „Zurück“ wirkungslos (Fenster bleibt) |

## Neue Tests

Alle unter `Tests/B07/`, Testnamen mit AK-/EC-Nummer. Belege für Fehler mit `XCTExpectFailure("BUG-NN …")`.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B07Support.swift` | – | stumme Testmedien (ffmpeg `-an`, ffprobe-Prüfung), Stream-Mock mit Anfrage-/Verbindungsprotokoll, Beobachtung von `AVPlayer`/PiP-Controller/Delegate ohne Produktänderung, Systemfenster über CGWindowList, Beep-Wächter, Helfer-Aufträge, Navigation wie in der App, Basisklasse mit Aufräumen |
| `B07KnopfTests.swift` | 11 + 1 (`B07ImportHinweisTests`) | AK-01–AK-07, AK-09, EC-01, EC-02, EC-04, EC-05 |
| `B07VerlassenTests.swift` | 6 | AK-13, AK-15 (a, b), AK-16, AK-17, EC-03, EC-10 |
| `B07AppOberflaecheTests.swift` | 1 | AK-15 in der echten `ContentView` (c) |
| `B07DatenschutzTests.swift` | 5 | AK-12, AK-18–AK-20, AK-22–AK-24, EC-11 |
| `B07AngriffTests.swift` | 4 | Angriff 3, 5, 7, 8 |
| `B07SystemfensterTests.swift` (neu) | 7 | echte Knöpfe des Systemfensters: AK-16, EC-07, EC-08, AK-15 (d, e); AK-10 Mac; EC-09. Ohne Helfer (`B07_BRIDGE`) übersprungen |

Ohne Test im Test-Target (nur im iOS-Simulator bedienbar): AK-01/03/04/05/10/11/14/21/22 am iPad bzw. iPhone, EC-06, EC-08 am iPad –
Protokoll `qa/ios-protokoll.txt`. Die Hilfsskripte liegen unter `qa/werkzeuge/` und gehören in die Wurzel einer QA-Kopie (neben
`MikaPlusPlayer.xcodeproj`): `swiftc pipwin.swift -o pipwin`, dann `./bridge2.sh 3600 &` (Helfer für Fensteraufnahme, Vordergrund und
Systemfenster-Knöpfe) und `./run.sh <log> B07SystemfensterTests`; `mkmedia.sh` erzeugt die stummen Medien für `iosserver.py`,
`ios.py` bedient die iOS-Simulatoren über AXe (`AXE=<Pfad>`).

**Letzter Gesamtlauf** (Kopie, Debug, 2026-09-26 17:39–17:49, gefiltert auf Testergebnisse; auch `qa/testlauf-gesamt-gefiltert.txt`):

```
B07AngriffTests testAngriff3_PiPUmschaltenInSchnellerFolge_EinFensterKeinAbsturzKeineZusatzverbindungen passed (15.243 seconds).
B07AngriffTests testAngriff5_BildInBildErzeugtKeineZusaetzlichenAnfragenNurLoopback passed (9.856 seconds).
B07AngriffTests testAngriff7_SendernameLangEmojiSonderzeichen_PlatzhalterUndFensterOhneName passed (9.836 seconds).
B07AngriffTests testAngriff8_PlaylistLoeschenWaehrendPiP_WiedergabeLaeuftWeiter passed (11.792 seconds).
B07AppOberflaecheTests testAK15c_EchteOberflaeche_ZurueckMitPiP_AndererSender_DannZurUebersicht passed (69.111 seconds).
B07DatenschutzTests testAK12_EC11_Multiview_KeinKnopfKeineTasteKeinAutoStart_ControllerJeKachel passed (6.326 seconds).
B07DatenschutzTests testAK18_StartAbgelehnt_KeineMeldungKnopfBleibtOeffnen passed (11.939 seconds).
B07DatenschutzTests testAK19_AK20_AK22_NurBild_UeberAllenFenstern_KeineJetztLaeuftAngaben passed (3.964 seconds).
B07DatenschutzTests testAK23_KeinProtokollVonSenderAdresseZugangsdaten passed (10.749 seconds).
B07DatenschutzTests testAK24_NachPiPNichtsGespeichert_NeueEngineInaktiv passed (5.648 seconds).
B07ImportHinweisTests testAK09_ImportSheetStandardMPEGTS_OhneHinweisAufBildInBild passed (1.689 seconds).
B07KnopfTests testAK01_KnopfObenRechtsNebenVollbildMitTooltip passed (0.651 seconds).
B07KnopfTests testAK02_KeinKnopfBeimLadenFehlerUndAusgeblendet passed (5.891 seconds).
B07KnopfTests testAK03_AK04_KnopfOeffnetUndSchliesstSystemfenster passed (5.608 seconds).
B07KnopfTests testAK05_TasteP_KleinUndGross_BlendetSteuerungEin_KeinHUD_KeinBeep passed (9.904 seconds).
B07KnopfTests testAK06_PWaehrendDesLadens_KeinFensterAuchSpaeterNicht_KeineMeldung passed (9.694 seconds).
B07KnopfTests testAK07_PNachFehlschlag_NichtsFehleransichtBleibt passed (3.967 seconds).
B07KnopfTests testAK09_TSUeberVLC_KeinKnopf_PNurSteuerung_KeinHinweis passed (6.572 seconds).
B07KnopfTests testAK09_XtreamStandardformatLandetBeiVLC passed (0.585 seconds).
B07KnopfTests testEC01_OhneEndung_AVKit_RohesTSScheitert_KeinKnopf passed (1.742 seconds).
B07KnopfTests testEC02_M3UEndung_AVKit_PiPWieM3U8 passed (1.285 seconds).
B07KnopfTests testEC04_EC05_AbbruchWaehrendPiP_FehleransichtFensterBleibt_PBeendet_ErneutVersuchen passed (62.443 seconds).
B07SystemfensterTests testAK10_Mac_KeinAutoStartBeimAppWechsel passed (5.806 seconds).
B07SystemfensterTests testAK15d_NachZurueck_SchliessenImSystemfenster passed (50.762 seconds).
B07SystemfensterTests testAK15e_EC08_NachZurueck_ZurueckZurAppImSystemfenster passed (70.877 seconds).
B07SystemfensterTests testAK16_PauseKnopfDesSystemfensters_AppZeigtWeiterLaeuft passed (24.816 seconds).
B07SystemfensterTests testEC07_SchliessenKnopfDesSystemfensters_AppMerktEsPlayerSpieltImPlayer passed (5.367 seconds).
B07SystemfensterTests testEC08_ZurueckZurAppKnopf_BeiOffenemPlayer_BildKehrtZurueck passed (5.631 seconds).
B07SystemfensterTests testEC09_PiPImVollbild_PlatzhalterFuelltVollbild_VollbildBleibt passed (7.000 seconds).
B07VerlassenTests testAK13_OhnePiP_ZurueckUndTabwechselPausieren passed (4.982 seconds).
B07VerlassenTests testAK15a_Mac_ZurueckMitPiP_DenselbenSenderErneutOeffnen passed (64.134 seconds).
B07VerlassenTests testAK15b_Mac_ZurueckMitPiP_AnderenSenderOeffnen passed (79.361 seconds).
B07VerlassenTests testAK16_PauseImPiPFenster_AppZeigtWeiterLaeuft_ErsterDruckVerpufft passed (5.660 seconds).
B07VerlassenTests testAK17_EC10_ZweiterPlayerStartetPiP_ErsterPausiertZeigtAberLaeuft passed (4.513 seconds).
B07VerlassenTests testEC03_TabwechselMitPiP_KeinePause_EngineBleibt passed (7.593 seconds).
PlaybackEngineTests testPictureInPictureInactiveInitially passed (0.001 seconds).
PlaybackEngineTests testRaisingVolumeUnmutes passed (0.001 seconds).
PlaybackEngineTests testSetVolumeClampsToUnitRange passed (0.001 seconds).
PlaybackEngineTests testToggleMuteFlips passed (0.001 seconds).
PlaybackEngineTests testTogglePictureInPictureIsSafeWithoutOnscreenLayer passed (0.002 seconds).
PlaybackEngineTests testTogglePlayPauseFlipsIsPaused passed (0.001 seconds).
Executed 41 tests, with 0 failures (0 unexpected) in 601.004 (601.030) seconds
** TEST SUCCEEDED **
```

Build-Warnungen aus `Tests/B07`: eine – `CGWindowListCreateImage` ist seit macOS 14 als veraltet markiert (Aufnahme eigener Fenster in
`B07Support.swift:49`); die sieben Hinweise zu `weak var` sind behoben. Laufzeitwarnungen siehe H-1. Frühere Läufe derselben Tests
(abgebrochener Teil und drei Gesamtläufe dieser Fortsetzung, 17:15, 17:25 und 17:39 – der letzte oben, nach dem letzten
Änderungsstand der Tests) lieferten dieselben Befunde. Protokollzeilen des letzten Laufs: `qa/macos-testprotokoll.txt`.

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Mac: Nach „Zurück“ spielt Bild-in-Bild verwaist weiter, App kann es nicht beenden, nächster Sender läuft parallel (42–60 s beobachtet), „Zurück zur App“ im Fenster lässt den Stream unsichtbar weiterlaufen (50 s) – Bezug BF-97 | hoch | `Views/PlayerView.swift:17, 83-92`, `Services/AVKitPlaybackEngine.swift:76-78, 153-172` | BUG-01 |
| iOS/iPadOS: „Zurück“ beendet Bild-in-Bild sofort und ohne Hinweis, entgegen dem Kommentar; gegensätzlich zum Mac – Zielverhalten wartet auf OF-04 | mittel | `Views/PlayerView.swift:17, 83-92`, `Services/AVKitPlaybackEngine.swift:154` | BUG-02 |
| Wiedergabezustand folgt dem Player nicht (Pause/Schließen im Systemfenster, zweites Bild-in-Bild): Knopf zeigt „läuft“, erster Druck verpufft | mittel | `Services/AVKitPlaybackEngine.swift:13, 45-47`, `Views/PlayerView.swift:146, 348-353` | BUG-03 |
| Kein Bild-in-Bild im Xtream-Standardformat MPEG-TS (VLC), ohne Hinweis in Import-Sheet, Player und Website | mittel | `Views/ImportPlaylistView.swift:33`, `Services/PlaybackEngine.swift:85-94`, `web/content/features.ts:31-33, 38`, `web/app/support/page.tsx:70` | BUG-04 |
| iPad: Das Bild-in-Bild-Fenster verdeckt den eigenen Knopf „Bild-in-Bild schließen“ | mittel | `Views/PlayerView.swift:113-133` | BUG-05 |
| Englische Systemtexte („Minimise/Maximise Video“, Platzhalter) – wartet auf OF-03 | niedrig | `Views/PlayerView.swift:119-124`, keine deutsche Lokalisierung | BUG-06 |

Bestätigt, nicht neu: BF-25 (= FB-01), BF-97, BF-102, BF-56, BF-43. Für *Muster*: BUG-06 gehört zu „Englische Texte in einer
deutschen Oberfläche“; BUG-04 zu „Außendarstellung läuft dem Code voraus“.

## Nächster Schritt

`/sdd-build B07` mit dem Auftrag, BUG-01 bis BUG-06 zu beheben, danach erneut `/sdd-qa B07` (Durchlauf 2). Vorher entscheidet der
Nutzer **OF-04** (Verlassen mit aktivem Bild-in-Bild: weiterlaufen mit Steuerung oder sauber beenden); davon hängen BUG-01 und BUG-02
ab. BUG-01 wird am besten zusammen mit B06 BUG-02 (BF-97, `stop()` im Protokoll) repariert, der Website-Teil von BUG-04 mit der
B10-Reparatur Teil 2. Wegen BUG-01 (hoch) **wartet die Erfassung der weiteren Bestandsfeatures**. Offen und keine Befunde: OF-01
(automatischer Start abschaltbar, Sichtbarkeit bei Bildschirmfreigabe), OF-02 (Rückmeldung bei nicht möglichem Start), OF-03
(Sprache, BUG-06). Am Gerät nachzuholen: EC-12 (echtes iPhone) und die Sichtprüfung des Sperrbildschirms (AK-22).
