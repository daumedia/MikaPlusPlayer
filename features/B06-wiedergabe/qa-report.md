# B06 · Wiedergabe — Testbericht

Durchlauf 1 · Stand: 2026-09-26 · Geprüft gegen `spec.md` vom 2026-09-16 (Status `rekonstruiert`, Stand `c01f1cf` + Reparatur B01)
· Geprüfter Code: **aktueller Arbeitsbaum** (`c01f1cf` + Reparaturen B01, B09, B10-Teil-1, Branch `sdd/rueckerfassung`, nicht committet).
Die B06-Dateien `PlaybackEngine.swift`, `AVKitPlaybackEngine.swift`, `VLCPlaybackEngine.swift`, `PlayerLayerView.swift` sind gegenüber
`c01f1cf` unverändert, `PlayerView.swift` trägt nur die Resolver-Anbindung aus B01; die Fundstellen der Spec stimmen.

Dieser Durchlauf setzt einen abgebrochenen Durchlauf fort. Übernommen und neu ausgeführt wurden dessen Tests (`Tests/B06/`,
39 Fälle) und Nachweisbilder; ergänzt wurden fünf Tests, ein Release-Lauf auf dem echten Navigationsweg und ein Lauf in eigenen
iOS-Simulatoren.

## Fazit

**Production-ready: nein** · höchster Schweregrad: **hoch** (BUG-01, BUG-02, BUG-03)

Die Grundfunktion trägt: Die Engine-Wahl nach Endung (25 Adressen), die abspielbare Adresse aus dem Schlüsselbund, beide Engines
mit HLS, MP4 und rohem MPEG-TS, alle AVKit-Fehlertexte samt Zeitgrenzen (40 s / 120 s / 30 s), „Erneut versuchen“, Steuerung,
HUD, Tastatur am Mac und am iPhone, natives Vollbild, Tabwechsel, iPad-Vollbild und Hintergrundwiedergabe unter iOS sind
ausgeführt und bestanden. Im Release-Build unter Hardened Runtime steht im Systemprotokoll der normal gestarteten App weder
Passwort noch Adresse (4.531 Zeilen, 764 × `<private>`), und der Player schreibt nichts in die Datenbank.

Durchgefallen sind alle neun ⚠-Kriterien und drei reguläre: Schwer wiegen drei Funde. **BUG-01**: Fehler der VLC-Engine – und
damit jedes Xtream-Senders im Standardformat MPEG-TS – erreichen die Oberfläche nie. 401, 403, 404 und ein nicht erreichbarer
Host ergeben einen endlosen Ladekreis (60 s beobachtet, Release und iOS ebenso), ein Hänger gilt als „läuft“ (200 s), ein Abbruch
bleibt als Standbild stehen. **BUG-02**: „Zurück“ pausiert nur. Im Release-Build lebte die VLC-Engine des ersten Senders mitsamt
Verbindung bis zum Beenden der App (180 s, 5,5 MB nachgeladen) und bis zu **drei gleichzeitige Verbindungen** zum Anbieter bei
einem sichtbaren Player; ein verlassener Live-HLS-Stream lud weiter (18 Abrufe in 20 s). Wird ein `.ts`-Sender während des Ladens
verlassen, spielt VLC ihn danach ab (im Release belegt). Am iPhone lud eine verlassene TS-Verbindung 10 Minuten mit voller Rate
nach. **BUG-03**: Unvertraute Streams beliebiger Hosts und `file://`-Adressen laufen ohne Sandbox durch eine libVLC
`3.0.21-49-g608e9fb467` mit veröffentlichten Lücken (VideoLAN-Bulletin 3.0.22, u. a. Schreibzugriffe außerhalb der Grenzen im
CEA-708-Decoder); das eingebundene Paket `vlckit-spm` hat keine neuere Version, VideoLANs eigenes VLCKit 3.7.x baut auf 3.0.23.

Mittel sind der README-Hinweis in der Fehleransicht (BUG-04), der nicht an das Fenster gebundene Vollbildzustand – jetzt auch
über den Tabwechsel im Vollbild belegt (BUG-06) –, ein **libVLC-Hänger**, den der abgebrochene Durchlauf zweimal im Test-Host
aufzeichnete und der hier in rund 110 Senderwechseln und 80 Engine-Abbauten nicht wiederkam (BUG-07), und die am iPad wirkungslose
Tastatursteuerung (BUG-08). Niedrig: die Website verspricht Rückmeldung für jede Taste (BUG-05), der Ladekreis ist dunkelgrau statt
weiß und der Sendername unter iOS im hellen Erscheinungsbild unsichtbar (BUG-09).

Nicht prüfbar blieb AK-25 in seinem fraglichen Teil (Querformat **rechts**, Zwang ins Hochformat bei vorher quer liegendem Gerät):
Die Gerätedrehung ließ sich ohne Simulator-App nicht steuern. Der Warnton bei unbelegten Tasten (AK-18) wurde auf Anweisung des
Nutzers nicht ausgelöst.

Nächster Schritt: `/sdd-build B06` mit BUG-01 bis BUG-09 (BUG-03 braucht eine Paketentscheidung), danach `/sdd-qa B06`
(Durchlauf 2). Wegen der drei hohen Funde **wartet die Erfassung der weiteren Bestandsfeatures**. BUG-02 und BUG-07 betreffen
dieselben Engines in Multiview (B08) und sollten dort mitgeprüft werden.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 34 von 35 |
| davon bestanden | 22 |
| davon durchgefallen | 12 (alle neun ⚠-Kriterien, dazu AK-01, AK-18, AK-19) |
| **nicht prüfbar** | 1 (AK-25) |
| Edge Cases belegt | 16 von 16 ausgeführt, davon 2 abweichend von der Spec (EC-04, EC-11) |
| Tests neu geschrieben | 44 in `Tests/B06/` (39 aus dem abgebrochenen Teil übernommen und angepasst, 5 neu) |
| Tests grün | GESAMT_ZEILE |

## Prüfumgebung

| Was | Wie |
|---|---|
| Kopie | `scratchpad/qa1-b06/` (rsync ohne `build`, `.git`, `.xcodeproj`), `xcodegen generate`, eigene DerivedData in der Kopie. **Eigene Bundle-IDs**: macOS-App `lu.daumedia.MikaPlusPlayer.qa1b06` (Test-Host), Tests `…Tests.qa1b06`, Release-Lauf `…qa1b06r`. Die Einstellungsdomäne, der Cache und die `vlcrc` der installierten App wurden weder gelesen noch beschrieben |
| Build/Test | `xcodebuild build-for-testing` / `test-without-building -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -only-testing:MikaPlusPlayerTests/B06…`, Läufe mit Wachhund (Sample und Abbruch nach 150–360 s ohne Ausgabe). In der Kopie nur `Tests/B06`, `Tests/Support` und die drei Basistests (die übrigen Feature-Ordner liefen parallel in deren QA) |
| Release-Lauf | Release-Build der Kopie (Hardened Runtime, ad-hoc, `disable-library-validation`, Sandbox aus – wie ausgeliefert), gestartet als **normale App** mit `CFFIXED_USER_HOME`/`HOME` im Scratchpad und gesäter Datenbank (6 Sender). Bedienung auf dem echten Weg Playlists → Senderliste → Player → Zurück durch eine **Sonde in der Kopie** (`QAProbeB06.swift` + Lader `.m`, nur mit `QA_B06_PROBE=1` aktiv, ändert keine bestehende Datei, bricht vor `main` ab, falls die Pfade nicht im Scratchpad liegen – beim ersten Start griff diese Sperre). Die Sonde protokolliert nur in eine Datei, nicht ins Systemprotokoll. Protokoll `qa/REL-10-release-lauf-protokoll.txt` |
| iOS | zwei **eigens angelegte** Simulatoren („QA-B06 iPhone 17“, „QA-B06 iPad Air 11“, iOS 27.0, am Ende gelöscht), Debug-Build der Kopie, Datenbank im App-Container gesät, Bedienung mit AXe (Tippen per Accessibility/Koordinate, Tasten als HID-Ereignisse einer Hardware-Tastatur). Protokoll `qa/IOS-11-simulator-protokoll.txt` |
| Streams | Test-Host: `B06StreamServer` im Prozess (127.0.0.1, zufälliger Port); Release/iOS: Python-Mock auf 127.0.0.1:18966/18967. Alle Medien ohne Tonspur (`ffprobe`: 0 Audiospuren in `src.ts`, `clip.mp4`, 10 HLS-Segmenten); zusätzlich schaltet die Testbasis selbst erzeugte Engines vor dem Laden stumm |
| Zugangsdaten | nur erfunden (`qa-user` / `qa-pass-b06`, `qa-pass-b06rel`), Schlüsselbund nur mit Test-Dienstnamen (`…xtream.tests.<UUID>`) |
| Rechner | Apple Silicon, macOS 27 (Darwin 27.0.0). Parallel liefen vier weitere QA-Läufe (Lastmittel bis 104) |
| Ton | kein Ton: Medien ohne Tonspur, keine Systembeeps (nur belegte Tasten, Beep-Wächter aktiv, `B06BeepGuard.hits` in jedem UI-Test leer) |

## Akzeptanzkriterien im Einzelnen

Testnamen ohne Klasse: `B06EngineWahlTests` (W), `B06EngineZustandTests` (Z), `B06SteuerungTests` (S), `B06PlayerViewTests` (P),
`B06NachtragTests` (N). Bilder unter `features/B06-wiedergabe/qa/`. `<pass>` steht für das erfundene Passwort.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ❌ durchgefallen | P `testAK01_AK14_…`: Titel „QA Live“, Ladekreis am Anfang, keine Steuerung beim Laden, spielt nach 0,4 s mit `volume=1.0`, `muted=false`, `rate=1.0`. Release (echter Weg): Fenstertitel „QA 1 TS stumm“, Symbolleiste mit „Back“ und Tab-Auswahl „Playlists/Favoriten“ (`REL-06-ts-vlc-release.png`). iPhone: Player im Stapel, Sendername als Überschrift in der Navigationsleiste. **Aber:** Der Ladekreis ist dunkelgrau auf Schwarz, nicht weiß (`AK-10-vlc-404-ladekreis-ohne-meldung.png`, `REL-08-…`, `IOS-10-…`), und der Sendername ist unter iOS im hellen Erscheinungsbild **unsichtbar** (schwarz auf schwarz, `IOS-01-hls-spielt-hochformat.jpg`; im dunklen sichtbar, `IOS-10-…`) → **BUG-09** |
| AK-02 | ✅ bestanden | W `testAK02_EC15_…`: 25 Adressen, 0 Abweichungen (`.ts/.TS/.mpegts/.mts/.m2ts`, `?token`, `#frag`, `a.m3u8.ts`, `file:///tmp/a.ts` → VLC; `.m3u8/.M3U8/.m3u/a.ts.m3u8` → AVKit; `.mp4`, `.mkv`, ohne Endung, `play.php?file=a.ts`, `a.ts%20`, `rtmp/rtsp/udp` → AVKit). Zusätzlich `stream.ts/` → VLC (URL ignoriert den Schrägstrich). Kein Wechsel bei Fehlern: AK-10 bleibt VLC |
| AK-03 | ✅ bestanden | W `testAK03_EC14_…`: `/live/101.ts` → `/live/qa-user/<pass>/101.ts` (VLC), `.m3u8` → AVKit; `qa user` / `a/b#c?d.m3u8` → `/live/qa%20user/a%2Fb%23c%3Fd.m3u8/106.ts` (VLC); Altbestand und M3U mit `u:pw@…?token=geheim` unverändert. Tatsächlicher Abruf am Mock: Z `testAK09_…` `GET /live/qa-user/<pass>/101.ts` |
| AK-04 | ✅ bestanden | P `testAK13_AK04_AK31_…`: Meldung wörtlich, 50 ms nach dem Öffnen kein Ladekreis, **0 Anfragen** für den Sender, „Erneut versuchen“ → dieselbe Meldung, weiter 0 Anfragen; Adresse ohne `/live/` → „Die Stream-Adresse ist ungültig.“ (`AK-04-AK-13-zugangsdaten-fehlen-mit-readme-hinweis.png`, `AK-04-adresse-ungueltig.png`); W `testAK04_…` |
| AK-05 | ✅ bestanden | Z `testAK05_EC02_…`: HLS-VOD, Live-HLS, MP4 (Byte-Range), HLS unter `.m3u` je `playing` nach 0,1 s; Live-Playlist 6 Abrufe im Abstand 2,0 s, 7 Segmente |
| AK-06 | ✅ bestanden | Z `testAK06_AK31_…`: alle neun schnellen Fälle wörtlich wie in der Tabelle, je nach 0,1 s; Z `testAK06_EC09_…_langsam` (`B06_LANGSAM=1`): Hänger `.m3u8` → „resource unavailable“ nach **40,0 s**, `.mp4` → „The operation could not be completed“ nach **120,0 s**, Live-HLS-Abbruch nach 10 s → „The network connection was lost.“ nach 40,3 s (30,3 s Standbild). Sprache → OF-01 |
| AK-07 | ✅ bestanden | Z `testAK07_…_langsam`: neuer Abruf nach **20,0 s**, danach `playing` nach 20,2 s, Playlist dann alle 2 s. Ein zweiter Lauf unter hoher Last (Lastmittel ≈ 100) scheiterte zur selben Zeit mit „resource unavailable“ – das Ergebnis hängt an einer Frist in AVFoundation (Abweichung, siehe unten) |
| AK-08 | ✅ bestanden | P `testAK08_Angriff3_…`: je Öffnen 2 Abrufe der Playlist; zwei „Erneut versuchen“ → 4, dann 6 Abrufe, Ladekreis kurz sichtbar, weiterhin **ein** `AVPlayer` (dieselbe Engine), danach wieder die Fehleransicht; keine Wartezeit |
| AK-09 | ✅ bestanden | Z `testAK09_AK32_AK35_…`: `.ts`, `.mpegts`, `.mts`, `.m2ts`, `.TS` und Xtream-Form über `VLCPlaybackEngine`, `playing` nach 0,1 s, VLC `isPlaying`, je Verbindung 289.520 B in 5 s (= Echtzeit). Release: VLC spielt unter Hardened Runtime (`REL-06`); iPhone: `IOS-09-ts-vlc-spielt.jpg` |
| AK-10 ⚠ | ❌ durchgefallen | Z `testAK10_…` (15 s und 60 s): 401, 403, 404, geschlossener Port, unbekannter Host, Xtream-404 → Zustand `idle` nach 0,06 s, VLC-Rohzustand `stopped`, **nie** `failed`; je 4 Anfragen. P `testAK10_AK11_…`: nach 12 s nur `AXBusyIndicator`, kein „Erneut versuchen“ (`AK-10-vlc-404-ladekreis-ohne-meldung.png`). Release: Ladekreis nach 15 s (`REL-08-ts-404-ladekreis-15s.png`), iPhone ebenso (`IOS-10-…`) → **BUG-01** |
| AK-11 ⚠ | ❌ durchgefallen | Z `testAK11_…` (200 s): Hänger → `playing` nach 0,05 s und so bis zum Ende; verzögert (30 s) → `playing` nach 0,05 s; HTML → in beiden Läufen `loading` (Ladekreis), VLC `paused`; keine Meldung. P: Hänger zeigt nach 0,8 s die Steuerung wie ein laufender Stream (`AK-11-vlc-haenger-steuerung-wie-laeuft.png`) → **BUG-01** |
| AK-12 ⚠ | ❌ durchgefallen | Z `testAK12_EC04_…`: Server bricht nach 5 s ab (`abort-after-5s`) → Engine bleibt `playing`, VLC `paused`, 17 s lang keine Meldung → **BUG-01** |
| AK-13 ⚠ | ❌ durchgefallen | P `testAK13_AK04_AK31_…`: Kasten mit Warndreieck, „Wiedergabe fehlgeschlagen“, Meldung, „Erneut versuchen“, keine Steuerung; README-Hinweis **nur** bei der Xtream-Playlist ohne Zugangsdaten (gespeicherte Adresse `.ts`), nicht bei VLC-Fehlern (dort gibt es keine Fehleransicht, AK-10) → **BUG-04** |
| AK-14 | ✅ bestanden | P `testAK01_AK14_…`: Steuerung nur bei `playing`, ausgeblendet **3,6 s ab Öffnen**; Klick → an, Klick → aus; ↑ blendet nicht ein (HUD ja), Leertaste blendet ≈ 3,5 s ein; Stream mit 5 s Verzögerung zeigt nach dem Start keine Steuerung (Timer lief ab Öffnen) (`AK-14-steuerung-sichtbar.png`, `…-ausgeblendet.png`) |
| AK-15 | ✅ bestanden | P `testAK15_…`: Leertaste → `rate 0`, HUD `pause.fill`, Knopf ▶; nach 1,1 s HUD weg; erneut → `rate 1`, HUD `play.fill`; Knopf-Aktionen ebenso (`AK-15-hud-pause.png`). VLC: `paused`/`playing` (S `testAK15_…`, P `testAK20_AK15_…`). iPhone mit Hardware-Tastatur: HUD Pause, Knopf „Play“ (`IOS-04-hardware-leertaste.jpg`) |
| AK-16 | ✅ bestanden | P: `m`, Umschalt-M, Feststell-m, Knopf → `isMuted` wechselt, HUD `speaker.slash.fill`, Lautstärke bleibt 1,0 (`AK-16-hud-stumm.png`); VLC `audio.muted=1` bei `volume 100` (P `testAK20_…`, S `testAK16_…`) |
| AK-17 | ✅ bestanden | P: 3 × ↑ bei 100 % → 100 %, HUD „100 %“; 20 × ↓ → 0 %, HUD „0 %“; `+`/`=` je +5, `-` −5; stumm + ↓ → Stumm aufgehoben (OF-02) (`AK-17-hud-lautstaerke-100.png`). S: beide Engines, VLC `audio.volume` 35 bei 0,35; neue Engines 1,0 und nicht stumm (S `testAK01_…`). Systemlautstärke vorher = nachher, am Prüfrechner allerdings nicht als Zahl lesbar (`missing value`, Ausgabe über ein Audio-Interface ohne Software-Lautstärke) |
| AK-18 | ❌ durchgefallen | macOS bestanden: P `testAK15_…_EC07_…` und `testAK21_…`: Leertaste, ↑, ↓, +, =, -, M (auch Umschalt/Feststell), F, P, ⌘↑, ⌘F wirken; Esc nur im Vollbild; Beep-Wächter ohne Treffer. iPhone mit Hardware-Tastatur: Leertaste, F, Esc, M wirken (`IOS-04`, `IOS-05`, `IOS-07`). **iPad: keine Taste wirkt** (Leertaste, F – frisch geöffnet, nach Tipp aufs Bild, HLS und TS), obwohl dieselben HID-Tasten im Suchfeld ankommen (`IPAD-05`, `IPAD-07`, `IPAD-08`) → **BUG-08**. Der dritte Punkt (Warnton bei unbelegten Tasten) wurde auf Anweisung des Nutzers nicht ausgelöst |
| AK-19 | ❌ durchgefallen | macOS bestanden: Tasten ohne vorherigen Klick, nach Vollbild hin und zurück, nach Klick aufs Bild (P `testAK15_…`, `testAK21_…`) und nach Tabwechsel (P `testAK27_AK19_…`). **iPad:** ohne Wirkung, auch nach Tipp aufs Bild → **BUG-08** |
| AK-20 | ✅ bestanden | P `testAK20_AK15_…`: P bei VLC → nur Steuerung, kein HUD, kein PiP-Knopf, kein Warnton (`AK-20-vlc-taste-p-nur-steuerung.png`) |
| AK-21 | ✅ bestanden | P `testAK21_AK19_EC07_…`: F → natives Vollbild 1920 × 1028 auf 1920 × 1080, Titel leer, Knopf 24,5 pt vom rechten Rand (`AK-21-vollbild-nativ.png`); Esc → Fenster wieder 640 × 484 an derselben Stelle, Titel zurück; ⌘F wie F; „Zurück“ im Vollbild → Fenster verlässt das Vollbild (0,1 s) |
| AK-22 | ✅ bestanden | P `testAK22_…`: im Vollbild ausgeblendete Steuerung erscheint bei `mouseMoved` in den oberen 90 pt (synthetische Mausbewegung; kein echter Mauszeiger) |
| AK-23 ⚠ | ❌ durchgefallen | P `testAK23_…`: Aktion des Vollbild-Knopfs in A, B ist Schlüsselfenster → **B** geht ins Vollbild, A bleibt normal ohne Titel; zweite Aktion holt B zurück (`AK-23-fenster-b-im-vollbild.png`, `AK-23-fenster-a-player-ohne-titel.png`) → **BUG-06** |
| AK-24 ⚠ | ❌ durchgefallen | P `testAK24_…`: `toggleFullScreen` wie grüner Knopf → Fenster im Vollbild, Player zeigt „Vollbild an“-Symbol, Abstand 12,5 pt, Titel bleibt; erstes F → Fenster bleibt im Vollbild, nur Titel weg; zweites F verlässt es (`AK-24-gruener-knopf-…png`). Zusätzlich N `testAK21_FB06_TabwechselImVollbild…`: Tabwechsel im Vollbild → Fenster verlässt das Vollbild, zurück im Player: Titel leer, Knopf zeigt „Vollbild verlassen“ (`FB-06-tabwechsel-im-vollbild-player-verstimmt.png`) → **BUG-06** |
| AK-25 ⚠ | ⚠️ nicht prüfbar | Ausgeführt am iPhone: Knopf bzw. F → Navigations-, Tab- und Statusleiste weg, Querformat (Bild 2622 × 1206, `IOS-02-vollbild.jpg`, `IOS-05-…`); Knopf bzw. Esc → Hochformat mit Leisten (`IOS-03-…`, `IOS-07-…`). **Nicht prüfbar** ist der fragliche Teil: ob es Querformat *rechts* ist, lässt sich am Bild nicht ablesen, und ein vorher quer liegendes Gerät lässt sich ohne Simulator-App nicht herstellen (keine Drehung per `simctl`/AXe). „Verlassen im Vollbild“ ist am iPhone nicht erreichbar: Navigationsleiste ausgeblendet, Wischen vom Rand wirkt nicht (`IOS-06`, siehe Hinweise). OF-03 bleibt offen |
| AK-26 | ✅ bestanden | iPad Air 11: Vollbild über den Knopf → Leisten weg, Ausrichtung bleibt Hochformat (1640 × 2360, `IPAD-04-knopf-vollbild.jpg`); zurück über den Knopf |
| AK-27 | ✅ bestanden | P `testAK27_AK19_…` (VLC): anderer Tab → `paused`, zurück → `playing`, dieselbe Engine, **1** Anfrage insgesamt, Verbindung offen |
| AK-28 ⚠ | ❌ durchgefallen | P `testAK28_…`: HLS 12 s nach „Zurück“ **12 Anfragen** (6 Playlist, 6 Segmente), `AVPlayer` lebt mit `rate 0`; TS: Engine `paused`, Verbindung offen, Bytes steigen weiter. N `testAK28_FB02_…`: 8 s nach Zurück von HLS 8 Abrufe, Verbindung offen. **Release, echter Weg**: erste TS-Engine lebte nach „Zurück“ **bis zum Beenden der App** (180 s, 5,5 MB, über 30 Senderwechsel), HLS-Engine lud 20 s lang 18 Mal nach, bis zu **3 Verbindungen** gleichzeitig bei einem sichtbaren Player (`REL-10-…txt`). iPhone: verlassene TS-Verbindung lud 10 min mit voller Rate (17,8 MB) und blieb 14 min offen (`IOS-11-…txt`) → **BUG-02** |
| AK-29 ⚠ | ❌ durchgefallen | P `testAK29_…`: 9 s nach „Zurück“ VLC `isPlaying=true`, Engine `isPaused=true`, 289.520 B in 5 s (volle Rate). Release: Sender „QA 6 TS verzögert“ nach 0,6 s verlassen → VLC `playing=true` bei +4, +8, +12 s (`REL-10`) → **BUG-02** |
| AK-30 | ✅ bestanden | iPhone, Live-HLS über AVKit, Taste Home: **21 Abrufe in 20 s im Hintergrund**, danach Rückkehr ohne Neuaufbau. VLC im Hintergrund: Daten fließen 20 s mit voller Rate weiter; ob Ton liefe, ist ohne Ton nicht prüfbar (so im Kriterium, OF-05) |
| AK-31 | ✅ bestanden | Z `testAK06_AK31_…` (12 AVKit-Fälle, davon 1 Xtream) und P `testAK13_AK04_AK31_…` (4 Ansichten, davon 3 Xtream): kein `qa-user`, kein Passwort, kein `127.0.0.1`, kein Hostname, kein `/live/` in Text oder Accessibility; VLC zeigt keinen Text |
| AK-32 | ✅ bestanden | Z `testAK09_…`: `.ts` genau **1** Anfrage je Öffnen `GET /live/qa-user/<pass>/101.ts`, `Range: bytes=0-`, UA `VLC/3.0.21 LibVLC/3.0.21`, Kopfzeilen `accept, accept-language, host, range, user-agent`; `.m3u8`: UA `AppleCoreMedia/1.0.0.26A428 (Macintosh; U; Intel Mac OS X 27_0; de_de)` plus `x-playback-session-id`, Playlist alle 2 s; „Erneut versuchen“ fragt erneut (AK-08). Nur der Host der Adresse erhält Anfragen |
| AK-33 | ✅ bestanden | Release-Lauf (normale App, Hardened Runtime): `log show --predicate 'processID == 60453' --info --debug` → 4.531 Zeilen, **0** Treffer für Passwort, `qa-user`, `/live/`, `tslive`, `livehls`, `127.0.0.1:18966`, Sendername; CFNetwork/MediaToolbox schreiben `<private>` (764 ×); stdout/stderr 35 Zeilen, nur „creating player instance using shared library“ und die Zustandsdatei-Meldung. Gegenprobe Test-Host → EC-10 |
| AK-34 | ✅ bestanden | N `testAK34_…`: Datenbank auf Datei vor/nach Wiedergabe mit Tasten (Pause, Stumm, Lautstärke) inhaltsgleich, `hasChanges=false`. Release: Datenbank unverändert, Cache-Ordner 0 Dateien, `HTTPStorages` nur leere Tabelle `alt_services`, Einstellungen mit `VLCParams` (`--verbose=4`, `--extraintf=macosx_dialog_provider` …). `vlcrc` (88.704 B, `-rw-------`) untersucht: nur `auhal-audio-device=0` und nach Lautstärkeänderung `auhal-volume=228`, keine Adresse, kein Zugangsdatum |
| AK-35 ⚠ | ❌ durchgefallen | Eingebettet: `strings` über `VLCKit.framework` → `3.0.21-49-g608e9fb467`, UA `VLC/3.0.21 LibVLC/3.0.21`; Release-Entitlements `app-sandbox=false`, `disable-library-validation=true`. Z `testAK35_Angriff7_…`: `file://…/lokal.ts` spielt über libVLC, `file://…/text.ts` (harmloser Text) ohne Meldung. `git ls-remote tylerjonesio/vlckit-spm`: Tags `3.6.0`, `v3.6.0.b10`, `v3.5.1`, `HEAD` = 3.6.0. VideoLAN-Bulletin 3.0.22 (Dez. 2025) gelesen. Kein Exploit ausgeführt, keine präparierten Dateien → **BUG-03** |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | Z `testAK06_…`: roher Live-TS ohne Endung → AVKit, „Operation Stopped“ nach 0,1 s, kein Hinweis, kein VLC (OF-04) |
| EC-02 | ✅ belegt | Z: M3U-Senderliste unter `.m3u` → „…CoreMediaErrorDomain error -12646.“; echtes HLS unter `.m3u` spielt (AK-05) |
| EC-03 | ✅ belegt | Z (AVKit erzwungen): abgeschlossene `.ts`-Datei mit Byte-Range → `playing`; Live-TS → „Operation Stopped“ |
| EC-04 | ❌ weicht ab | MP4 bis zum Ende: `playing`, `rate 0`, `isPaused=false` (Knopf ❚❚), keine Ende-Anzeige ✓. VLC-Dateiende (`short.ts`, 8 s): **bleibt `playing`** (Rohzustand `paused`) – nicht `idle`/Ladekreis wie in der Spec gelesen |
| EC-05 | ✅ belegt | S `testEC05_…`: `pause()` 0,5 s nach `load` → `isPaused=true`, VLC 8 s später `isPlaying=true`, 236.880 B in 4 s (Teil von BUG-02) |
| EC-06 | ✅ belegt | S: 0,95 → 0,8999… → … → 0,0499… (5 %) → 0,0 (0 %) beim 20. Schritt, beide Engines |
| EC-07 | ✅ belegt | P: ⌘↑ über `NSApp.sendEvent` +5 %, ⌘F schaltet das Vollbild |
| EC-08 | ✅ belegt | P `testEC12_…`: Leertaste über `NSApp` erreicht nur den Player im Schlüsselfenster; P `testAK23_…`: Vollbild-Aktion trifft das Schlüsselfenster |
| EC-09 | ✅ belegt | Z `…_langsam`: Live-HLS-Abbruch → 30,3 s Standbild ohne Hinweis, dann Fehleransicht; verzögerter Start → Ladekreis bis 20 s |
| EC-10 | ✅ belegt | Test-Host (PID 61263, 15:44–15:48): `log show` 21.764 Zeilen, **7** mit `…/live/qa-user/<pass>/…` im Klartext (Network/CFNetwork) – im Release-Lauf 0 (AK-33) |
| EC-11 | ❌ weicht ab | P `testEC11_…`: Xtream-Playlist gelöscht, dann „Erneut versuchen“ → Abruf `/live/404/ec11.m3u8` **ohne** Zugangsdaten, keine Meldung „Zugangsdaten fehlen“; die Ansicht zeigt weiter den alten Engine-Fehler (Spec gelesen: meldet fehlende Zugangsdaten). Deckt sich mit B03 BUG-05 (BF-56) |
| EC-12 | ✅ belegt | P `testEC12_…`: zwei Fenster, zwei offene Verbindungen, Leertaste pausiert nur B |
| EC-13 | ✅ belegt | P `testEC13_…`: ⌘W-gleiches Schließen → VLC-Engine nach ≤ 2 s freigegeben, Verbindung geschlossen (Spec: nicht geprüft) |
| EC-14 | ✅ belegt | W `testAK03_EC14_…`: Kennwort `a/b#c?d.m3u8` → Engine folgt `.ts` der `stream_id` |
| EC-15 | ✅ belegt | W: `rtmp://`, `rtsp://`, `udp://` → AVKit (Engine-Wahl ausgeführt; Wiedergabe dieser Schemata nicht) |
| EC-16 | ✅ belegt | Knöpfe über schwarzem Rand ohne sichtbaren Kreis, nur weiße Symbole (`IOS-01-hls-spielt-hochformat.jpg`, `AK-14-steuerung-sichtbar.png`) |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf eine lokale App ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | bestanden | W `testAngriff_FremderHostUndFremdePlaylistID`: gespeicherte Adresse auf `http://evil.example/live/../../x/live/101.ts` umgeschrieben → abspielbare Adresse mit Host `127.0.0.1` aus dem Schlüsselbund; Sender einer fremden Playlist mit denormalisierter `playlistID` von A → `missingCredentials`, keine fremden Zugangsdaten |
| 2 · Zugriffsregeln (Betriebssystem) | **BUG-03** | Release-Entitlements: `app-sandbox=false`, `disable-library-validation=true`; libVLC verarbeitet Streams beliebiger Hosts und `file://` im Prozess der App, der die Xtream-Zugangsdaten aus dem Schlüsselbund lesen darf. `vlcrc` `-rw-------` |
| 3 · Rate Limit / Wiederholversuche | bestanden (Hinweis) | P `testAK08_Angriff3_…`: 10 × „Erneut versuchen“ in 0,6 s → **20** Anfragen am Anbieter, keine Bremse – laut Spec-Katalog 4.1 bewusste Handlung, kein Befund. Gleichzeitige Verbindungen dagegen → BUG-02 (bis zu 3 bei einem Player) |
| 4 · PII in Protokollen | bestanden | Normale App (Release): 0 Treffer in 4.531 Zeilen, Adressen als `<private>` (AK-33); App-Code protokolliert nichts. Test-Host: 7 Zeilen mit Passwort (EC-10, nur Entwicklerrechner, wie B01 BF-43) |
| 5 · PII an externe Dienste | bestanden | Tatsächlicher Payload am Mock (AK-32): VLC `GET /live/qa-user/<pass>/101.ts` mit `accept`, `accept-language`, `host`, `range`, `user-agent: VLC/3.0.21 LibVLC/3.0.21`; AVKit mit `AppleCoreMedia/…(Macintosh; U; Intel Mac OS X 27_0; de_de)`, `x-playback-session-id`. Kein Cookie, keine Authorization, kein anderer Empfänger – wie in Spec 2.2 zugesagt |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` über die fünf B06-Dateien (4 Commits): 0 Adressen, Tokens, Zugangsdaten; `Tests/B06` nur `qa-user`/`qa-pass-b06` und Hosts `127.0.0.1`, `b06-qa.invalid`, `evil.example`; `strings` über das Release-Binary: 0 Treffer für `password=`, `token=`, `sk_live`, `service_role`, `api_key` |
| 7 · Eingaben | **BUG-03** (Schema) | W `testAngriff7_…`: 10.000 Zeichen, Emoji, `';drop table--`, `<script>`, `../../etc/passwd.ts`, `file:///etc/hosts`, `javascript:`, `data:` → kein Absturz, Wahl nur nach Endung; `file://….ts` geht an libVLC und wird abgespielt (Z `testAK35_…`) – keine Eingrenzung von Schema und Ziel |
| 8 · Löschen | teils, **BUG-02** | Der Player speichert nichts (AK-34). Nach dem Löschen einer Playlist während der Wiedergabe ruft „Erneut versuchen“ die Adresse ohne Zugangsdaten ab (EC-11, = B03 BF-56); Engines verlassener Player halten ihre Verbindungen samt Zugangsdaten im Pfad weiter (BUG-02). `VLCParams` und `vlcrc` bleiben (Spec 5.3) |

## Fehler

### BUG-01 · VLC-Fehler erreichen die Oberfläche nie: endloser Ladekreis, Schwarz oder Standbild — hoch

**Betrifft:** AK-10, AK-11, AK-12 (FB-01); Sicherheitskatalog 4.5
**Reproduktion:**
1. Sender mit Adresse `http://<host>/404/a.ts` (bzw. 401, 403, Port geschlossen, Host unbekannt) öffnen
2. 60 s warten
3. Zweiter Fall: Server nimmt an und liefert nichts (bzw. HTML, bzw. bricht nach 5 s ab)
**Erwartet:** Fehleransicht mit Meldung und „Erneut versuchen“ (der Code enthält dafür den Zweig „VLC konnte den Stream nicht
abspielen.“; README und CLAUDE.md beschreiben den Fehler-Fallback); bei Hänger eine Zeitgrenze
**Tatsächlich:** HTTP-Fehler und Host weg → Zustand `idle` nach 0,06 s, Ladekreis ohne Ende (60 s; Release 15 s, iPhone 15 s
beobachtet), vier Anfragen je Öffnen; Hänger und verzögerter Start → `playing` nach 0,05 s mit Steuerung wie ein laufender Stream
(200 s); HTML → Ladekreis; Abbruch → Standbild, gilt als `playing`. `failed` wird in keinem Fall gesetzt. Xtream-Sender laufen
standardmäßig über VLC (MPEG-TS), gesperrte oder abgelaufene Konten und gelöschte Sender sehen also aus wie „lädt noch“
**Ort:** `Sources/Services/VLCPlaybackEngine.swift:80-99` (Zustand erst in einer späteren Main-Actor-Aufgabe aus
`mediaPlayer.state` gelesen, `error` wird von `stopped` überholt; `.buffering` → `.playing`; `.paused` ignoriert),
`Sources/Views/PlayerView.swift:100-103` (`.idle` → Ladekreis); keine Zeitgrenze
**Vorschlag:** Zustand aus der Benachrichtigung übernehmen (bzw. `error` merken), `stopped` nach `opening` ohne Daten als Fehler
werten, `.buffering` erst nach dem ersten Bild als spielend zählen und eine Zeitgrenze ohne empfangene Daten setzen.
**Test:** Z `testAK10_…`, `testAK11_…`, `testAK12_EC04_…`, P `testAK10_AK11_…` (je `XCTExpectFailure("BUG-01 …")`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — Mit eigenem Mock auf 127.0.0.1 und eigenem Test in getrennter Kopie meldet VLC bei 401/403/404, geschlossenem Port und unbekanntem Host `error` und in derselben Millisekunde `stopped`, die Engine steht nach 0,3 s auf `idle` und bleibt dort 60 s (vier Anfragen je Öffnen), Hänger und HTML gelten als `playing` (HTML in diesem Lauf `playing` statt Ladekreis, vgl. „je nach Lauf“), ein Abbruch nach 5 s lässt VLC auf `paused` (Bildzeit steht bei 4,3 s) und die Engine 25 s auf `playing`, `failed` wird nie gesetzt, und die gehostete `PlayerView` zeigt nach 30 s bei `.ts`-404 nur den Ladekreis bzw. beim Hänger eine schwarze Fläche, während die AVKit-404-Kontrolle im selben Lauf „Wiedergabe fehlgeschlagen“ mit „Erneut versuchen“ zeigt; Grad angemessen.

### BUG-02 · Verlassen beendet die Wiedergabe nicht: Engines und Verbindungen überleben den Player, VLC spielt nach Verlassen während des Ladens — hoch

**Betrifft:** AK-28, AK-29 (FB-02), EC-05; Sicherheitskatalog 4.2, 4.3
**Reproduktion:**
1. Release-App: Playlist → Sender „TS“ (roher MPEG-TS) öffnen, 8 s schauen, „Zurück“
2. Weitere Sender öffnen und verlassen (HLS, TS), Verbindungen am Server zählen (`lsof`, Server-Protokoll)
3. Zweiter Fall: `.ts`-Sender öffnen, dessen Server 3 s bis zur ersten Antwort braucht, nach 0,6 s „Zurück“
**Erwartet:** Nach „Zurück“ endet die Wiedergabe: Engine gestoppt, Verbindung geschlossen, kein weiteres Nachladen; höchstens eine
Verbindung je sichtbarem Player
**Tatsächlich:** Die erste TS-Engine lebte pausiert bis zum Beenden der App (180 s nach „Zurück“, 5,5 MB nachgeladen, über 30
Senderwechsel hinweg), die HLS-Engine lud nach „Zurück“ in 20 s 18 Mal Playlist und Segmente, bis ein neuer Sender geöffnet wurde;
bei einem sichtbaren Player bestanden bis zu **3 Verbindungen** zum Anbieter (in 34 von 177 Sekunden). Verlassen während des
Ladens: VLC spielt danach (`playing=true` bei +4 bis +12 s), die App hält ihn für pausiert – mit Tonspur wäre er zu hören, ohne
Knopf zum Anhalten. iPhone: eine verlassene TS-Verbindung lud 10 min mit voller Rate weiter (17,8 MB, bis VLCs Vorpuffer voll war)
und blieb 14 min offen. Im Test-Host ist die Lebensdauer kürzer und schwankt (0,3 s bis über 12 s), der Effekt ist derselbe.
Viele Abos erlauben nur eine Verbindung – der nächste Sender kann dann scheitern, unter VLC ohne sichtbaren Grund (BUG-01)
**Ort:** `Sources/Views/PlayerView.swift:83-92` (nur `pause()`), `:17` (Engine als `@State`, Lebensdauer bestimmt SwiftUI);
`Sources/Services/PlaybackEngine.swift:35-81` (kein `stop()`), `Sources/Services/AVKitPlaybackEngine.swift:145-148` (`deinit` beendet
nur Beobachter), `Sources/Services/VLCPlaybackEngine.swift:49` (pausiert nur, wenn VLC schon spielt; kein `deinit`/`stop`);
der Kommentar `Sources/Services/MultiviewSession.swift:70` benennt die Lücke
**Vorschlag:** `stop()` ins Protokoll (AVKit: `replaceCurrentItem(with: nil)`, VLC: `stop()` + Medium lösen), in `onDisappear`
aufrufen (außer bei aktivem PiP) und die Engine freigeben; `pause()` bei VLC auch während des Ladens wirksam machen.
**Test:** P `testAK28_…`, `testAK28b_…` (nicht strikt), `testAK29_…`, S `testEC05_…`, `testAK28_PausierteEnginesLadenWeiter`,
N `testAK28_FB02_SenderwechselHaeltAlteVerbindungenOffen` (nicht strikt)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — In eigener Kopie (Test-Host, stumme Medien, Mock 127.0.0.1) lebte nach dem echten „Back“-Knopf auf dem Weg ContentView → Playlist → Sender die TS-Engine 60 s pausiert weiter bei laut `lsof`/`netstat` offener Verbindung (2/2 Läufe; Nachladen nur bis zum vollen Socket-Puffer, Recv-Q 576.120 B), die HLS-Engine rief in 12 s nach „Zurück“ 10 bzw. 12 Mal Playlist und Segmente ab, und nach Verlassen während des Ladens spielte VLC ohne Testreferenz ab +4 s bis +20 s mit voller Rate (Recv-Q 0, `isPaused=true`) – nur im reduzierten `NavigationStack`-Host wurde die spielende TS-Engine sofort freigegeben (3/3) und es trat keine zweite gleichzeitige Verbindung auf; Grad angemessen.

### BUG-03 · Unvertraute Streams laufen durch eine libVLC mit veröffentlichten Lücken, ohne Sandbox und ohne Eingrenzung von Schema und Ziel — hoch

**Betrifft:** AK-35 (FB-03); Sicherheitskatalog 4.4, Angriff 2 und 7
**Reproduktion:**
1. `strings -a …/MikaPlusPlayer.app/Contents/Frameworks/VLCKit.framework/Versions/A/VLCKit | grep '3\.0\.2'` → `3.0.21-49-g608e9fb467`
2. `codesign -d --entitlements - --xml MikaPlusPlayer.app` (Release) → `app-sandbox=false`, `disable-library-validation=true`
3. Playlist mit einem Sender `file:///…/lokal.ts` bzw. `http://<beliebiger Host>/x.ts` öffnen
4. `git ls-remote --tags https://github.com/tylerjonesio/vlckit-spm`
**Erwartet:** Eine libVLC ohne bekannte Lücken für Streams aus fremden Quellen, zumindest Eingrenzung auf `http`/`https`
**Tatsächlich:** Die eingebettete libVLC ist 3.0.21 plus 49 Commits (VLCKit-Patches); das VideoLAN Security Bulletin VLC 3.0.22
(Dezember 2025, „Affected versions: 3.0.21 and earlier“, CVE-2025-51602) nennt u. a. Schreibzugriffe außerhalb der Grenzen im
CEA-708-Untertiteldecoder (in MPEG-TS-Videoströmen), im SVCD- und tx3g-Decoder, im MP4-Demuxer und einen Stack-Überlauf in der
Audioausgabe; Angriffsweg „maliciously crafted files or streams“, Code-Ausführung „can't exclude“. libVLC öffnet `file://`-Adressen
aus einer Playlist und spielt sie (lokale Datei ✓, Textdatei ohne Meldung), die App läuft ohne Sandbox. `vlckit-spm` hat außer 3.6.0
keine Version. **Eine Aktualisierung gibt es beim Hersteller:** VideoLANs VLCKit hat die Tags 3.7.0–3.7.3 (3.7.3 vom 2026-02-24),
dessen Build-Skript baut auf libVLC-Commit `79128878` = Tag `3.0.23-2` (Dezember 2025), der die Korrekturen aus 3.0.22 enthält
(GitLab-API, nur gelesen). Kein Exploit ausgeführt, keine präparierten Dateien erzeugt
**Ort:** `project.yml:17-19` (`tylerjonesio/vlckit-spm`, `exactVersion: "3.6.0"`), `Sources/Services/VLCPlaybackEngine.swift:40-46`
(jede Adresse ungeprüft), `Sources/Services/PlaybackEngine.swift:13-19` (nur Endung), `Sources/Resources/MikaPlusPlayer.entitlements:7-12`
**Vorschlag:** Auf VideoLANs VLCKit ≥ 3.7 (libVLC ≥ 3.0.22) wechseln (eigene Einbindung oder gepflegtes SPM-Paket) und nur `http`/`https`
an die Engines geben; mittelfristig Sandbox bzw. Developer-ID mit Library Validation (vgl. B09 BF-09).
**Test:** Z `testAK09_AK32_AK35_…` (User-Agent), Z `testAK35_Angriff7_…`, W `testAngriff7_…` (Ist-Verhalten, ohne `XCTExpectFailure`)

**Gegenprüfung 2026-09-26:** bestätigt ✅ — `libvlc_get_version` liefert zur Laufzeit „3.0.21 Vetinari“ / `3.0.21-49-g608e9fb467` (die 49 sind die VLCKit-Patches auf `TESTEDHASH dd8bfdba` = Tag 3.0.21, keine 3.0.22-Korrekturen), alle Bulletin-Module (`codec_cc`, `demux_mp4_mp4`, `demux_libogg`, `access_mms`, `codec_substx3g` …) sind statisch gelinkt, ein per `importFromFile` importiertes M3U reicht `file://` (TS spielt, stummes MP4 unter `.ts`-Namen wird von libVLC demuxt) und `http://localhost:<port>` (`GET` mit `VLC/3.0.21`) ungeprüft an libVLC, Release `app-sandbox=false`/`disable-library-validation=true`, `vlckit-spm` endet bei 3.6.0, VLCKit 3.7.3 (`79128878`) enthält 3.0.22 vollständig; Grad angemessen

### BUG-04 · Die Fehleransicht schickt Endnutzer zur README und behauptet, VLCKit fehle — mittel

**Betrifft:** AK-13 (FB-04, DS-06)
**Reproduktion:**
1. Xtream-Playlist (Format MPEG-TS), deren Schlüsselbund-Eintrag fehlt; Sender öffnen
2. Zum Vergleich: `.ts`-Sender mit HTTP 404 öffnen
**Erwartet:** Der Hinweis erscheint höchstens in einem Build ohne VLCKit (README „Ohne VLCKit“), nie für Endnutzer mit eingebundenem VLCKit
**Tatsächlich:** Bei fehlenden Zugangsdaten steht unter der Meldung „Hinweis: Rohe MPEG-TS-Streams (.ts) benötigen VLCKit – siehe
README.“, obwohl VLCKit eingebunden ist und die Ursache eine andere; beim echten VLC-Fehler erscheint gar keine Fehleransicht (BUG-01)
**Ort:** `Sources/Views/PlayerView.swift:220-223`, Bedingung `:234-236` (Endung der gespeicherten Adresse statt „VLCKit fehlt“)
**Vorschlag:** Hinweis an `#if !canImport(VLCKitSPM) …` binden oder entfernen.
**Test:** P `testAK13_AK04_AK31_Fehleransichten` (`XCTExpectFailure("BUG-04 …")`)

### BUG-05 · Die Website verspricht Bildschirm-Rückmeldung für jede Taste; F, Esc und P (VLC) haben keine — niedrig

**Betrifft:** FB-05
**Reproduktion:**
1. `web/content/features.ts:38` lesen: „… F goes full screen, P opens Picture in Picture, Esc comes back. On-screen feedback confirms each one, then disappears.“; `web/app/support/page.tsx:65-72` listet P als „Picture in Picture“ ohne Einschränkung
2. Im Player F, Esc drücken; bei einem `.ts`-Sender P
**Erwartet:** Jede genannte Taste bestätigt sich sichtbar, oder die Website nennt nur, was zutrifft
**Tatsächlich:** Leertaste zeigt das HUD; F und Esc zeigen 2 s lang **kein** HUD (nur der Vollbildwechsel); P zeigt bei VLC – dem
Standardformat – kein HUD und kein Bild-in-Bild, nur die Steuerung
**Ort:** `web/content/features.ts:38`, `web/app/support/page.tsx:65-72`; Code `Sources/Views/PlayerView.swift:306-313, 362-365`
**Vorschlag:** Website-Text auf Leertaste/M/Lautstärke einschränken und P als „nur HLS“ kennzeichnen (Teil der B10-Reparatur, vgl. BF-25).
**Test:** N `testFB05_FUndEscZeigenKeinHUD_LeertasteSchon` (`XCTExpectFailure("BUG-05 …")`), P `testAK20_AK15_VLCTasteP`

### BUG-06 · Der Vollbildzustand des Players ist nicht an sein Fenster gebunden — mittel

**Betrifft:** AK-23, AK-24 (FB-06, AS-03), AK-21
**Reproduktion:**
1. Zwei Fenster; Player in A, B ist Schlüsselfenster; Aktion des Vollbild-Knopfs in A
2. Player-Fenster über den grünen Knopf ins Vollbild, dann F
3. Player im Vollbild (F), per Hover eingeblendete Tab-Auswahl → anderer Tab → zurück zum Player
**Erwartet:** Vollbild schaltet immer das Fenster des Players; der Player kennt den tatsächlichen Zustand seines Fensters
**Tatsächlich:** (1) B geht ins Vollbild, A verliert den Titel. (2) Player bleibt in Fensterdarstellung (12,5 pt Abstand, Titel), das
erste F verlässt das Vollbild nicht. (3) Der Tabwechsel beendet das Fenster-Vollbild, zurück im Player ist der Titel leer und der
Knopf zeigt „Vollbild verlassen“, obwohl das Fenster normal ist (Symbolleiste im echten Fenster nur bei Hover, gelesen)
**Ort:** `Sources/Views/PlayerView.swift:399-404` (`NSApp.keyWindow ?? NSApp.mainWindow`), `:20, 306-313` (`isFullscreen` nur aus
eigenen Aktionen), `:408-411` (`resetOrientation` beim Verschwinden, `isFullscreen` bleibt `true`)
**Vorschlag:** Fenster der Ansicht ermitteln (z. B. über einen `NSViewRepresentable`-Anker) und `isFullscreen` aus
`NSWindow.didEnter/didExitFullScreenNotification` dieses Fensters führen; beim Verschwinden zurücksetzen.
**Test:** P `testAK23_…`, `testAK24_…`, N `testAK21_FB06_TabwechselImVollbildVerstimmtPlayer` (je `XCTExpectFailure("BUG-06 …")`)

### BUG-07 · libVLC kann den Hauptthread beim Erzeugen eines Players dauerhaft blockieren, während andere Player abgebaut werden — mittel

**Betrifft:** AK-09 (Stabilität der VLC-Engine); FB-02 (Abbau ohne `stop`)
**Reproduktion:** (so zweimal aufgetreten, abgebrochener Durchlauf 2026-09-26 11:09 und 11:30)
1. Sechs VLC-Engines gleichzeitig 10 s spielen lassen (Test-Host: `testAK09_…`)
2. Alle stoppen und freigeben, ohne auf den Abbau zu warten
3. Sofort sechs neue Engines erzeugen (`testAK10_…`)
**Erwartet:** Neue Player entstehen, unabhängig davon, ob alte gerade abgebaut werden
**Tatsächlich:** Der Hauptthread hing unbegrenzt (6 min bzw. bis zum Abbruch) in `VLCMediaPlayer.init` → `config_GetFloat` →
`pthread_rwlock` (Lesesperre der libVLC-Konfiguration), vier libVLC-Threads in `config_PutPsz`/`config_GetPsz`, drei bis vier
`releaseQueue`-Threads in `-[VLCMediaPlayer dealloc]` → `libvlc_media_player_destroy` → `pthread_join` (Samples
`qa/BUG-07-libvlc-deadlock-sample.txt`, `…-sample-2.txt`). Die App wäre eingefroren. **In dieser Fortsetzung nicht reproduziert:**
12 × 4 Engines (1,5 s), 8 × 6 Engines (10 s, mit `stop` und Fenstern), 30 + 40 Senderwechsel im Navigationsstapel, 30 Senderwechsel
in der Release-App auf dem echten Weg, Folge AK-09 → AK-10 (mit Warten im `tearDown`). Der Einzel-Player-Weg löst ihn damit
nicht nachweisbar aus; mehrere gleichzeitig abgebaute VLC-Player – wie beim Schließen von Multiview (B08, bis zu vier) – schon.
Die Testbasis wartet seit dem Fund im `tearDown`, bis alle VLC-Player abgebaut sind
**Ort:** `Sources/Services/VLCPlaybackEngine.swift:30` (neuer `VLCMediaPlayer` je Engine), `:34-38`; Abbau ohne `stop()` (BUG-02);
libVLC 3.0.21 (BUG-03)
**Vorschlag:** Mit BUG-02 Player vor der Freigabe stoppen und den Abbau serialisieren (nicht mehrere gleichzeitig), mit BUG-03 die
aktuelle libVLC prüfen; in B08 gezielt mit vier Kacheln wiederholen.
**Test:** `B06DeadlockTests.testBUG07_…` und N `testBUG07_SenderwechselImNavigationsstapel` (nur mit `B06_DEADLOCK=1`, Wachhund)

### BUG-08 · Am iPad erreicht die Tastatur den Player nicht — mittel

**Betrifft:** AK-18, AK-19 (iPad-Teil, in der Spec „gelesen“)
**Reproduktion:**
1. iPad (Simulator „iPad Air 11-inch (M4)“, iOS 27.0) mit Hardware-Tastatur; Sender öffnen (HLS oder TS)
2. Leertaste, F drücken; dann aufs Bild tippen und F erneut drücken
3. Gegenprobe: dieselben HID-Tasten im Suchfeld der Senderliste
**Erwartet:** Leertaste pausiert mit HUD, F schaltet das Vollbild (wie am Mac und am iPhone)
**Tatsächlich:** Keine Taste wirkt – kein HUD, keine Steuerung, kein Vollbild (`IPAD-05-leertaste-ohne-wirkung.jpg`,
`IPAD-07-nach-tipp-taste-f.jpg`); im Suchfeld kommen die Tasten an („Qa“, `IPAD-08-hid-tasten-kommen-an.jpg`); am iPhone wirken
Leertaste, F, Esc und M mit derselben Methode
**Ort:** `Sources/Views/PlayerView.swift:58-61, 81` (`.focusable()`, `keyboardFocused = true` in `onAppear`); Ursache vermutlich der
Fokus der oben liegenden iPad-Tab-Leiste (nicht belegt)
**Vorschlag:** Fokus am iPad nachweislich auf den Player legen (z. B. `defaultFocus`, verzögertes Setzen nach dem Push) oder Tasten
über `UIKeyCommand`/`.keyboardShortcut` anbinden.
**Test:** keiner (nur im iOS-Simulator bedienbar), Protokoll `qa/IOS-11-simulator-protokoll.txt`

### BUG-09 · Ladekreis dunkelgrau statt weiß; Sendername unter iOS im hellen Erscheinungsbild unsichtbar — niedrig

**Betrifft:** AK-01; Design-System („Laden (Video): `ProgressView` `.large`, weiß, mittig auf Schwarz“)
**Reproduktion:**
1. `.ts`-Sender mit HTTP 404 öffnen (Ladekreis bleibt, BUG-01) – macOS und iOS
2. iPhone im hellen Erscheinungsbild: beliebigen Sender öffnen, Navigationsleiste ansehen; dann `simctl ui appearance dark`
**Erwartet:** weißer Ladekreis; Sendername klein in der Navigationsleiste lesbar
**Tatsächlich:** Der Ladekreis ist dunkelgrau und auf Schwarz kaum zu sehen (`AK-10-vlc-404-ladekreis-ohne-meldung.png`,
`REL-08-ts-404-ladekreis-15s.png`); `.tint(.white)` färbt den kreisförmigen Indikator nicht. Der Sendername steht als Überschrift in
der Navigationsleiste (Accessibility), ist aber schwarz auf der schwarzen Player-Fläche **unsichtbar** (`IOS-01-…`); im dunklen
Erscheinungsbild sichtbar (`IOS-10-…`). Am iPad ebenso
**Ort:** `Sources/Views/PlayerView.swift:53, 101-103` (`.tint(.white)`), `:66-68` (Titel ohne `.toolbarColorScheme(.dark, …)`)
**Vorschlag:** Indikator mit `.controlSize(.large)` und `.colorScheme(.dark)`/`.environment(\.colorScheme, .dark)` bzw. eigener Farbe;
Navigationsleiste des Players dunkel erzwingen.
**Test:** keiner (Darstellung), Bilder unter `qa/`

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · VLC speichert die letzte Ausgabelautstärke.** Nach einer Lautstärkeänderung steht `auhal-volume=228` in der `vlcrc`; die
  Engine setzt beim Übergang nach `playing` wieder 100 %, dazwischen gilt der gespeicherte Wert (AK-17 „nichts wird gespeichert“ gilt
  für die App, nicht für libVLC). Die Datei bleibt nach dem Löschen aller Playlists (Spec 5.3).
- **H-2 · Am iPhone lässt sich der Player im Vollbild nicht verlassen.** Navigationsleiste und Tab-Leiste sind ausgeblendet, das
  Wischen vom linken Rand wirkt nicht (`IOS-06`); nur Esc bzw. der Knopf beenden erst das Vollbild. Der in AK-25 beschriebene Fall
  „Verlassen im Vollbild“ ist dort also nur über das Hintergrund-Schicksal der App erreichbar.
- **H-3 · Fenstertitel am Mac nicht sichtbar.** `NSWindow.title` trägt den Sendernamen (Sonde: `titel='QA 1 TS stumm'`), angezeigt
  wird er im echten Fenster nicht, weil die Symbolleiste mit Tab-Auswahl die Titelzeile ersetzt (`REL-06`). Gehört zur App-Shell.
- **H-4 · Senderzeilen ohne Logo zeigen einen Ladeindikator (für B04).** In der Release-App meldet jede Senderzeile ohne Logo
  `AXBusyIndicator` („QA 1 TS stumm, QA“), unter iOS ein Fortschrittselement. Nicht Teil von B06, dort zu prüfen.
- **H-5 · iOS-Hintergrund und VLC.** Bei VLC fließen im Hintergrund weiter Daten mit voller Rate (20 s beobachtet), weil die
  Audio-Sitzung von einer vorher benutzten AVKit-Engine aktiv bleibt; ob bei reinem VLC-Betrieb angehalten wird, ist offen (OF-05).
- **H-6 · Bild-in-Bild-Knopf.** Am iPad erscheint „Minimise Video“, am iPhone-Simulator nicht (Systemfähigkeit) – für B07.

## Code-Review

Der `code-reviewer`-Lauf (Skill `code-review`, mittlere Stufe, über `PlayerView.swift`, `PlaybackEngine.swift`,
`AVKitPlaybackEngine.swift`, `VLCPlaybackEngine.swift`, `PlayerLayerView.swift`, `StreamURLResolver.swift`) wurde gestartet; CODE_REVIEW_SATZ

| Fund | Nachprüfung | Ergebnis |
|---|---|---|
| VLC-Zustand wird verspätet aus `mediaPlayer.state` gelesen, `error` geht verloren, `buffering` gilt als spielend | ausgeführt (AK-10 bis AK-12) | bestätigt → BUG-01 |
| Kein `stop()`/`deinit`, `onDisappear` pausiert nur, VLC-`pause()` wirkungslos vor Spielbeginn | ausgeführt (AK-28, AK-29, Release, iPhone) | bestätigt → BUG-02 |
| `isFullscreen` wird in `onDisappear` nicht zurückgesetzt, `resetOrientation` schaltet aber das Fenster | ausgeführt (Tabwechsel im Vollbild) | bestätigt → BUG-06 |
| `retry()` setzt bei vorhandener Engine `resolveError`, die Ansicht zeigt ihn nicht | ausgeführt (EC-11) | bestätigt, = B03 BF-56 |
| `.tint(.white)` wirkt nicht auf den kreisförmigen Indikator; Titel ohne dunkles Farbschema | ausgeführt (Bilder macOS/iOS) | bestätigt → BUG-09 |
| `PlayerLayerHostView` hält den Layer nur schwach | Code nachvollzogen: der Layer gehört der Engine, die ihn stark hält | kein Fehler |

## Abweichung Spec ↔ Code

Rückmeldung an die Spezifikation (Stand `c01f1cf` + Reparatur B01); geprüft wurde der Arbeitsbaum vom 2026-09-26.

| Stelle | Spec sagt | Code tut (ausgeführt) |
|---|---|---|
| AK-01, Design-System | weißer Ladekreis; Sendername unter iOS in der Navigationsleiste | dunkelgrauer Ladekreis; Name im hellen Erscheinungsbild unsichtbar (BUG-09); am Mac Titel gesetzt, aber nicht angezeigt (H-3) |
| AK-07 | spielt nach dem neuen Abruf normal | in einem Lauf unter hoher Last scheiterte AVKit zur selben Zeit (20,0 s) mit „resource unavailable“; ohne Last spielt es |
| AK-11 | HTML: „je nach Lauf auch Ladekreis“ | in beiden Läufen Ladekreis (`loading`, VLC `paused`) |
| AK-18, AK-19 | iPad mit Hardware-Tastatur (gelesen) wie macOS | am iPad keine Wirkung (BUG-08); iPhone wie beschrieben |
| AK-22, AK-26, EC-13 | gelesen bzw. nicht geprüft | ausgeführt und bestanden |
| AK-28 | Engine lebte 12 s bzw. über 45 s, andere Male 0,2–2 s | Release auf dem echten Weg: bis zum Beenden der App (180 s); Test-Host-Stapel 0,3 s bis über 12 s; iPhone: HLS sofort frei, TS-Verbindung 14 min offen |
| AK-34, Spec 5.3 | Inhalt der `vlcrc` nicht untersucht | nur `auhal-audio-device`, `auhal-volume`; keine Adressen (H-1) |
| AK-35 | libVLC 3.0.21 (User-Agent) | genau `3.0.21-49-g608e9fb467`; VideoLAN bietet VLCKit 3.7.x mit libVLC 3.0.23 an |
| EC-04 | VLC-Dateiende → `idle` → Ladekreis (gelesen) | bleibt `playing` (Rohzustand `paused`), Standbild |
| EC-11 | „Erneut versuchen“ meldet fehlende Zugangsdaten (gelesen) | Abruf ohne Zugangsdaten, alter Engine-Fehler bleibt stehen (= B03 BF-56) |
| FB-02 | „beim nächsten Sender entsteht eine zweite Verbindung“ | bis zu drei gleichzeitige Verbindungen gemessen |
| FB-06 | zwei Fenster, grüner Knopf | zusätzlich Tabwechsel im Vollbild |

## Neue Tests

Alle unter `Tests/B06/`, Testnamen mit AK-/EC-Nummer. Belege für Fehler mit `XCTExpectFailure("BUG-NN …")`.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B06Support.swift` | — | stumme Testmedien (ffmpeg `-an`, ffprobe-Prüfung), Stream-Mock mit Verbindungs-/Byteprotokoll, Engine-Registratur, Beep-Wächter, Fenster/Accessibility/Tasten, Basisklasse mit Aufräumen (wartet auf den Abbau der VLC-Player) |
| `B06EngineWahlTests.swift` | 5 | AK-02, AK-03, AK-04, EC-14, EC-15, Angriff 1 und 7 |
| `B06EngineZustandTests.swift` | 10 (2 nur mit `B06_LANGSAM=1`) | AK-05–AK-07, AK-09–AK-12, AK-31, AK-32, AK-35, EC-01–EC-04, EC-09 |
| `B06SteuerungTests.swift` | 5 | AK-01, AK-15–AK-17, AK-28 (Engine), EC-05, EC-06 |
| `B06PlayerViewTests.swift` | 17 | AK-01, AK-04, AK-08, AK-10, AK-11, AK-13–AK-24, AK-27–AK-29, AK-31, EC-07, EC-08, EC-11–EC-13, Angriff 3 |
| `B06NachtragTests.swift` (neu) | 5 (1 nur mit `B06_DEADLOCK=1`) | FB-05, FB-02 beim Senderwechsel, AK-34, FB-06 beim Tabwechsel, BUG-07 im Navigationsstapel |
| `B06DeadlockTests.swift` | 1 (nur mit `B06_DEADLOCK=1`) | BUG-07 (Runden, Parallelität, Spielzeit, `stop`, Fenster per Umgebungsvariable) |
| `B06ErkundungTests.swift` | 1 (nur mit `B06_ERKUNDUNG=1`) | Accessibility-Baum des Players |

**Letzter Gesamtlauf** (Kopie, Debug, `dd/`):

```
GESAMT_BLOCK
```

Zusätzliche Läufe am selben Tag (gleicher Build-Stand der Tests, Ausgaben in der Kopie):
`B06_LANGSAM=1` für AK-06/EC-09, AK-07, AK-10 (60 s), AK-11 (200 s) → `Executed 4 tests, with 0 failures (0 unexpected) in 438.524 s`;
AK-07 erneut → `playing` nach 20,2 s; `B06_DEADLOCK=1` in vier Varianten (siehe BUG-07) → je `passed`, kein Hänger.
Build-Warnungen aus `Tests/B06`: keine (die zwei Concurrency-Warnungen in `B06DeadlockTests` sind behoben).

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| VLC-Fehler (401/403/404, Host weg, Hänger, HTML, Abbruch) erreichen die Oberfläche nie: endloser Ladekreis, Schwarz oder Standbild; betrifft jeden Xtream-Sender im Standardformat MPEG-TS | hoch | `Services/VLCPlaybackEngine.swift:80-99`, `Views/PlayerView.swift:100-103` | BUG-01 |
| „Zurück“ pausiert nur: Engines und Verbindungen überleben den Player (Release: 180 s bis App-Ende, bis zu 3 Verbindungen zum Anbieter; iPhone: 10 min Nachladen), VLC spielt nach Verlassen während des Ladens | hoch | `Views/PlayerView.swift:17, 83-92`, `Services/PlaybackEngine.swift:35-81`, `Services/VLCPlaybackEngine.swift:49` | BUG-02 |
| libVLC `3.0.21-49` mit veröffentlichten Lücken (Bulletin 3.0.22, CVE-2025-51602) verarbeitet Streams beliebiger Hosts und `file://` ohne Sandbox; `vlckit-spm` ohne neuere Version, VLCKit 3.7.x von VideoLAN mit libVLC 3.0.23 verfügbar | hoch | `project.yml:17-19`, `Services/VLCPlaybackEngine.swift:40-46`, `Services/PlaybackEngine.swift:13-19`, `Resources/MikaPlusPlayer.entitlements:7-12` | BUG-03 |
| Fehleransicht zeigt Endnutzern den README-Hinweis „VLCKit fehlt“ bei fehlenden Zugangsdaten, nie bei echten VLC-Fehlern | mittel | `Views/PlayerView.swift:220-223, 234-236` | BUG-04 |
| Website verspricht Rückmeldung für jede Taste; F, Esc und P (VLC) haben keine | niedrig | `web/content/features.ts:38`, `web/app/support/page.tsx:65-72` | BUG-05 |
| Vollbildzustand nicht an das Player-Fenster gebunden: falsches Fenster bei zwei Fenstern, grüner Knopf verstimmt den Player, Tabwechsel im Vollbild ebenso | mittel | `Views/PlayerView.swift:20, 306-313, 399-411` | BUG-06 |
| libVLC-Hänger des Hauptthreads beim Erzeugen eines Players, während mehrere andere abgebaut werden (zweimal im Test-Host, auf dem Einzel-Player-Weg nicht reproduziert; relevant für Multiview) | mittel | `Services/VLCPlaybackEngine.swift:30-38` (libVLC `config`-Sperre / `libvlc_media_player_destroy`) | BUG-07 |
| Am iPad erreicht die Hardware-Tastatur den Player nicht | mittel | `Views/PlayerView.swift:58-61, 81` | BUG-08 |
| Ladekreis dunkelgrau statt weiß; Sendername unter iOS im hellen Erscheinungsbild unsichtbar | niedrig | `Views/PlayerView.swift:53, 66-68, 101-103` | BUG-09 |

## Nächster Schritt

`/sdd-build B06` mit dem Auftrag, BUG-01 bis BUG-09 zu beheben – BUG-03 zuerst als Entscheidung (Bezugsquelle VLCKit ≥ 3.7 bzw.
libVLC ≥ 3.0.22), BUG-05 gemeinsam mit der B10-Reparatur Teil 2 –, danach erneut `/sdd-qa B06`. Wegen BUG-01, BUG-02 und BUG-03 (hoch)
**wartet die Erfassung der weiteren Bestandsfeatures**. Die offenen Produktfragen OF-01 bis OF-05 (englische Systemtexte, ↓ hebt
Stumm auf, iPhone-Ausrichtung, Engine-Wahl nur nach Endung, VLC im iOS-Hintergrund) sind keine Befunde, gehören aber vor die
Reparatur entschieden. Für B08: BUG-02 und BUG-07 mit vier VLC-Kacheln wiederholen; für B03: EC-11 bestätigt BF-56 aus Sicht des
Players.
