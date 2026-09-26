# B05 · Favoriten — Testbericht

Durchlauf 1 · Stand: 2026-09-26 · Geprüft gegen `spec.md` vom 2026-09-16 (Status `rekonstruiert`, Stand `c01f1cf` + Reparatur B01)
· Geprüfter Code: **aktueller Arbeitsbaum** (`c01f1cf` + Reparatur B01 + Reparatur B09 + Reparatur B10 Teil 1, Branch `sdd/rueckerfassung`,
nicht committet)

## Fazit

**Production-ready: ja** · höchster Schweregrad: **mittel** (BUG-01 bis BUG-04, BUG-11)

Der Kern hält, was die Rekonstruktion beschreibt, und ist jetzt mit dauerhaften Tests belegt: Der Stern schaltet mit einem Klick,
speichert synchron (der Wert steht im selben Moment in der Datei und übersteht einen Neustart), öffnet keinen Player, und jede
offene Ansicht folgt ohne Neuladen — auch in einem zweiten Fenster. Der Tab zeigt die Favoriten aller Playlists in einer Liste, der
Leerzustand stimmt wörtlich, Aktualisieren erkennt Favoriten über `tvg-id` bzw. Namen wieder (M3U und Xtream), lässt bei HTTP-Fehler,
leerer Liste und fehlenden Zugangsdaten alles unverändert, berührt nie eine andere Playlist, und Löschen entfernt die Sender samt
Favoriten aus jeder Tabelle. Die Abfrage des Tabs bleibt bei 34.000 Sendern unter 4 ms. Durchgefallen sind alle acht ⚠-Kriterien
(Ist-Verhalten reproduziert und jeweils als BUG erfasst) und AK-28: In 3 von 11 Läufen blieb der Name eines gelöschten Favoriten
als Bytes in der Datenbankdatei stehen (BUG-10, wie BF-59).

Mittel sind die vier Fehlbestände der Rückerfassung, alle ausgeführt bestätigt: **BUG-01** — ein Aktualisieren einer
*unveränderten* Liste macht aus 3 Favoriten 8 (Xtream: 2 → 6), vom Nutzer entfernte Sterne kommen beim nächsten Aktualisieren
zurück; gleiche Ursache wie B03 BUG-02 (BF-53). **BUG-02** — auf einem vollen Datenträger zeigt der Stern den neuen Zustand, der Tab
nimmt die Karte auf, gespeichert ist nichts, eine Meldung gibt es nicht, nach dem Neustart ist der alte Zustand zurück. **BUG-03** —
der Tab fragt bei jedem Öffnen genau die Logos der Favoriten an (3 von 20, beim zweiten Öffnen wieder 3), jeder Logo-Host sieht damit
die Favoritenliste samt IP, App-Build und Systemsprache; das widerspricht der FAQ „Nowhere“ und der PRD-Begründung der Stufe B.
**BUG-04** — für VoiceOver ist der Favoriten-Zustand nicht wahrnehmbar (Karte vor und nach dem Umschalten identisch, Aktion englisch
„Favourite“). Neu und ebenfalls mittel ist **BUG-11**: Scheitert das abschließende Speichern eines Aktualisierens (voller
Datenträger), zeigt die Oberfläche trotzdem den neuen, ungespeicherten Stand samt neuer Favoriten und meldet nur „The operation
couldn’t be completed. (NSSQLiteErrorDomain error 13.)“; auf der Platte bleibt der alte Stand, bis irgendein späteres Speichern den
neuen mitschreibt. Niedrig: vier Produktfragen mit offener OF (BUG-05 bis BUG-08), ein NUL-Zeichen in Name oder `tvg-id` (**BUG-09**:
beim Speichern abgeschnitten, der Favorit geht bei jedem Aktualisieren verloren) und die Restbytes gelöschter Favoriten (BUG-10).

Nicht prüfbar blieb AK-06 im iOS-Teil (Tab-Wechsel im Simulator nicht automatisierbar) — alle macOS-Teile sind ausgeführt und
bestanden, zeigen aber, dass die macOS-Tab-Leiste kein Stern-Symbol darstellt (Abweichung, kein Fehler). EC-10 (iOS-Tippen) ist aus
demselben Grund nicht belegt.

Nächster Schritt: Befunde nach `features/befunde.md` übernehmen (BUG-01 mit BF-53, BUG-10 mit BF-59 zusammenführen), weiter mit
dem nächsten Feature; Reparatur von BUG-01 bis BUG-04, BUG-09 und BUG-11 in `/sdd-build B05`, BUG-05 bis BUG-08 nach Entscheidung zu
OF-01 bis OF-04. Status bleibt `review`.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 29 von 30 |
| davon bestanden | 20 |
| davon durchgefallen | 9 (die acht ⚠-Kriterien AK-05, AK-09, AK-10, AK-14, AK-15, AK-20, AK-25, AK-27 und AK-28) |
| **nicht prüfbar** | 1 (AK-06, iOS-Teil) |
| Edge Cases belegt | 10 von 11 (EC-10 nicht belegt) |
| Tests neu geschrieben | 36 in `Tests/B05/` (7 Testklassen + Hilfsdatei) |
| Tests grün | 36 von 36 · **0 Fehlschläge**; darin 14 Tests mit `XCTExpectFailure` als Belege für BUG-01 bis BUG-11 (der für BUG-10 nicht strikt, weil der Fehler nicht in jedem Lauf auftritt) |

## Prüfumgebung

| Was | Wie |
|---|---|
| Code-Stand | Arbeitsbaum 2026-09-26: `c01f1cf` + Reparaturen B01, B09, B10 Teil 1. Die B05-Dateien `FavoritesView.swift`, `ChannelRowView.swift`, `ContentView.swift` sind byte-gleich zu `c01f1cf`, `Channel.swift` hat nur eine Kommentarzeile mehr (B01), `PlaylistImporter.refresh`/`attach` unverändert gegenüber der Spec. Produktcode nicht verändert |
| Isolation | eigene Kopie im Scratchpad (`qa1-b05/`, per `rsync` ohne `build`, `dist`, `.git`, `.xcodeproj`, `web/node_modules`), `xcodegen generate`, DerivedData in der Kopie. In der Kopie **nur** für die Isolation geändert: Bundle-ID der App `lu.daumedia.MikaPlusPlayer.qa1b05`, der Tests `….qa1b05tests`; `SUFeedURL` → `http://127.0.0.1:9/appcast.xml`, `SUEnableAutomaticChecks` → aus |
| Build/Test | `xcodebuild build-for-testing` / `test-without-building -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd -only-testing:MikaPlusPlayerTests/B05…`, Debug. Nachweise mit `TEST_RUNNER_B05_EVIDENCE=1` nach `qa/`, Speicherfehler mit `TEST_RUNNER_B05_FULL_VOLUME=<Mountpoint>` |
| Rechner | Apple M3 Max, macOS 27 (Darwin 27.0.0). **Parallel liefen vier weitere QA-Durchläufe** (Last 1-min-Mittel 11–123, je Messung in `qa/AK-29-30-messung.txt`) |
| Anbieter, Logo-Hosts | `MockXtreamServer` (Tests/Support) auf 127.0.0.1 mit M3U-Routen, `player_api.php` und Logo-Pfaden; jede Anfrage roh mitgeschrieben. Erfundene Listen und Zugangsdaten (`qa-user` / `qa-pass-123`), kein echter Anbieter |
| Datenbank | je Test eine Datei in einem eigenen Temp-Ordner über den Produktionsweg `AppPersistence.diskContainer` (versioniertes Schema + Migrationsplan) oder ein In-Memory-Container. Die Datenbank des Nutzers wurde weder geöffnet noch gelesen (nur der **Pfad** wurde über `AppPersistence.storeURL` gebildet) |
| Speicherfehler | 8-MB-HFS+-Abbild `voll.dmg` in der Kopie, `hdiutil attach -nobrowse -mountpoint <kopie>/voll-mnt`; der Test füllt es mit einer Datei, danach wieder ausgehängt und gelöscht |
| Schlüsselbund | nur `XtreamCredentialStore.standard` des Test-Hosts = Dienst `lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>` (je Lauf neu), `deleteAll()` nach jedem Test |
| Oberfläche macOS | echte `ContentView`, `FavoritesView`, `ChannelListView`, `PlayerView` in Fenstern des Test-Hosts; Stern und Karte per synthetischem Mausklick, Zustand über AppKit-Accessibility, Sternfarbe über Pixelauswertung, Aufnahmen in `qa/`. Keine Tastaturereignisse |
| Oberfläche iOS | nicht ausgeführt: Ein Tab-Wechsel oder Tippen ist im Simulator dieser Umgebung nicht automatisierbar; der B06-Durchlauf belegte den einzigen gebooteten Simulator |
| Ton | keiner: Stream-Adressen auf den geschlossenen Port 9, der Player zeigt „Could not connect to the server.“ |
| SQL | `com.apple.CoreData.SQLDebug=1` nur in der Domäne der Kopie (`lu.daumedia.MikaPlusPlayer.qa1b05`) für einen Lauf, danach gelöscht (`qa/AK-10-29-sql.txt`) |
| Codequalität | `code-review`-Skill über die B05-Dateien (siehe *Code-Review*) |

## Akzeptanzkriterien im Einzelnen

Abgehakt ist nur, was ausgeführt wurde. Testnamen ohne Klasse: `B05SternTests` (S), `B05TabTests` (T),
`B05AktualisierenTests` (A), `B05LoeschenTests` (L), `B05DatenschutzTests` (D), `B05LeistungTests` (P),
`B05SicherheitTests` (X). Nachweise unter `features/B05-favoriten/qa/`.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | S `testAK01_…`: Senderliste mit 3 Karten, Stern von „Das Erste HD“/„arte“ grau, von „ZDF“ (Favorit) Akzent; im Tab ebenso Akzent; Pixel 58 pt vor dem Kartenrand (⊞) ohne Akzent; Aktionen der Karte in Leserichtung `["Rectangle Split Two By Two", "Favourite"]` (⊞ links vom Stern); einziger Hilfetext der Karte „Zu Multiview hinzufügen“ (⊞), der Stern hat keinen · `AK-01-senderliste-stern-grau-und-akzent.png`, `AK-01-favoriten-tab-stern-akzent.png`, `AK-01-05-accessibility.txt`. Nur macOS; iOS nicht ausgeführt |
| AK-02 | ✅ bestanden | S `testAK02_…`: Klick → Wert in der SQLite-Datei **direkt nach dem Ereignis** (ohne Run-Loop) `1`, `hasChanges=false`; neuer Container auf dieselbe Datei („Neustart“) liefert `[ZDF]`; zweiter Klick → sofort `0`, Neustart leer; zwei Klicks ohne Pause (zweiter mit `clickCount 2`) → Ausgangszustand, Datei `0` · `AK-02-speichern.txt`, `AK-02-nach-klick-akzent.png` |
| AK-03 | ✅ bestanden | S `testAK03_…`: Klick auf den Stern von „arte“ → Favorit, Kopfzeile „MIKA+PLAYER · 3 SENDER“ und Fenstertitel „QA Stern“ bleiben, 3 Karten. Klick auf den Namen von „Das Erste HD“ → Fenstertitel „Das Erste HD“, Player („Wiedergabe fehlgeschlagen“ / „Could not connect to the server.“), Stern unverändert · `AK-03-klick-auf-karte-player.png`. Nur macOS |
| AK-04 | ✅ bestanden | S `testAK04_EC07_…`: Liste in Fenster A, Tab in Fenster B auf demselben Container; zwei Sterne setzen und wieder entfernen → Karten erscheinen/verschwinden jeweils < 1 s ohne Neuladen, am Ende „Keine Favoriten“ · `AK-04-tab-zweites-fenster-zwei-favoriten.png` |
| AK-05 ⚠ | ❌ durchgefallen | S `testAK05_…`: Karte = **ein** Element (0 Kinder), Label „ZDF, Vollprogramm“ bzw. „arte“ ohne Gruppe, Hilfe „Zu Multiview hinzufügen“, Rolle `AXBusyIndicator` („busy indicator“, Wert 0 — Karten ohne Logo dauerhaft); Aktion „Favourite“ ausgeführt → Favorit, danach **dieselben** Werte (Label, Wert, Aktionen, `selected=false`); AX-„Drücken“ öffnet den Player; Leerzustand-Symbol „Favourite“ · `AK-01-05-accessibility.txt` → **BUG-04** |
| AK-06 | ⚠️ nicht prüfbar | **macOS ausgeführt und bestanden**, T `testAK06_…`: Fenster-Toolbar enthält `AXTabGroup „Navigation Tab Bar“` mit `Playlists` (gewählt) und `Favoriten`; nach Wahl von „Favoriten“ Fenstertitel „Favoriten“, Kopfzeile „MIKA+PLAYER · FAVORITEN“ in Akzentfarbe (379 Akzent-Pixel), darunter „Favoriten“; zurück zu „Playlists“ zeigt deren Kopfzeile · `AK-06-contentview-tab-playlists.png`, `AK-06-contentview-tab-favoriten.png`, `AK-06-tabs.txt`. **Nicht beobachtbar:** der iOS-Teil („Navigationsleiste ausgeblendet“) — Tab-Wechsel im Simulator nicht automatisierbar. Außerdem zeigt die macOS-Tab-Leiste **kein** Stern-Symbol, nur Text (siehe *Abweichung*) |
| AK-07 | ✅ bestanden | T `testAK07_…`: ohne Playlists und mit einer Playlist ohne Favoriten jeweils wörtlich `["MIKA+PLAYER · FAVORITEN", "Favoriten", "Favourite", "Keine Favoriten", "Markiere Sender mit dem Stern, um sie hier zu sammeln."]`, kein Button · `AK-07-leer-ohne-playlists.png` |
| AK-08 | ✅ bestanden | T `testAK08_…`: Favoriten aus zwei Playlists in einer Liste `["3sat", "Das Erste HD, Deutschland", "KiKA, Kinder"]`; kein Playlistname, einzige Kopfzeile ohne Anzahl, kein Such-/Filterelement; jede Karte mit ⊞ und Stern; Stern bei „KiKA“ → Karte weg, Datei `0`; Klick auf „3sat“ → Player im Stapel des Tabs (Titel „3sat“) · `AK-08-favoriten-zwei-playlists.png`, `AK-08-nach-entfernen-kika.png`, `AK-08-klick-karte-player-im-tab.png` |
| AK-09 ⚠ | ❌ durchgefallen | T `testAK09_…`: zwei identische Karten „Das Erste HD, Deutschland“, nichts nennt die Playlist; Reihenfolge `ORDER BY ZNAME, Z_PK` → A (früher importiert) oben; oberen Stern entfernen → A entmarkiert. **Jetzt ausgeführt** (Spec: abgeleitet): Nach dem Aktualisieren von A steht B oben (`Z_PK` 3 vs. 5), der obere Stern trifft dann B · `AK-09-zwei-gleichnamige-karten.png`, `AK-09-reihenfolge.txt` → **BUG-06** |
| AK-10 ⚠ | ❌ durchgefallen | T `testAK10_…`: Tab zeigt die 26 Namen exakt in der Spec-Reihenfolge (Zeichencode: „Zebra“ vor „ard alpha“, „zdf“ vor „Ärger TV“, Emoji zuletzt); SQL der `@Query`: `… WHERE t0.ZISFAVORITE = ? ORDER BY t0.ZNAME, t0.Z_PK` ohne Kollation; die Senderliste derselben Playlist sortiert `COLLATE NSCollateLocaleSensitive` anders · `AK-10-sortierung.txt`, `AK-10-29-sql.txt` → **BUG-07** |
| AK-11 | ✅ bestanden | A `testAK11_AK12_AK13_AK14_…M3U`: Schlüssel `id:<tvg-id>` exakt, sonst `name:<klein>` (12 Schlüssel protokolliert). A `testAK11_AK12_AK13_…Xtream`: `id:ZDF.de` (Groß/Klein erhalten), leere `epg_channel_id` → `name:de: sky sport 1`; nach dem Aktualisieren sind genau die Sender mit gemerktem Schlüssel Favorit · `AK-11-14-m3u.txt`, `AK-11-13-xtream.txt` |
| AK-12 | ✅ bestanden | ebenda: umgekehrte Reihenfolge und neue Stream-Adressen → dieselben 12 Favoriten, 0 alte IDs; „Beta“ → „Beta HD“ (gleiche `tvg-id`) bleibt; Xtream mit neuen `stream_id`s (101–107) und „DE: ARD HD“ → „Das Erste HD“ (gleiche `epg_channel_id`) bleibt |
| AK-13 | ✅ bestanden | ebenda: bleibt bei „Sport1“→„SPORT1“, „München TV“→„MÜNCHEN TV“, „Café“ zusammengesetzt → zerlegt, M3U „  Rand TV  “ (getrimmt), Xtream „Sport Extra“→„SPORT EXTRA“; verloren bei „Straße TV“→„STRASSE TV“, „İstanbul TV“→„ISTANBUL TV“, „Kanal  Zwei“→„Kanal Zwei“, „DE: Sky Sport 1“→„DE \| Sky Sport 1“ und bei Xtream „ Rand TV“→„Rand TV“ (**jetzt ausgeführt**, Spec: gelesen) |
| AK-14 ⚠ | ❌ durchgefallen | ebenda: verloren bei `tvg-id` „ard.de“→„ARD.de“, Xtream „kika.de“→„KiKA.de“, `tvg-id` neu („Tagesschau24“) bzw. entfernt („Phoenix“), Wegfall („KiKA“); „KiKA“ kommt zurück → kein Favorit; Liste ohne passenden Sender → 0 Favoriten, **kein Fehler** · `AK-11-14-m3u.txt` → **BUG-05** |
| AK-15 ⚠ | ❌ durchgefallen | A `testAK15_EC01_EC03_…M3U`: 3 Favoriten („ZDF HD“, erste „News“, „Leer-ID A“ mit `tvg-id=" "`) → nach Aktualisieren der **unveränderten** Liste 8; Nutzer entfernt die 5 zusätzlichen → nächstes Aktualisieren wieder 8; nur „ZDF SD“ markiert → danach alle drei ZDF. A `testAK15_EC02_…Xtream`: 2 → 6 (drei ZDF-Varianten mit gleicher `epg_channel_id`, drei namenlose Sender) · `AK-15-dubletten.txt`, `EC-01-…png`, `EC-02-…png` → **BUG-01** |
| AK-16 | ✅ bestanden | A `testAK16_EC11_…`: B aktualisiert → A behält seinen Favoriten (dasselbe Objekt), B bekommt keinen; umgekehrt behält B „ZDF“, A bekommt keinen für „ZDF“ · `AK-16-ec11.txt` |
| AK-17 | ✅ bestanden | A `testAK17_EC05_…`: HTTP 500/404 → „Netzwerkfehler: HTTP 500/404“, `#EXTM3U` allein und HTML → „Die Playlist enthält keine gültigen Sender.“, Xtream leer → dieselbe Meldung, Xtream ohne Schlüsselbund-Eintrag → „Die Zugangsdaten dieser Xtream-Playlist fehlen …“; jeweils dieselben Senderobjekte, dieselben Favoriten, Datei 2 Favoriten · `AK-17-fehlschlag.txt`. Außerhalb der aufgezählten Fälle, als Randfall ausgeführt: scheitert das **Speichern** (voller Datenträger), bleibt die Oberfläche nicht unverändert → **BUG-11** (`AK-17-randfall-speicherfehler.txt`) |
| AK-18 | ✅ bestanden | A `testAK18_…`: Datei-Playlist `isRemote=false`; Datei geändert, `refresh` → dieselben IDs, 0 Anfragen, Favorit bleibt, bis er entfernt wird (Menü ohne „Aktualisieren“: B03 AK-06) · `AK-18-datei.txt` |
| AK-19 | ✅ bestanden | A `testAK19_…`: Tab offen → nach dem Aktualisieren ohne Neuladen `["ZDF HD, …", "ZDF SD, …", "arte, Kultur"]` (einschließlich AK-15); zweites Fenster mit aus dem Tab geöffnetem Player („arte“) bleibt offen, kein Absturz · `AK-19-*.png` |
| AK-20 ⚠ | ❌ durchgefallen | L `testAK20_Angriff8_…`: Tab zeigt 3 Karten, Playlist A gelöscht (wie `PlaylistsView.delete`) → < 1 s nur „Neutral B“, **kein** Alert; erneuter Import derselben Quelle → 0 Favoriten · `AK-20-favoriten-vor-/nach-loeschen.png`, `AK-20-loeschen.txt` → **BUG-08** |
| AK-21 | ✅ bestanden | T `testAK21_…`: 62 Hauptmenü-Einträge (ohne Fensterliste) ohne „Favorit“, „Export“, „Sicher…“; Tab ohne Buttons außer den Karten · `AK-21-menue.txt`, `AK-21-favoriten-tab-ohne-sammelbefehl.png` (Produktfrage OF-05, kein Fehler) |
| AK-22 | ✅ bestanden | D `testAK22_AK23_AK24_…`: Pfad über `AppPersistence.storeURL` = `~/Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store`; Anlage über `prepareStore` im Probeordner → Store/-wal/-shm `644`, Ordner `755`, `~/Library` `700`; Marker nicht in den Einstellungen; Build ohne iCloud-/CloudKit-Berechtigung (`qa/Angriff-6-geheimnisse.txt`); Umschalten erzeugt 0 Netzanfragen (X `testAngriff3_…`). iOS nicht ausgeführt |
| AK-23 | ✅ bestanden | ebenda: `isExcludedFromBackup=false` für Store, -wal, -shm und Ordner |
| AK-24 | ✅ bestanden | ebenda: ein separater Prozess `/usr/bin/sqlite3 -readonly` liest „B05ORT Favorit“ (Status 0); `~/Library` `700` gegen andere Benutzer · `AK-22-24-speicherort.txt` |
| AK-25 ⚠ | ❌ durchgefallen | D `testAK25_Angriff5_…`: 20 Sender mit Logos, 3 Favoriten → beim Öffnen **genau 3** Anfragen `/logos/sender-3.png`, `-11`, `-17`; tatsächlicher Payload `GET /logos/sender-3.png HTTP/1.1`, `accept-language: de-DE,de;q=0.9`, `user-agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`, kein Cookie, kein Referer; erneutes Öffnen → wieder dieselben 3; zum Vergleich die Senderliste: 20 Anfragen · `AK-25-logo-anfragen.txt`, `AK-25-favoriten-mit-logos.png` → **BUG-03** |
| AK-26 | ✅ bestanden | D `testAK26_Angriff4_…`: 6 Klicks bei offenem Tab, Aktualisieren, Löschen; `OSLogStore` des Prozesses 6.518 Einträge, 0 Treffer für Sendername, Playlistname, `tvg-id`, Gruppe (8 Treffer „Favorit“ sind AppKit-Gestenzeilen mit dem Typnamen `FavoritesView`). `log show --predicate 'processID == 86054'`: 9.991 Zeilen, 0 Marker-Treffer · `AK-26-protokoll.txt`, `AK-26-log-show.txt`; siehe Hinweis H-2 |
| AK-27 ⚠ | ❌ durchgefallen | D `testAK27_…` auf vollem 8-MB-Abbild (0 Byte frei): Klick → `isFavorite=true`, `hasChanges=true`, Datei `0`, Stern Akzent, Tab zeigt „Voll Zwei“, **keine** Meldung; `save()` wirft `NSSQLiteErrorDomain 13`; Neustart → `[]`; nach 3 s voll und 3 s nach Freigabe weiter Datei `0`; nächster Stern mit Platz schreibt beide; Entfernen im Tab bei vollem Datenträger → Karte weg, Neustart bringt sie zurück; Systemprotokoll: 33 Zeilen `com.apple.coredata` „database or disk is full“ · `AK-27-speicherfehler.txt`, `AK-27-speicher-voll-*.png` → **BUG-02** |
| AK-28 | ❌ durchgefallen | L `testAK28_…`: 300 Sender, 2 markierte Marker-Favoriten („B05REST Glaube TV“/Religion, „B05REST Partei TV“/Politik), gelöscht → bei offener Datenbank 4–5 Vorkommen im `-wal`, 0 im Store (wie beschrieben); nach Freigabe des Containers und „Neustart“ meist 0/0/0 — aber in **3 von 11 Läufen** steht danach ein Name in der Hauptdatei (`store=1`, `-wal` leer, 0 Zeilen in `ZCHANNEL`), nach Prozessende per `grep -a` bestätigt: „B05REST Partei TV“ bzw. „B05REST Glaube TV“ (`secure_delete=2`, `freelist_count=6`) · `AK-28-restbytes.txt`, `AK-28-wiederholung.txt` → **BUG-10** |
| AK-29 | ✅ bestanden | P `testAK29_AK30_…`: 17.000/50 → laden kalt 2,1 ms, warm 1,0–1,1 ms, zählen 0,4 ms; 34.000/100 → 3,8 / 2,1–2,2 / 0,9 ms; Tab öffnen längste Blockade 51 ms; Stern im Tab 32 ms / 34 ms; Stern in der Liste (17.000) mit Tab 272–280 ms / 289–564 ms, ohne Tab 289–293 ms / 290–293 ms (die Blockade stammt von der Senderliste, B04); `EXPLAIN QUERY PLAN`: `SCAN t0`, `USE TEMP B-TREE FOR ORDER BY`, einziger Index `ZCHANNEL_ZPLAYLIST_INDEX` · `AK-29-30-messung.txt` (Debug, Last 1-min-Mittel 111–123) |
| AK-30 | ✅ bestanden | ebenda: derselbe Ausdruck wie `PlaylistImporter.swift:253` auf frischem Container: 17.000 Sender kalt 1.161 ms (Main-Thread-Blockade 1.161 ms), warm 11 ms; bei 34.000 Sendern in der Datenbank 1.129 ms. Gemessen wurde nur dieser Schritt (das ganze Aktualisieren: B03 BUG-01/BF-52) |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | T `testEC01_…`: zwei „Kanal X“ ohne `tvg-id`, einer markiert → 1 Karte; nach unverändertem Aktualisieren 2 gleiche Karten (`EC-01-vor-…`, `EC-01-nach-aktualisieren-zwei-karten.png`) — BUG-01 |
| EC-02 | ✅ belegt | A `testAK15_EC02_…`: `name` leer, fehlend und `null` → drei Sender mit leerem Namen, alle Schlüssel `name:`; einer markiert → nach dem Aktualisieren alle drei. Die Karte zeigt nur das Gruppen-Badge, VoiceOver-Label nur „Sport“ (`EC-02-*.png`) |
| EC-03 | ✅ belegt | A `testAK15_EC01_EC03_…`: `tvg-id=" "` gilt als vorhanden, „Leer-ID A“ markiert → „Leer-ID B“ nach dem Aktualisieren ebenfalls |
| EC-04 | ✅ belegt | A `testEC04_…` (Spec: gelesen): Anbieter antwortet nach 3 s; Klick auf den Stern von „Beta“ nach 1 s → Datei sofort `1`; nach Ende des Aktualisierens `["Alpha", "Beta"]` Favorit, Stern Akzent (`EC-04.txt`) |
| EC-05 | ✅ belegt | A `testAK17_EC05_…`: Schlüsselbund-Eintrag entfernt → Meldung wörtlich; dem Rat gefolgt (löschen, neu importieren) → 0 Favoriten (vgl. B03 BUG-12/BF-63) |
| EC-06 | ✅ belegt | D `testEC06_…`: alte `default.store` mit 2 Favoriten im Probeordner → `prepareStore` = `adopted`, alte Datei entfernt, Favoriten erhalten. Zusätzlich in der Kopie ausgeführt: `B01ReparaturTests.testBUG01_MigrationVorhandenerDatenbankOhneDatenverlust`, `…testBUG01_AktualisierenLiestSchluesselbundUndBehaeltFavoriten`, `B09PersistenzTests.testBUG13_DatenbankAusV11OeffnetUnveraendert` → 3 von 3 grün |
| EC-07 | ✅ belegt | S `testAK04_EC07_…` (zwei Fenster, ein Container) |
| EC-08 | ✅ belegt | S `testEC08_…` (Spec: gelesen): Stern im Tab entfernt → Stern in der offenen Senderliste grau ohne Neuladen (`EC-08-liste-nach-entfernen-im-tab.png`) |
| EC-09 | ✅ belegt | P `testEC09_…` (Spec: nicht gemessen): 17.000 Sender, **5.667 Favoriten** → laden kalt 67,1 ms, Tab öffnen längste Blockade 111 ms, Stern im Tab 99 ms / Blockade 169 ms |
| EC-10 | ⚠️ nicht belegt | iOS: Tippen im Simulator nicht automatisierbar |
| EC-11 | ✅ belegt | A `testAK16_EC11_…`: zweiter Import derselben Quelle → 0 Favoriten, die der ersten Playlist bleiben |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf eine lokale App ohne
Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Fremde IDs in Predicates (IDOR) | bestanden, Hinweis H-1 | Kein Server, keine per ID abrufbare Ressource. X `testAngriff1_…`: Aktualisieren einer Playlist ändert nie Favoriten einer anderen (auch AK-16); ein Sender mit fremder `playlistID` (zeigt auf B), aber ohne Beziehung, wird beim Aktualisieren von B weder gelöscht noch umgeschaltet. Der Tab filtert nur `isFavorite`: zwei künstlich verwaiste Favoriten (`ZPLAYLIST = NULL`) bleiben nach dem Löschen **aller** Playlists im Tab, nur per Stern entfernbar (`Angriff-1-verwaiste-favoriten.png`) — erreichbar nur über eine manipulierte oder beschädigte Datenbank |
| 2 · Zugriffsregeln (Betriebssystem) | bestanden (bekannte Entscheidung) | Store/-wal/-shm `644`, Ordner `755`, `~/Library` `700`; ein fremder Prozess desselben Benutzers liest die Favoriten (AK-24) — Sandbox bewusst aus (Decision Log Nr. 12) |
| 3 · Wiederholversuche | bestanden | X `testAngriff3_…`: 40 Klicks ohne Pause in 223 ms (5,6 ms je Klick), Dateiwert nach **jedem** Klick abwechselnd 1/0, Endzustand konsistent (`isFavorite=false`, Datei `0`, Tab leer, `hasChanges=false`), 0 Netzanfragen. Ein Limit ist für eine lokale Markierung nicht nötig |
| 4 · PII in Protokollen | bestanden, Hinweis H-2 | App-Code protokolliert keine Sender (AK-26: 0 Treffer in `OSLogStore` und `log show`). Aber: das Network-Framework schreibt die Logo-Adressen der Favoriten auf Ebene `Default` (`url: http://127.0.0.1:…/logos/sender-3.png`, 78 Zeilen) — am Test-Host ist die Schwärzung privater Daten aus |
| 5 · PII an externe Dienste | **BUG-03** | tatsächlicher Payload am Mock (AK-25): genau die Logo-Adressen der Favoriten, `user-agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`, `accept-language: de-DE,de;q=0.9`, IP; kein Cookie, kein Referer. Zusage der FAQ („Nowhere“) und der PRD-Begründung („verlassen das Gerät nie“) nicht eingehalten |
| 6 · Geheimnisse | bestanden | `git log -p --all` (19 Commits) über `FavoritesView`, `ChannelRowView`, `ContentView`, `Channel`: 0 hinzugefügte Zeilen mit Passwort/Token/Secret/URL/IP; `strings` über alle Binärdateien des gebauten Bundles: 0 Treffer für `password=`, `token=`, `sk_live`, `service_role`, `qa-pass`; Berechtigungen ohne iCloud/CloudKit · `Angriff-6-geheimnisse.txt` |
| 7 · Eingaben | **BUG-09** | X `testAngriff7_…`: Namen/`tvg-id` „A“, 10.008 Zeichen, Emoji, `'; DROP TABLE ZCHANNEL; --`, `<script>alert(1)</script>`, `../../etc/passwd`, U+202E, Tabulator, Komma mit Anführungszeichen → Import, Stern, Aktualisieren ohne Absturz, Tabelle intakt, alle Karten 76 pt hoch (einzeilig), Stern auf der langen Karte speichert. **Ausnahme:** `Null\u{0000}Byte` — die Datei speichert nur „Null“/„tvg-Null“, der Favorit geht beim Aktualisieren verloren (10 → 9); X `testAngriff7_NulZeichen…`: Parser 9 Zeichen, im Speicher `id:tvg-Null\0Byte`, nach Neustart `id:tvg-Null` |
| 8 · Löschen | teils bestanden, **BUG-10** | L `testAK20_Angriff8_…`: nach dem Löschen `ZPLAYLIST` 1, `ZCHANNEL` 1, Zeilen der gelöschten Playlist 0, Zeilen ohne Playlist 0, Marker 0, `ZISFAVORITE=1` 1 — jede Tabelle sauber. Bytesuche (AK-28): `-wal` nach dem Beenden immer leer, in 3 von 11 Läufen aber ein gelöschter Favoriten-Name in der Hauptdatei. Was darüber hinaus bleibt (HTTP-Cache, Backups, beiseitegelegte Datenbank) ist in B03 erfasst (BF-57, BF-58) |

## Fehler

### BUG-01 · Aktualisieren vervielfacht Favoriten und macht Entfernen rückgängig — mittel

**Betrifft:** AK-15 (FB-01); EC-01, EC-02, EC-03; gleiche Ursache wie B03 BUG-02 (**BF-53**)
**Reproduktion:**
1. M3U mit „ZDF HD“/„ZDF SD“/„ZDF FHD“ (`tvg-id="zdf.de"`), „News“/„News“/„NEWS“ (ohne `tvg-id`), „Leer-ID A“/„Leer-ID B“
   (`tvg-id=" "`) importieren
2. „ZDF HD“, die erste „News“ und „Leer-ID A“ markieren (3 Favoriten)
3. Aktualisieren, die Quelle liefert **dieselbe** Liste; danach die 5 zusätzlichen Sterne entfernen und erneut aktualisieren
**Erwartet:** Dieselben 3 Favoriten wie vorher; ein entfernter Stern bleibt entfernt (Code-Kommentar: „Schlüssel, über den **ein**
Channel beim Refresh wiedererkannt wird“; Website: „does not wipe your selection“)
**Tatsächlich:** 3 → 8 Favoriten, nach dem Entfernen 3 → wieder 8; wer nur „ZDF SD“ markiert, hat danach alle drei ZDF-Varianten.
Xtream: „DE: ZDF HD“ + ein namenloser Sender → 6 (drei Varianten mit gleicher `epg_channel_id`, drei namenlose Sender mit Schlüssel
`name:`). Im Tab sichtbar als zusätzliche, gleich aussehende Karten.
**Ort:** `Sources/Models/Channel.swift:49-52` (Schlüssel nicht eindeutig: `tvg-id` ohne Prüfung auf Leerzeichen, sonst Name klein,
auch leer), `Sources/Services/PlaylistImporter.swift:253` (merkt nur die **Menge** der Schlüssel), `:299` (markiert jeden neuen
Sender mit passendem Schlüssel)
**Vorschlag:** Wiedererkennung zuerst über einen eindeutigen Schlüssel (Stream-Adresse bzw. `stream_id`), ersatzweise
`tvg-id`/Name, und je Schlüssel höchstens so viele Favoriten wie vorher; gemeinsam mit B03 BUG-02 reparieren.
**Test:** `B05AktualisierenTests.testAK15_EC01_EC03_…M3U`, `testAK15_EC02_…Xtream`, `B05TabTests.testEC01_…`

**Warum mittel, nicht hoch:** Kein markierter Sender geht verloren und der Tab bleibt benutzbar; falsch sind die zusätzlichen
Favoriten. Gleicher Grad wie BF-53 für dieselbe Ursache.

### BUG-02 · Speicherfehler beim Umschalten wird verschluckt — mittel

**Betrifft:** AK-27 (FB-02)
**Reproduktion:**
1. Datenbank auf einem Datenträger ohne freien Platz (Test: 8-MB-Abbild, vollgeschrieben); Senderliste und Tab offen
2. Stern von „Voll Zwei“ anklicken
3. App neu starten (neuer Container auf dieselbe Datei)
**Erwartet:** Entweder gespeichert oder der Stern springt zurück und eine Meldung sagt, dass nicht gespeichert wurde
(`docs/datenmodell.md`: `isFavorite` „sofort gespeichert“)
**Tatsächlich:** Stern gefüllt, Tab zeigt die Karte, Datei `0`, `hasChanges=true`, kein Alert; `save()` wirft `NSSQLiteErrorDomain 13`,
`try?` verwirft es. Nach dem Neustart kein Favorit. Auch 3 s nach dem Freigeben von Platz holt das automatische Speichern nichts nach;
erst der nächste Stern schreibt beide. Umgekehrt verschwindet eine im Tab entfernte Karte und kommt nach dem Neustart zurück.
Der Fehler steht nur im Systemprotokoll (33 Zeilen `com.apple.coredata`).
**Ort:** `Sources/Views/ChannelRowView.swift:60-62` (`channel.isFavorite.toggle()`; `try? modelContext.save()`)
**Vorschlag:** Fehler abfangen, Änderung zurücknehmen (`isFavorite` zurücksetzen bzw. `rollback()`) und eine Meldung zeigen.
**Test:** `B05DatenschutzTests.testAK27_SpeicherfehlerBeimUmschaltenWirdVerschluckt` (braucht `TEST_RUNNER_B05_FULL_VOLUME`)

### BUG-03 · Der Favoriten-Tab verrät die Favoritenliste an Logo-Hosts — mittel

**Betrifft:** AK-25 (FB-03); Angriff 5; Katalog 1.2, 2.2
**Reproduktion:**
1. Playlist mit 20 Sendern, Logos auf einem Host, 3 davon Favorit (einer in der Gruppe „Religion“)
2. Favoriten-Tab öffnen, schließen, erneut öffnen; Anfragen am Logo-Host mitschreiben
**Erwartet:** Die Favoritenliste verlässt das Gerät nicht (PRD, Begründung Stufe B: „verlassen das Gerät aber nie“; FAQ: „Where
does my data go? Nowhere.“) — oder der Nutzer kann das Laden der Logos im Tab abschalten
**Tatsächlich:** Bei **jedem** Öffnen genau 3 Anfragen, genau die Logos der Favoriten, mit IP, `user-agent: Mika+Player/3
CFNetwork/3896.100.1.1.1 Darwin/27.0.0` und `accept-language: de-DE,de;q=0.9`. Ein Host, der die Logos einer Playlist ausliefert,
kann daraus das Nutzungsprofil ablesen, bei Religion, Politik oder Erwachsenenkanälen auch besondere Kategorien.
**Ort:** `Sources/Views/FavoritesView.swift:8-12, 22-28` (genau die Favoriten als Karten), `Sources/Views/ChannelRowView.swift:36`
(`AsyncImage` lädt beim Sichtbarwerden), `Sources/Resources/Info.plist:47-48` (HTTP erlaubt)
**Vorschlag:** Logos im Tab aus einem lokalen Zwischenspeicher zeigen (beim Anzeigen in der Senderliste abgelegt) oder eine
Einstellung „Logos laden“; Datenschutzseite und FAQ an das Verhalten angleichen (BF-20).
**Test:** `B05DatenschutzTests.testAK25_Angriff5_TabFragtGenauDieLogosDerFavoritenAn`

### BUG-04 · Favoriten-Zustand für VoiceOver nicht wahrnehmbar — mittel

**Betrifft:** AK-05 (FB-04); Sprache der Aktion wartet auf OF-06
**Reproduktion:**
1. Senderliste mit „ZDF“ (Gruppe „Vollprogramm“) öffnen, Accessibility der Karte lesen
2. Aktion „Favourite“ ausführen (VoiceOver-Aktionen-Menü), Accessibility erneut lesen
**Erwartet:** VoiceOver sagt, ob der Sender Favorit ist (Wert, Zustand oder unterschiedlich benannte Aktion), deutsch wie die App
**Tatsächlich:** Vor und nach dem Umschalten identisch: Rolle `AXBusyIndicator` („busy indicator“, Wert 0), Label „ZDF,
Vollprogramm“, Aktionen „Rectangle Split Two By Two“, „Favourite“; der Stern ist kein eigenes Element. Das Symbol des Leerzustands
heißt ebenfalls „Favourite“. Ohne Logo bleibt die Karte dauerhaft „busy indicator“ (H-3).
**Ort:** `Sources/Views/ChannelRowView.swift:59-69` (kein `accessibilityLabel`/`Value`), `Sources/Views/FavoritesView.swift:24-27`,
`Sources/Views/ChannelListView.swift:111-114` (Karte als `NavigationLink`)
**Vorschlag:** `.accessibilityAction(named: "Favorit hinzufügen" / "Favorit entfernen")` und `.accessibilityValue("Favorit")` an der
Karte bzw. `accessibilityLabel` + `.isSelected` am Stern; Symbol des Leerzustands `accessibilityHidden`.
**Test:** `B05SternTests.testAK05_VoiceOverKarteEinElementSternNurAlsAktionOhneZustand`

### BUG-05 · Favorit geht beim Aktualisieren ohne Hinweis verloren und kommt nicht zurück — niedrig (wartet auf OF-03)

**Betrifft:** AK-14; Grenzen aus AK-13
**Reproduktion:**
1. M3U mit „ARD“ (`tvg-id="ard.de"`), „Tagesschau24“ (ohne), „Phoenix“ (`phoenix.de`), „KiKA“ (`kika.de`), alle markiert
2. Aktualisieren: `tvg-id` „ARD.de“, „Tagesschau24“ mit neuer `tvg-id`, „Phoenix“ ohne, „KiKA“ fehlt
3. Erneut aktualisieren, „KiKA“ ist zurück; dann eine Liste ohne passenden Sender
**Erwartet:** Produktentscheidung offen (OF-03): Hinweis auf verlorene Favoriten oder Merken bis zur Rückkehr
**Tatsächlich:** Alle vier verloren, keine Meldung; „KiKA“ kommt ohne Stern zurück; ohne passenden Sender 0 Favoriten und das
Aktualisieren gilt als Erfolg. Ebenso bei „ß“→„SS“, „İ“→„I“, doppeltem Leerzeichen, Xtream-Leerzeichen am Rand.
**Ort:** `Sources/Services/PlaylistImporter.swift:253-262`, `Sources/Models/Channel.swift:49-52`
**Vorschlag:** Nach Entscheidung zu OF-03.
**Test:** `B05AktualisierenTests.testAK11_AK12_AK13_AK14_SchluesselUndVerlustM3U`

### BUG-06 · Gleichnamige Favoriten verschiedener Playlists nicht unterscheidbar — niedrig (wartet auf OF-02)

**Betrifft:** AK-09
**Reproduktion:**
1. „Das Erste HD“ (Gruppe „Deutschland“) aus Playlist A und B markieren
2. Tab öffnen, den oberen Stern entfernen; beide wieder markieren, A aktualisieren, erneut den oberen Stern entfernen
**Erwartet:** Produktentscheidung offen (OF-02): Playlist an der Karte oder Gruppierung
**Tatsächlich:** zwei identische Karten; oben steht zuerst A (niedrigerer `Z_PK`), nach dem Aktualisieren von A steht B oben — derselbe
Klick trifft einmal A, einmal B
**Ort:** `Sources/Views/FavoritesView.swift:8-12, 22-28`
**Vorschlag:** Nach Entscheidung zu OF-02.
**Test:** `B05TabTests.testAK09_GleichnamigeFavoritenNichtUnterscheidbarReihenfolgeDerAnlage`

### BUG-07 · Tab sortiert nach Zeichencode statt wie die Senderliste — niedrig (wartet auf OF-01)

**Betrifft:** AK-10
**Reproduktion:** 26 Favoriten (u. a. „Zebra“, „ard alpha“, „zdf“, „Ärger TV“, „Sport 2“, „Sport 10“) im Tab und in der Senderliste
vergleichen
**Erwartet:** Produktentscheidung offen (OF-01): sprachgerecht wie die Senderliste (B04)
**Tatsächlich:** Tab: „Zebra“ vor „ard alpha“, „zdf“ vor „Ärger TV“, Emoji zuletzt (`ORDER BY t0.ZNAME, t0.Z_PK` ohne Kollation);
Senderliste: `COLLATE NSCollateLocaleSensitive`
**Ort:** `Sources/Views/FavoritesView.swift:10` (`sort: \Channel.name`)
**Vorschlag:** Nach Entscheidung zu OF-01, z. B. `sort: [SortDescriptor(\.name, comparator: .localized)]` wie die Senderliste.
**Test:** `B05TabTests.testAK10_SortierungNachZeichencode`

### BUG-08 · Löschen einer Playlist nimmt ihre Favoriten ohne Hinweis mit — niedrig (wartet auf OF-04)

**Betrifft:** AK-20; Rückfrage vor dem Löschen allgemein: B03 BUG-10 (BF-61)
**Reproduktion:**
1. Playlist A mit zwei Favoriten, Playlist B mit einem; Tab offen
2. A löschen; dieselbe Quelle neu importieren
**Erwartet:** Produktentscheidung offen (OF-04): Hinweis auf die Zahl verlorener Favoriten oder Erhalt über einen Neuimport
**Tatsächlich:** Karten von A sofort weg, kein Alert; nach dem Neuimport 0 Favoriten
**Ort:** `Sources/Views/PlaylistsView.swift:104-107`, `Sources/Services/PlaylistImporter.swift:270-278`
**Vorschlag:** Nach Entscheidung zu OF-04.
**Test:** `B05LoeschenTests.testAK20_Angriff8_LoeschenNimmtFavoritenOhneHinweisMit`

### BUG-09 · NUL-Zeichen in Name oder tvg-id: Favorit geht bei jedem Aktualisieren verloren — niedrig

**Betrifft:** Angriff 7, AK-11 (neu, nicht in der Spec)
**Reproduktion:**
1. M3U mit `#EXTINF:-1 tvg-id="tvg-Null<NUL>Byte",Null<NUL>Byte` (U+0000 im Wert) importieren, Sender markieren
2. Dieselbe Liste aktualisieren
**Erwartet:** Der Favorit bleibt (unveränderte Liste); Steuerzeichen werden beim Import entfernt oder abgewiesen
**Tatsächlich:** Der Parser behält das Zeichen (9 bzw. 13 Zeichen), die SQLite-Datei speichert nur bis zum NUL („Null“, „tvg-Null“).
Nach dem Laden ist der Schlüssel `id:tvg-Null`, der neu geparste `id:tvg-Null\0Byte` → der Favorit geht verloren (10 → 9), bei jedem
Aktualisieren wieder. Der gespeicherte Name weicht außerdem vom angezeigten ab.
**Ort:** `Sources/Services/M3UParser.swift:83, 113` (keine Bereinigung von Steuerzeichen), `Sources/Models/Channel.swift:49-52`;
Kürzung durch den SQLite-Speicher von SwiftData
**Vorschlag:** Steuerzeichen (mindestens U+0000) beim Import von Name, `tvg-id` und Gruppe entfernen (M3U und Xtream, B02/B01).
**Test:** `B05SicherheitTests.testAngriff7_UngewoehnlicheNamenUndTvgIDs`, `testAngriff7_NulZeichenWirdBeimSpeichernGekuerzt`

### BUG-10 · Namen gelöschter Favoriten bleiben teils als Bytes in der Datenbankdatei — niedrig

**Betrifft:** AK-28; Angriff 8; Bestätigung von B03 BUG-07 (**BF-59**) für Favoriten
**Reproduktion:**
1. M3U mit 300 Sendern, darunter „B05REST Glaube TV“ (Gruppe „Religion“) und „B05REST Partei TV“ („Politik“), beide markieren
2. Playlist löschen, Container freigeben, Datei neu öffnen und schließen („Neustart“), Prozess beenden
3. `grep -a -c B05REST MikaPlusPlayer.store*`
**Erwartet:** 0 Vorkommen nach dem Beenden (so beschreibt es AK-28)
**Tatsächlich:** meist 0, in **3 von 11 Läufen** 1 Vorkommen in der Hauptdatei (einmal „B05REST Partei TV“, einmal „B05REST Glaube TV“),
`-wal` leer, 0 Zeilen in `ZCHANNEL`. Für Favoriten wiegt das schwerer als für beliebige Sender: gerade die Namen, die besondere
Kategorien berühren, überleben das Löschen (Katalog 1.2, 5.2).
**Ort:** `Sources/Services/PlaylistImporter.swift:270-278` (kein Verdichten nach dem Löschen); SQLite `secure_delete = FAST`
**Vorschlag:** wie BF-59 — nach dem Löschen einer Playlist `PRAGMA secure_delete = ON` bzw. `VACUUM` + `wal_checkpoint(TRUNCATE)`.
**Test:** `B05LoeschenTests.testAK28_NamenGeloeschterFavoritenInDatenbankdateien` (`XCTExpectFailure`, nicht strikt)

### BUG-11 · Scheitert das Speichern beim Aktualisieren, zeigt die App trotzdem den neuen Stand — mittel

**Betrifft:** Randfall zu AK-17 (dort nur HTTP-Fehler, leere Liste, fehlende Zugangsdaten aufgezählt); verwandt mit B03 EC-03 (dort
nicht provozierbar) und BUG-02
**Reproduktion:**
1. Datenbank auf einem Datenträger, M3U mit „ZDF HD“/„ZDF SD“ (gleiche `tvg-id`) und „arte“ importieren, „ZDF HD“ markieren, Tab offen
2. Datenträger vollschreiben, „Aktualisieren“ (Quelle unverändert)
3. App neu starten; alternativ Platz freigeben und einen beliebigen Stern setzen
**Erwartet:** Das Aktualisieren gilt als gescheitert, Sender und Favoriten bleiben wie vorher (AK-17), eine verständliche Meldung
**Tatsächlich:** Fehler „The operation couldn’t be completed. (NSSQLiteErrorDomain error 13.)“ (englisch, technisch), aber der Tab
zeigt sofort den neuen Stand `["ZDF HD", "ZDF SD"]` (einschließlich BUG-01), alle Senderobjekte sind ersetzt, `hasChanges=true`. In der
Datei steht der alte Stand (nach Neustart nur „ZDF HD“). Der nächste erfolgreiche Speichervorgang irgendwo im Kontext (hier ein Stern)
schreibt den ungespeicherten Aktualisierungsstand nachträglich mit — ohne dass der Nutzer davon weiß.
**Ort:** `Sources/Services/PlaylistImporter.swift:256-264` (Löschen und Neuanlegen im Haupt-Kontext, `try modelContext.save()` ohne
`rollback()` im Fehlerfall), `Sources/Views/PlaylistsView.swift:113-116` (zeigt `error.localizedDescription` unverändert)
**Vorschlag:** Im Fehlerfall `modelContext.rollback()` und eine eigene Meldung („Die Playlist konnte nicht gespeichert werden …“);
besser in einem eigenen Kontext aktualisieren und erst nach erfolgreichem Speichern sichtbar machen (vgl. BF-52).
**Test:** `B05AktualisierenTests.testAK17_Randfall_SpeicherfehlerBeimAktualisieren` (braucht `TEST_RUNNER_B05_FULL_VOLUME`)

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · Verwaiste Favoriten bleiben im Tab.** Der Tab filtert nur `isFavorite`. Ein Sender ohne Playlist (`ZPLAYLIST = NULL`) bleibt
  nach dem Löschen aller Playlists sichtbar und ist nur per Stern entfernbar. Im normalen Betrieb entsteht keiner (Löschen und
  Aktualisieren über die Beziehung, AK-20/AK-28); erreichbar über eine manipulierte oder beschädigte Datenbank.
- **H-2 · Logo-Adressen der Favoriten im Systemprotokoll.** Das Network-Framework protokolliert beim Laden jedes Logos
  `url: http://…/logos/sender-3.png` auf Ebene `Default` (78 Zeilen im letzten Gesamtlauf). Am Test-Host ist die Schwärzung privater Daten
  aus; ob die regulär gestartete App schwärzt, ist ohne Start der echten App nicht prüfbar (gleiche Lage wie BF-43, B03 H-1).
- **H-3 · Karten ohne Logo sind dauerhaft eine Ladeanzeige.** `AsyncImage(url: nil)` bleibt in `.empty`, die Karte dreht einen
  Spinner und meldet sich für VoiceOver als „busy indicator“ (Wert 0), statt den Platzhalter zu zeigen — gehört zu B04.
- **H-4 · Namenloser Favorit.** Eine Karte mit leerem Namen zeigt nur das Gruppen-Badge; VoiceOver liest nur „Sport“ (EC-02).
- **H-5 · Website-Aussagen.** „Refreshing a remote playlist matches favourites by their tvg-id“ (`web/content/features.ts:18`) ist
  unvollständig: ohne `tvg-id` gilt der Name (AK-11, AK-13). „does not wipe your selection“ stimmt nicht — die Auswahl wird
  vergrößert (BUG-01) und geht bei Schreibweisenwechsel der `tvg-id` verloren (BUG-05). FAQ „Nowhere“ widerspricht BUG-03 (BF-20).
  „Star a channel anywhere“: im Player gibt es keinen Stern (AK-03, Player-Texte) — Produktfrage OF-07. Für B10.
- **H-6 · Beiseitegelegte Datenbank enthält Favoriten.** Seit der B09-Reparatur legt `AppPersistence.openStore` eine nicht zu öffnende
  Datei samt Favoriten unter `Application Support/<Bundle-ID>/Beiseitegelegt/<Zeitstempel>/` ab; die Spec (AK-22, Katalog 1.3/5.3)
  kennt diesen Ort nicht (in B03 als Teil von BF-58 erfasst).

## Code-Review

Ein eigener `code-reviewer`-Agent steht in dieser Umgebung nicht zur Verfügung; aufgerufen wurde der `code-review`-Skill (Stufe
medium) über `FavoritesView.swift`, `ChannelRowView.swift`, `ContentView.swift`, `Channel.swift` und `PlaylistImporter.swift`. Er hat
nur den **Arbeitsbaum-Diff** gegenüber `c01f1cf` geprüft — in den drei Ansichten gibt es keinen Diff, dort meldete er folglich nichts.
Seine Funde, nachgeprüft:

| Fund des Reviews | Nachprüfung | Ergebnis |
|---|---|---|
| `refresh` baut Sender über `attach` je Sender auf dem Main-Actor auf, quadratisch, friert bei 17.000 Xtream-Sendern minutenlang ein | in B03 ausgeführt (AK-37: 280 s Release); hier nur der B05-Anteil gemessen (AK-30: 1,1 s für das Merken der Schlüssel) | bestätigt, **bereits erfasst als BF-52** (B03 BUG-01), kein neuer B05-Befund |
| Xtream-Import speichert in Blöcken zu 5.000; bei Absturz bleibt eine Teil-Playlist stehen | nur im Code nachvollzogen (`PlaylistImporter.swift:148-170`), nicht ausgeführt; betrifft B01 | nicht bestätigt, nicht als BUG geführt — Hinweis an B01 |
| Aufräumen nach gescheitertem Block mit `try?`, danach Schlüsselbund-Eintrag gelöscht → Playlist ohne Zugangsdaten | nur im Code nachvollzogen (`:171-176`, `:104`), nicht ausgeführt; betrifft B01 | nicht bestätigt — Hinweis an B01 |
| `PlaylistsView.delete` verwirft Fehler (`try?`) | bekannt | bereits erfasst als BF-60 (B03 BUG-08) |

Da der Skill die unveränderten B05-Dateien nicht durchgesehen hat, stammen die Befunde zu `FavoritesView`, `ChannelRowView` und
`Channel.favoriteKey` aus der eigenen Durchsicht und sind **alle ausgeführt** belegt: `try? save()` ohne Zurücksetzen (BUG-02),
fehlende Accessibility-Angaben und nicht ausgeblendetes Leerzustand-Symbol (BUG-04), `AsyncImage` ohne lokalen Zwischenspeicher im Tab
(BUG-03), `sort: \Channel.name` ohne Kollation (BUG-07), Schlüssel ohne Trimmen der `tvg-id`, mit leerem Namen und nur als Menge
gemerkt (BUG-01), `lowercased()` ohne Unicode-Faltung („İ“, „ß“ → BUG-05), kein `rollback()` nach gescheitertem `save()` in `refresh`
(BUG-11), Tab-Abfrage ohne Bezug zur Playlist (H-1), `ProgressView` für `url == nil` (H-3).

## Abweichung Spec ↔ Code

Rückmeldung an die Spezifikation (Stand `c01f1cf` + Reparatur B01); geprüft wurde der aktuelle Stand einschließlich der
Reparaturen B09 und B10 Teil 1.

| Stelle | Spec sagt | Code tut (ausgeführt) |
|---|---|---|
| AK-06, design.md *Komponentenstruktur* | Tab „Favoriten“ mit gefülltem Stern-Symbol; Tab-Leiste gelesen | macOS 27: Die Tab-Leiste liegt als `AXTabGroup „Navigation Tab Bar“` in der Fenster-Toolbar und zeigt **nur Text**, kein Symbol (Bildschirmaufnahme `AK-06-contentview-tab-favoriten.png`). Das Symbol aus `ContentView.swift:19` erscheint auf macOS nicht |
| AK-09 | Verschiebung nach dem Aktualisieren abgeleitet | ausgeführt und bestätigt (`Z_PK` 3 vs. 5) |
| AK-13 | Leerzeichen am Rand gelesen | ausgeführt: M3U getrimmt → bleibt; Xtream „ Rand TV“ → „Rand TV“ → verloren |
| AK-05 | Karte meldet sich als Ladeanzeige, „solange das Logo lädt“ | ohne Logo **dauerhaft** (`AXBusyIndicator`, H-3) |
| EC-02 | „Karte ohne Namen“ | VoiceOver-Label besteht nur aus der Gruppe („Sport“) |
| EC-04, EC-08 | gelesen | ausgeführt, bestätigt |
| EC-09 | nicht gemessen | gemessen: 5.667 Favoriten, Tab öffnen 111 ms Blockade |
| AK-26, Katalog 1.4, PRD („kein `print`, `Logger` oder `os_log`“) | kein Logging im Code | seit B09 `Logger` in `AppPersistence.swift:64` (nur Datenbankfehler, `privacy: .private`, keine Sender); Befund zu B05 unverändert |
| AK-22, Katalog 1.3/5.3 | Speicherorte Datenbank, `-wal`, Backups | zusätzlich `…/Beiseitegelegt/<Zeitstempel>/` (B09, H-6) |
| AK-25, FB-03 | `Resources/Info.plist:39-40` | jetzt `Info.plist:47-48` (Zeilen durch B09 verschoben) |
| Kopf der Spec | Code-Stand ohne B09 | B05-Dateien unverändert; alle übrigen Zeilenangaben der Spec stimmen weiterhin |

## Neue Tests

Alle unter `Tests/B05/`, Testnamen mit AK-/EC-Nummer bzw. Angriff. Belege für Fehler mit `XCTExpectFailure("BUG-NN …")`.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B05Support.swift` | — | Temp-Datenbank über `AppPersistence.diskContainer`, SQLite-Zählung und Bytesuche, M3U-/Logo-Routen am `MockXtreamServer`, Fenster mit Halter-View, Accessibility (Karten, Tab-Leiste, benutzerdefinierte Aktionen), synthetische Klicks, Sternfarbe per Pixel, Aufnahmen, Main-Thread-Herzschlag, Basisklasse mit Aufräumen (Fenster, Cache-Einträge des Mocks, Schlüsselbund-Testdienst, Temp-Ordner) |
| `B05SternTests.swift` | 6 | AK-01–AK-05, EC-07, EC-08 |
| `B05TabTests.swift` | 7 | AK-06–AK-10, AK-21, EC-01 |
| `B05AktualisierenTests.swift` | 10 | AK-11–AK-19 (mit Randfall Speicherfehler zu AK-17), EC-02–EC-05, EC-11 |
| `B05LoeschenTests.swift` | 2 | AK-20, AK-28; Angriff 8 |
| `B05DatenschutzTests.swift` | 5 | AK-22–AK-27, EC-06; Angriffe 2, 4, 5 |
| `B05LeistungTests.swift` | 2 | AK-29, AK-30, EC-09 |
| `B05SicherheitTests.swift` | 4 | Angriffe 1, 3, 7 |

**Letzter Gesamtlauf** (2026-09-26 16:14–16:17, Debug, Kopie `qa1-b05`, `build/dd`, mit `TEST_RUNNER_B05_EVIDENCE=1` und
`TEST_RUNNER_B05_FULL_VOLUME`; vollständige gefilterte Ausgabe in `qa/testlauf-gesamt.txt`):

```
xcodebuild test-without-building -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' \
  -derivedDataPath build/dd -only-testing:MikaPlusPlayerTests/B05SternTests -only-testing:MikaPlusPlayerTests/B05TabTests \
  -only-testing:MikaPlusPlayerTests/B05AktualisierenTests -only-testing:MikaPlusPlayerTests/B05LoeschenTests \
  -only-testing:MikaPlusPlayerTests/B05DatenschutzTests -only-testing:MikaPlusPlayerTests/B05LeistungTests \
  -only-testing:MikaPlusPlayerTests/B05SicherheitTests
Test Suite 'B05AktualisierenTests' passed   Executed 10 tests, with 0 failures (0 unexpected) in 20.721 seconds
Test Suite 'B05DatenschutzTests' passed     Executed 5 tests, with 0 failures (0 unexpected) in 41.762 seconds
Test Suite 'B05LeistungTests' passed        Executed 2 tests, with 0 failures (0 unexpected) in 25.450 seconds
Test Suite 'B05LoeschenTests' passed        Executed 2 tests, with 0 failures (0 unexpected) in 4.635 seconds
Test Suite 'B05SicherheitTests' passed      Executed 4 tests, with 0 failures (0 unexpected) in 10.763 seconds
Test Suite 'B05SternTests' passed           Executed 6 tests, with 0 failures (0 unexpected) in 22.919 seconds
Test Suite 'B05TabTests' passed             Executed 7 tests, with 0 failures (0 unexpected) in 24.706 seconds
Executed 36 tests, with 0 failures (0 unexpected) in 150.955 (150.979) seconds
** TEST EXECUTE SUCCEEDED **
```

Der vorletzte Gesamtlauf (16:10–16:12, 35 Tests) war **nicht** grün: `testAK28_…` scheiterte mit 1 Restvorkommen in der Datei — daraus
entstand BUG-10, die Erwartung ist seitdem nicht strikt. Zusätzlich in der Kopie ausgeführt (EC-06):
`B01ReparaturTests.testBUG01_MigrationVorhandenerDatenbankOhneDatenverlust`, `…testBUG01_AktualisierenLiestSchluesselbundUndBehaeltFavoriten`,
`B09PersistenzTests.testBUG13_DatenbankAusV11OeffnetUnveraendert` → `Executed 3 tests, with 0 failures`. Die übrigen Test-Suites des
Projekts liefen hier nicht mit (parallele QA-Durchläufe).

Umgebungsvariablen (xcodebuild reicht `TEST_RUNNER_…` ohne Präfix an den Test-Host weiter): `TEST_RUNNER_B05_EVIDENCE=1` schreibt
Nachweise nach `qa/`, `TEST_RUNNER_B05_FULL_VOLUME=<Mountpoint>` aktiviert AK-27 (sonst übersprungen), `TEST_RUNNER_B05_KEEP_STORES=1`
lässt die Temp-Datenbanken für Nachkontrollen liegen. Build-Warnung aus `Tests/B05`: nur `CGWindowListCreateImage` veraltet
(Bildschirmaufnahme der Tab-Leiste).

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Aktualisieren vervielfacht Favoriten (3 → 8, Xtream 2 → 6) und macht entfernte Sterne rückgängig — **gleiche Ursache wie BF-53, dort zusammenführen** | mittel | `Models/Channel.swift:49-52`, `Services/PlaylistImporter.swift:253, 299` | BUG-01 |
| Speicherfehler beim Umschalten des Sterns wird verschluckt: Stern und Tab zeigen den neuen Zustand, nichts gespeichert, keine Meldung, nach Neustart alter Zustand | mittel | `Views/ChannelRowView.swift:60-62` | BUG-02 |
| Favoriten-Tab fragt bei jedem Öffnen genau die Logos der Favoriten an (IP, App-Build, Sprache an Logo-Hosts) — widerspricht PRD-Begründung Stufe B und FAQ „Nowhere“ (BF-20) | mittel | `Views/FavoritesView.swift:8-12, 22-28`, `Views/ChannelRowView.swift:36` | BUG-03 |
| Favoriten-Zustand für VoiceOver nicht wahrnehmbar, Aktion englisch „Favourite“ (Sprache wartet auf OF-06) | mittel | `Views/ChannelRowView.swift:59-69` | BUG-04 |
| Favorit geht beim Aktualisieren ohne Hinweis verloren (Schreibweise der `tvg-id`, Umbenennung, Wegfall) und kommt nicht zurück — wartet auf OF-03 | niedrig | `Services/PlaylistImporter.swift:253-262` | BUG-05 |
| Gleichnamige Favoriten verschiedener Playlists nicht unterscheidbar, Reihenfolge wechselt nach dem Aktualisieren — wartet auf OF-02 | niedrig | `Views/FavoritesView.swift:8-12, 22-28` | BUG-06 |
| Favoriten-Tab sortiert nach Zeichencode statt sprachgerecht — wartet auf OF-01 | niedrig | `Views/FavoritesView.swift:10` | BUG-07 |
| Löschen einer Playlist nimmt ihre Favoriten ohne Hinweis mit, Neuimport ohne Favoriten — wartet auf OF-04 | niedrig | `Views/PlaylistsView.swift:104-107`, `Services/PlaylistImporter.swift:270-278` | BUG-08 |
| NUL-Zeichen in Name/`tvg-id` wird beim Speichern abgeschnitten, der Favorit geht bei jedem Aktualisieren verloren | niedrig | `Services/M3UParser.swift:83, 113`, `Models/Channel.swift:49-52` | BUG-09 |
| Namen gelöschter Favoriten bleiben teils als Bytes in der Datenbankdatei (3 von 11 Läufen) — **Bestätigung von BF-59, dort zusammenführen** | niedrig | `Services/PlaylistImporter.swift:270-278` | BUG-10 |
| Scheitert das Speichern beim Aktualisieren, zeigt die App den neuen, ungespeicherten Stand samt Favoriten; technische englische Meldung; späteres Speichern schreibt ihn unbemerkt mit | mittel | `Services/PlaylistImporter.swift:256-264`, `Views/PlaylistsView.swift:113-116` | BUG-11 |

## Nächster Schritt

Höchster Grad mittel: Befunde in `features/befunde.md` übernehmen — BUG-01 als Bestätigung von **BF-53** und BUG-10 als Bestätigung
von **BF-59** (beide B03) führen, nicht als zweite Einträge — und mit dem nächsten Feature weitermachen; Status bleibt `review`.
Reparatur später mit `/sdd-build B05` (BUG-01 gemeinsam mit B03 BUG-02, BUG-11 gemeinsam mit B03 BUG-01/BF-52, BUG-02 bis BUG-04,
BUG-09; BUG-05 bis BUG-08 erst nach Entscheidung zu OF-01 bis OF-04), danach `/sdd-qa B05` (Durchlauf 2). Für andere Features: H-3
an B04, H-5 an B10, BUG-09 betrifft den Import (B02/B01), H-2 wie BF-43, die beiden nicht bestätigten Review-Funde an B01.
