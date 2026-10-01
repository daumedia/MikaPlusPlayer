# B04 · Senderliste — Testbericht

Durchlauf 1 · Stand: 2026-09-26 · Geprüft gegen `spec.md` vom 2026-09-16 (Status `rekonstruiert`, gelesen gegen `c01f1cf` ohne Reparaturen)
· Geprüfter Code: **aktueller Arbeitsbaum** (`c01f1cf` + Reparatur B01 + Reparatur B09 + B10 Teil 1, Branch `sdd/rueckerfassung`).
`ChannelListView.swift`, `ChannelRowView.swift` und `PlayerTheme.swift` sind gegenüber `c01f1cf` unverändert; `Channel.swift` und
`Playlist.swift` nur in Kommentaren. Fortsetzung eines abgebrochenen Laufs: dessen Tests (`Tests/B04/`) wurden übernommen, geprüft,
ergänzt und vollständig neu ausgeführt; die Nachweise in `qa/` stammen alle aus diesem Durchlauf.

## Fazit

**Production-ready: ja** · höchster Schweregrad: **mittel** (BUG-01 bis BUG-07, BUG-10, BUG-13)

Der fachliche Kern hält, was die Rekonstruktion beschreibt, und ist jetzt mit dauerhaften Tests belegt: Öffnen aus der Übersicht,
Kopfzeile mit Gesamtzahl, Kartenaufbau, Player-Öffnung, Lazy-Aufbau (17 von 2.000 Karten), Suche mit der vollständigen Semantik aus
AK-07/AK-08 (41 Namen × 47 Begriffe, echte Ansicht = Abfrage), Chip-Leiste, Auswahl und Kombination mit der Suche, Zurücksetzen beim
Verlassen, Leerzustand, Logos inkl. Platzhalter bei Fehlerantworten, Abbruch beim Wegscrollen und nach 60 s, keine Stream-Adressen
oder Zugangsdaten in der Liste, Suchtext verlässt das Gerät nicht, Filter und Sortierung als SQL (echtes SQL der Ansicht mitgeschnitten).
**Erstmals auch auf iOS ausgeführt** (Simulator iOS 27.0 und 26.5, eigene Geräte): Titel, Kopfzeile, Chips, Filter, Player, kein ⊞.

Durchgefallen sind alle 16 ⚠-Kriterien: Das Ist-Verhalten ist reproduziert und je als BUG erfasst. Kein Fund ist kritisch oder hoch.
Mittel sind die Gruppenlogik (Chip gekürzt/Filter ungekürzt BUG-01, veraltete Chips BUG-02, falsche Aussage „enthält keine Sender“
BUG-03), die Logos (Dauer-Ladeindikator BUG-04, keine Größengrenze – 12.000 × 12.000 px kosten +620 MB, in 2 von 3 Läufen auch nach dem
Verlassen nicht freigegeben – BUG-05, Weitergabe an beliebige Hosts BUG-06, Plattencache inkl. `no-store` über das Löschen hinaus
BUG-07), Kontrast/VoiceOver der Chips (gerendert 3,16 : 1 hell, 2,33 : 1 dunkel, BUG-10) und die Leistung (BUG-13): **Der Release-Build
ist nicht schneller als Debug** – bei 17.000 Sendern blockiert das Öffnen der Liste die Oberfläche 0,68–0,90 s, das Leeren der Suche
0,30–0,47 s, das Abwählen eines Chips 0,55–0,58 s, das erste Zeichen 0,31–0,33 s. Die Website-Aussagen „Search that keeps up with
17,000 channels … the list responds immediately“ und „narrows as fast as you can type“ sind damit nicht gedeckt (Korrektur gehört zu B10).
Niedrig: Zahlen- und Chip-Sortierung, englischer Leerzustand (warten auf OF-01, OF-02, OF-03), fehlender Index (BUG-12), Chip-Abfrage
liest alle Spalten (BUG-14).

Nicht prüfbar blieb nichts; alle 34 Kriterien und 12 Edge Cases sind ausgeführt. Neu beobachtet (kein Kriterium, Hinweise): Auf iOS ist
das Suchfeld beim Öffnen **verborgen** und erscheint erst nach Herunterziehen der Liste (H-1, iOS 26.5 und 27.0); Logo-Adressen stehen in
Netzwerk-Protokollzeilen des Test-Hosts (H-2).

Nächster Schritt: Die Befunde gehen nach `features/befunde.md` (Orchestrator); die Erfassung wird **nicht** pausiert. Reparatur mit
`/sdd-build B04` (BUG-01–BUG-07, BUG-10, BUG-12–BUG-14; BUG-08, BUG-09, BUG-11 erst nach Entscheidung zu OF-01, OF-02, OF-03), danach
`/sdd-qa B04` Durchlauf 2. Die Leistungsaussagen der Website gehören in B10 Teil 2.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 34 von 34 |
| davon bestanden | 18 |
| davon durchgefallen | 16 (alle ⚠-Kriterien) |
| **nicht prüfbar** | 0 |
| Edge Cases belegt | 12 von 12 |
| Tests neu geschrieben | 49 in `Tests/B04/` (48 macOS in 8 Testklassen + 1 iOS-UI-Test; Hilfsdatei `B04Support.swift`) |
| Tests grün | 49 von 49 in ihrem vorgesehenen Modus, **0 Fehlschläge**. Standardlauf macOS: 47 ausgeführt, 46 bestanden, 1 übersprungen (SQL-Test braucht `-com.apple.CoreData.SQLDebug 1`, separat grün); `testEC11_…` (Datenvorbereitung iOS) separat grün; iOS-UI-Test auf iOS 27.0 und 26.5 grün. Darin 17 Tests mit `XCTExpectFailure` als Belege für BUG-01 bis BUG-14 und H-1 |

## Prüfumgebung

| Was | Wie |
|---|---|
| Kopie | `rsync` des Repos nach `scratchpad/qa1-b04/` (ohne `build`, `dist`, `.git`, `.xcodeproj`, `web/node_modules`, `web/.next`), dort `xcodegen generate`, eigene DerivedData (`build/dd`, `build/dd-rel`, `build/dd-ios`). **Eigene Bundle-ID** `lu.daumedia.MikaPlusPlayer.qa1b04` (nur in der Kopie), damit Plattencache, Einstellungen und Test-Schlüsselbund der App nie berührt werden. Kopie am Ende gelöscht |
| Build/Test macOS | `xcodebuild build-for-testing` / `test-without-building -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd -only-testing:MikaPlusPlayerTests/B04…`; Nachweise per `TEST_RUNNER_B04_QA_DIR` direkt in `features/B04-senderliste/qa/`; Ausgaben mit Präfix `B04QA|` |
| SQL-Mitschnitt | Kopie der xctestrun-Datei mit Startargument `-com.apple.CoreData.SQLDebug 1`; der Test leitet stderr in eine Pipe und wertet die Zeilen `CoreData: sql:` aus |
| Release-Messung | `-configuration Release -derivedDataPath build/dd-rel ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES` (Swift `-O`; Hardened Runtime nur im Messbuild aus, damit der Test-Host das Test-Bundle laden kann), `test-without-building -xctestrun …`, einmal mit 17.000, einmal mit 2 × 17.000 Sendern (`TEST_RUNNER_B04_LISTS=2`) |
| iOS | In der Kopie ein iOS-UI-Test-Target (`bundle.ui-testing`, Scheme `B04-iOS-UI`, nur diese eine Datei). Eigene Simulatorgeräte „QA-B04 iPhone 17“ (iOS 27.0) und „QA-B04 iPhone 17 iOS26“ (iOS 26.5), nach dem Lauf gelöscht. Daten: Datenbankdatei aus `testEC11_DatenbankFuerIOSSimulatorErzeugen`, vor dem Start in den App-Container kopiert. Nur Tippen und Wischen, keine Tastatur |
| Rechner | Apple M3 Max, macOS 27 (Darwin 27.0.0). **Parallel liefen vier weitere QA-Runden** (B05–B08) und Builds; 1-Minuten-Last während der Messungen 37–77 (je Zeile in `qa/AK-31-34-messung.txt`) |
| Logo-Hosts | `B04LogoHost` (NWListener nur auf 127.0.0.1, schreibt Anfragezeile und Kopfzeilen roh mit, erkennt Verbindungsabbrüche), zweite Instanz als „fremder Host“, `localhost` als zweiter Hostname, geschlossener Port 9, `.invalid`-Namen |
| Anbieter | `MockXtreamServer` (Tests/Support, unverändert benutzt) auf 127.0.0.1; erfundene Zugangsdaten `qa-user` / `qa-pass-b04-ak30` |
| Datenbank | je Test eine Datei im Temp-Verzeichnis über den Produktionsweg `AppPersistence.diskContainer` (versioniertes Schema); Test-Host selbst im Speicher. Die Datenbank des Nutzers wurde weder geöffnet noch gelesen; die App wurde nicht regulär gestartet (sie würde eine alte `default.store` übernehmen, `AppPersistence.prepareStore`) |
| Oberfläche macOS | echte `PlaylistsView` → `ChannelListView` im `NSHostingView`, **eingebettet in eine Halter-View** (sonst setzt die Hosting-View das Fenster auf 42 × 48 pt); Bedienung über AppKit-Accessibility (`accessibilityPerformPress`), synthetische Mausklicks, Suchfeld über `NSSearchField` ohne Tastaturereignisse; Fensteraufnahmen in `qa/` |
| Ton | keiner: Streams zeigen auf den geschlossenen Port 9, keine Tastaturereignisse, iOS nur Tippen |
| Codequalität | `code-review`-Skill (Code-Reviewer) über `ChannelListView.swift`, `ChannelRowView.swift`, `PlayerTheme.swift`; 4 Funde, alle nachgeprüft (Abschnitt *Code-Review*) |

## Akzeptanzkriterien im Einzelnen

Abgehakt ist nur, was ausgeführt wurde. Testklassen: `B04AufbauTests` (A), `B04SucheTests` (S), `B04GruppenTests` (G),
`B04LogoTests` (L), `B04LeistungTests` (P), `B04SicherheitTests` (X), `B04ErgaenzungTests` (E), `B04iOSOberflaecheUITests` (I).
Aufnahmen und Protokolle unter `features/B04-senderliste/qa/`.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | A `testAK01_…`: Klick auf die Karte „QA Aufbau“ in der Übersicht → im selben Fenster Titel „QA Aufbau“, Texte „MIKA+PLAYER · 5 SENDER“, „QA Aufbau“; Toolbar `navigationStack.back`, `com.apple.SwiftUI.search`, Platzhalter „Sender suchen“; Subline in Akzentfarbe (1.359 Akzentpunkte) · `AK-01-senderliste.png` · **iOS** I `testAK01_EC11_…`: Navigationsleiste „QA iOS“ (inline), Name groß im Inhalt, Kopfzeile „MIKA+PLAYER · 30 SENDER“, Suchfeld „Sender suchen“ in der Navigationsleiste (y 116–160) – **erst nach Herunterziehen** (H-1) · `EC-11-ios-*.png`, iOS 27.0 und 26.5 |
| AK-02 | ✅ bestanden | A `testAK02_…`: Chip „News“ → 1 Karte, Kopfzeile „5 SENDER“; Suche „zzz-nichts“ → 0 Karten, Kopfzeile „5 SENDER“ · iOS: Chip „Sport“ → 10 Karten, Kopfzeile weiter „30 SENDER“ |
| AK-03 | ✅ bestanden | A `testAK03_EC01_EC10_…`: 6 Karten je 76 pt hoch; Logo 40 × 40 pt an x 18/y 18 der Karte (48-pt-Feld, 4 pt Innenabstand); Badge „Sport“ bzw. ungekürzt „ Sport“ (AX „Beta Zwei,  Sport“); ohne Gruppe kein Badge; ⊞ und ☆ rechts · `AK-03-karten.png` |
| AK-04 | ✅ bestanden | A `testAK04_…`: Klick 16 pt vor dem rechten Rand (Stern) → Favorit umgeschaltet, Titel bleibt „QA Player“; Klick links in die Karte → Titel „Alpha Eins“, „Wiedergabe fehlgeschlagen / Could not connect to the server.“ (Port 9), kein zweites Fenster, Liste verdeckt · `AK-04-player.png` · iOS: Tipp auf „Sport Kanal 0“ → Player im selben Stapel (`EC-11-ios-player.png`) |
| AK-05 | ✅ bestanden | A `testAK05_…`: 2.000 Sender, Fenster 900 × 700 pt: nach dem Öffnen 17 Karten und 17 Logo-Anfragen; nach Scrollen zur Mitte Karten „Sender 0991 …“, 43 Anfragen insgesamt (Dokumenthöhe 172.100 pt) · `AK-05-lazy.txt` |
| AK-06 | ✅ bestanden | S `testAK06_…`: „G“, „Ga“, „Gam“, „Gamma S“ → je 1 Treffer ohne Bestätigung; „alpha“ → nur „Alpha“ der offenen Playlist (nicht „Alpha Fremd“); Gruppenname „Nachrichten“ und tvg-ID „zeta“ → 0; „Sport“ → nur „Gamma Sport“ (Name), nicht „Beta“ (Gruppe Sport) |
| AK-07 | ✅ bestanden | S `testAK07_SucheSemantikUeber41NamenUnd46Begriffe` (41 Namen, 47 Begriffe inkl. 10.000 Zeichen, `AK-07-suchmatrix.txt`): (a)–(f) wie beschrieben · S `testAK07_SucheSemantikOberflaecheGegenSpiegel`: 14 Begriffe in der echten Ansicht = gespiegelte Abfrage, 0 Abweichungen |
| AK-08 | ✅ bestanden | S `testAK08_…` (echte Ansicht): „ ard“ → 0; „ard “ → „ard alpha“, „ＡＲＤ Fullwidth“; „ “ → 27 (alle Namen mit Leerzeichen); `%` `_` `*` `?` `\` `'` `"` → je genau der eine Name; „sport 2“ → „Sport 2“, „sport  2“ → „Sport  2“; 10.000 Zeichen → 0 Treffer, Suchansicht, kein Fehler |
| AK-09 ⚠ | ❌ durchgefallen | S `testAK09_…`: Reihenfolge wie in der Spec (`AK-09-sortierung.txt`), gleich `localizedCompare`; mit Suche „sport“ → „Sport  2, Sport 10, Sport 2“; „100% Hits“ vor „1LIVE“ → **BUG-08** (OF-01) |
| AK-10 | ✅ bestanden | G `testAK10_ChipLeisteNurBeiMehrAlsEinerGruppe`: zwei Gruppen → „Alle, News, Sport“; eine Gruppe + nil/„“/„   “ → keine Leiste; keine Gruppe → keine Leiste · G `testAK10_LeisteIstWaagerechtScrollbar`: 30 Gruppen → waagerechte ScrollView 5.886 pt breit in 700 pt, 31 Chips · `AK-10-chipleiste.png` |
| AK-11 | ✅ bestanden | G `testAK11_EC02_…`: 18 Gruppenwerte → „Alle“ + 13 Chips („10 Musik“, „2 Musik“, „News“, „News⏎“, „SPORT“, „Sport“, „Tab“, „Zebra“, „kids“, „sport“, „Ärger“, „Österreich“, „Ünter“) · `AK-11-chips.png` |
| AK-12 ⚠ | ❌ durchgefallen | G `testAK12_…`: „10 Musik | 2 Musik | News | News⏎ | SPORT | Sport | Tab | Zebra | kids | sport | Ärger | Österreich | Ünter“ (`AK-12-chipreihenfolge.txt`) → **BUG-09** (OF-02) |
| AK-13 | ✅ bestanden | G `testAK13_…`: „Alle“ in Akzentfarbe, „Sport“ grau; nach Tipp auf „Sport“ getauscht, 2 Karten; erneuter Tipp → 4; „News“ dann „Sport“ → nur Sport; „Alle“ → 4; Chip „Sport“ + „alpha“ → 1, + „gamma“ → 0 · `AK-13-alle-gewaehlt.png`, `AK-13-sport-gewaehlt.png` · iOS: Chip „Sport“ → 10 Sport-, 0 Kino-Karten. Kontrast und VoiceOver-Merkmal → **BUG-10** (FB-11) |
| AK-14 ⚠ | ❌ durchgefallen | G `testAK14_…`: Chip „Sport“ → 2 von 6 Sport-Sendern („S1 exakt“, „S4 exakt“); die mit „ Sport“/„Sport “ nur unter „Alle“ (7) · `AK-14-chip-sport.png` → **BUG-01** |
| AK-15 ⚠ | ❌ durchgefallen | G `testAK15_AK19_…`: Chips „Alle, Tab, News“; Chip „Tab“ → 0 Karten, „Keine Sender“ / „Diese Playlist enthält keine Sender.“, Kopfzeile „4 SENDER“ (Anzeige jetzt ausgeführt, Spec: gelesen) · `AK-15-chip-tab-leerzustand.png` → **BUG-01**, **BUG-03** |
| AK-16 | ✅ bestanden | G `testAK16_…`: Chip „News“ + „beta“ → 1 Karte; zurück, Sender mit neuer Gruppe „Doku“ angelegt, wieder öffnen → 4 Karten, Suchfeld leer, Chips „Alle, Doku, News, Sport“ (Zurücksetzen jetzt ausgeführt, Spec: gelesen) |
| AK-17 ⚠ | ❌ durchgefallen | G `testAK17_EC08_…`: M3U-Playlist über den Mock, zwei Fenster (Kino bzw. News gewählt); Aktualisieren (Kino → Doku, 5 → 3 Sender) → Kopfzeile sofort „3 SENDER“, Chips bleiben „Alle, Kino, News, Sport“, Liste „Diese Playlist enthält keine Sender.“; in der Datenbank Doku/News/Sport; „Alle“ → die 3 neuen Sender; nach erneutem Öffnen „Alle, Doku, News, Sport“; kein Absturz · `AK-17-chips-veraltet.png` → **BUG-02**, **BUG-03** |
| AK-18 | ✅ bestanden | G `testAK18_…`: „MIKA+PLAYER · 0 SENDER“, Symbol „Television With A Slash Through It“, „Keine Sender“, „Diese Playlist enthält keine Sender.“, keine Chips · `AK-18-leere-playlist.png` |
| AK-19 ⚠ | ❌ durchgefallen | ausgeführt über AK-15 und AK-17 (Chip gewählt, Suchfeld leer, 0 Treffer → „Diese Playlist enthält keine Sender.“) → **BUG-03** |
| AK-20 ⚠ | ❌ durchgefallen | G `testAK20_EC04_…`: „No Results for “zzz-kein-treffer”“, „Check the spelling or try a new search.“ · `AK-20-suche-ohne-treffer.png` → **BUG-11** (OF-03) |
| AK-21 | ✅ bestanden | L `testAK21_…`: genau die 8 Adressen angefragt (zwei Hostnamen), unverändert; 4 Bilder mit je 6.400 Logopunkten; HTML, HTML als `image/png`, JSON, 404 → 0 Logopunkte (Platzhalter), kein Ladeindikator bleibt · `AK-21-logos.png`, `AK-21-logoantworten.txt`. Ladeindikator bis zur Antwort: L `testAK23_Zeitgrenze…` (1 Karte dreht, solange der Host schweigt) |
| AK-22 ⚠ | ❌ durchgefallen | L `testAK22_…`: nach 10 s und 18 s drehen „ohne Logo“, „Port geschlossen“, „https ohne Gegenstelle“, „Host unbekannt“, „Weiterleitungsschleife“ (21 Anfragen); „Bild kommt“ nicht · `AK-22-ladeindikator.png` · iOS: 20 Ladeindikatoren bei Sendern ohne Logo-Adresse (`EC-11-ios-senderliste.png`) → **BUG-04** |
| AK-23 | ✅ bestanden | L `testAK23_AbbruchBeimWegscrollenUndVerlassen`: 2.000 Sender, Logos 8 s verzögert: 6 Anfragen beim Öffnen (6 Verbindungen je Host), Scrollen zur Mitte → 6 Abbrüche innerhalb 0,1 s, ans Ende → 6, Verlassen → 6 · L `testAK23_Zeitgrenze…`: Host antwortet nie → App schließt nach **60,0 s**, Ladeindikator bleibt · `AK-23-abbruch.txt`, `AK-23-timeout.txt` |
| AK-24 ⚠ | ❌ durchgefallen | L `testAK24_…`: 12.000 × 12.000 px (445.847 Bytes) und 27.005.128 Bytes, je 1 Anfrage, vollständig geladen; Speicher 150–197 → 770–814 MB (+616 bis +622 MB); 8 s bzw. 30 s nach dem Verlassen 186 MB (1 Lauf) bzw. **unverändert 779 / 815 MB** (2 Läufe) · `AK-24-speicher.txt` → **BUG-05** |
| AK-25 ⚠ | ❌ durchgefallen | L `testAK25_AK26_…`: Weiterleitung auf anderen Host und Port ohne Rückfrage gefolgt (zweiter Mock 1 Anfrage); Schleife 21 Anfragen in 26 ms, danach Ladeindikator; `NSAllowsArbitraryLoads = true` im Bundle → **BUG-06** |
| AK-26 ⚠ | ❌ durchgefallen | tatsächlicher Payload am Mock (`AK-26-kopfzeilen.txt`): `GET /nocache/e1.png HTTP/1.1 · Host · Accept: */* · Accept-Language: de-DE,de;q=0.9 · Connection: keep-alive · Accept-Encoding: gzip, deflate · User-Agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`; kein Cookie, kein Referer; beim Weiterleitungsziel identisch → **BUG-06** |
| AK-27 ⚠ | ❌ durchgefallen | L `testAK27_…` (jetzt ausgeführt, Spec: abgeleitet): beim Öffnen 16 Logos (Kino/News); Suche „Religion“ → genau die 12 Religion-Logos; Chip „Sport“ → nur Sport-Logos · `AK-27-sichtbare-sender.txt` → **BUG-06** |
| AK-28 ⚠ | ❌ durchgefallen | L `testAK28_…`: 6 von 6 Antworten im `URLCache` und in `Cache.db` (max-age, ohne Kopfzeilen, `no-store`, HTML 35 B, 404 9 B, JSON 7 B); zweites Öffnen: alle außer max-age erneut angefragt; nach dem Löschen der Playlist 6 `Cache.db`-Zeilen, 6/6 im `URLCache`, 0 Sender in der Datenbank · `AK-28-cache.txt` → **BUG-07** |
| AK-29 | ✅ bestanden | X `testAngriff4_SuchtextErscheintNicht…`: eindeutige Marke als Suchtext → 0 Zeilen in `log show --info --debug` des Prozesses, nicht in `UserDefaults`, 0 Bytes in Datenbank/-wal/-shm, 0 im Plattencache, 0 Anfragen am Mock · `angriff-4-suchtext.txt` |
| AK-30 | ✅ bestanden | A `testAK30_…`: Xtream-Import über `MockXtreamServer` (`qa-user`), Liste offen: kein `qa-user`, Passwort, `127.0.0.1`, `player_api`, `/live/`, `http`, `.m3u8` in Titel und Accessibility-Texten; gespeicherte Adressen `…/live/102.m3u8` ohne Zugangsdaten (B01-Reparatur) · `AK-30-xtream-liste.png` |
| AK-31 | ✅ bestanden | E `testAK31_AK33_EchtesSQLDerSenderliste` (mit SQLDebug): Öffnen `… WHERE t0.ZPLAYLISTID = ? ORDER BY t0.ZNAME COLLATE NSCollateLocaleSensitive , t0.Z_PK`; Chip `… AND t0.ZGROUP = ?`; Suche `… AND NSCoreDataStringSearch( t0.ZNAME, ?, 417, 1)`; beides kombiniert · `AK-31-33-sql.txt` · Abfragedauern P `testAK31_AK32_…` (Tabelle bei BUG-13) |
| AK-32 ⚠ | ❌ durchgefallen | P `testAK31_AK32_…`: Plan der App `SCAN t0 / USE TEMP B-TREE FOR ORDER BY` (auch mit Gruppe); über die Beziehung `SEARCH t0 USING INDEX ZCHANNEL_ZPLAYLIST_INDEX (ZPLAYLIST=?)`; einziger Index auf `ZCHANNEL`: `ZCHANNEL_ZPLAYLIST_INDEX`; 17.000 gegenüber 34.000 Sendern: ohne Filter 259 gegenüber 259–264 ms (Release) · `AK-31-34-messung.txt` → **BUG-12** |
| AK-33 ⚠ | ❌ durchgefallen | E (SQLDebug): Chip-Abfrage `SELECT 0, t0.Z_PK, …, t0.ZGROUP, t0.ZID, t0.ZISFAVORITE, t0.ZLOGOURL, t0.ZNAME, t0.ZPLAYLISTID, t0.ZSTREAMURL, t0.ZTVGID, t0.ZPLAYLIST FROM ZCHANNEL t0 WHERE t0.ZPLAYLISTID = ?` trotz `propertiesToFetch = [\.group]`; Spiegel von `loadGroups` bei 17.000 Sendern → 300 Gruppen, 198–204 ms (Release), 192–203 ms (Debug) auf dem Main-Thread → **BUG-14** |
| AK-34 ⚠ | ❌ durchgefallen | P `testAK33_AK34_EC12_…` in Debug und Release, 17.000 und 2 × 17.000 Sender, Fenster 1.100 × 850 pt (Tabelle bei BUG-13, `AK-31-34-messung.txt`) → **BUG-13** |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | A `testAK03_EC01_EC10_…`: Gruppe „   “ → kein Chip, aber Badge mit unsichtbarem Text (AX „Epsilon Fünf,    “, leere Kapsel in `AK-03-karten.png`) |
| EC-02 | ✅ belegt | G `testAK11_EC02_…`: eigener Chip „News⏎“ neben „News“, findet genau K06a/K06b, „News“ genau K05a/K05b; Darstellung einzeilig als „News…“ (`AK-11-chips.png`) – optisch kaum von „News“ zu unterscheiden |
| EC-03 | ✅ belegt | A `testEC03_…`: drei „Doppel“ erscheinen alle, Reihenfolge B, C, A (nicht Anlagereihenfolge); SQL sortiert zusätzlich nach `Z_PK` |
| EC-04 | ✅ belegt | G `testAK20_EC04_…`: Chip „Sport“ + Suche „beta“ → „No Results for “beta”“, nicht „Keine Sender“ |
| EC-05 | ✅ belegt | L `testEC05_…`: `file:///System/…/GenericApplicationIcon.icns` → keine Netzanfrage, kein Ladeindikator, **Bild wird angezeigt** (`EC-05-file-logo.png`) → OF-06 |
| EC-06 | ✅ belegt | L `testEC06_…`: 1 Byte je 10 s → nach 75 s keine Trennung, Ladeindikator dreht; beim Verlassen schließt die App die Verbindung (`EC-06-troepfeln.txt`) → BUG-05 |
| EC-07 | ✅ belegt | L `testEC07_…` (in der Spec offen): 40 Sender, Logos 4 s verzögert; weg- und zurückgescrollt → die 6 abgebrochenen Logos werden **erneut angefragt** (je 2 Anfragen), danach alle da, 0 Ladeindikatoren (`EC-07-zurueckgescrollt.png`, `EC-07-neuladen.txt`) |
| EC-08 | ✅ belegt | G `testAK17_EC08_…`: zwei Fenster mit unabhängiger Auswahl (Kino / News); Aktualisieren lässt die Chips veralten (AK-17) |
| EC-09 | ✅ belegt | X `testEC09_…` (in der Spec offen): Playlist gelöscht, während ihre Liste offen ist → **kein Absturz**; Titel „QA Gelöscht“, Kopfzeile „3 SENDER“ und Chips „Alle, News, Sport“ bleiben, Liste „Diese Playlist enthält keine Sender.“; auch nach Chip-Druck und Eingabe (`EC-09-playlist-geloescht.png`). Gleicher Befund wie B03 BUG-05 (BF-56), hier nicht neu gezählt |
| EC-10 | ✅ belegt | A `testAK03_EC01_EC10_…`: Name mit 315 Zeichen → Karte 76 pt wie alle, einzeilig mit „…“ (`AK-03-karten.png`) |
| EC-11 | ✅ belegt | I `testAK01_EC11_…` (iOS 27.0 und 26.5): Suchfeld in der Navigationsleiste (nach Herunterziehen, H-1), Chip-Leiste unter der Navigationsleiste (y 126, Leiste endet bei 116), kein ⊞-Button (Buttons: Karten und „Favourite“), Player per Tipp · `EC-11-ios*.png`, `EC-11-ios.txt`, `EC-11-ios26.5.txt` |
| EC-12 | ✅ belegt | P `testAK33_AK34_EC12_…`: 8 Zeichen im Abstand von 100 ms → Eingabe 1,0–1,1 s statt 0,8 s, längster Block 404–427 ms → BUG-13 |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf eine lokale App ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | bestanden, Hinweis H-3 | X `testAngriff1_…`: Playlist A zeigt nur „A1 Alpha, A2 Beta“, Suche „alpha“ in A nur „A1 Alpha“ (nicht „B1 Alpha“); Sender ohne `playlistID` nirgends; Sender mit Beziehung A, aber `playlistID` B erscheint unter **B** (die Liste folgt der Kopie; nur per Datenbank-Manipulation erreichbar) · `angriff-1-fremde-ids.txt` |
| 2 · Zugriffsregeln (Betriebssystem) | Befund bekannt (B01) → trägt BUG-07 | `~/Library/Caches/<Bundle-ID>/Cache.db` `-rw-r--r--`, Ordner `drwxr-xr-x`; Sandbox aus (`MikaPlusPlayer.entitlements`: `com.apple.security.app-sandbox` = false) → jeder Prozess des Benutzers liest die Logo-Adressen und -Antworten (hier nur am Cache der QA-Bundle-ID nachgesehen) |
| 3 · Rate Limit / Wiederholversuche | bestanden (kein kostenpflichtiger Dienst), Beobachtung | X `testAngriff3_…`: Liste 10× öffnen und verlassen → 20 Logo-Anfragen, davon 10 für dasselbe Logo; keine Bremse, begrenzt nur durch Sichtbarkeit (AK-05), Abbruch (AK-23) und `max-age` (AK-28) · `angriff-3-wiederholung.txt` |
| 4 · PII in Protokollen | Suchtext bestanden; Hinweis H-2 | X `testAngriff4_Suchtext…`: Suchtext-Marke 0 Zeilen im Systemprotokoll, 0 in Einstellungen/Datenbank/Cache/Anfragen · E `testAngriff4_LogoAdressenImSystemprotokoll`: `log show --info --debug --last 3m --predicate 'process == "MikaPlusPlayer"'` → 42–43 Zeilen mit der Logo-Marke aus `com.apple.network`, z. B. `… url: http://qab04log206761.invalid/logo.png …` und `[ATS violation] Did not use TLS … server: qab04log….invalid`; die App selbst protokolliert nichts · `angriff-4-logoadressen.txt` |
| 5 · PII an externe Dienste | **BUG-06** | tatsächlicher Payload an Logo-Host und Weiterleitungsziel (AK-26): IP, `User-Agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`, `Accept-Language: de-DE,de;q=0.9`; nach Suche/Chip genau die Logos der Treffer (AK-27). Kein Suchtext im Payload (X `testAngriff5_…`: nur `GET /nocache/s<n>.png`), keine offenen Verbindungen an Nicht-Loopback-Adressen (`lsof` des Prozesses: leer) · `angriff-5-payload.txt` |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` (19 Commits, davon 3 an den B04-Dateien) über `ChannelListView.swift`, `ChannelRowView.swift`, `PlayerTheme.swift`: 0 Treffer für Passwort/Token/Secret/API-Key/Fremd-URLs; `Tests/B04/` nur `127.0.0.1`, `localhost`, `.invalid`, `qa-…`; `strings` über `MikaPlusPlayer.debug.dylib` (Debug) und das Release-Binary: 0 Treffer für `password=`, `token=`, `sk_live`, `service_role`, `qa-pass` |
| 7 · Eingaben | bestanden, Hinweis H-4 | X `testAngriff7_…`: Suchfeld mit `'; drop table ZCHANNEL; --`, `<script>alert(1)</script>`, `../../etc/passwd`, `%00`, Emoji, RTL-Override, 10.000 × „ä“, leer, 1 Zeichen, `\n`, `NULL`, `1=1` → kein Absturz, 8 Sender vorher und nachher, Namen mit SQL/Skript werden als Text gefunden; Gruppennamen mit Skript/SQL werden wörtlich zu Chips und filtern exakt; Logo-Schemata `javascript:` (Ladeindikator dauerhaft), `data:` (geladen), `file:///etc/passwd` (Platzhalter) → 0 Netzanfragen · `angriff-7-eingaben.txt`, `angriff-7-eingaben.png` |
| 8 · Löschen | teils bestanden, **BUG-07** | X `testAngriff8_…`: nach dem Löschen `ZPLAYLIST` 0, `ZCHANNEL` 0; aber 2 Logo-Einträge in `Cache.db` bleiben (BUG-07) und der Sendername steht 1× als Byte in der Datenbankdatei (gleicher Befund wie B03 BUG-07, BF-59) · `angriff-8-loeschen.txt` |

## Fehler

### BUG-01 · Gruppen-Chip gekürzt, Filter vergleicht ungekürzt — mittel

**Betrifft:** AK-14, AK-15 (FB-01)
**Reproduktion:**
1. Playlist mit Sendern der Gruppen „Sport“, „ Sport“, „Sport “ (je zwei) und „⇥Tab“ (nur mit Tabulator) anlegen
2. Senderliste öffnen, Chip „Sport“ antippen, danach Chip „Tab“
**Erwartet:** Der Chip „Sport“ zeigt alle sechs Sport-Sender, der Chip „Tab“ die Tab-Sender
**Tatsächlich:** „Sport“ zeigt 2 von 6 Sendern; „Tab“ zeigt 0 Sender und „Diese Playlist enthält keine Sender.“ – die übrigen Sender
sind nur über „Alle“ oder die Suche erreichbar
**Ort:** `Sources/Views/ChannelListView.swift:77` (Chips `trimmingCharacters(in: .whitespaces)`) gegen `:95` (`ch.group == g` ungekürzt)
**Vorschlag:** Gruppen beim Import normalisieren (B01/B02) oder den Filter auf dieselbe Kürzung abbilden; beides zusammen testen.
**Test:** `B04GruppenTests.testAK14_…`, `testAK15_AK19_…`

**Behoben 2026-09-29:** Chip und Filter benutzen dieselbe gekürzte Form: `ChannelListQuery.groups` bildet je Chip-Titel
(Leerzeichen und Tabulatoren am Rand entfernt, wie bisher, AK-11) die Liste der gespeicherten Rohwerte, der Filter fragt genau
diese ab (`t0.ZGROUP = ?` bzw. `t0.ZGROUP IN (?, …)`). Reproduktion wie oben erneut ausgeführt: Chip „Sport“ zeigt **6 von 6**
Sport-Sendern (vorher 2), Chip „Tab“ die **2** Sender mit „⇥Tab“ (vorher 0 und „Diese Playlist enthält keine Sender.“); das Badge
zeigt die Gruppe weiter ungekürzt (AK-03). Tests: `testAK14_ChipZeigtAlleSenderDerGruppeAuchMitRandleerzeichen`,
`testAK15_AK19_…`, `B04ReparaturTests.testBUG01_GruppenwerteJeChipUndFilter`.

### BUG-02 · Chip-Leiste wird nach einem Aktualisieren nicht neu berechnet — mittel

**Betrifft:** AK-17 (FB-02), EC-08
**Reproduktion:**
1. Playlist mit Gruppen Kino/News/Sport in zwei Fenstern öffnen, im ersten Chip „Kino“ wählen
2. Die Quelle ändert „Kino“ in „Doku“; Playlist aktualisieren
**Erwartet:** Chips „Alle, Doku, News, Sport“; eine weggefallene Auswahl wird aufgehoben
**Tatsächlich:** Kopfzeile sofort „3 SENDER“, Chips bleiben „Alle, Kino, News, Sport“, „Doku“ fehlt; der gewählte Chip „Kino“ zeigt
„Diese Playlist enthält keine Sender.“; erst Verlassen und Öffnen zeigt die neuen Chips
**Ort:** `Sources/Views/ChannelListView.swift:43` (`.task(id: playlist.id)` – die ID bleibt beim Aktualisieren gleich)
**Vorschlag:** Gruppen reaktiv aus der Datenbank ableiten oder `.task(id:)` an `lastRefreshed`/`channelCount` koppeln; verschwundene Auswahl zurücksetzen.
**Test:** `B04GruppenTests.testAK17_EC08_…`

**Behoben 2026-09-29:** Nach dem Aktualisieren meldet `PlaylistImporter.refresh` die ersetzten Sender
(`PlaylistEvents.didReplaceChannels`, nach dem Abholen in den Kontext der Ansicht). Jede offene Senderliste – in jedem Fenster –
berechnet daraufhin Chips und Trefferliste neu; eine weggefallene Auswahl wird aufgehoben, eine weiter vorhandene bleibt.
Reproduktion (zwei Fenster, Kino → Doku, 5 → 3 Sender) erneut ausgeführt: beide Fenster zeigen sofort „Alle, Doku, News, Sport“;
Fenster 1 (Kino gewählt) zeigt alle 3 Sender, Fenster 2 (News gewählt) „News Eins v2“; kein „Diese Playlist enthält keine Sender.“
Tests: `testAK17_EC08_ChipsFolgenDemAktualisierenInAllenFenstern`, `B04ReparaturTests.testBUG02_…`; B03
`testAK27_EC05_…` prüft jetzt, dass der neue Chip „Neu“ erscheint.

### BUG-03 · „Diese Playlist enthält keine Sender.“ bei leerem Filterergebnis — mittel

**Betrifft:** AK-15, AK-17, AK-19 (FB-03); ebenso EC-09
**Reproduktion:** wie BUG-01 Schritt 2 (Chip „Tab“) oder BUG-02 Schritt 2
**Erwartet:** ein Hinweis, dass in dieser Gruppe keine Sender sind (die Kopfzeile zeigt 4 bzw. 3 Sender)
**Tatsächlich:** „Keine Sender – Diese Playlist enthält keine Sender.“ – eine falsche Aussage über die Playlist
**Ort:** `Sources/Views/ChannelListView.swift:101-104` (prüft nur `searchText.isEmpty`, nicht die gewählte Gruppe)
**Vorschlag:** eigener Leerzustand für „Gruppe ohne Treffer“ mit Weg zurück zu „Alle“.
**Test:** `B04GruppenTests.testAK15_AK19_…`, `testAK17_EC08_…`

**Behoben 2026-09-29:** Eigener Leerzustand für einen gewählten Chip ohne Treffer: „Keine Sender in dieser Gruppe“ /
„In der Gruppe „<Name>“ sind keine Sender.“ mit der Taste „Alle Sender zeigen“. „Diese Playlist enthält keine Sender.“ erscheint
nur noch ohne Chip und ohne Suchtext; ein Lesefehler lässt die bisherige Liste stehen, statt eine leere Playlist zu behaupten.
Die Reproduktionen aus BUG-01/BUG-02 führen nicht mehr in einen leeren Chip; der Leerzustand selbst ist mit einem Chip belegt,
dessen Sender die Gruppe wechseln, ohne dass die Leiste es erfährt (`testAK15_AK19_…`: Meldung, Taste führt zurück zu 4 Sendern).
Nicht geändert: der englische Leerzustand der Suche (BUG-11, OF-03).

### BUG-04 · Ladeindikator dreht dauerhaft statt Platzhalter — mittel

**Betrifft:** AK-22 (FB-04), AK-23 (nach dem 60-s-Abbruch), H-4
**Reproduktion:**
1. Sender ohne Logo-Adresse, mit Logo auf geschlossenem Port, `https://` ohne Gegenstelle, unbekanntem Host, Weiterleitungsschleife
2. Liste öffnen, 18 s warten
**Erwartet:** graues TV-Symbol wie bei 404/HTML (der Code sieht `.failure → placeholder` vor)
**Tatsächlich:** fünf Karten mit dauerhaft drehendem Ladeindikator; auf iOS 20 von 20 Karten ohne Logo-Adresse
**Ort:** `Sources/Views/ChannelRowView.swift:36-46` (`AsyncImage(url: nil)` bleibt in `.empty`; Verbindungsfehler ebenso)
**Vorschlag:** ohne Adresse direkt den Platzhalter zeigen; Verbindungsfehler/Zeitüberschreitung als Fehler behandeln (eigener Loader, siehe BUG-05).
**Test:** `B04LogoTests.testAK22_…`, `testAK23_ZeitgrenzeSechzigSekundenOhneDaten`

**Behoben 2026-09-29:** Logos laden über den gemeinsamen `ChannelLogoLoader` (Senderliste und Favoriten-Tab). Ohne Adresse
und bei anderen Schemata als `http`/`https` erscheint sofort der Platzhalter, ohne Anfrage; jeder Fehler (Verbindung, DNS,
TLS, HTTP-Status, kein Bild, zu groß, Frist, Weiterleitung) endet im Platzhalter. Reproduktion erneut ausgeführt: nach 10 s und
18 s **0** Ladeindikatoren (vorher 5), Logo „Bild kommt“ angezeigt, Weiterleitungsschleife nach 4 Anfragen beendet (vorher 21);
`host hängt` → Abbruch nach der Leerlauffrist von 10 s, danach Platzhalter; `javascript:`, `data:`, `file:` → Platzhalter, 0
Anfragen. Tests: `testAK22_OhneLogoOderUnerreichbarErscheintDerPlatzhalter`, `testAK23_ZeitgrenzeOhneDatenDannPlatzhalter`,
`B04SicherheitTests.testAngriff7_…`, `B04ReparaturTests.testBUG04_…`.

### BUG-05 · Keine Grenzen für Logo-Antworten (Größe, Abmessung, Dauer) — mittel

**Betrifft:** AK-24 (FB-05), EC-06; `sicherheit.md` 4.4
**Reproduktion:**
1. Zwei Sender mit Logo-Adressen auf ein PNG 12.000 × 12.000 px (446 KB) und eine 27-MB-Datei
2. Liste öffnen, 12 s warten, Liste verlassen, 30 s warten
**Erwartet:** Logos werden in Größe und Abmessung begrenzt (bzw. verkleinert dekodiert); der Speicher bleibt im Rahmen
**Tatsächlich:** beide vollständig geladen und dekodiert, Speicher +616 bis +622 MB (150–197 → 770–814 MB); nach dem Verlassen in einem
von drei Läufen 186 MB, in zwei Läufen **unverändert 779 bzw. 815 MB auch nach 30 s**. Ein tröpfelnder Host (1 Byte je 10 s) hält die
Verbindung beliebig lange offen (EC-06). Mehrere solcher Logos würden sich addieren; auf iOS droht die Beendigung durch das System
(nicht ausgeführt: der Simulator erzwingt keine Speichergrenze)
**Ort:** `Sources/Views/ChannelRowView.swift:36` (`AsyncImage(url:)` ohne eigene Session, Größen-, Abmessungs- oder Gesamtzeitgrenze)
**Vorschlag:** eigener Logo-Loader mit Höchstgröße (z. B. 1 MB), Downsampling per `CGImageSourceCreateThumbnailAtIndex` auf 96 px und Gesamtzeitgrenze.
**Test:** `B04LogoTests.testAK24_…`, `testEC06_…`

**Behoben 2026-09-29:** Grenzen je Logo: höchstens 1 MiB (größere Antworten werden schon an `Content-Length` abgebrochen),
höchstens 2.048 × 2.048 Bildpunkte laut Bildkopf, 10 s Leerlauf, 15 s Gesamtfrist. Das Bild wird nie voll dekodiert, sondern
per ImageIO als Vorschaubild mit höchstens 128 px Kantenlänge erzeugt (`CGImageSourceCreateThumbnailAtIndex`). Reproduktion
(12.000 × 12.000 px und 27 MB) erneut ausgeführt: je 1 Anfrage, die 27-MB-Antwort bricht vor dem Körper ab, beide Karten zeigen den
Platzhalter, ein normales Logo daneben wird angezeigt; Speicher 171 → 199 MB (+28 MB, Debug) statt +616 bis +622 MB. Tröpfelnder
Host (1 Byte je 4 s): getrennt nach 15,5 s (vorher nach 75 s nicht). Tests: `testAK24_GrenzenFuerDateigroesseUndBildabmessung`,
`testEC06_TroepfelnderHostWirdNachDerGesamtfristGetrennt`, `B04ReparaturTests.testBUG05_…`.

**Nachtrag 2026-09-30:** Die Fristen galten zunächst ab dem Einreihen der Anfrage. Warteten bei einem langsamen Host mehr als
sechs Logos auf eine Verbindung, liefen die letzten schon in der Warteschlange ab und zeigten den Platzhalter (Gesamtlauf
30.09.: `testEC07_…` rot, „Sender 00“ und „Sender 02“ mit Platzhalter nach dem Zurückscrollen). Jetzt warten Logo-Anfragen
abbrechbar in `RequestGate` (höchstens 6 je Host, wie die Verbindungen von `URLSession`); Leerlauf- und Gesamtfrist beginnen mit
dem Senden. Belegt: `B04ReparaturTests.testBUG05_FristenBeginnenMitDemSenden` (6 Logos, 2 je Host, je 2 s, Frist 3 s: 6 von 6
angezeigt nach 6,1 s), `testEC07_…` 4 × einzeln grün und prüft jetzt alle sechs sichtbaren Karten.

### BUG-06 · Logos gehen ohne Wahl an beliebige Hosts, auch unverschlüsselt und über Weiterleitungen — mittel

**Betrifft:** AK-25, AK-26, AK-27 (FB-06); Angriff 5
**Reproduktion:**
1. Playlist mit Logos auf Host A, eines davon mit 302 auf Host B (anderer Port), Kopfzeilen am Mock mitschreiben
2. Liste öffnen, „Religion“ suchen, Chip „Sport“ wählen
**Erwartet:** Logos nur mit Zustimmung bzw. abschaltbar, ohne App-/Systemkennung, keine Weiterleitung auf fremde Hosts, nur HTTPS –
oder zumindest eine zutreffende Datenschutzerklärung
**Tatsächlich:** Jeder Host erhält IP, `User-Agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0` und `Accept-Language:
de-DE,de;q=0.9`, auch das Weiterleitungsziel; unverschlüsselt über HTTP (`NSAllowsArbitraryLoads`); nach Suche bzw. Chip genau die Logos
der Treffer (der Host erfährt, wonach gefiltert wurde). Keine Einstellung zum Abschalten. Die Datenschutzseite sagt gleichzeitig, jede
Logo-Anfrage gehe an „the host you entered“ (`web/app/privacy/page.tsx:47-49`) – bereits als B10 BF-20 erfasst
**Ort:** `Sources/Views/ChannelRowView.swift:36`; `Sources/Resources/Info.plist:45-48`
**Vorschlag:** Schalter „Senderlogos laden“, eigene `URLSession` ohne Weiterleitung auf fremde Hosts und mit neutralem User-Agent; Website korrigieren (B10).
**Test:** `B04LogoTests.testAK25_AK26_…`, `testAK27_…`

**Teilweise behoben 2026-09-29.** Behoben: eigene Session ohne Cookies und Zugangsdatenspeicher; Weiterleitungen nur auf
denselben Host und Port (einzige Ausnahme `http` → `https` desselben Hosts), höchstens 3; neutrale Kopfzeilen `User-Agent:
Mozilla/5.0` und `Accept-Language: *` statt App-Name, Build, CFNetwork-/Darwin-Version und Systemsprache. Reproduktion erneut
ausgeführt: Weiterleitung auf Host 127.0.0.1 mit anderem Port → **0** Anfragen am Ziel (vorher 1), Platzhalter; Weiterleitung auf
denselben Host wird gefolgt und angezeigt; gesendete Kopfzeilen `Host · Accept: */* · Accept-Language: * · Connection ·
Accept-Encoding: gzip, deflate · User-Agent: Mozilla/5.0`, kein Cookie, kein Referer (`BUILD-AK-26-kopfzeilen.txt`).
**Nicht behoben:** Logo-Hosts erfahren weiter die IP-Adresse und über die angefragten Logos, was gesucht, gefiltert oder als
Favorit markiert ist (AK-27); `http://`-Logos gehen unverschlüsselt. Logos abschaltbar, nur mit Zustimmung oder nur über HTTPS zu
laden ist Produktverhalten mit spürbarer Folge → `spec.md` **OF-07**. `testAK27_…` behält sein `XCTExpectFailure` (Grund jetzt
„wartet auf OF-07“). Tests: `testAK25_AK26_…`, `B04ReparaturTests.testBUG06_…` (Regel und Kopfzeilen).

### BUG-07 · Logo-Antworten im Plattencache, auch `no-store`, 404 und HTML, und über das Löschen hinaus — mittel

**Betrifft:** AK-28 (FB-07); Angriff 2, Angriff 8
**Reproduktion:**
1. Logos mit `max-age`, ohne Cache-Kopfzeilen, mit `Cache-Control: no-store`, HTML, 404, JSON anzeigen
2. Playlist löschen
3. `select request_key from cfurl_cache_response` auf `~/Library/Caches/<Bundle-ID>/Cache.db`
**Erwartet:** `no-store` wird nicht gespeichert; nach dem Löschen der Playlist keine Einträge ihrer Logos
**Tatsächlich:** 6 von 6 Antworten gespeichert (auch `no-store`, 404 mit 9 B, HTML mit 35 B); nach dem Löschen 6 Zeilen in `Cache.db`,
6/6 über `URLCache.shared` abrufbar; Datei `-rw-r--r--`, ohne Sandbox für jeden Prozess des Benutzers lesbar
**Ort:** `AsyncImage` über `URLSession.shared`/`URLCache.shared` (`Sources/Views/ChannelRowView.swift:36`); kein Code leert den Cache
(`Sources/Services/PlaylistImporter.swift`, `delete`)
**Vorschlag:** Logo-Loader mit eigenem, begrenztem Cache (Schlüssel ohne Klartext-Adresse), `no-store` beachten, beim Löschen einer Playlist ihre Einträge entfernen.
**Test:** `B04LogoTests.testAK28_…`, `B04SicherheitTests.testAngriff8_…`

**Behoben 2026-09-29:** Logos gehen weder in `URLCache.shared` noch in einen anderen Plattencache (Session ohne
`URLCache`). Fertige Vorschaubilder liegen nur im Arbeitsspeicher (höchstens 400 bzw. 24 MB); Antworten mit `Cache-Control:
no-store` und Fehlerantworten nie. Das Löschen einer Playlist und „Alle Daten entfernen“ leeren diesen Speicher. Reproduktion
erneut ausgeführt: 0 von 6 Antworten im `URLCache`, **0** Zeilen in `Cache.db` (vorher 6/6 und 6); beim zweiten Öffnen kommen die
zwei Bilder aus dem Arbeitsspeicher, `no-store` wird erneut angefragt; nach dem Löschen 0 Einträge überall. Tests:
`testAK28_KeinPlattencacheUndLoeschenLeertDieLogos`, `B04SicherheitTests.testAngriff8_…` (0 Cache-Zeilen),
`B04ReparaturTests.testBUG07_…` (2 Tests, inkl. „Alle Daten entfernen“). Folge: `testAngriff3_…` fragt beim zehnmaligen Öffnen
jedes Logo nur noch einmal an.

### BUG-08 · Zahlen in Sendernamen werden als Text sortiert — niedrig (wartet auf OF-01)

**Betrifft:** AK-09 (OF-01)
**Reproduktion:** Sender „Sport 2“, „Sport 10“, „1LIVE“, „100% Hits“ anlegen, Liste öffnen
**Erwartet:** Produktentscheidung offen (OF-01)
**Tatsächlich:** „100% Hits“ vor „1LIVE“, „Sport 10“ vor „Sport 2“
**Ort:** `Sources/Views/ChannelListView.swift:97` (`SortDescriptor(\.name, comparator: .localized)`)
**Vorschlag:** nach Entscheidung zu OF-01 `.localizedStandard` verwenden.
**Test:** `B04SucheTests.testAK09_…`

**Nicht behoben (2026-09-29):** wartet auf OF-01 (Produktentscheidung). Unverändert: `testAK09_…` behält sein
`XCTExpectFailure` und schlägt darin weiter fehl.

### BUG-09 · Gruppen-Chips nach Zeichencode sortiert, Groß-/Klein-Varianten getrennt — niedrig (wartet auf OF-02)

**Betrifft:** AK-12 (OF-02), AK-11 (c)
**Reproduktion:** Gruppen „10 Musik“, „2 Musik“, „Zebra“, „kids“, „Ärger“, „Sport“, „sport“, „SPORT“ anlegen, Liste öffnen
**Erwartet:** Produktentscheidung offen (OF-02)
**Tatsächlich:** „10 Musik | 2 Musik | … | SPORT | Sport | Tab | Zebra | kids | sport | Ärger | Österreich | Ünter“ – abweichend von der
Sortierung der Sender; drei Chips für „Sport“
**Ort:** `Sources/Views/ChannelListView.swift:79` (`sorted()`)
**Vorschlag:** nach Entscheidung zu OF-02 `localizedStandardCompare` und ggf. Zusammenfassen.
**Test:** `B04GruppenTests.testAK12_…`

**Nicht behoben (2026-09-29):** wartet auf OF-02 (Produktentscheidung). Die Chips werden weiter nach Zeichencode sortiert
und nach Groß-/Kleinschreibung getrennt; `testAK12_…` behält sein `XCTExpectFailure`.

### BUG-10 · Gewählter Chip mit zu wenig Kontrast und ohne Auswahl-Merkmal für VoiceOver — mittel

**Betrifft:** AK-13 (FB-11, DS-01)
**Reproduktion:**
1. Liste mit zwei Gruppen öffnen, Chip „Sport“ wählen, hell und dunkel aufnehmen
2. Accessibility-Eigenschaften des gewählten Chips lesen
**Erwartet:** Schrift auf dem gewählten Chip mindestens 4,5 : 1 (15-pt-Text, WCAG AA); VoiceOver meldet „ausgewählt“
**Tatsächlich:** Akzent aus dem Code hell (239, 68, 68) → Weiß 3,76 : 1, dunkel (248, 113, 113) → 2,77 : 1; **gerendert** Fläche
(233, 105, 91) → 3,16 : 1 hell, (242, 142, 134) → 2,33 : 1 dunkel. Der gewählte Chip ist `AXButton` mit `isAccessibilitySelected = false`
und leerem Wert – die Auswahl ist nur über die Farbe erkennbar
**Ort:** `Sources/Views/ChannelListView.swift:137-157` (`GroupChip`), `Sources/Views/Theme/PlayerTheme.swift:26`
**Vorschlag:** dunklere Akzentvariante für Text auf Fläche (wie `--accent-ink` der Website) und `.accessibilityAddTraits(.isSelected)`.
**Test:** `B04ErgaenzungTests.testAK13_KontrastGewaehlterChipHellUndDunkel`, `B04GruppenTests.testAK13_…`

**Behoben 2026-09-29:** Schrift des gewählten Chips in beiden Modi im neuen Token `Color.playerOnAccent` (#120F10, das
Fast-Schwarz der Familie, wie `--on-accent` der Website im Dunkelmodus), Fläche unverändert `playerAccent`; dazu
`.accessibilityAddTraits(.isSelected)`. Aus dem Code: 5,07 : 1 hell, 6,89 : 1 dunkel (Weiß: 3,76 / 2,77). **Gerendert**
gemessen (Fensteraufnahme, Fläche/Schrift): hell (233, 105, 91) / (23, 18, 20) → **5,86 : 1**, dunkel (242, 142, 134) /
(23, 18, 20) → **7,94 : 1** (vorher 3,16 / 2,33). Der gewählte Chip meldet `isAccessibilitySelected = true`, „Alle“ nicht mehr
nach der Auswahl eines anderen Chips. Tests: `B04ErgaenzungTests.testAK13_KontrastGewaehlterChipHellUndDunkel`,
`B04GruppenTests.testAK13_…`; Aufnahmen `BUILD-AK-13-chip-hell.png`, `BUILD-AK-13-chip-dunkel.png`.

### BUG-11 · Leerzustand der Suche englisch — niedrig (wartet auf OF-03)

**Betrifft:** AK-20 (OF-03), EC-04
**Reproduktion:** Suchbegriff ohne Treffer eingeben
**Erwartet:** Produktentscheidung offen (OF-03); die übrige Oberfläche ist deutsch
**Tatsächlich:** „No Results for “zzz-kein-treffer”“ / „Check the spelling or try a new search.“
**Ort:** `Sources/Views/ChannelListView.swift:105-106` (`ContentUnavailableView.search`, Bundle ohne deutsche Lokalisierung)
**Vorschlag:** nach Entscheidung zu OF-03 eigener deutscher Leerzustand oder Lokalisierung des Bundles.
**Test:** `B04GruppenTests.testAK20_EC04_…`

**Nicht behoben (2026-09-29):** wartet auf OF-03 (Sprache der Oberfläche). `testAK20_EC04_…` behält sein
`XCTExpectFailure`.

### BUG-12 · Kein Index; der Filter umgeht den einzigen vorhandenen — niedrig

**Betrifft:** AK-32 (FB-08, DM-05)
**Reproduktion:** Datenbank mit 17.000 bzw. 2 × 17.000 Sendern; `EXPLAIN QUERY PLAN` für den Filter der App und über die Beziehung
**Erwartet:** Die als „schnell“ begründete Kopie `playlistID` nutzt einen Index
**Tatsächlich:** `SCAN t0 / USE TEMP B-TREE FOR ORDER BY`; nur `ZCHANNEL_ZPLAYLIST_INDEX` existiert, `WHERE ZPLAYLIST = ?` würde ihn nutzen.
Bei 34.000 gegenüber 17.000 Sendern gemessen noch kaum Unterschied (ohne Filter 259–264 gegenüber 259 ms, Release); die Kosten wachsen mit
jeder weiteren großen Playlist
**Ort:** `Sources/Models/Channel.swift:20-23` (Begründung), `Sources/Views/ChannelListView.swift:73, 93`
**Vorschlag:** über die Beziehung filtern oder (ab iOS 18/macOS 15) `#Index` auf `playlistID`, `name`, `group`; Kommentar korrigieren.
**Test:** `B04LeistungTests.testAK31_AK32_…`

**Behoben 2026-09-29:** Die Liste filtert über die Beziehung statt über die Kopie `playlistID`. Das Prädikat ist so
geschrieben (`$0.playlist!.persistentModelID == id`), dass Core Data `t0.ZPLAYLIST IS NOT NULL AND t0.ZPLAYLIST = ?` erzeugt
(mit `?.` entstünde `CASE … END = ?` und wieder ein `SCAN`). Belegt mit dem echten SQL (SQLDebug) und `EXPLAIN QUERY PLAN` bei
17.000 Sendern: **`SEARCH t0 USING INDEX ZCHANNEL_ZPLAYLIST_INDEX (ZPLAYLIST=?)`** für Liste, Suche und Gruppe (vorher `SCAN t0`);
die Sortierung bleibt ein temporärer B-Baum, weil `ZNAME` ohne `#Index` (erst iOS 18/macOS 15) keinen Index bekommen kann.
Deployment-Ziel unverändert. Kommentar in `Channel.swift` berichtigt. Nebenwirkung (H-3): Ein Sender mit widersprüchlicher Kopie
erscheint jetzt in der Playlist seiner Beziehung (wie beim Abspielen, `StreamURLResolver`). Tests: `B04LeistungTests.testAK31_AK32_…`,
`B04ErgaenzungTests.testAK31_AK33_…` (SQLDebug), `B04SicherheitTests.testAngriff1_…`, `B04ReparaturTests.testBUG12_…`.

### BUG-13 · Die Liste blockiert bei 17.000 Sendern die Oberfläche – „responds immediately“ ist nicht eingelöst — mittel

**Betrifft:** AK-34, EC-12 (FB-10)
**Reproduktion:**
1. Playlist mit 17.000 Sendern (300 Gruppen), Fenster 1.100 × 850 pt
2. Liste öffnen; „Fußball 12“ Zeichen für Zeichen tippen; Suchfeld leeren; „a“ tippen; Chip „DE | Sport“ wählen und abwählen; 8 Zeichen im Abstand von 100 ms tippen
3. Main-Thread mit 5-ms-Takt überwachen
**Erwartet:** Website: „Type a name, tap a group chip, and the list responds immediately“ (`web/content/features.ts:12-13`), „the list
narrows as fast as you can type“ (`web/app/page.tsx:105-110`), „Lists past 17,000 channels stay responsive“ (`web/content/faq.ts:35`)
**Tatsächlich:** längster Block der Oberfläche je Vorgang (ms):

| Vorgang | Rückerfassung (Debug) | QA Debug | **QA Release** 17.000 | **QA Release** 2 × 17.000 |
|---|---|---|---|---|
| Liste öffnen (zwei Runden) | 626 / 817 | 877 / 839 | **681 / 895** | 686 / 895 |
| Liste verlassen | 100–111 | 72 / 87 | 90 / 70 | 98 / 77 |
| erstes Zeichen „F“ / „Fu“ | 143 / – | 317 / 307 | **312 / 153** | 327 / 302 |
| weitere Zeichen bis „Fußball 12“ | 43–100 | 65–145 | 67–126 | 68–130 |
| „a“ aus leerem Feld (7.359 Treffer) | 153 | 186 | 173 | 178 |
| Suchfeld leeren (zurück auf 17.000) | 278–378 | 298–455 | **304–444** | 310–472 |
| Chip wählen (58 Treffer) / abwählen | 129 / 386 | 188 / 551 | **194 / 565** | 188 / 575 |
| 8 Zeichen à 100 ms: längster Block / Dauer | 341 / 1,95 s | 404 / 1,0 s | **427 / 1,1 s** | 423 / 1,1 s |
| Speicher mit offener Liste | 119–152 MB | 207–221 MB | 123–129 MB | 104–146 MB |

Reine Abfragen (Release, 1 kalt + 4 warm): ohne Filter 17.000 Objekte 259–263 ms, Suche „a“ 113–118 ms, „Sport“ 16 ms, 10.000 Zeichen
11 ms, Gruppe 2 ms, Chips berechnen 198–204 ms. Der Release-Build ist **nicht** schneller als Debug: die Kosten entstehen in SwiftData
(Anlegen von bis zu 17.000 Objekten je Eingabe auf dem Main-Thread), nicht im eigenen Code. Öffnen, Leeren und Abwählen liegen über der
Hang-Schwelle von 250 ms. Messung unter Last (1-Minuten-Mittel 37–77, parallele QA-Runden)
**Ort:** `Sources/Views/ChannelListView.swift:23-27, 42, 70-80, 88-97` (neue `@Query` je Änderung, ohne Entprellung, ohne Obergrenze, auf dem Main-Actor)
**Vorschlag:** Suche entprellen (~150 ms), Trefferliste begrenzen/paginieren (`fetchLimit`, `fetchBatchSize`), Gruppenliste einmal beim Import speichern; Website-Aussagen an die Messung anpassen (B10).
**Test:** `B04LeistungTests.testAK33_AK34_EC12_…` (`XCTExpectFailure`, Grenze 100 ms; Größen per `TEST_RUNNER_B04_SIZE`, `TEST_RUNNER_B04_LISTS`)

**Behoben 2026-09-29 (Listengröße); Rest: Grundlast unabhängig von der Liste.** Trefferliste und Gruppen laufen in einem
eigenen Kontext im Hintergrund (nur Listen bis 2.000 Sender laden beim ersten Öffnen sofort), die Trefferliste nur als Kennungen (17.000: 64 ms statt 237 ms als Objekte auf dem Main-Thread,
Release); jede Karte holt ihren Sender erst beim Sichtbarwerden; Suche 150 ms entprellt; bei großen Trefferlisten wird die
Kartenliste neu aufgebaut statt abgeglichen; die Chip-Leiste baut ab 41 Chips nur die sichtbaren auf. Reproduktion im Release
(`-configuration Release -derivedDataPath build/dd-release`, 17.000 Sender, 300 Gruppen, 1.100 × 850 pt, je zwei Läufe
vorher/nachher abwechselnd, Last 4–5), längste Blockade in ms:

| Vorgang | vorher | nachher | 20 Sender (vorher / nachher) |
|---|---|---|---|
| Liste öffnen (Runde 1 / 2) | 645 / 862 · 638 / 831 | **105 / 85 · 104 / 65** | 154 / 172 · 154 / 95 |
| erstes Zeichen „F“ / „Fu“ | 297 / 160 · 318 / 307 | **62 / 76 · 55 / 77** | 58 / 39 · 58 / 47 |
| weitere Zeichen bis „Fußball 12“ | 66–141 | **26–94** | 13–26 · 14–24 |
| „a“ aus leerem Feld | 157 · 189 | **55 · 55** | 76 · 55 |
| Suchfeld leeren (1 / 2) | 434 / 288 · 444 / 291 | **58 / 55 · 43 / 53** | 107 / 63 · 89 / 61 |
| Chip wählen / abwählen | 188 / 511 · 197 / 535 | **69 / 57 · 98 / 56** | 69 / 87 · 48 / 47 |
| 8 Zeichen à 100 ms (Block / Dauer) | 390 / 1,0 s · 404 / 1,0 s | **52 / 0,8 s · 51 / 0,8 s** | 65 / 0,8 s · 40 / 0,8 s |
| Speicher mit offener Liste | 122 · 116 MB | 82 · 80 MB | 66 · 64 MB |

Zeit bis zur Anzeige (nachher, 17.000): Öffnen 111–112 ms, Suche „Fußball 12“ 225–228 ms (einschließlich 150 ms Entprellen),
Suchfeld leeren 285–289 ms. Die Blockaden hängen nicht mehr von der Listengröße ab: 17.000 Sender blockieren so lange wie
20 Sender. **Nicht erreicht** sind zwei Grenzen der QA, weil schon eine Liste mit 20 Sendern – vorher wie nachher – darüber liegt:
Öffnen < 100 ms (Navigation, Suchfeld, erste Karten: 104–105 ms in Runde 1) und < 50 ms je Zeichen (Aufbau einer neuen
Bildschirmseite Karten: bis 94 ms). Der Test führt diese beiden Grenzen als nicht strikte Erwartung („BUG-13 (Rest)“) und prüft
stattdessen streng: Öffnen mit 17.000 ≤ Öffnen einer 20er-Liste im selben Lauf + 50 ms, jedes Zeichen < 150 ms (Rückfallschutz;
vorher 297–318 ms), alle übrigen Grenzen der QA (100 ms für Leeren, Chip, Abwählen, „a“, 8 Zeichen; Eingabe < 1,0 s) unverändert,
dazu Anzeige nach < 1 s. Die Website-Aussagen gehören zu B10.

**Nachtrag 2026-09-30 – Wiederholung mit dem Endstand** (nach `RequestGate`, Release-Build 30.09. 18:08, gleicher Ablauf,
Last 5–11), längste Blockade in ms; Test in allen sechs Läufen grün, beim Endstand nur die nicht strikte Erwartung „< 50 ms je Zeichen“
ausgelöst („Fußball 1“: 76 / 88 ms):

| Vorgang | vorher | nachher | 20 Sender (vorher / nachher) |
|---|---|---|---|
| Liste öffnen (Runde 1 / 2) | 641 / 831 · 639 / 870 | **67 / 66 · 65 / 60** | 129 / 162 · 100 / 124 |
| erstes Zeichen „F“ / „Fu“ | 310 / 150 · 317 / 312 | **41 / 47 · 62 / 73** | 61 / 47 · 30 / 35 |
| weitere Zeichen bis „Fußball 12“ | 67–141 | **28–88** | 15–30 · 10–28 |
| „a“ aus leerem Feld | 187 · 189 | **59 · 62** | 54 · 52 |
| Suchfeld leeren (1 / 2) | 441 / 302 · 446 / 293 | **66 / 57 · 60 / 56** | 107 / 48 · 84 / 52 |
| Chip wählen / abwählen | 180 / 539 · 187 / 527 | **72 / 34 · 71 / 56** | 71 / 107 · 31 / 72 |
| 8 Zeichen à 100 ms (Block / Dauer) | 397 / 1,0 s · 401 / 1,0 s | **53 / 0,8 s · 44 / 0,8 s** | 52 / 0,8 s · 40 / 0,8 s |
| Speicher mit offener Liste | 121 · 118 MB | 77 · 77 MB | 69 · 59 MB |

Zeit bis zur Anzeige (nachher, 17.000): Öffnen 115 / 116 ms, Suche „Fußball 12“ 234 / 215 ms, Suchfeld leeren 289 / 270 ms, Chip
64 / 71 ms, Abwählen 120 / 120 ms. Eine 20er-Liste im selben Lauf blockiert beim Öffnen 93–134 ms, also länger als die 17.000er-Liste:
kleine Listen laden beim ersten Öffnen sofort (Annahme 9 im Build-Bericht), große im Hintergrund, sodass sich die Arbeit dort auf
zwei Durchläufe verteilt. Reine Abfragen (Release): Kennungen ohne Filter 64–70 ms (als Objekte 241–248 ms), „a“ 29–31 ms
(105–108 ms), Chips berechnen 195–204 ms im Hintergrund (vorher 188–200 ms auf dem Main-Thread).

### BUG-14 · Chip-Berechnung lädt alle Sender mit allen Spalten auf dem Main-Thread — niedrig

**Betrifft:** AK-33 (FB-09, DM-07)
**Reproduktion:** Liste mit SQLDebug öffnen; SQL der Chip-Abfrage lesen; Dauer bei 17.000 Sendern messen
**Erwartet:** nur die Spalte `ZGROUP` (Absicht `propertiesToFetch = [\.group]`), deduplizierte Gruppen aus der Datenbank; FAQ „searching and
filtering happen in the database rather than in memory“ (`web/content/faq.ts:35`)
**Tatsächlich:** `SELECT … ZLOGOURL, ZNAME, ZPLAYLISTID, ZSTREAMURL, ZTVGID … FROM ZCHANNEL t0 WHERE t0.ZPLAYLISTID = ?`; 17.000 Objekte,
Deduplizieren im Speicher, 198–204 ms (Release) bei jedem Öffnen – Teil des Öffnen-Blocks aus BUG-13. Seit der B01-Reparatur tragen die
Stream-Adressen keine Zugangsdaten mehr (AK-30)
**Ort:** `Sources/Views/ChannelListView.swift:70-80`
**Vorschlag:** Gruppen beim Import/Aktualisieren an der Playlist speichern oder per `NSFetchRequest` mit `.dictionaryResultType` + `returnsDistinctResults` holen.
**Test:** `B04ErgaenzungTests.testAK31_AK33_EchtesSQLDerSenderliste` (nur mit `-com.apple.CoreData.SQLDebug 1`), `B04LeistungTests.testAK31_AK32_…` (Dauer)

**Teilweise behoben 2026-09-29.** Behoben: Die Chip-Berechnung läuft in einem eigenen Kontext im Hintergrund und blockiert den
Main-Thread nicht mehr (17.000 Sender, 300 Gruppen: 200–212 ms Rechenzeit im Hintergrund, Öffnen blockiert 65–105 ms statt
638–862 ms, siehe BUG-13); sie filtert über den Index der Beziehung. **Nicht behoben:** SwiftData liest trotz
`propertiesToFetch = [\.group]` weiter alle Spalten (belegt mit SQLDebug: `SELECT 0, t0.Z_PK, … ZSTREAMURL … FROM ZCHANNEL t0
WHERE ( t0.ZPLAYLIST IS NOT NULL AND t0.ZPLAYLIST = ?)`); nur die Spalte `ZGROUP` zu lesen ginge mit dieser SwiftData-Version
nur über eine gespeicherte Gruppenliste (Schemaänderung) → `spec.md` **OF-08**. `testAK31_AK33_EchtesSQLDerSenderliste` (nur
mit SQLDebug) behält für diesen Teil ein `XCTExpectFailure`.

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · iOS: Suchfeld beim Öffnen der Liste verborgen.** Auf iOS 27.0 und 26.5 (iPhone 17, Simulator) enthält die Senderliste beim
  Öffnen kein Suchfeld (auch nicht im Accessibility-Baum); erst Herunterziehen der Liste blendet „Sender suchen“ in der Navigationsleiste
  ein (`EC-11-ios-senderliste.png` gegen `EC-11-ios-suchfeld-nach-herunterziehen.png`). AK-01 ist damit erfüllt, die Hauptfunktion Suche
  (US-01) ist auf iOS aber schwer zu entdecken. Vermutlich Folge von `ScrollView` + `.safeAreaInset` statt `List`; Abhilfe z. B.
  `.searchable(…, placement: .navigationBarDrawer(displayMode: .always))`. Beleg: `B04iOSOberflaecheUITests` (`XCTExpectFailure` „Hinweis H-1“).
- **H-2 · Logo-Adressen im Systemprotokoll des Test-Hosts.** `com.apple.network` schreibt je Logo-Abruf die volle Adresse (`url: http://…`)
  und ATS-Warnungen mit dem Hostnamen (42–43 Zeilen je Durchgang). Am Test-Host ist die Schwärzung privater Daten aus (wie B03 H-1,
  B01 H-2); ob die regulär gestartete App schwärzt, ist hier nicht prüfbar, ohne die App zu starten (sie würde eine alte `default.store`
  des Nutzers übernehmen). Die App-eigenen Zeilen enthalten nichts.
- **H-3 · Widersprüchliche Denormalisierung wird angezeigt.** Ein Sender mit Beziehung zu Playlist A, aber `playlistID` B erscheint in der
  Liste von B; ein Sender ohne `playlistID` erscheint nirgends. Nur per Datenbank-Manipulation oder künftigem Importfehler erreichbar (DM-10).
- **H-4 · Fremde Logo-Schemata.** `file:` lädt lokale Bilddateien ohne Netz und zeigt sie an (EC-05, OF-06), `data:` wird geladen,
  `javascript:` hinterlässt einen dauerhaften Ladeindikator (BUG-04). Die Schemata werden beim Import ungeprüft gespeichert (B02 BF-68).
- **H-5 · Chip „News⏎“ sieht aus wie „News…“.** Ein Gruppenname mit Zeilenumbruch ergibt einen zweiten, abgeschnittenen Chip neben „News“
  (EC-02, `AK-11-chips.png`) – für den Nutzer zwei scheinbar gleiche Gruppen.
- **H-6 · Kein Rollbalken.** `.scrollIndicators(.hidden)` (`ChannelListView.swift:32`) – bei 17.000 Karten (Dokumenthöhe ≈ 1,5 Mio. pt) gibt
  es keinen sichtbaren Hinweis auf die Position; nicht gesondert als Bedienbarkeitstest ausgeführt.

## Code-Review

`code-review`-Skill (Code-Reviewer) über `ChannelListView.swift`, `ChannelRowView.swift`, `PlayerTheme.swift` (kein Diff gegenüber
`c01f1cf`, daher der aktuelle Stand). Funde nachgeprüft:

| Fund des Reviewers | Nachprüfung | Ergebnis |
|---|---|---|
| Chips gekürzt, Filter vergleicht ungekürzt (`:77` gegen `:95`) | ausgeführt (AK-14, AK-15) | bestätigt → BUG-01 |
| Leerzustand unterscheidet nicht, ob eine Gruppe gewählt ist (`:101-103`) | ausgeführt (AK-15, AK-17) | bestätigt → BUG-03 (Reviewer: niedrig; hier mittel, weil die Aussage über die Playlist falsch ist) |
| ⊞ öffnet das Multiview-Fenster auch, wenn `add()` still scheitert; derselbe Sender mehrfach möglich (`ChannelRowView.swift:74-76`) | im Code nachvollzogen: `MultiviewSession.add` kehrt bei Auflösungsfehler ohne Meldung zurück (`MultiviewSession.swift:57`), keine Dublettenprüfung; **nicht ausgeführt** | gehört zu B08, als Hinweis weitergegeben, nicht als BUG geführt |
| Favoriten-Umschalten verwirft Speicherfehler mit `try?` (`ChannelRowView.swift:61-62`) | im Code nachvollzogen; ein scheiterndes `save()` war schon in B03 nicht provozierbar | gehört zu B05, als Hinweis weitergegeben |
| `PlayerTheme.swift` | – | keine Funde |

## Abweichung Spec ↔ Code

Rückmeldung an die Spezifikation (gelesen gegen `c01f1cf` ohne Reparaturen); geprüft wurde der aktuelle Stand.

| Stelle | Spec sagt | Code tut (ausgeführt) |
|---|---|---|
| AK-33, FB-09, Katalog 6.1 | Chip-Berechnung lädt „Stream-Adressen mit Xtream-Zugangsdaten“ in den Speicher | seit der B01-Reparatur ohne Zugangsdaten (`…/live/102.m3u8`, AK-30); die Abfrage liest `ZSTREAMURL` weiterhin mit |
| AK-24 | Speicher fällt nach dem Verlassen auf 62 MB | 186 MB in einem Lauf, **unverändert 779 bzw. 815 MB** 8 s und 30 s nach dem Verlassen in zwei Läufen; Anstieg +616 bis +622 MB (Spec +603) |
| AK-27 | abgeleitet, nicht mit Suche ausgeführt | ausgeführt für Suche und Chip |
| AK-15, AK-16 | Anzeige bzw. Zurücksetzen „gelesen“ | ausgeführt, wie beschrieben |
| AK-01, AK-04, EC-11 | iOS gelesen, „keine iOS-Tests“ | ausgeführt (iOS 27.0, 26.5); Suchfeld erst nach Herunterziehen (H-1) |
| EC-05 | ob das `file://`-Bild angezeigt wird, nicht angesehen | wird angezeigt |
| EC-07 | nicht eindeutig | eindeutig: abgebrochene Logos werden beim Zurückscrollen neu angefragt (6 von 6), keine hängenden Ladeindikatoren |
| EC-09 | nicht ausgeführt | ausgeführt: kein Absturz, Titel/Kopfzeile/Chips der gelöschten Playlist bleiben (wie B03 BUG-05) |
| AK-13 / FB-11 | Kontrast 3,76 : 1 hell, 2,77 : 1 dunkel | aus dem Code bestätigt; gerendert noch geringer (3,16 : 1 / 2,33 : 1), weil die Chipfläche heller erscheint als der Akzentwert |
| AK-29 | `log stream` auf den Suchtext | mit `log show --info --debug` ausgeführt; zusätzlich Logo-Adressen in Netzwerk-Zeilen (H-2) |
| AK-34, FB-10 | Release nicht gemessen, „dürfte schneller sein“ | gemessen: Release gleich Debug (Tabelle BUG-13); einzelne Blöcke höher als in der Rückerfassung (Last 37–77) |
| AK-25 | Schleife 21 Anfragen in 40 ms | 21 Anfragen in 26 ms |
| AK-26 | `Mika+Player/<Build>` | `Mika+Player/3` (Build 3 seit der B09-Reparatur) |
| FB-06 Fundstelle | `Resources/Info.plist:39-40` | jetzt `Sources/Resources/Info.plist:45-48` |
| FB-08 Fundstelle | `Models/Channel.swift:19-22` | jetzt `:20-23` (Kommentarzeile der B01-Reparatur davor) |
| Kopf | Hosting-View setzt das Fenster auf 42 × 48 pt | bestätigt; Einbetten in eine Halter-View löst es (`B04Support.swift`, `B04Window`) |

## Neue Tests

Alle unter `Tests/B04/`, Testnamen mit AK-/EC-Nummer. Belege für Fehler sind mit `XCTExpectFailure("BUG-NN …")` markiert.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B04Support.swift` | — | Seed wie der Xtream-Import, Spiegel der Abfragen, SQLite-/Bytesuche, Cache-Zugriff nur auf eigene Mock-Adressen, Main-Thread-Wachhund, Fenster mit Halter-View, Accessibility, Aufnahmen und Farbmessung, Logo-Mock (`B04LogoHost`: Verzögerung, Weiterleitung, Schleife, Tröpfeln, Hängen, 12.000²-PNG, 27-MB-PNG), Nachweise nach `TEST_RUNNER_B04_QA_DIR` |
| `B04AufbauTests.swift` | 7 | AK-01–AK-05, AK-30; EC-01, EC-03, EC-10 |
| `B04SucheTests.swift` | 5 | AK-06–AK-09 |
| `B04GruppenTests.swift` | 11 | AK-10–AK-20; EC-02, EC-04, EC-08 |
| `B04LogoTests.swift` | 11 | AK-21–AK-28; EC-05–EC-07 |
| `B04LeistungTests.swift` | 2 | AK-31–AK-34, EC-12 (Größen per `TEST_RUNNER_B04_SIZE`, `…_LISTS`) |
| `B04SicherheitTests.swift` | 7 | Angriff 1, 3, 4, 5, 7, 8; AK-29; EC-09 |
| `B04ErgaenzungTests.swift` | 4 | AK-31/AK-33 echtes SQL (nur mit SQLDebug), AK-13 Kontrast hell/dunkel aus Code und Aufnahme, Angriff 4 Logo-Adressen im Protokoll, EC-11 Datenbank für den Simulator (nur mit `TEST_RUNNER_B04_IOS_STORE`) |
| `B04ErkundungTests.swift` | 1 | Accessibility-Baum und Fensteraufbau (Grundlage der Hilfen) |
| `B04iOSOberflaecheUITests.swift` | 1 | AK-01, AK-02, AK-04, AK-10, AK-13, AK-22, EC-11 auf iOS; `#if os(iOS)`, braucht ein iOS-UI-Test-Target (im Projekt nicht vorhanden; Anleitung im Dateikopf) |

**Letzter Gesamtlauf** (2026-09-26 15:57–16:07, Debug, Kopie, `build/dd`; vollständig in `qa/testlauf.txt`):

```
xcodebuild test-without-building -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' \
  -derivedDataPath build/dd -only-testing:MikaPlusPlayerTests/B04AufbauTests -only-testing:MikaPlusPlayerTests/B04ErgaenzungTests \
  -only-testing:MikaPlusPlayerTests/B04ErkundungTests -only-testing:MikaPlusPlayerTests/B04GruppenTests \
  -only-testing:MikaPlusPlayerTests/B04LeistungTests -only-testing:MikaPlusPlayerTests/B04LogoTests \
  -only-testing:MikaPlusPlayerTests/B04SicherheitTests -only-testing:MikaPlusPlayerTests/B04SucheTests
Test Suite 'B04AufbauTests' passed        Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B04ErgaenzungTests' passed    Executed 3 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B04ErkundungTests' passed     Executed 1 test, with 0 failures (0 unexpected)
Test Suite 'B04GruppenTests' passed       Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B04LeistungTests' passed      Executed 2 tests, with 0 failures (0 unexpected)
Test Suite 'B04LogoTests' passed          Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B04SicherheitTests' passed    Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B04SucheTests' passed         Executed 5 tests, with 0 failures (0 unexpected)
Executed 47 tests, with 1 test skipped and 0 failures (0 unexpected) in 608.291 (608.319) seconds
** TEST EXECUTE SUCCEEDED **
```

Zusätzlich (alle in `qa/testlauf.txt`): SQL-Test mit `-com.apple.CoreData.SQLDebug 1` → passed; Release 17.000 und 2 × 17.000
(`B04LeistungTests`) → je 2 passed; `testEC11_DatenbankFuerIOSSimulatorErzeugen` → passed (nach dem Gesamtlauf ergänzt, ohne Variable
übersprungen); iOS-UI-Test auf iOS 27.0 und 26.5 → je 1 passed. Die übrigen Test-Suites des Projekts liefen hier nicht mit (parallele
QA-Runden). Build-Warnungen aus `Tests/B04`: `CGWindowListCreateImage` veraltet, eine `Sendable`-Warnung (`NSMutableData` im Mock-Handler),
ein überflüssiges `??`.

Um den iOS-Test im Projekt zu nutzen, braucht `project.yml` ein Target `bundle.ui-testing` (`platform: iOS`, `TEST_TARGET_NAME:
MikaPlusPlayer`, Quelle nur diese Datei) und die Datenbank aus `testEC11_…` im App-Container des Simulators.

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Gruppen-Chip gekürzt, Filter vergleicht ungekürzt: Sender mit Randleerzeichen fehlen unter ihrem Chip, Gruppen nur mit Randzeichen zeigen nichts | mittel | `Views/ChannelListView.swift:77, 95` | BUG-01 |
| Chip-Leiste wird nach einem Aktualisieren nicht neu berechnet (weggefallene Gruppen bleiben, neue fehlen) | mittel | `Views/ChannelListView.swift:43` | BUG-02 |
| „Diese Playlist enthält keine Sender.“ auch bei leerem Gruppenfilter – falsche Aussage über die Playlist | mittel | `Views/ChannelListView.swift:101-104` | BUG-03 |
| Ladeindikator dreht dauerhaft ohne Logo-Adresse und bei Verbindungsfehlern (statt Platzhalter), auch auf iOS | mittel | `Views/ChannelRowView.swift:36-46` | BUG-04 |
| Keine Größen-, Abmessungs- und Zeitgrenze für Logos (12.000² px + 27 MB → +620 MB, teils nach dem Verlassen nicht freigegeben; Tröpfeln unbegrenzt) | mittel | `Views/ChannelRowView.swift:36` | BUG-05 |
| Logos gehen ungefragt an beliebige Hosts, auch per HTTP und über Weiterleitungen; IP, App-Build, OS-Version, Sprache und gefilterte Sender werden sichtbar | mittel | `Views/ChannelRowView.swift:36`, `Resources/Info.plist:45-48` | BUG-06 |
| Logo-Antworten im Plattencache, auch `no-store`/404/HTML, bleiben nach dem Löschen der Playlist (für andere Prozesse lesbar) | mittel | `Views/ChannelRowView.swift:36` (`URLCache.shared`), `Services/PlaylistImporter.swift` (`delete`) | BUG-07 |
| Zahlen in Sendernamen als Text sortiert — wartet auf OF-01 | niedrig | `Views/ChannelListView.swift:97` | BUG-08 |
| Gruppen-Chips nach Zeichencode sortiert, Groß-/Klein-Varianten getrennt — wartet auf OF-02 | niedrig | `Views/ChannelListView.swift:79` | BUG-09 |
| Gewählter Chip: Kontrast 3,16 : 1 hell / 2,33 : 1 dunkel (gerendert), kein Auswahl-Merkmal für VoiceOver | mittel | `Views/ChannelListView.swift:137-157`, `Views/Theme/PlayerTheme.swift:26` | BUG-10 |
| Leerzustand der Suche englisch — wartet auf OF-03 | niedrig | `Views/ChannelListView.swift:105-106` | BUG-11 |
| Kein Index; Filter über `playlistID` umgeht den einzigen Index | niedrig | `Models/Channel.swift:20-23`, `Views/ChannelListView.swift:73, 93` | BUG-12 |
| Bei 17.000 Sendern blockieren Öffnen (0,7–0,9 s), Leeren der Suche (0,3–0,5 s), Chip abwählen (0,6 s) und erstes Zeichen (0,3 s) die Oberfläche, auch im Release; Website verspricht „responds immediately“ | mittel | `Views/ChannelListView.swift:23-27, 42, 88-97`; `web/content/features.ts:12-13`, `web/app/page.tsx:105-110`, `web/content/faq.ts:35` | BUG-13 |
| Chip-Berechnung liest alle Spalten aller Sender (`propertiesToFetch` wirkungslos), ~200 ms je Öffnen auf dem Main-Thread | niedrig | `Views/ChannelListView.swift:70-80` | BUG-14 |

## Nächster Schritt

Höchster Grad **mittel**, Bestandsfeature: Einträge in `features/befunde.md` (Orchestrator), die Erfassung der übrigen Features läuft
weiter. Reparatur mit `/sdd-build B04`: BUG-01 bis BUG-07, BUG-10, BUG-12 bis BUG-14 (BUG-08, BUG-09, BUG-11 erst nach Entscheidung zu
OF-01, OF-02, OF-03), danach `/sdd-qa B04` Durchlauf 2. Die Website-Aussagen zu Tempo und „not in memory“ (BUG-13, BUG-14) sowie die
Logo-Empfänger (BUG-06, schon B10 BF-20) gehören in B10 Teil 2. Hinweise für andere Features: B08 (⊞ ohne Rückmeldung/Dubletten),
B05 (`try?` beim Favoriten, Stern-Label „Favourite“ englisch auf iOS), B03 (EC-09 = BF-56).
