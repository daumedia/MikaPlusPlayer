# B03 · Playlist-Verwaltung — Testbericht

Durchlauf 1 · Stand: 2026-09-16 · Geprüft gegen `spec.md` vom 2026-09-16 (Status `rekonstruiert`, Stand `c01f1cf` + Reparatur B01)
· Geprüfter Code: **aktueller Arbeitsbaum** (`c01f1cf` + Reparatur B01 + Reparatur B09, Branch `sdd/rueckerfassung`)

## Fazit

**Production-ready: nein** · höchster Schweregrad: **hoch** (BUG-01)

Der fachliche Kern hält, was die Rekonstruktion beschreibt, und ist jetzt mit dauerhaften Tests belegt: Übersicht,
Kontextmenü, Aktualisieren von M3U- und Xtream-Playlists (ein Abruf bzw. drei Anfragen, Zugangsdaten nur aus dem
Schlüsselbund und nur an den Host aus dem Schlüsselbund), Favoriten-Erhalt über tvg-ID bzw. Namen, alle 15
Fehlermeldungen mit vollständigem Erhalt der alten Liste und ohne Zugangsdaten, Anmeldebremse, Löschen samt Sendern,
Favoriten und Schlüsselbund-Eintrag, Löschen während eines Aktualisierens. Durchgefallen sind alle 15 ⚠-Kriterien:
Das Ist-Verhalten ist reproduziert und jeweils als BUG erfasst.

Schwer wiegt **BUG-01**: Aktualisieren und Löschen laufen vollständig auf dem Main-Thread und wachsen quadratisch.
17.000 Sender zu aktualisieren friert die App im **Release-Build 280 s** ein (Debug 284 s, Rückerfassung 292 s), das Löschen 41–133 s. Der Release-Build ist nicht schneller: Die Kosten entstehen in SwiftData, nicht im unoptimierten eigenen Code. Das PRD verspricht Bedienbarkeit „bei Anbieterlisten mit mehr als 17.000 Sendern“. Mittel sind
Favoriten-Vermehrung (BUG-02), der Ladeindikator (BUG-03), ungebremstes Mehrfach-Aktualisieren (BUG-04), weiterlaufende
Wiedergabe und „Erneut versuchen“ ohne Zugangsdaten nach Löschen/Aktualisieren (BUG-05), M3U-Adresse samt Token im
Plattencache nach dem Löschen (BUG-06) und das Fehlen jedes Wegs, alle Daten zu entfernen (BUG-09). Niedrig: Bytes
gelöschter Sender in der Datenbankdatei (BUG-07), verwaister Schlüsselbund-Eintrag (BUG-08) sowie die drei ⚠-Kriterien mit
offener Produktfrage: **Löschen ohne Rückfrage und ohne Rückgängig (BUG-10, OF-01)**, kürzere Liste ersetzt ohne Rückfrage
(BUG-11, OF-02), „Zugangsdaten fehlen“ führt nur über Löschen (BUG-12, OF-06).

Nicht prüfbar blieben AK-06 (destruktive Kennzeichnung von „Löschen“ im Test-Host nicht beobachtbar) und AK-31
(Systemprotokoll: am Test-Host ist die Schwärzung privater Daten aus; CFNetwork schreibt dort die M3U-Adresse samt Token).
Die Spec weicht an mehreren Stellen vom aktuellen Code ab (Abschnitt *Abweichung Spec ↔ Code*), am deutlichsten bei AK-28: „Erneut
versuchen“ zeigt nach dem Löschen **keine** Meldung „Zugangsdaten fehlen“.

Nächster Schritt: `/sdd-build B03` mit BUG-01 bis BUG-12; die Erfassung der weiteren Bestandsfeatures wartet, bis BUG-01
behoben und erneut geprüft ist. Randbeobachtung für B08 (nicht hier gewertet): Die Rückerfassung sah einen Absturz „Index
out of range“ in `MultiviewScreen.swift:79`, wenn die Session im Raster-Layout bei sichtbarem Fenster geleert wird. Diese
QA hat das Raster-Layout bewusst nicht geleert (Fokus-Layout), der Absturz ist hier weder bestätigt noch widerlegt.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 36 von 38 |
| davon bestanden | 21 |
| davon durchgefallen | 15 (alle ⚠-Kriterien) |
| **nicht prüfbar** | 2 (AK-06, AK-31) |
| Edge Cases belegt | 9 von 12 (EC-06 weicht von der Spec ab) |
| Tests neu geschrieben | 42 in `Tests/B03/` (4 Testklassen + Hilfsdatei) |
| Tests grün | 41 von 42 · 1 übersprungen (EC-03, nicht provozierbar), **0 Fehlschläge**; darin 16 Tests mit `XCTExpectFailure` als Belege für BUG-01 bis BUG-12 |

## Prüfumgebung

| Was | Wie |
|---|---|
| Code-Stand | Arbeitsbaum 2026-09-16 abends: `c01f1cf` + Reparatur B01 + Reparatur B09 (`AppPersistence.openAppStore`, `AppSchema`, `StoreRecoveryAlert`). Produktcode nicht verändert |
| Build/Test | `xcodegen generate` (neue Dateien) · `xcodebuild build-for-testing` / `test-without-building -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-qa-b03 -only-testing:MikaPlusPlayerTests/B03…` · Ausgaben unter `B03QA|…` |
| Release-Messung | eigener Build `-configuration Release -derivedDataPath build/dd-qa-b03-release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES` (Swift `-O`, universell arm64/x86_64; Hardened Runtime nur in diesem Messbuild aus, damit der Test-Host das Test-Bundle laden kann – die Optimierung bleibt unverändert) |
| Rechner | Apple M3 Max (16 Kerne), macOS 27 (Darwin 27.0.0). **Parallel liefen die QA-Runden von B01 und B09** (Last-Mittel 3,5–15, je Messung in `qa/AK-37-38-messung.txt`) |
| Anbieter | `MockXtreamServer` (Tests/Support) auf 127.0.0.1, zweiter Mock als „fremder Host“, geschlossene Ports für „nicht erreichbar“; jede Anfrage roh mitgeschrieben |
| Zugangsdaten | nur erfunden (`qa-user`, `qa-pass-b03…`) |
| Datenbank | je Test eine Datei im Temp-Verzeichnis, geöffnet über den Produktionsweg `AppPersistence.diskContainer` (versioniertes Schema + Migrationsplan); Prüfung per SQLite und Bytesuche. Der Test-Host selbst öffnet nur einen In-Memory-Container. Die Datenbank des Nutzers wurde weder geöffnet noch gelesen |
| Schlüsselbund | nur `XtreamCredentialStore.standard` des Test-Hosts = Dienst `lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>` (je Lauf neu, jeder Test prüft das Präfix und leert ihn am Ende) |
| Plattencache | Tests schreiben über `URLSession.shared` in `~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db` (Test-Host und App teilen die Bundle-ID) und entfernen ihre eigenen Einträge (Gegenprobe in AK-33: 0) |
| Oberfläche macOS | echte `PlaylistsView`, `ChannelListView`, `PlayerView`, `MultiviewScreen` in Fenstern des Test-Hosts; Links-/Rechtsklick als synthetische Mausereignisse, Kontextmenü über `NSMenu.didBeginTrackingNotification` (ein synthetisches Menü hält den Test-Host je Aufruf 4–14 s auf; Verzögerungen des Mocks sind darauf abgestimmt, gemessen wird nie über einem Menüaufruf), Zustand über AppKit-Accessibility, Fensteraufnahmen in `qa/`. Keine Tastaturereignisse |
| Oberfläche iOS | Build und Start im Simulator (iPhone 17, iOS 26.5, `build/dd-qa-b03-ios`), UI-Snapshot und Aufnahme `qa/AK-01-02-ios-leerzustand.jpg`. Tippen/langes Drücken ist in dieser Umgebung nicht automatisierbar |
| Ton | keiner: Stream-Pfade antworten nie oder mit 404, M3U-Streams zeigen auf Port 9, Multiview-Engine sofort stumm, keine Tastaturereignisse |
| Codequalität | `code-reviewer`-Agent über `PlaylistsView`, `PlaylistImporter` (refresh/delete/attach/fetchText) und Beteiligte; 5 Funde, alle nachgeprüft (Abschnitt *Code-Review*) |

## Akzeptanzkriterien im Einzelnen

Abgehakt ist nur, was ausgeführt wurde. Testnamen ohne Klasse: `B03AktualisierenTests` (A), `B03LoeschenTests` (L),
`B03OberflaecheTests` (O), `B03LeistungTests` (P). Aufnahmen unter `features/B03-playlist-verwaltung/qa/`.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | O `testAK01_AK02_…`: Fenstertitel „Playlists“, AX-Texte „MIKA+PLAYER · PLAYLISTS“, „Playlists“, Button „Add“ (+) · `AK-01-02-leerzustand.png` (Akzentfarbe) · iOS: UI-Snapshot ohne Navigationsleiste, Kopfzeile im Inhalt, `AK-01-02-ios-leerzustand.jpg` |
| AK-02 | ✅ bestanden | O `testAK01_AK02_…`: „List With A Film Strip“ (Symbol), „Keine Playlists“, Hinweistext wörtlich, „Playlist importieren“; Klick darauf **und** auf „+“ öffnet jeweils das Sheet „Playlist importieren“ (Reiter Xtream gewählt), „Abbrechen“ schließt es · iOS-Aufnahme mit denselben Texten |
| AK-03 | ✅ bestanden | O `testAK03_AK05_EC10_…`: vier Karten, obere Kanten 642/563/484/405 in Anlage-Umkehr (Xtream, Adresse, Datei, lang); AX „QA Zugang, 4 Sender“ usw. · `AK-03-vier-playlists.png`: Globus bei Adresse und Xtream, Dokument bei Datei, Name einzeilig, Badge „N Sender“, Pfeil |
| AK-04 | ✅ bestanden | O `testAK04_KarteOeffnetSenderliste`: Klick auf die Karte → im selben Fenster Titel „QA Öffnen“, „MIKA+PLAYER · 7 SENDER“, Sender „Alpha, News“ … · `AK-04-senderliste.png` |
| AK-05 | ✅ bestanden | O `testAK03_AK05_EC10_…`: Kartentexte nur „<Name>, N Sender“; in allen AX-Texten der Übersicht kein `127.0.0.1`, `qa-user`, `player_api`, `list.m3u`, „HLS“, „MPEG“, „Xtream“, „M3U“, „2026“ (nach einem Aktualisieren) |
| AK-06 | ⚠️ nicht prüfbar | Ausgeführt und bestanden: O `testAK06_…` – Menü einer Datei-Playlist `["Löschen"]`, einer M3U- und einer Xtream-Playlist `["Aktualisieren", "Löschen"]`; Hauptmenü (66 Einträge) ohne „Aktualisieren“; `delete:` (Bearbeiten › Löschen) an das Fenster wird von niemandem behandelt, 3 Playlists bleiben. **Nicht beobachtbar:** „Löschen ist als destruktiv gekennzeichnet“ – das von SwiftUI gebaute `NSMenuItem` hat `isDestructive = false`, kein farbiges `attributedTitle`, ein Template-Bild wie „Aktualisieren“; das Menü erscheint im Test-Host nicht als aufnehmbares Fenster (Hinweis H-3). iOS (langes Drücken) nicht automatisierbar |
| AK-07 | ✅ bestanden | A `testAK07_EC02_…`: genau 1 Abruf `/list.m3u?token=…`, 7 → 9 Sender, 0 von 7 IDs übernommen, `ZCHANNEL` der Playlist = 9, `ZCHANNELCOUNT` = 9, `playlistID` gesetzt; Name, Adresse, `createdAt` gleich; Reihenfolge der Übersicht unverändert; keine verwaisten Zeilen |
| AK-08 | ✅ bestanden | A `testAK08_AK32_EC01_…`: Payload `GET /player_api.php?username=qa-user&password=<pass>` + `get_live_categories` + `get_live_streams`, alle am Port des gespeicherten Hosts; MPEG-TS → `.ts`, HLS → `.m3u8`; Adressen `http://127.0.0.1:<port>/live/102.ts` ohne Zugangsdaten; Schlüsselbund-Eintrag gleich; Passwort in Store/-wal/-shm: 0/0/0 |
| AK-09 | ✅ bestanden | A `testAK09_…_M3U`: „Alpha“→„Alpha Neu“ (gleiche tvg-ID) bleibt, „Gamma“→„Gamma Plus“ fällt weg, „Beta“→„BETA“ bleibt, umgekehrte Reihenfolge; Favoriten-Tab-Abfrage `["Alpha Neu", "BETA"]` · A `testAK09_…_Xtream`: `["Kanal A (neu)", "Kanal B"]` |
| AK-10 ⚠ | ❌ durchgefallen | A `testAK10_…`: M3U 4 → 7 Favoriten (`Film 4K`, `Film SD`, `sport hd` nie markiert); „Kanal X“ 1 → 2; Xtream „Sport 1“ 1 → 3 → **BUG-02** |
| AK-11 ⚠ | ❌ durchgefallen | A `testAK11_…`: 7 → 1 → 7 Sender, Favoriten 4 → 0 → 0, kein Fehler, keine Rückfrage → **BUG-11** |
| AK-12 | ✅ bestanden | O `testAK12_AK13_EC09_…`: während des Wartens (M3U 25 s verzögert) 1 Ladeindikator in Fenster A, Main-Thread-Lücke über 2 s **≤ 0,01 s** (zwei Läufe), Kontextmenü einer anderen Karte öffnet `["Aktualisieren", "Löschen"]`; danach kein Indikator, kein Alert, Karte „QA Eins, 9 Sender“ · `AK-12-ladeindikator-eine-karte.png` |
| AK-13 ⚠ | ❌ durchgefallen | ebenda: beide laufen (belegt über `lastRefreshed`) → **1** Indikator, nur bei der zuletzt gestarteten Karte (`AK-13-zwei-laufen-ein-indikator.png`); M3U fertig, Xtream läuft → **0** Indikatoren (`AK-13-m3u-fertig-xtream-laeuft-kein-indikator.png`) → **BUG-03** |
| AK-14 ⚠ | ❌ durchgefallen | A `testAK14_…`: gleichzeitig gestartet M3U 2× → 2 Abrufe, 7 Sender, Favorit bleibt; Xtream 3× → 9 Anfragen mit Passwort, 4 Sender · O `testAK14_Angriff3_…`: „Aktualisieren“ bei jeder Wahl aktiv (`isEnabled` 3× true), obwohl die vorige Aktualisierung noch auf die Antwort wartete (15 s Verzögerung, Abstand der Wahlen 4–14 s) → 3 Abrufe, 7 Zeilen → **BUG-04** |
| AK-15 | ✅ bestanden | A `testAK15_…`: M3U und Xtream gleichzeitig in 1,53 s → 8 bzw. 4 Sender, Favoriten je `["Alpha"]` / `["Kanal Int"]`, 12 Zeilen, `playlistID` stimmt |
| AK-16 | ✅ bestanden | A `testAK16_EC12_…`: Datei-Playlist ohne `sourceURL`; interner Aufruf ohne Fehler, 0 Anfragen, IDs gleich; geänderte Datei → weiter 7 Sender; erneuter Import legt eine zweite Playlist an (1 Sender). Menü ohne „Aktualisieren“: AK-06 |
| AK-17 | ✅ bestanden | A `testAK17_…` (eigener Lauf, nicht nur der B01-Test): Altbestand mit Zugangsdaten in `sourceURL` und `streamURL` → 3 Anfragen mit diesen Zugangsdaten, Eintrag im Test-Schlüsselbund, `ZSOURCEURL`/`ZSTREAMURL` mit Passwort: 0/0, Favorit bleibt, danach über den Schlüsselbund abspielbar |
| AK-18 | ✅ bestanden | A `testAK18_AK30_…`: HTTP 404 → „Netzwerkfehler: HTTP 404“, 500 → „… HTTP 500“, HTML/leer/nur `#EXTM3U` → „Die Playlist enthält keine gültigen Sender.“, geschlossener Port → „Netzwerkfehler: Could not connect to the server.“; jeweils IDs, Favoriten, Anzahl, `lastRefreshed`, SQLite-Zählung gleich, `hasChanges = false` · O `testAK18_EC04_…`: Alert „Fehler“ / „Netzwerkfehler: HTTP 404“ / „OK“, nach OK weg, Karte weiter „7 Sender“ (`AK-18-fehler-alert.png`) |
| AK-19 | ✅ bestanden | A `testAK19_AK30_…`: leer → „Die Playlist enthält keine gültigen Sender.“; 500 → „Netzwerkfehler: HTTP 500“; Objekt statt Liste → „Netzwerkfehler: Unerwartete Serverantwort (The data couldn’t be read because it isn’t in the correct format.)“; Grenze 2 → „Die Senderliste ist zu groß (mehr als 2 Sender).“, Standardtext „(mehr als 100.000 Sender)“; nicht erreichbar → „Could not connect to the server.“; alte Liste jeweils unverändert |
| AK-20 | ✅ bestanden | A `testAK20_…`: ein abgelehnter Import + zwei abgelehnte Aktualisierungen (gemeinsame Bremse) → dritte Meldung „Anmeldung fehlgeschlagen. …“, vierter Versuch „Zu viele fehlgeschlagene Anmeldungen. Bitte in 30 Sekunden erneut versuchen.“; Anmeldeanfragen am Mock vor/nach: 3/3 |
| AK-21 ⚠ | ❌ durchgefallen | A `testAK21_…`: Meldung wörtlich, 0 Anfragen, Liste unverändert; der empfohlene Weg (löschen, neu importieren) → Favoriten 2 → 0 → **BUG-12** |
| AK-22 ⚠ | ❌ durchgefallen | O `testAK22_AK24_…`: „Löschen“ im Menü → sofort `ZPLAYLIST=0, ZCHANNEL=0`, kein Sheet, keine weiteren Fenster, Übersicht „Keine Playlists“; `undo:` von keinem Responder behandelt, Datenbank bleibt leer · L `testAK22_…`: `openAppStore()` und `diskContainer` ohne `UndoManager`, `rollback()` bringt nichts zurück · `AK-22-vor-loeschen.png`, `AK-22-nach-loeschen.png` → **BUG-10** |
| AK-23 | ✅ bestanden | L `testAK23_AK24_Angriff8_…`: 3 Playlists/60 Sender, 8 Favoriten → M3U und Xtream gelöscht → `ZPLAYLIST=1`, `ZCHANNEL=20`, 0 verwaist, 0 Zeilen der gelöschten; Favoriten-Tab-Abfrage = genau die 2 Favoriten der verbliebenen Playlist, deren IDs und `channelCount` unverändert |
| AK-24 | ✅ bestanden | ebenda: Eintrag X entfernt, Eintrag Y (Passwort `qa-pass-b03-y`) bleibt · über das Kontextmenü: O `testAK22_AK24_…` → Eintrag entfernt |
| AK-25 | ✅ bestanden | L `testAK25_…`: Datei nach dem Löschen vorhanden, SHA-256 und Änderungsdatum gleich |
| AK-26 | ✅ bestanden | A `testAK26_EC07_…_M3U` und `testAK26_…_Xtream`: Löschen 0,4 s bzw. 0,6 s nach dem Start → Aktualisieren endet ohne Fehler, danach 0 Playlists, 0 Sender, Favoriten-Abfrage 0, kein Schlüsselbund-Eintrag, auch nach weiterem `save()`; kein Absturz |
| AK-27 ⚠ | ❌ durchgefallen | O `testAK27_EC05_…`: Fenstertitel „QA Offen“, Kopfzeile „MIKA+PLAYER · 9 SENDER“, Chips „Alle, Doku, Film, News, Sport“ bleiben, Liste „Keine Sender – Diese Playlist enthält keine Sender.“ · `AK-27-senderliste-nach-loeschen.png` → **BUG-05** |
| AK-28 ⚠ | ❌ durchgefallen | O `testAK28_PlayerUndMultiview…`: vor dem Löschen `/live/qa-user/<pass>/102.m3u8` (Player) und `/101.m3u8` (Multiview), 4 Socket-Enden offen (lsof); nach dem Löschen weiterhin 4, Player-Titel „Kanal String“, Kachel „Kanal Int“, Engine nicht pausiert (`AK-28-player-/multiview-nach-loeschen.png`); erst Entfernen der Ansichten leert die Session und pausiert. O `testAK28_AK29_Erneut…`: **abweichend von der Spec** zeigt „Erneut versuchen“ bei Xtream nach dem Löschen **nicht** „Die Zugangsdaten … fehlen“ – die alte Engine-Meldung bleibt stehen; je nach Lauf lädt der Knopf nichts oder `/live/101.m3u8` ohne Zugangsdaten. M3U lädt die alte Adresse erneut (2 → 4 Abrufe) → **BUG-05** |
| AK-29 ⚠ | ❌ durchgefallen | A `testAK29_…`: gehaltener Sender nach Aktualisieren → Adresse `http://127.0.0.1:<port>/live/101.m3u8` ohne Zugangsdaten, `playlist == nil` · O `testAK28_AK29_…`: Klick auf „Erneut versuchen“ nach Aktualisieren → Mock erhält `/live/102.m3u8` (vorher `/live/qa-user/<pass>/102.m3u8`); `AK-29-erneut-versuchen-nach-aktualisieren.png` → **BUG-05** |
| AK-30 | ✅ bestanden | A `testAK18_AK30_…`, `testAK19_AK30_…`, `testAK20_…`, `testAK21_…`: 15 Fehlerfälle, keine Meldung enthält Token, Benutzer, Passwort, `127.0.0.1`, `player_api` oder Dateinamen der Adresse |
| AK-31 | ⚠️ nicht prüfbar | L `testAK31_Angriff4_…`: im Unified Log des Test-Prozesses (`OSLogStore`, 13.810 Einträge; Aktualisieren mit Erfolg und HTTP 500, gleichzeitiges Aktualisieren/Löschen, Löschen) **0** Treffer für Benutzer, Passwort, Token, Sender- und Playlistnamen, 16 SwiftData-Zeilen „remapped to a temporary identifier“ ohne Nutzdaten. Aber: `log show --predicate 'process == "MikaPlusPlayer"'` enthält für die Fälle „Host nicht erreichbar“ je eine CFNetwork-Zeile mit `NSErrorFailingURLStringKey=http://127.0.0.1:<port>/weg.m3u?token=<token>` bzw. `…player_api.php?username=qa-user&password=<pass>`. Am Test-Host ist die Schwärzung privater Daten aus (Sonde: `privacy: .private` im Klartext); ob die regulär gestartete App schwärzt, ist ohne Start der echten App (öffnet die Nutzerdatenbank) nicht prüfbar → Hinweis H-1 (wie B01 H-2) |
| AK-32 | ✅ bestanden | A `testAK08_AK32_EC01_…`: 3 Anfragen nur am Port des gespeicherten Hosts; `Cache.db`-Schlüssel mit Passwort 0; Passwort in Datenbankdateien 0 · L `testAngriff1_…`: Host in `sourceURL` auf einen zweiten Mock umgeschrieben → fremder Host 0 Anfragen, Anfragen gehen an den Host aus dem Schlüsselbund |
| AK-33 ⚠ | ❌ durchgefallen | L `testAK33_…`: nach Import + Aktualisieren 1 `Cache.db`-Schlüssel mit `token=…` und 1 Antwortkörper mit den Sendernamen; nach dem Löschen und 2 s Wartezeit unverändert 1/1, `URLCache.shared` liefert die Antwort weiter → **BUG-06** |
| AK-34 ⚠ | ❌ durchgefallen | L `testAK34_…`: M3U (20 Sender) und Xtream (20 Sender) gelöscht, Container geschlossen, neu geöffnet (0 Playlists, 0 Sender) → Bytesuche in Store/-wal/-shm: M3U-Sendernamen **14**, Stream-Adressen **14**, Xtream-Sendernamen **40** (Vorlauf: 12/12/40); Playlistname und Token 0; `freelist_count` 2, `secure_delete` 2 (neue Verbindung) → **BUG-07** |
| AK-35 ⚠ | ❌ durchgefallen | A `testAK35_…`: Altbestand, Löschen 0,6 s nach Start des Aktualisierens → direkt nach dem Löschen kein Eintrag, nach Ende des Aktualisierens Eintrag mit Passwort `qa-pass-b03-ak35`, 0 Playlists → **BUG-08** |
| AK-36 ⚠ | ❌ durchgefallen | L `testAK36_…`: kein Menüeintrag zum Entfernen aller Daten (66 Hauptmenü-Einträge durchsucht); die Speicherorte `~/Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store`, `…/Beiseitegelegt` (B09), `~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db`, `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` und der Anmelde-Schlüsselbund liegen außerhalb des App-Bundles. Das Löschen der App selbst wurde **nicht** ausgeführt; die Website sagt weiter „deleting the app removes all of it“ (`web/app/privacy/page.tsx:39`) → **BUG-09** |
| AK-37 ⚠ | ❌ durchgefallen | P `testAK37_AK38_…`, `qa/AK-37-38-messung.txt`: Release (`-O`): M3U 1.000/2.000/4.000 Sender → Aktualisieren 1,21/4,25/16,05 s, Main-Thread-Blockade 1,19/4,23/16,03 s; Xtream 1,23/4,40/15,94 s (Blockade 1,19/4,35/15,86 s); doppelte Senderzahl → Blockade ×3,56 (M3U) bzw. ×3,67 (Xtream), linear wäre ×2. **17.000 Xtream-Sender: 280,48 s, Blockade 280,38 s** (Debug: 284,30 s / 284,15 s), Speicher 54 → 86 MB, 17 von 17 Favoriten erhalten. Debug-Standardlauf: M3U 1.000/2.000 → 1,22/4,36 s (×3,64), Xtream 1,23/4,36 s (×3,66) → **BUG-01** |
| AK-38 ⚠ | ❌ durchgefallen | ebenda: Release: Löschen nach dem Aktualisieren (Sender geladen) M3U 1.000/2.000/4.000 → 0,62/0,47/6,30 s, Xtream 0,51/1,78/6,39 s; Löschen nach „Neustart“ (neuer Container, Sender nicht geladen) 1.000/2.000: M3U 0,22/0,68 s, Xtream 0,59/0,27 s. **17.000 Xtream-Sender: nach dem Aktualisieren 132,60 s, nach Neustart 41,31 s** (Debug: 122,51 s / 118,51 s). Die Blockade entspricht jeweils der ganzen Dauer; die Streuung beim Löschen ist groß (parallel liefen Builds anderer Features) → **BUG-01** |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | A `testAK08_AK32_EC01_…`: `"ts"`, `"m3u8"`, `""`, `nil` → `.m3u8`; `"mpegts"` → `.ts` |
| EC-02 | ✅ belegt | A `testAK07_EC02_…`: unveränderte Liste → 1 Abruf, 0 von 7 IDs bleiben, `lastRefreshed` neu; Dauer siehe AK-37 |
| EC-03 | ⚠️ nicht belegt | A `testEC03_…` (übersprungen): Schreibkonflikt über zweiten Container → `save()` gelingt (Objekt gewinnt), kein Fehler. Zuvor: Schreibsperre über eine zweite SQLite-Verbindung → `save()` wartete auf dem Main-Thread über 5 min, Lauf abgebrochen (Hinweis H-4). Ein gescheitertes Speichern ließ sich ohne Eingriff in den Produktcode nicht erzeugen; der Code-Review-Fund dazu ist im Code nachvollzogen (kein `rollback()`), aber nicht ausgeführt |
| EC-04 | ✅ belegt | O `testAK18_EC04_…`: zwei Fehler (404 nach 9 s, 500 nach 8 s, kurz nacheinander gestartet) → genau 1 sichtbares Sheet mit „Netzwerkfehler: HTTP 500“ (spätere ersetzt frühere), nach „OK“ kein weiterer Alert (`EC-04-zwei-fehler.png`) |
| EC-05 | ✅ belegt | O `testAK27_EC05_…`: offene Senderliste, Aktualisieren mit neuer Gruppe „Neu“ → Kopfzeile „· 9 SENDER“, Sender „Delta, Neu“ erscheint, Chip „Neu“ fehlt (`EC-05-senderliste-vorher.png`, `…-nach-aktualisieren.png`) |
| EC-06 | ❌ weicht ab | A `testEC06_DefekteEintraegeBeimAktualisieren`: Eintrag **ohne `stream_id`** wird still übersprungen, sein Favorit („Kanal B“) geht verloren. Ein Eintrag mit `name: null` wird dagegen **nicht** übersprungen, sondern als Sender mit leerem Namen übernommen und bleibt über die tvg-ID Favorit (Spec: „still übersprungen“) |
| EC-07 | ✅ belegt | A `testAK26_EC07_…` (Aktualisieren meldet nach dem Löschen keinen Fehler) · O `testAK14_Angriff3_…`: „Löschen“ im Menü einer laufenden Aktualisierung `isEnabled = true` |
| EC-08 | ⚠️ nicht belegt | Abfrage des Anmeldepassworts nach einem App-Update (geänderte Ad-hoc-Signatur) ist im Test-Host nicht nachstellbar, ohne echte Schlüsselbund-Einträge oder Signaturen anzufassen |
| EC-09 | ✅ belegt | O `testAK12_AK13_EC09_…`: zwei Übersichtsfenster auf demselben Container; Aktualisieren in A → Indikator in A 1, in B 0; nach Ende zeigt B sofort „QA Eins, 9 Sender“ |
| EC-10 | ✅ belegt | O `testAK03_AK05_EC10_…`: Name mit 320 Zeichen → Karte 69 pt hoch wie alle anderen, Darstellung einzeilig mit „…“ (`AK-03-vier-playlists.png`), voller Name in der Accessibility |
| EC-11 | ⚠️ nicht belegt | iOS: langes Drücken im Simulator nicht automatisierbar (nur Build, Start, Snapshot, Aufnahme) |
| EC-12 | ✅ belegt | A `testAK16_EC12_…`: Datei nach dem Import gelöscht → Playlist behält 7 Sender, IDs und Favorit; Aktualisieren ohne Wirkung |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf eine lokale App
ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | bestanden, Hinweis H-2 | Kein Server, keine per ID abrufbare Ressource. Übertragen auf manipulierte Datenbank (L `testAngriff1_…`): (a) `sourceURL` einer Xtream-Playlist auf fremden Host umgeschrieben → fremder Mock **0** Anfragen, echter Host 3 (Host kommt aus dem Schlüsselbund). (b) zweite Playlist mit **derselben `id`** eingefügt und gelöscht → der Schlüsselbund-Eintrag der echten Playlist ist weg, Aktualisieren meldet „Zugangsdaten fehlen“ (nur mit Schreibzugriff auf die Datenbank erreichbar) |
| 2 · Zugriffsregeln (Betriebssystem) | Befund bekannt (B01) | `~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db` `-rw-r--r--`, Ordner `drwxr-xr-x`; Datenbank-Ordner des Nutzers existiert auf diesem Rechner noch nicht (nur Metadaten gelesen). Ohne Sandbox für jeden Prozess des Benutzers lesbar – trägt BUG-06 und BUG-07 |
| 3 · Rate Limit / Wiederholversuche | **BUG-04** | O `testAK14_Angriff3_…`: „Aktualisieren“ 10× über das Menü einer Xtream-Playlist → **30 von 30** Anfragen mit Passwort erreichen den Anbieter, keine Sperre, kein Hinweis. Abgelehnte Anmeldungen bremst die B01-Bremse auch beim Aktualisieren (AK-20: 4. Versuch 0 Anfragen) |
| 4 · PII in Protokollen | Hinweis H-1 (nicht prüfbar) | App-Code protokolliert nichts (OSLogStore: 0 Treffer in 13.810 Einträgen). `log show --predicate 'process == "MikaPlusPlayer"' --start "2026-09-16 22:05:00"`: 2 CFNetwork-Fehlerzeilen des Test-Hosts mit M3U-Token bzw. Xtream-Passwort im Klartext (Fall „Host nicht erreichbar“); Schwärzung am Test-Host aus |
| 5 · PII an externe Dienste | bestanden | L `testAngriff5_…`, tatsächlicher Payload: `GET /list.m3u?token=qa-b03-tok-payload HTTP/1.1` und `GET /player_api.php?username=qa-user&password=qa-pass-b03-payload[&action=…] HTTP/1.1`, Kopfzeilen nur `accept: */*`, `accept-encoding: gzip, deflate`, `accept-language: de-DE,de;q=0.9`, `connection: keep-alive`, `host`, `user-agent: Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0`; kein Cookie, keine Authorization. Löschen: 0 Anfragen. Wie zugesagt (Spec 2.2): Adresse bzw. Zugangsdaten unverändert, nur an den Host der Playlist |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` (19 Commits) über `PlaylistsView.swift`, `PlaylistImporter.swift`, `Playlist.swift`, `Channel.swift`: keine Adressen, Tokens oder Zugangsdaten; `Tests/B03/` nur `qa-…`-Werte; `strings` über das gebaute Test-Host-Binary: 0 Treffer für `password=`, `token=`, `sk_live`, `service_role` |
| 7 · Eingaben | bestanden | L `testAngriff7_…`: Playlistname und Sendernamen leer, 1 Zeichen, 10.000 Zeichen, Emoji, `'; drop table ZPLAYLIST; --`, `<script>alert(1)</script>`, `../../etc/passwd`, Komma/Anführungszeichen → Import, Aktualisieren, Löschen ohne Absturz, Namen exakt gespeichert (10.000 Zeichen), Tabelle `ZPLAYLIST` intakt, danach 0/0; leerer Name → Host. Darstellung eines 320-Zeichen-Namens: EC-10 |
| 8 · Löschen | teils bestanden, **BUG-05, BUG-06, BUG-07, BUG-08, BUG-09** | Jede Tabelle nachgezählt (L `testAK23_AK24_Angriff8_…`): `ZPLAYLIST` 3→1, `ZCHANNEL` 60→20, `Z_PRIMARYKEY`, `Z_METADATA`, `Z_MODELCACHE` unverändert; persistente Historie `ACHANGE` 73→115, `ATRANSACTION` 6→8 (nur Entität/Primärschlüssel, 0 Zeilen mit Sendernamen, Hinweis H-5); Schlüsselbund ✅; Datei ✅. Es bleiben: Cache-Eintrag mit Token (BUG-06), Bytes in der Datei (BUG-07), verwaister Eintrag bei Altbestand (BUG-08), laufende Verbindungen mit Zugangsdaten (BUG-05), alles nach dem Löschen der App (BUG-09) |

## Fehler

### BUG-01 · Aktualisieren und Löschen großer Playlists blockieren die Oberfläche minutenlang — hoch

**Betrifft:** AK-37, AK-38 (FB-01); EC-02
**Reproduktion:**
1. Xtream-Playlist mit 17.000 Sendern importieren (Mock), einige Favoriten setzen
2. „Aktualisieren“ wählen (Liste unverändert)
3. Danach „Löschen“ wählen; zusätzlich: App neu starten und eine gleich große Playlist löschen
**Erwartet:** Die Oberfläche bleibt bedienbar (PRD: „bleibt auch bei Anbieterlisten mit mehr als 17.000 Sendern bedienbar“,
Website „Seventeen thousand channels, still usable“)
**Tatsächlich:** Die Oberfläche ist für die ganze Dauer blockiert (Main-Thread-Wachhund):

| 17.000 Xtream-Sender | Release-Build (`-O`) | Debug-Build | Rückerfassung (Debug) |
|---|---|---|---|
| Aktualisieren | **280,48 s** (Blockade 280,38 s) | 284,30 s (284,15 s) | 292,43 s |
| Löschen nach dem Aktualisieren | **132,60 s** | 122,51 s | 59,87 s |
| Löschen nach Neustart (Sender nicht geladen) | **41,31 s** | 118,51 s | – (69,81 s mit geladenen Sendern) |

Doppelte Senderzahl → ×3,6 Dauer (quadratisch); 4.000 Sender bereits 16 s. Der Release-Build ist nicht schneller.
Unter iOS droht die Beendigung durch das System, wenn die App währenddessen in den Hintergrund geht (nicht ausgeführt).
**Ort:** `Sources/Services/PlaylistImporter.swift:220-265` (`refresh` auf dem Main-Actor, lädt und löscht jeden Sender einzeln),
`:284-305` (`attach`: `Channel(playlist:)` + `playlist.channels.append` je Sender, Zeile 296/301), `:270-278` (`delete` kaskadiert
auf dem Main-Actor). Import über Xtream ist seit B01 BUG-12 blockweise im Hintergrund – Aktualisieren und M3U-Import nicht.
**Vorschlag:** Ersetzen und Löschen wie `persistXtreamPlaylist` in einem Hintergrund-Kontext blockweise (`append(contentsOf:)`,
Stapel-Löschen per Prädikat), Ansicht erst nach dem Speichern aktualisieren.
**Test:** `B03LeistungTests.testAK37_AK38_AktualisierenUndLoeschenBlockierenDenMainThread` (`XCTExpectFailure`, Grenze 1 s)

**Behoben 2026-09-26:** Ersetzen und Löschen laufen über `Services/PlaylistStore.swift` (Actor, eigener
`ModelContext`): Beziehung auf einmal lösen (`channels = []`), Sender löschen, neue per `append(contentsOf:)` – ein
Speichervorgang. Die Ansicht holt danach nur die Playlist neu ab (Millisekunden); die Playlist-Zeile selbst entfernt der
Kontext der Ansicht, damit `@Query` sofort stimmt. 17.000 Sender (Debug, Store-Datei): Aktualisieren M3U 4,09 s /
Xtream 4,13 s, längste Blockade 0,02 s (vorher 280 s); Löschen nach Aktualisieren 1,48 s / 1,47 s und nach Neustart
1,51 s / 1,53 s, Blockade 0,00 s (vorher 41–133 s). Nachweis:
`B03LeistungTests.testAK37_AK38_AktualisierenUndLoeschenBlockierenDenMainThreadNicht` (Standard 1.000/2.000,
Messlauf `TEST_RUNNER_B03_SIZES=17000`).

**Behoben 2026-09-27:** Reproduktion (Schritte 1–3) erneut ausgeführt mit dem QA-Test (`TEST_RUNNER_B03_SIZES=17000`,
`B03_KINDS=m3u,xtream`, `B03_RESTART_DELETE=1`; Store-Datei über `AppPersistence.diskContainer`, 17 Favoriten,
Main-Thread-Wachhund alle 20 ms):

| 17.000 Sender | Release (`-O`, `build/dd-release`), Lauf 1 / Lauf 2 | Debug (`build/dd-test`) | QA 1 Release (vorher) |
|---|---|---|---|
| Xtream aktualisieren | 6,43 s / 5,27 s · Blockade **0,00 s / 0,00 s** | 5,26 s · 0,02 s | 280,48 s · 280,38 s |
| Xtream löschen nach Aktualisieren | 2,48 s / 1,97 s · 0,01 s / 0,00 s | 1,86 s · 0,01 s | 132,60 s |
| Xtream löschen nach Neustart | 2,26 s / 2,05 s · 0,00 s / 0,01 s | 2,00 s · 0,00 s | 41,31 s |
| M3U aktualisieren | 5,36 s / 4,94 s · 0,00 s / 0,01 s | 7,51 s · 0,04 s | — |
| M3U löschen nach Aktualisieren | 1,85 s / 1,69 s · 0,00 s / 0,00 s | 2,51 s · 0,00 s | — |
| M3U löschen nach Neustart | 1,90 s / 1,87 s · 0,00 s / 0,00 s | 2,17 s · 0,00 s | — |

Favoriten jeweils 17 → 17, danach `ZPLAYLIST=0`, `ZCHANNEL=0`. Längste Blockade über alle Läufe 0,04 s (Debug) bzw. 0,01 s
(Release), vorher so lang wie der ganze Vorgang. Standardlauf im Gesamtlauf (1.000/2.000 Sender): Aktualisieren 0,30–0,67 s,
Löschen 0,12–0,29 s, Blockade 0,00–0,01 s. **Korrektur zum Vermerk vom 26.09.:** Die dort genannten Zeiten (Aktualisieren
4,09 s / 4,13 s, Löschen 1,47–1,53 s, Debug) sind in keinem erhaltenen Protokoll belegt; heute gemessen sind die Werte der
Tabelle, unter hoher Fremdlast (Last-Mittel 38–177 bei 16 Kernen). Die Blockade ist bestätigt.

### BUG-02 · Ein Favorit wird beim Aktualisieren zu mehreren — mittel

**Betrifft:** AK-10 (FB-02)
**Reproduktion:**
1. M3U mit „Sport HD“/„sport hd“ (ohne tvg-ID) und „Film HD“/„Film SD“ (tvg-ID `film.id`) importieren
2. „Sport HD“ und „Film HD“ (und zwei weitere) als Favorit markieren
3. Aktualisieren; die Quelle liefert zusätzlich „Film 4K“ mit `film.id`
**Erwartet:** 4 Favoriten, dieselben Sender
**Tatsächlich:** 7 Favoriten: zusätzlich „sport hd“, „Film SD“, „Film 4K“. Xtream: „Sport 1“ → 3 Favoriten
(`Sport 1 HD`, `Sport 1 4K` mit derselben `epg_channel_id`). Zwei gleichnamige „Kanal X“: 1 → 2
**Ort:** `Sources/Models/Channel.swift:49-52` (`favoriteKey` nicht eindeutig), `Sources/Services/PlaylistImporter.swift:253, 299`
**Vorschlag:** Wiedererkennung über einen eindeutigeren Schlüssel (z. B. `stream_id`/Adresse, erst ersatzweise tvg-ID/Name) und
höchstens so viele Favoriten je Schlüssel wie vorher.
**Test:** `B03AktualisierenTests.testAK10_EinFavoritWirdZuMehreren`

**Behoben 2026-09-26:** `FavoriteCarryOver` (in `PlaylistStore.swift`): Der Schlüssel (tvg-ID bzw. Name) entscheidet
weiter, **ob** ein neuer Sender Favorit werden darf (AK-09 unverändert); je Schlüssel werden höchstens so viele Sender
Favorit wie vorher, bevorzugt derselbe Sender (gleiche Stream-Adresse), dann gleicher Name, dann der erste Kandidat.
Nachweis: `B03AktualisierenTests.testAK10_EinFavoritBleibtEinFavorit` (4 → 4, Kanal X 1 → 1, Xtream 1 → 1),
`B03ReparaturTests.testBUG02_FavoritenUebernahmeRegeln`, B05 `testAK15_…` (M3U und Xtream), `B05TabTests.testEC01_…`.

**Behoben 2026-09-27:** Reproduktion (Schritte 1–3) erneut ausgeführt (`testAK10_EinFavoritBleibtEinFavorit`, Gesamtlauf):
M3U **4 → 4** Favoriten, genau „Alpha", „Film HD", „Gamma", „Sport HD" (vorher 7 mit „sport hd", „Film SD", „Film 4K"); zwei
gleichnamige „Kanal X": 1 → 1 (vorher 2); Xtream „Sport 1": 1 → 1 (vorher 3). AK-09 unverändert erfüllt (Wiedererkennung über
tvg-ID bzw. Namen: „Alpha Neu", „BETA"; Xtream „Kanal A (neu)", „Kanal B"). Der Vermerk vom 26.09. stimmt.

### BUG-03 · Ladeindikator nur für eine Playlist — mittel

**Betrifft:** AK-13 (FB-03)
**Reproduktion:**
1. Zwei Remote-Playlists; der Anbieter antwortet langsam (25 s bzw. 50 s)
2. Bei der ersten „Aktualisieren“ wählen, danach bei der zweiten
3. Warten, bis die erste fertig ist
**Erwartet:** Jede laufende Aktualisierung zeigt ihren Indikator, bis sie fertig ist (App-Shell: „Spinner in der betroffenen Karte“)
**Tatsächlich:** Während beide laufen, zeigt nur die zweite Karte einen Indikator; nach dem Ende der ersten zeigt keine Karte
einen, obwohl die zweite noch 25 s läuft
**Ort:** `Sources/Views/PlaylistsView.swift:11` (ein `refreshingID`), `:110-111` (`defer { refreshingID = nil }`)
**Vorschlag:** Menge laufender Playlist-IDs statt eines einzelnen Werts.
**Test:** `B03OberflaecheTests.testAK12_AK13_EC09_LadeindikatorBeiEinerUndZweiAktualisierungen`

**Behoben 2026-09-26:** `PlaylistsView` führt eine Menge laufender Aktualisierungen (`refreshingIDs`) statt eines
Werts; jede Karte zeigt ihren Indikator bis zum eigenen Ende (je Fenster, EC-09 unverändert). Nachweis:
`B03OberflaecheTests.testAK12_AK13_EC09_…` (beide laufen → 2 Indikatoren, erste fertig → 1).

**Behoben 2026-09-27:** Reproduktion (zwei Remote-Playlists, Anbieter antwortet verzögert, beide nacheinander aktualisieren)
im echten Fenster erneut ausgeführt: solange beide laufen **2** Indikatoren (vorher 1), nach dem Ende der M3U-Aktualisierung
**1** Indikator, während Xtream noch läuft (vorher 0); danach 0, kein Alert; zweites Fenster ohne Indikator, zeigt sofort
„QA Eins, 9 Sender" (EC-09). Abweichung zur Reproduktion: Der Anbieter antwortet nach 45 s / 55 s statt 25 s / 50 s (Begründung
im Build-Bericht, Annahme 20). Der Vermerk vom 26.09. stimmt.

### BUG-04 · Keine Sperre gegen mehrfaches Aktualisieren derselben Playlist — mittel

**Betrifft:** AK-14 (FB-04), Angriff 3
**Reproduktion:**
1. Xtream-Playlist; „Aktualisieren“ im Kontextmenü zehnmal hintereinander wählen
2. Anfragen am Anbieter zählen
**Erwartet:** Während eine Aktualisierung läuft, ist der Eintrag gesperrt oder die Wahl ohne Wirkung; Zugangsdaten gehen einmal raus
**Tatsächlich:** 30 von 30 Anfragen mit Benutzername und Passwort erreichen den Anbieter; bei M3U erzeugen drei Wahlen während
eines laufenden Abrufs drei Abrufe und drei Ersetzungen. Das Ergebnis bleibt richtig (7 Sender, Favorit bleibt), die Kosten
vervielfachen sich – bei großen Listen jeweils die Blockade aus BUG-01
**Ort:** `Sources/Views/PlaylistsView.swift:39-46` (Menüeintrag nie deaktiviert, ungebundene `Task`), `Sources/Services/PlaylistImporter.swift:220`
**Vorschlag:** Laufende Aktualisierungen je Playlist-ID merken, Menüeintrag deaktivieren und zweiten Aufruf verwerfen.
**Test:** `B03AktualisierenTests.testAK14_…`, `B03OberflaecheTests.testAK14_Angriff3_…`

**Behoben 2026-09-26:** Zwei Sperren: `PlaylistImporter.refreshing` (über alle Fenster; ein zweiter Aufruf für
dieselbe Playlist kehrt ohne Wirkung und ohne Anfrage zurück) und im Fenster ein deaktivierter Menüeintrag
„Aktualisieren", solange die Playlist läuft (`PlaylistsView.startRefresh` markiert sie schon vor dem Start der Aufgabe). Nachweis: `B03AktualisierenTests.testAK14_…Gesperrt` (M3U 1 Abruf, Xtream
3 Anfragen), `B03OberflaecheTests.testAK14_Angriff3_AktualisierenWaehrendDesLaufsGesperrt` (Eintrag gesperrt,
10 Wahlen → 3 Anfragen; Anbieterverzögerung im Test verlängert, damit alle Wahlen in den Lauf fallen, und 0,3 s
zwischen zwei Wahlen, damit das Menü neu gezeichnet ist).

**Behoben 2026-09-27:** Reproduktion (zehnmal „Aktualisieren" über das Kontextmenü einer Xtream-Playlist, Anfragen am Anbieter
zählen) im echten Fenster erneut ausgeführt: 10 Wahlen in 25,97 s → **3 Anfragen** mit Passwort, d. h. genau ein Aktualisieren
(vorher 30 von 30); M3U: der Eintrag ist ab der zweiten Wahl gesperrt (`isEnabled` true, false, false), **1 Abruf** (vorher 3),
7 Zeilen, Favorit bleibt, kein Alert. Über den Dienst gleichzeitig gestartet: M3U 2× → 1 Abruf, Xtream 3× → 3 Anfragen, Ergebnis
unverändert richtig (7 bzw. 4 Sender). Der Vermerk vom 26.09. stimmt.

### BUG-05 · Wiedergabe, Multiview und Senderliste halten gelöschte bzw. ersetzte Sender — mittel

**Betrifft:** AK-27, AK-28, AK-29 (FB-05)
**Reproduktion:**
1. Xtream-Playlist (HLS); Sender A im Player, Sender B im Multiview, Senderliste in einem weiteren Fenster offen
2. Playlist löschen
3. Zweiter Fall: Stream antwortet mit 404 → „Erneut versuchen“ erscheint; Playlist aktualisieren (bzw. löschen), dann „Erneut versuchen“ klicken
**Erwartet:** Nach dem Löschen enden Wiedergabe und Verbindungen mit Zugangsdaten, offene Ansichten zeigen, dass die Playlist weg
ist; nach dem Aktualisieren spielt „Erneut versuchen“ den Sender mit gültiger Adresse
**Tatsächlich:** Nach dem Löschen bleiben alle Verbindungen offen (Pfad `/live/qa-user/<pass>/…`), Player-Titel und Kachel
unverändert, Engine nicht pausiert; die Senderliste zeigt „· 9 SENDER“, alle Chips und „Diese Playlist enthält keine Sender.“.
„Erneut versuchen“ ruft nach dem Aktualisieren `/live/102.m3u8` **ohne** Zugangsdaten ab (der Anbieter lehnt ab); nach dem
Löschen lädt es bei M3U die alte Adresse erneut, bei Xtream je nach Lauf nichts oder die Adresse ohne Zugangsdaten – eine Meldung
erscheint in keinem Fall
**Ort:** `Sources/Services/MultiviewSession.swift:37-41`, `Sources/Views/PlayerView.swift:13, 45-51, 239-257` (Engine-Zustand
verdeckt `resolveError`), `Sources/Services/StreamURLResolver.swift:25` (ohne `playlist` → gespeicherte Adresse),
`Sources/Views/ChannelListView.swift:9, 18-21, 35`, `Sources/Services/PlaylistImporter.swift:256-259`
**Vorschlag:** Beim Löschen/Aktualisieren betroffene Sitzungen beenden bzw. Sender über ihre Stream-ID neu auflösen; Ansichten
über die Playlist-ID statt über gehaltene Objekte führen.
**Test:** `B03OberflaecheTests.testAK27_EC05_…`, `testAK28_PlayerUndMultiview…`, `testAK28_AK29_Erneut…`, `B03AktualisierenTests.testAK29_…`

**Behoben 2026-09-26:** `PlaylistEvents.willDelete` vor jedem Löschen: `PlayerView` beendet die Engine
(`PlaybackEngine.stop()`, neu: AVKit gibt das Element frei, VLC `stop()`), zeigt „Die Playlist dieses Senders wurde
gelöscht." und fragt beim „Erneut versuchen" nicht mehr an; `MultiviewSession` entfernt und beendet die Kacheln der
Playlist; `ChannelListView` zeigt „Playlist gelöscht" statt alter Senderzahl und Chips. `StreamURLResolver` schlägt die
Playlist über `playlistID` nach, dadurch spielt ein gehaltener Sender nach dem Aktualisieren mit Zugangsdaten.
Nachweis: `B03OberflaecheTests.testAK27_EC05_…`, `testAK28_PlayerUndMultiviewEndenMitDemLoeschen` (0 Verbindungen),
`testAK28_AK29_ErneutVersuchen…` (nach Löschen kein Abruf, nach Aktualisieren `/live/qa-user/<pass>/102.m3u8`),
`B03AktualisierenTests.testAK29_…MitZugangsdaten`, `B03ReparaturTests.testBUG05_…`. Laufende Kacheln nach dem
**Aktualisieren** bleiben bei der alten Adresse (B08 BUG-05, → spec.md OF-09).

**Behoben 2026-09-27 (Löschen und „Erneut versuchen"; laufende Wiedergabe beim Aktualisieren nicht, wartet auf OF-09):**
Reproduktion (Schritte 1–3) im echten Fenster erneut ausgeführt: Nach dem Löschen **0** offene Verbindungen (vorher 4 mit
`/live/qa-user/<pass>/…`), Multiview-Kacheln 0, Engine beendet (`idle`, pausiert), Datenbank 0; offene Senderliste zeigt
Fenstertitel „Playlist gelöscht" und „Diese Playlist wurde gelöscht. Ihre Sender sind nicht mehr verfügbar." statt „· 9 SENDER",
Chips und „Diese Playlist enthält keine Sender." „Erneut versuchen" nach dem Löschen: Xtream meldet „Die Playlist dieses
Senders wurde gelöscht." ohne neue Anfrage, M3U lädt nichts nach (2 → 2 Abrufe, vorher 2 → 4). Nach dem **Aktualisieren** ruft
„Erneut versuchen" `/live/qa-user/<pass>/102.m3u8` **mit** Zugangsdaten ab (vorher `/live/102.m3u8` ohne), ein gehaltener Sender
löst nach dem Aktualisieren weiter mit Zugangsdaten auf (`testAK29_…MitZugangsdaten`). Offen bleibt wie am 26.09. vermerkt:
Player und Kacheln, die beim Aktualisieren **laufen**, spielen die alte Adresse weiter (`B08SessionTests.testAK28_…` behält
sein `XCTExpectFailure`, schlägt darin weiter fehl) – Produktentscheidung OF-09. Der Vermerk vom 26.09. stimmt.

### BUG-06 · M3U-Adresse samt Token und Senderliste überstehen das Löschen im HTTP-Plattencache — mittel

**Betrifft:** AK-33 (FB-06); Angriff 8
**Reproduktion:**
1. M3U-Playlist von `http://<host>/list-<n>.m3u?token=<token>` importieren und aktualisieren
2. Playlist löschen
3. `select count(*) from cfurl_cache_response where instr(request_key, '<token>') > 0` auf `~/Library/Caches/<Bundle-ID>/Cache.db`
**Erwartet:** 0 – nach dem Löschen keine Kopie von Adresse und Senderliste
**Tatsächlich:** 1 Schlüssel mit Token, 1 Antwortkörper mit allen Sendernamen, `URLCache.shared` liefert die Antwort; unter
macOS für jeden Prozess des Benutzers lesbar (`-rw-r--r--`)
**Ort:** `Sources/Services/PlaylistImporter.swift:307-321` (`URLSession.shared`; `.reloadIgnoringLocalCacheData` verhindert nur
das Lesen), `:270-278` (`delete` räumt keinen Cache)
**Vorschlag:** M3U-Abruf über eine flüchtige Sitzung ohne `URLCache` wie `XtreamHTTPLoader`; beim Löschen eigene Einträge entfernen.
**Test:** `B03LoeschenTests.testAK33_…`

**Behoben 2026-09-26:** gemeinsam mit B02 · BUG-02 – M3U-Abrufe schreiben nicht mehr in den HTTP-Plattencache
(`PlaylistHTTPLoader`), `delete` entfernt einen etwaigen Alt-Eintrag der Adresse (auch der vollständigen mit
Zugangsdaten) und die Cookies des Hosts. Nachweis: `B03LoeschenTests.testAK33_M3UAdresseUndAntwortNichtImPlattencache`
(auf einen Temp-Ordner umgelenkter Cache: 0 Einträge, 0 Bytes vor und nach dem Löschen).

**Behoben 2026-09-27:** Reproduktion (M3U mit `?token=` importieren und aktualisieren, löschen, Cache abfragen) erneut
ausgeführt: vor und nach dem Löschen liefert `URLCache.shared` **keine** Antwort, 0 Bytes im Cache-Ordner (vorher 1 Schlüssel
mit Token, 1 Antwortkörper mit allen Sendernamen). Abweichung zur Reproduktion: Statt `~/Library/Caches/<Bundle-ID>/Cache.db`
der installierten App wird ein auf einen Temp-Ordner umgelenkter `URLCache.shared` abgefragt (der Test-Host teilt die
Bundle-ID mit der echten App, deren Cache nicht gelesen wird). Der Vermerk vom 26.09. stimmt.

### BUG-07 · Namen und Stream-Adressen gelöschter Sender bleiben als Bytes in der Datenbankdatei — niedrig

**Betrifft:** AK-34 (FB-07)
**Reproduktion:**
1. M3U- und Xtream-Playlist mit je 20 markierten Sendernamen anlegen, beide löschen
2. Container schließen, Datei neu öffnen und schließen („Neustart“)
3. Bytesuche nach den Marken in `MikaPlusPlayer.store`, `-wal`, `-shm`
**Erwartet:** 0 Vorkommen
**Tatsächlich:** M3U-Sendernamen 14, Stream-Adressen 14, Xtream-Sendernamen 40 (Rückerfassung: Xtream 0 – der Rest ist nicht
deterministisch); Playlistname und Token 0
**Ort:** `Sources/Services/PlaylistImporter.swift:270-278` (kein Verdichten); `AppPersistence.compactStore` (`AppPersistence.swift:344-354`)
läuft nur nach der Zugangsdaten-Umstellung
**Vorschlag:** Nach dem Löschen einer Playlist `secure_delete` bzw. `VACUUM` + `wal_checkpoint(TRUNCATE)` (im Hintergrund).
**Test:** `B03LoeschenTests.testAK34_…`

**Behoben 2026-09-26:** Nach jedem Löschen verdichtet `PlaylistStore.compact` die Datei (`VACUUM`,
`wal_checkpoint(TRUNCATE)` über `AppPersistence.compactStore`, abseits des Main-Actors). Nachweis:
`B03LoeschenTests.testAK34_KeineBytesGeloeschterSenderInDerDatei` (M3U-/Xtream-Namen und Adressen 0 nach Neustart),
`B03ReparaturTests.testBUG09_…`. Beim Aktualisieren wird nicht verdichtet (→ spec.md OF-10).

**Behoben 2026-09-27:** Reproduktion (Schritte 1–3) erneut ausgeführt, im Gesamtlauf und zusätzlich fünfmal hintereinander
(`-test-iterations 5`), weil der Rest in der QA nicht deterministisch war: jedes Mal M3U-Sendernamen **0**, Stream-Adressen
**0**, Xtream-Sendernamen **0** (vorher 14 / 14 / 40), Playlistname und Token 0, freie Seiten 0 – offen wie nach „Neustart".
Der Vermerk vom 26.09. stimmt.

### BUG-08 · Verwaister Schlüsselbund-Eintrag; Fehler beim Löschen werden verschwiegen — niedrig

**Betrifft:** AK-35 (FB-08), EC-08
**Reproduktion:**
1. Xtream-Playlist aus dem Altbestand (Zugangsdaten noch in `sourceURL`), Anbieter antwortet mit 1,5 s Verzögerung
2. „Aktualisieren“, nach 0,6 s „Löschen“
3. Schlüsselbund-Eintrag für die Playlist-ID lesen
**Erwartet:** kein Eintrag
**Tatsächlich:** Direkt nach dem Löschen kein Eintrag, nach Ende des Aktualisierens ein Eintrag mit dem Passwort, ohne Playlist
und ohne Weg, ihn in der App zu entfernen. Zusätzlich verwirft `PlaylistsView` jeden Fehler von `delete` (`try?`), ein
verweigerter Schlüsselbund-Zugriff bliebe unbemerkt (im Code nachvollzogen, nicht ausgeführt – EC-08)
**Ort:** `Sources/Services/PlaylistImporter.swift:242-245` (Speichern nach dem Netzabruf ohne Existenzprüfung), `:273-277`,
`Sources/Views/PlaylistsView.swift:106`
**Vorschlag:** Vor dem Speichern prüfen, ob die Playlist noch existiert; Fehler beim Löschen anzeigen; verwaiste Einträge beim Start entfernen.
**Test:** `B03AktualisierenTests.testAK35_…`

**Behoben 2026-09-26:** Der Schlüsselbund-Eintrag aus dem Altbestand wird im selben Schritt wie das Ersetzen
geschrieben und nur, wenn die Playlist dann noch existiert und nicht gerade gelöscht wird (`PlaylistStore.replaceChannels`,
`beginDelete`); `PlaylistsView` zeigt Fehler beim Löschen an (kein `try?` mehr, eigener Text, wenn nur der
Schlüsselbund-Eintrag bleibt). Nachweis: `B03AktualisierenTests.testAK35_…OhneVerwaistenEintrag`. Ältere verwaiste
Einträge entfernt nur „Alle Daten entfernen" (→ spec.md OF-08).

**Behoben 2026-09-27:** Reproduktion (Altbestand mit Zugangsdaten in `sourceURL`, Anbieter 1,5 s verzögert, „Aktualisieren",
nach 0,6 s „Löschen", Schlüsselbund lesen) erneut ausgeführt (`testAK35_…OhneVerwaistenEintrag`): direkt nach dem Löschen kein
Eintrag und **auch nach dem Ende des Aktualisierens keiner** (vorher Eintrag mit Passwort), 0 Playlists, 0 Sender. Der zweite
Teil (Fehler beim Löschen werden angezeigt) ist im Code nachvollzogen (`PlaylistsView.delete` ohne `try?`,
`PlaylistImporter.DeleteError`), ein verweigerter Schlüsselbund-Zugriff (EC-08) ist wie in der QA nicht ausgeführt. Der Vermerk
vom 26.09. stimmt.

### BUG-09 · Kein Weg, alle Daten zu entfernen; App löschen entfernt nicht alles — mittel

**Betrifft:** AK-36 (FB-09); Angriff 8
**Reproduktion:**
1. Hauptmenü und Übersicht nach einer Funktion „Alle Daten löschen“ durchsuchen
2. Speicherorte der App bestimmen und mit dem App-Bundle vergleichen
**Erwartet:** Ein Weg, alle gespeicherten Daten zu entfernen; die Datenschutzseite beschreibt, was nach dem Löschen der App bleibt
**Tatsächlich:** Kein solcher Weg. Datenbank (`~/Library/Application Support/lu.daumedia.MikaPlusPlayer/`), der seit B09 mögliche
Ordner `…/Beiseitegelegt/<Zeitstempel>/` mit einer vollständigen alten Datenbank, `Cache.db`, Einstellungen und
Schlüsselbund-Einträge liegen außerhalb des Bundles; das Löschen der App erreicht sie nicht. Website: „deleting the app removes
all of it“ (`web/app/privacy/page.tsx:39`, Stand heute). Das Deinstallieren selbst wurde nicht ausgeführt
**Ort:** keine Funktion in `Sources/`; Orte aus `AppPersistence.swift:140-172, 201-205`, `XtreamCredentialStore.swift:26-30`, `URLCache.shared`
**Vorschlag:** Einstellung/Menüeintrag „Alle Daten entfernen“ (Datenbank samt beiseitegelegter Kopien, Cache, Schlüsselbund-Dienst)
und die Website korrigieren.
**Test:** `B03LoeschenTests.testAK36_…`

**Behoben 2026-09-26:** „Alle Daten entfernen …" (macOS im App-Menü, iOS im Menü „…" der Übersicht) mit
Warnung; `Services/AppDataReset.swift` beendet Wiedergaben, löscht alle Playlists über denselben Weg (verdichtet), alle
Einträge des Schlüsselbund-Dienstes, den HTTP-Cache, die Cookies des Loaders, beiseitegelegte Datenbanken und die
Einstellungen der App. Nachweis: `B03LoeschenTests.testAK36_WegAlleDatenZuEntfernen` (Menüeintrag),
`B03ReparaturTests.testBUG09_AlleDatenEntfernen` (alles leer, 0 Bytes, Blockade 0,00 s). Website-Text gehört zu B10
(Teil 2); Ort und Umfang → spec.md OF-07.

**Behoben 2026-09-27 (App-Teil; Website-Aussage offen bei B10):** Reproduktion (Hauptmenü und Übersicht nach einem Weg
durchsuchen, Speicherorte bestimmen) erneut ausgeführt: Das Hauptmenü (116 Einträge) enthält **„Mika+Player › Alle Daten
entfernen …"** (vorher kein Eintrag). Der Weg selbst (`testBUG09_AlleDatenEntfernen`, Temp-Datenbank): danach 0 Playlists,
0 Sender, 0 Favoriten, 0 Einträge im Schlüsselbund-Testdienst, Ordner `Beiseitegelegt` entfernt, HTTP-Cache, Einstellung und
Cookies des Loaders (Test-Ziele) leer, 0 Namensbytes in der Datei, Blockade 0,00 s; offene Ansichten wurden vorher benachrichtigt. Nicht ausgeführt: der
Menüeintrag an der installierten App (würde deren Daten löschen) und der iOS-Eintrag im Menü „…" (nur gebaut). Das Löschen der App
selbst entfernt weiterhin nicht alles; die Aussage „deleting the app removes all of it" (`web/app/privacy/page.tsx`) gehört zu
B10. Der Vermerk vom 26.09. stimmt.

### BUG-10 · Löschen ohne Rückfrage und ohne Rückgängig — niedrig

**Betrifft:** AK-22 (OF-01)
**Reproduktion:**
1. Xtream-Playlist mit zwei Favoriten; Kontextmenü → „Löschen“
2. Bearbeiten › Widerrufen (`undo:`)
**Erwartet:** Rückfrage oder Rückgängig – Produktentscheidung offen (OF-01); mit der Playlist verschwinden Favoriten und Zugangsdaten
**Tatsächlich:** Sofort gelöscht (Datenbank 0/0, Schlüsselbund-Eintrag weg), kein Sheet; `undo:` behandelt niemand, kein `UndoManager`
**Ort:** `Sources/Views/PlaylistsView.swift:47-51, 104-107`; `Sources/App/MikaPlusPlayerApp.swift:36` (`.modelContainer` ohne Undo)
**Vorschlag:** Nach Entscheidung zu OF-01: `confirmationDialog` mit Hinweis auf Favoriten und Zugangsdaten.
**Test:** `B03OberflaecheTests.testAK22_AK24_…`, `B03LoeschenTests.testAK22_…`

**Nicht behoben:** wartet auf die Nutzerentscheidung OF-01 (Rückfrage oder Rückgängig). `testAK22_…` behält
`XCTExpectFailure`.

**Nicht behoben (geprüft 2026-09-27):** wartet weiter auf OF-01. Reproduktion im Gesamtlauf erneut ausgeführt: „Löschen" im
Menü löscht sofort (Datenbank 0/0, Schlüsselbund-Eintrag weg), kein Sheet, `undo:` behandelt niemand; die Erwartung in
`XCTExpectFailure` schlägt weiter fehl („Rückfrage oder Rückgängig"). Neu seit der Reparatur: Das Löschen läuft über den
zentralen Weg (Wiedergabe endet, Datei wird verdichtet) – an der fehlenden Rückfrage ändert das nichts.

### BUG-11 · Kürzere Liste ersetzt ohne Rückfrage, Favoriten kommen nicht zurück — niedrig

**Betrifft:** AK-11 (OF-02)
**Reproduktion:**
1. M3U mit 7 Sendern, 4 Favoriten
2. Quelle liefert vorübergehend nur „Beta“ → Aktualisieren
3. Quelle liefert wieder die volle Liste → Aktualisieren
**Erwartet:** Warnung oder Aufbewahrung der Favoriten – Produktentscheidung offen (OF-02); US-02 verspricht, Favoriten nicht neu setzen zu müssen
**Tatsächlich:** 7 → 1 → 7 Sender, Favoriten 4 → 0 → 0, keine Meldung
**Ort:** `Sources/Services/PlaylistImporter.swift:250` (prüft nur „nicht leer“), `:253-262`
**Vorschlag:** Nach Entscheidung zu OF-02.
**Test:** `B03AktualisierenTests.testAK11_…`

**Nicht behoben:** wartet auf die Nutzerentscheidung OF-02 (Warnung bei kürzerer Liste, Favoriten aufbewahren).
`testAK11_…` behält `XCTExpectFailure`.

**Nicht behoben (geprüft 2026-09-27):** wartet weiter auf OF-02. Reproduktion im Gesamtlauf erneut ausgeführt: 7 → 1 → 7 Sender,
Favoriten 4 → 0 → 0, keine Meldung; die Erwartung in `XCTExpectFailure` schlägt weiter fehl.

### BUG-12 · „Zugangsdaten fehlen“ führt nur über Löschen, das alle Favoriten kostet — niedrig

**Betrifft:** AK-21 (OF-06)
**Reproduktion:**
1. Xtream-Playlist mit zwei Favoriten; Schlüsselbund-Eintrag entfernen (wie nach Wiederherstellung auf neuem Gerät)
2. Aktualisieren → Meldung „… Bitte die Playlist löschen und neu importieren.“
3. Dem Rat folgen
**Erwartet:** Zugangsdaten neu eingeben, Favoriten bleiben – Produktentscheidung offen (OF-06, B01 OF-05/OF-09)
**Tatsächlich:** Nach Löschen und Neu-Import 0 Favoriten
**Ort:** `Sources/Services/PlaylistImporter.swift:233-237`, `Sources/Services/StreamURLResolver.swift:17`
**Vorschlag:** Nach Entscheidung zu OF-06.
**Test:** `B03AktualisierenTests.testAK21_…`

**Nicht behoben:** wartet auf die Nutzerentscheidung OF-06 (Zugangsdaten neu eingeben statt löschen).
`testAK21_…` behält `XCTExpectFailure`.

**Nicht behoben (geprüft 2026-09-27):** wartet weiter auf OF-06. Reproduktion im Gesamtlauf erneut ausgeführt: Meldung „Die
Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren.", nach Löschen und
Neu-Import Favoriten 2 → 0; die Erwartung in `XCTExpectFailure` schlägt weiter fehl.

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · CFNetwork schreibt Adressen mit Token/Passwort ins Systemprotokoll des Test-Hosts.** Bei „Host nicht erreichbar“
  steht `NSErrorFailingURLStringKey=…?token=…` bzw. `…&password=…` im Unified Log, weil die Schwärzung am Test-Host aus ist.
  Gleicher Befund wie B01 H-2; die App selbst protokolliert nichts. Prüfen an einer regulär gestarteten Release-App ohne
  Nutzerdaten (z. B. eigene Bundle-ID) – nicht Teil dieser QA.
- **H-2 · Doppelte `Playlist.id` löscht fremde Zugangsdaten.** Zwei Playlists mit derselben `id` (nur per Datenbank-Manipulation
  oder künftigem Fehler erreichbar, `id` ohne `@Attribute(.unique)`, DM-09): Löschen der einen entfernt den Schlüsselbund-Eintrag
  der anderen.
- **H-3 · „Löschen“ im Kontextmenü ist in AppKit nicht als destruktiv markiert.** Das von SwiftUI erzeugte `NSMenuItem` hat
  `isDestructive = false` und unterscheidet sich in keiner auslesbaren Eigenschaft von „Aktualisieren“. Ob es rot gezeichnet
  wird, zeigt nur eine Bildschirmaufnahme der laufenden App.
- **H-4 · Schreibsperre einer anderen Verbindung friert die Oberfläche ein.** Hält ein anderer Prozess die SQLite-Schreibsperre
  (z. B. ein Datenbank-Browser), wartet das abschließende `save()` des Aktualisierens auf dem Main-Thread – im Versuch über 5 min.
- **H-5 · Persistente Historie wächst mit jedem Löschen.** SwiftData führt `ACHANGE`/`ATRANSACTION` (73 → 115 Zeilen nach dem
  Löschen von 40 Sendern und 2 Playlists), ohne Nutzdaten, ohne Bereinigung; in `docs/datenmodell.md` nicht erwähnt.
- **H-6 · Sender ohne Namen teilen sich einen Favoriten-Schlüssel.** Seit B01 werden Xtream-Einträge mit `name: null` als Sender mit
  leerem Namen übernommen; ohne tvg-ID haben alle den Schlüssel `name:` – ein Stern auf einem wird beim Aktualisieren zu allen (BUG-02).
- **H-7 · Nach dem Schließen von Player und Multiview bleibt eine Verbindung offen.** Engines pausieren, die Session ist leer, am Mock
  bleibt aber eine Verbindung bestehen (lsof 4 → 2 Enden). Gehört zu B06/B08.

## Code-Review

`code-reviewer`-Agent über `PlaylistsView.swift`, `PlaylistImporter.swift` und die beteiligten Dateien. Funde nachgeprüft:

| Fund des Agenten | Nachprüfung | Ergebnis |
|---|---|---|
| `refresh`/`attach` quadratisch auf dem Main-Thread | ausgeführt (AK-37, AK-38) | bestätigt → BUG-01 |
| `try?` beim Löschen verschluckt Schlüsselbund-Fehler | Code nachvollzogen; Fehler nicht provozierbar, verwaister Eintrag über die Race belegt | bestätigt als Teil von BUG-08 |
| HTTP-Cache behält M3U-Adresse und Antwort | ausgeführt (AK-33) | bestätigt → BUG-06 |
| Favoriten vervielfachen sich | ausgeführt (AK-10) | bestätigt → BUG-02 |
| Kein `rollback()` bei gescheitertem `save()` in `refresh` | zwei Provokationsversuche ohne gescheitertes `save()` (EC-03) | nicht reproduziert, nicht als BUG geführt |

## Abweichung Spec ↔ Code

Rückmeldung an die Spezifikation (Stand `c01f1cf` + Reparatur B01); geprüft wurde der aktuelle Stand einschließlich Reparatur B09.

| Stelle | Spec sagt | Code tut (ausgeführt) |
|---|---|---|
| AK-28, letzter Satz | „Erneut versuchen“ meldet nach dem Löschen bei Xtream „Die Zugangsdaten … fehlen …“ | Keine Meldung: Die Fehleransicht der Engine hat Vorrang vor `resolveError` (`PlayerView.swift:45-51`). Je nach Lauf ist `channel.playlist` noch die gelöschte Playlist (Schlüsselbund leer → nichts passiert) oder `nil` (→ Abruf `/live/<id>.m3u8` ohne Zugangsdaten) |
| EC-06 | defekte Xtream-Einträge werden still übersprungen | nur Einträge ohne `stream_id`; `name: null` → Sender mit leerem Namen (`XtreamClient.swift:202-207`, B01-Reparatur) |
| AK-34 | gelöschte Xtream-Playlist hinterließ 0 Vorkommen | in diesem Lauf 40 Vorkommen der Xtream-Sendernamen; das Ergebnis ist nicht deterministisch |
| AK-06 | „Löschen“ ist als destruktiv gekennzeichnet | im erzeugten `NSMenuItem` nicht nachweisbar (H-3) |
| Kopf, 1.3, 5.2, AK-36, FB-09 | Speicherorte Datenbank, Schlüsselbund, `Cache.db` | **neu seit B09:** `Application Support/<Bundle-ID>/Beiseitegelegt/<Zeitstempel>/` mit einer unverändert verschobenen alten Datenbank (`AppPersistence.moveStoreAside`, `:140-172`), wenn sie sich nicht öffnen ließ; keine Funktion der App löscht sie |
| Fundstellen | `MikaPlusPlayerApp.swift:35`, `AppPersistence.swift:61-65`, `AppPersistence.swift:204-214` | jetzt `MikaPlusPlayerApp.swift:36` (Container aus `AppPersistence.openAppStore()`), Speicherort `AppPersistence.swift:201-205`, `compactStore` `:344-354`. Container mit versioniertem Schema und Migrationsplan, weiterhin ohne `UndoManager` (AK-22 unverändert) |
| AK-31 | Mitschnitt mit `log stream` nicht ausgeführt | ausgeführt (`log show`), CFNetwork-Zeilen mit Token/Passwort am Test-Host (H-1) |
| AK-38 | beide Messspalten mit geladenen Sendern | zusätzlich gemessen: Löschen nach „Neustart“ (Sender nicht geladen), siehe AK-38 |

## Neue Tests

Alle unter `Tests/B03/`, Testnamen mit AK-/EC-Nummer. Belege für Fehler sind mit `XCTExpectFailure("BUG-NN …")` markiert.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `B03QASupport.swift` | — | Mock-Verhalten (`B03QAPanel`), SQLite-/Bytesuche, Main-Thread-Wachhund, lsof, Fenster/Accessibility/Kontextmenü/Aufnahmen, Basisklasse mit Aufräumen |
| `B03AktualisierenTests.swift` | 20 | AK-07–AK-11, AK-14–AK-21, AK-26, AK-29, AK-30, AK-32, AK-35, EC-01–EC-03, EC-06, EC-07, EC-12 |
| `B03LoeschenTests.swift` | 10 | AK-22–AK-25, AK-31, AK-33, AK-34, AK-36; Angriff 1, 4, 5, 7, 8 |
| `B03OberflaecheTests.swift` | 11 | AK-01–AK-06, AK-12–AK-14, AK-18, AK-22, AK-24, AK-27–AK-29; EC-04, EC-05, EC-07, EC-09, EC-10; Angriff 3 |
| `B03LeistungTests.swift` | 1 | AK-37, AK-38 (Standard 1.000/2.000 Sender; Messläufe per `TEST_RUNNER_B03_SIZES`, `…_KINDS`, `…_RESTART_DELETE`, `…_EVIDENCE`) |

**Letzter Gesamtlauf** (2026-09-16 22:49–22:57, Debug, `build/dd-qa-b03`):

```
xcodebuild test-without-building -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' \
  -derivedDataPath build/dd-qa-b03 -only-testing:MikaPlusPlayerTests/B03AktualisierenTests \
  -only-testing:MikaPlusPlayerTests/B03LoeschenTests -only-testing:MikaPlusPlayerTests/B03OberflaecheTests \
  -only-testing:MikaPlusPlayerTests/B03LeistungTests
Test Suite 'B03AktualisierenTests' passed   Executed 20 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'B03LeistungTests' passed
Test Suite 'B03LoeschenTests' passed        Executed 10 tests, with 0 failures (0 unexpected)
Test Suite 'B03OberflaecheTests' passed     Executed 11 tests, with 0 failures (0 unexpected)
Executed 42 tests, with 1 test skipped and 0 failures (0 unexpected) in 473.793 (473.812) seconds
** TEST EXECUTE SUCCEEDED **
```

Messläufe für AK-37/AK-38 zusätzlich mit `TEST_RUNNER_B03_SIZES=1000,2000,4000` bzw. `=17000 TEST_RUNNER_B03_KINDS=xtream
TEST_RUNNER_B03_RESTART_DELETE=1` in Release (`build/dd-qa-b03-release`) und Debug; alle Zeilen mit Zeitpunkt, Konfiguration und
Last in `qa/AK-37-38-messung.txt`. Die übrigen Test-Suites des Projekts (B01, B09) liefen hier nicht mit; sie werden parallel von
deren QA-Runden ausgeführt. Build-Warnung aus `Tests/B03`: nur `CGWindowListCreateImage` veraltet (Fensteraufnahmen).

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Aktualisieren und Löschen großer Playlists blockieren den Main-Thread minutenlang, Aufwand wächst quadratisch (PRD/Website versprechen Bedienbarkeit bei 17.000 Sendern) | hoch | `Services/PlaylistImporter.swift:220-265, 270-278, 284-305` | BUG-01 |
| Ein Favorit wird beim Aktualisieren zu mehreren (nicht eindeutiger `favoriteKey`) | mittel | `Models/Channel.swift:49-52`, `Services/PlaylistImporter.swift:253, 299` | BUG-02 |
| Ladeindikator nur für die zuletzt gestartete Aktualisierung, verschwindet beim ersten Ende | mittel | `Views/PlaylistsView.swift:11, 110-111` | BUG-03 |
| Keine Sperre gegen mehrfaches Aktualisieren; jede Wahl sendet Zugangsdaten erneut (10× → 30 Anfragen) | mittel | `Views/PlaylistsView.swift:39-46`, `Services/PlaylistImporter.swift:220` | BUG-04 |
| Player, Multiview und Senderliste halten gelöschte/ersetzte Sender: Verbindungen mit Zugangsdaten laufen weiter, „Erneut versuchen“ ohne Zugangsdaten bzw. mit alter Adresse | mittel | `Services/MultiviewSession.swift:37-41`, `Views/PlayerView.swift:45-51, 239-257`, `Services/StreamURLResolver.swift:25`, `Views/ChannelListView.swift:9-35` | BUG-05 |
| M3U-Adresse samt Token und Senderliste bleiben nach dem Löschen im HTTP-Plattencache | mittel | `Services/PlaylistImporter.swift:307-321, 270-278` | BUG-06 |
| Namen und Stream-Adressen gelöschter Sender bleiben als Bytes in der Datenbankdatei | niedrig | `Services/PlaylistImporter.swift:270-278` | BUG-07 |
| Verwaister Schlüsselbund-Eintrag nach Löschen während des Aktualisierens (Altbestand); Löschfehler mit `try?` verworfen | niedrig | `Services/PlaylistImporter.swift:242-245`, `Views/PlaylistsView.swift:106` | BUG-08 |
| Kein Weg, alle Daten zu entfernen; Datenbank, beiseitegelegte Datenbank, Cache, Einstellungen, Schlüsselbund überdauern das Löschen der App (Website verspricht das Gegenteil) | mittel | keine Funktion; `Services/AppPersistence.swift:140-172, 201-205`, `web/app/privacy/page.tsx:39` | BUG-09 |
| Löschen ohne Rückfrage und ohne Rückgängig (OF-01) | niedrig | `Views/PlaylistsView.swift:47-51, 104-107` | BUG-10 |
| Kürzere Liste ersetzt ohne Rückfrage, Favoriten kommen nicht zurück (OF-02) | niedrig | `Services/PlaylistImporter.swift:250-262` | BUG-11 |
| Meldung „Zugangsdaten fehlen“ führt nur über Löschen, das die Favoriten kostet (OF-06) | niedrig | `Services/PlaylistImporter.swift:233-237` | BUG-12 |

## Nächster Schritt

`/sdd-build B03` mit dem Auftrag, BUG-01 bis BUG-12 zu beheben (BUG-10 bis BUG-12 erst nach Entscheidung zu OF-01, OF-02, OF-06),
danach erneut `/sdd-qa B03`. Wegen BUG-01 (hoch) **wartet die Erfassung der weiteren Bestandsfeatures**. Die Reparatur von BUG-01
betrifft auch den M3U-Import (B02, gleicher Pfad `attach`) und sollte dort mitgeprüft werden; BUG-05 berührt B06 und B08.
