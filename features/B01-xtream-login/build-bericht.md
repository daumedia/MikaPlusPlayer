# B01 · Xtream-Codes-Login — Build-Bericht

Durchlauf 1 · 2026-09-16 · Eingang: Fehlerauftrag (`qa-report.md`, Status `review`) · Branch `sdd/rueckerfassung`, nicht committet

## 1 · Umgesetzt

Die zwölf Befunde aus QA-Durchlauf 1 sind bearbeitet; elf vollständig, BUG-09 nur im eindeutigen Teil. Das
Xtream-Passwort (und der Benutzername, samt einer etwa eingegebenen Benutzerinfo `u:pw@`) liegt je Playlist im
Schlüsselbund. `Playlist.sourceURL` und `Channel.streamURL` enthalten kein Geheimnis mehr. Eine abspielbare Adresse
entsteht nur noch an **einer** Stelle, `StreamURLResolver`, beim Abspielen. Vorhandene Datenbanken werden beim ersten
Start ohne Datenverlust umgestellt, einschließlich Verdichten der Datei. Ein eingegebenes `https://` bleibt erhalten;
ohne Schema bleibt es bei `http://`, mit sichtbarem Hinweis im Sheet. Die Datenbank liegt app-eigen, eine vorhandene
`default.store` wird nur bei nachweislich eigenem Schema kopiert. Anfragen an `player_api.php` laufen ohne HTTP-Cache,
mit Größen-, Mengen- und Zeitgrenzen und ohne Weiterleitungen zu fremden Servern. Wiederholte Fehlanmeldungen werden
gebremst. Defekte Einträge kippen den Import nicht mehr. Doppelklick startet keinen zweiten Import, „Abbrechen" bricht
wirklich ab. Der Import von 17.000 Sendern dauert **2,26 s statt 285 s** und blockiert den Main-Thread höchstens 0,01 s.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 | hoch | behoben | `XtreamCredentialStore`, `XtreamCodes` (`XtreamStreamAddress`), `StreamURLResolver`, `PlaylistImporter` (Import, `refresh`, `delete`), `AppPersistence.migrateCredentials`, `PlayerView`, `MultiviewSession`, `PlaylistsView` | `testAK24_…` (0/1, 0/4 Zeilen, 0 Bytes), `B01ReparaturTests` (Schlüsselbund, Resolver, Aktualisieren, Migration Temp-DB, Altbestand), `testBUG01_MigrationMit17000Sendern` |
| BUG-02 | hoch | behoben | `XtreamCredentials.baseURL`, `ImportPlaylistView` (Hinweis) | `testAK12_HTTPSBleibtErhalten` (0 Klartext-Anfragen), `testEC07_…`, `testBUG02_HinweisAufUnverschluesselteUebertragung`, `XtreamCodesTests.testKeepsHTTPS` |
| BUG-12 | hoch | behoben | `PlaylistImporter.persistXtreamPlaylist` | `testEC20_GrosseSenderlisteBlockiertMainThreadNicht` (1.500/3.000/6.000 + Einzelmessung 17.000) |
| BUG-03 | mittel | behoben | `XtreamHTTPLoader` (ephemeral, ohne Cache), `AppPersistence.purgeLegacyHTTPCacheOnce` | `testAK25_…` (0 Schlüssel, 0 Körper), `testBUG03_AlterHTTPCacheWirdEinmaligGeleert` |
| BUG-04 | mittel | behoben | `AppPersistence.configuration/prepareStore`, `MikaPlusPlayerApp`, `AppEnvironment` | `testAK28_SpeicherortUndBackup`, `testBUG04_UebernahmeNurBeiEigenemSchemaKopierenDannLoeschen` |
| BUG-05 | mittel | behoben | `XtreamURLEncoding` | `testAK14b_…`, `testAK14cd_…`, `testAngriff07_…` (0 statt 6 Fehlfälle) |
| BUG-06 | mittel | behoben | `XtreamClient` (`LossyList`, `FlexibleID`) | `testEC11_…`, `testEC12_…` |
| BUG-07 | mittel | behoben | `XtreamLoginThrottle`, `XtreamClient` | `testFB04_…` (3 von 10 beim Panel), `testBUG07_BremseZaehltJePanel` |
| BUG-08 | mittel | behoben | `XtreamClient.Limits`, `XtreamHTTPLoader` | `testFB05_…`, `testEC17_TroepfelndesPanelWirdVonGesamtfristGestoppt` |
| BUG-11 | mittel | behoben | `ImportPlaylistView` (gebundene Aufgabe), `PlaylistImporter` (Abbruch vor dem Speichern), `XtreamHTTPLoader` | `testEC18_AbbrechenBrichtImportAb`, `testBUG11_AbgebrochenerImportLegtNichtsAn` |
| BUG-09 | niedrig | Teil Doppelklick behoben, Teil Dublette offen | `ImportPlaylistView.startXtreamImport` | `testEC19_…` (1 statt 2 Anfragen/Playlists); `testAK09_…` behält `XCTExpectFailure` |
| BUG-10 | niedrig | behoben | `XtreamHTTPLoader` (Weiterleitungen) | `testAK26_WeiterleitungZuFremdemZielWirdAbgebrochen` (Ziel 0 Anfragen) |

H-1 (Benutzerinfo geht beim Aktualisieren verloren, B03) entfällt durch BUG-01, H-3 ebenso. H-2 bleibt (siehe 2).

Tests: 16 der 17 `XCTExpectFailure`-Blöcke (in QA 1: 25 erwartete Fehlschläge) entfernt, die Assertions auf das behobene Verhalten umgestellt;
11 neue Tests in `Tests/B01/B01ReparaturTests.swift`, 1 in `B01LangsamTests` (Migration 17.000), 1 in
`B01OberflaecheTests` (HTTPS-Hinweis). Gesamt 83 Tests (QA 1: 70), 1 erwarteter Fehlschlag (BUG-09 Teil Dublette,
QA 1: 25), 1 übersprungen (AK-27, unverändert). Gesamtlauf und Ausgaben siehe *Verifikation*.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-09, Teil Dublette** — nicht behoben. Ob ein zweiter Import desselben Zugangs verhindert, gemeldet oder als
  Aktualisieren behandelt wird, ist Produktverhalten mit spürbarer Folge (OF-01). Belegt: `testAK09_…` legt weiterhin
  2 Playlists an (erwarteter Fehlschlag mit Grund markiert).
- **H-2 · Zugangsdaten im Unified Log bei aktivem Private-Data-Logging** — nicht in der App behebbar: Das
  Xtream-Protokoll verlangt Benutzer und Passwort in Query und Stream-Pfad, CFNetwork protokolliert Fehler-URLs selbst.
  AK-27 bleibt *nicht prüfbar* (Test übersprungen, wie in QA 1).
- **iOS nur gebaut, nicht ausgeführt.** Schlüsselbund mit Zugriffsklasse, Speicherort-Übernahme im App-Container und
  das Wegwischen des Sheets (Abbruch über `onDisappear`) sind auf iOS nicht zur Laufzeit geprüft; die Umgebung hat keine
  UI-Automatisierung für den Simulator (wie QA 1, AK-04).
- **Schlüsselbund-Abfrage nach Updates (macOS)** — nicht in der App lösbar. Die Mac-App ist ad-hoc signiert; der
  Data-Protection-Schlüsselbund ist ohne Team-Entitlement nicht nutzbar (belegt: `SecItemAdd` mit
  `kSecUseDataProtectionKeychain` → `-34018`). Einträge im Anmelde-Schlüsselbund vertrauen nur dem Build, der sie
  angelegt hat. Nach jedem Update ist deshalb zu erwarten, dass macOS beim ersten Abspielen/Aktualisieren einer
  Xtream-Playlist einmal nach dem Anmeldepasswort fragt (nicht nachgestellt: die Abfrage ist interaktiv, ein Update
  wurde nicht gefahren). Abhilfe braucht Developer-ID-Signatur (Apple-Team, Schlüssel) → OF-08, gehört zu B09.
- **Wiederherstellung auf neuem Gerät** — Folge von `…ThisDeviceOnly`: Playlists kommen zurück, Zugangsdaten nicht;
  die App meldet „Die Zugangsdaten dieser Xtream-Playlist fehlen …". Ein Weg zum Neueingeben ohne Löschen fehlt (OF-09,
  hängt an OF-05).
- **Nicht aus dem Fehlerauftrag, festgestellt:** M3U-Import (B02) und Aktualisieren (B03) legen Sender weiter auf dem
  Main-Actor und je Sender mit Beziehung an – derselbe quadratische Pfad wie vorher bei Xtream. Aktualisieren einer
  großen Xtream-Playlist blockiert die Oberfläche also weiterhin. Nicht gebaut (B02/B03), Hinweis für deren QA.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus) und zur Bestätigung durch den Nutzer.

1. **Schlüsselbund-Eintrag:** ein generisches Passwort je Playlist, Dienst `lu.daumedia.MikaPlusPlayer.xtream`, Konto =
   `Playlist.id`, Inhalt JSON (`host` = normalisierte Basis einschließlich Benutzerinfo, `username`, `password`), Label
   „Mika+Player – Xtream-Zugang", nicht synchronisiert.
2. **Zugriffsklasse `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:** *AfterFirstUnlock*, weil Import/Aktualisieren
   großer Listen über eine Bildschirmsperre laufen können (iOS, Hintergrund-Audio) und sonst beim Speichern scheitern;
   *ThisDeviceOnly*, damit das Passwort nicht über Backup oder iCloud-Schlüsselbund auf andere Geräte wandert. macOS
   wertet die Klasse im Anmelde-Schlüsselbund nicht aus (Attribut wird angenommen, aber nicht gespeichert); dort schützt
   die Zugriffsliste des Eintrags.
3. **Gespeicherte Adressen:** `sourceURL` = `http[s]://host[:port]/player_api.php`, `streamURL` =
   `http[s]://host[:port]/live/<stream_id>.<ext>` (ohne Benutzerinfo). Kein Schemawechsel, keine neuen Felder – eine
   SwiftData-Migration ist dadurch nicht nötig; die Umstellung ist eine reine Datenmigration.
4. **Altbestand:** Eine Xtream-Playlist, deren `sourceURL` noch `username`/`password` trägt, gilt als nicht umgestellt.
   Sie bleibt spielbar (Resolver reicht die alte Adresse durch) und wird beim nächsten Start oder beim Aktualisieren
   umgestellt. Scheitert der Schlüsselbund-Eintrag, bleibt sie unverändert.
5. **Umstellung synchron beim Start**, vor der Oberfläche (bewusst, auch nach Hinweis des Reviews: nebenläufig
   liefe sie gegen die gerade startende Oberfläche und eine zweite Verbindung verdichtet dieselbe Datei):
   17.000 Sender 2,4 s einmalig (Debug-Build), danach nichts
   mehr. Anschließend `VACUUM` + `wal_checkpoint(TRUNCATE)` über eine zweite SQLite-Verbindung, weil ohne Verdichten bei
   17.000 Sendern ein Vorkommen des Passworts in einer freigegebenen Seite blieb (gemessen, danach 0).
6. **Übernahme der `default.store`:** nur wenn die Store-Metadaten genau die Entitäten `Playlist` und `Channel` nennen
   **und** `isConfiguration(compatibleWithStoreMetadata:)` zutrifft; Kopie per `replacePersistentStore`, Kopie erneut
   geprüft, dann `destroyPersistentStore` und Entfernen von `default.store`/`-wal`/`-shm`. In allen anderen Fällen
   unangetastet. Existiert die neue Datei schon, wird die alte nie angefasst. Neuer Pfad:
   `Application Support/<Bundle-ID>/MikaPlusPlayer.store` (iOS im App-Container, macOS unter `~/Library`).
7. **Kein Backup-Ausschluss** der Datenbank: Nach BUG-01 enthält sie keine Zugangsdaten; ein Ausschluss nähme dem
   Nutzer beim Wiederherstellen die Playlists und Favoriten. Die Zugangsdaten selbst reisen wegen *ThisDeviceOnly* nicht mit.
8. **HTTP-Hinweis (BUG-02):** Footer „Ohne „https://“ gehen Benutzername und Passwort unverschlüsselt über das Netz.",
   sichtbar, solange der Host nicht mit `https://` beginnt (auch bei leerem Feld). Begründung: Der Befund nennt
   ausdrücklich das „ohne Hinweis". Kein automatischer HTTP-Rückfall bei TLS-Fehler (OF-10).
9. **Grenzen (BUG-08):** 60 s Leerlauf je Anfrage (unverändert, AK-20), 180 s gemeinsame Frist je Import, 64 MB je
   Antwort, 100.000 Einträge je Liste, Name/Gruppe/tvg-ID auf 512 Zeichen gekürzt, Logo-Adressen > 2.048 Zeichen
   verworfen (OF-12).
10. **Bremse (BUG-07):** je Panel (Schema/Host/Port), nach 3 Ablehnungen in Folge (`auth ≠ 1`, HTTP 401/403) 30 s,
    verdoppelnd bis 5 min, Erfolg setzt zurück, nur im Arbeitsspeicher (Neustart setzt zurück). Netzwerkfehler zählen nicht.
11. **Dekodierung (BUG-06):** Pflicht ist nur `stream_id`; `name: null` → `""` (wie ein leerer Name, EC-15);
    Kategorien ohne ID oder Namen werden übersprungen.
12. **Weiterleitungen (BUG-10):** erlaubt nur bei gleichem Schema, Host und Port; auch `http`→`https` auf demselben Host
    wird abgelehnt (anderer Port). Eigene Meldung ohne Host.
13. **Abbrechen (BUG-11):** bricht den Import ab statt ihn im Hintergrund fortzusetzen (Vorschlag der QA, passt zur
    Beschriftung) – auch noch während des blockweisen Speicherns; bereits gespeicherte Blöcke und der
    Schlüsselbund-Eintrag werden dann wieder entfernt.
14. **Speichern in Blöcken (BUG-12):** 5.000 Sender je Block. Nach dem ersten Block ist die Playlist in der Übersicht
    sichtbar, `channelCount` wächst mit (bei 17.000 Sendern vier Blöcke in ~2 s). Scheitert ein Block, wird die Playlist
    samt Sendern entfernt; ein Absturz mitten im Speichern kann eine unvollständige Playlist mit stimmigem
    `channelCount` hinterlassen. Nach dem Hintergrund-Speichern setzt der Hauptkontext `lastRefreshed` und speichert,
    damit `@Query`-Ansichten die neue Playlist sicher sehen.
15. **Test-Host:** erkannt über die XCTest-Umgebungsvariablen bzw. `XCTestCase`; er öffnet nur einen In-Memory-Container,
    nutzt je Lauf einen eigenen Schlüsselbund-Dienst `…xtream.tests.<UUID>` und führt weder Umstellung noch Cache-Leeren aus.
16. **Multiview:** Fehlen die Zugangsdaten, fügt „⊞" den Sender nicht hinzu (ohne Meldung, OF-11). Der Player zeigt die
    Meldung in seiner Fehleransicht; „Erneut versuchen" bildet die Adresse neu.
17. **Alter HTTP-Cache:** `URLCache.shared.removeAllCachedResponses()` einmalig, Merker `B01.legacyHTTPCachePurged` in
    `UserDefaults.standard`. Betrifft nur den Cache-Ordner der Bundle-ID; mitgeleert werden zwischengespeicherte Logos und
    M3U-Antworten (werden neu geladen).
18. **QA-Tests angepasst**, wo sie das fehlerhafte Ist festschrieben: Stream-Adressen werden über den Resolver geprüft;
    `testEC01_FragmentImHost` nutzt `http://` statt `HTTPS://`, weil `https` jetzt erhalten bleibt und der Mock kein TLS
    spricht; `testEC03`/`testEC05` prüfen die Rekonstruktion am Schlüsselbund statt an `sourceURL`; umbenannte Tests
    tragen das neue Verhalten im Namen. `MockXtreamServer` hat die Antwortart `.unsized` (ohne `Content-Length`) bekommen.

## 4 · Systemweite Änderungen

Über B01 hinaus wirksam:

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Views/PlayerView.swift` | B06, B07 | lädt nicht mehr `channel.streamURL`, sondern `StreamURLResolver.playableURL(for:)`; neuer Zustand `resolveError` mit Fehleransicht; „Erneut versuchen" bildet die Adresse neu |
| `Sources/Services/MultiviewSession.swift` | B08 | `add(_:)` lädt über den Resolver; ohne Adresse kein Slot |
| `Sources/Views/PlaylistsView.swift` | B03 | Löschen über `PlaylistImporter.delete(_:)`, entfernt bei Xtream auch den Schlüsselbund-Eintrag |
| `Sources/Services/PlaylistImporter.swift` | B03 | `refresh` liest die Zugangsdaten aus dem Schlüsselbund (bzw. stellt Altbestand um); neue Methode `delete(_:)`; `init` mit Standardparametern für Schlüsselbund, Grenzen, Bremse. `attach` (M3U, Refresh) unverändert |
| `Sources/App/MikaPlusPlayerApp.swift` | alle, **B09** | Container-Konfiguration kommt aus `AppPersistence.configuration(schema:)`, danach `AppPersistence.finishLaunch(container:storeURL:)`. Schema-Definition und `fatalError` unverändert an Ort und Stelle — **Hinweis für die B09-Reparatur (Schema-Migration):** ein `SchemaMigrationPlan` gehört an denselben `ModelContainer`-Aufruf; `AppPersistence.modelTypes` nennt die Modelltypen für die Schema-Prüfung der alten Datei und müsste bei neuen Entitäten mitgezogen werden |
| `Sources/Services/AppPersistence.swift` (neu) | alle | Speicherort `Application Support/<Bundle-ID>/MikaPlusPlayer.store` für die gesamte Datenbank; Übernahme der alten `default.store`; einmalige Umstellung; einmaliges Leeren von `URLCache.shared` |
| `Sources/App/AppEnvironment.swift` (neu) | alle Tests | Test-Host arbeitet mit In-Memory-Datenbank – gilt auch für `M3UParserTests`, `PlaybackEngineTests` und alle späteren Test-Suites |
| `Sources/Models/Playlist.swift`, `Channel.swift` | alle | nur Kommentare (Bedeutung von `sourceURL`/`streamURL`); **kein** Schemawechsel |
| Schlüsselbund | alle | neuer Dienst `lu.daumedia.MikaPlusPlayer.xtream` im Schlüsselbund des Nutzers |
| `UserDefaults` | alle | neuer Schlüssel `B01.legacyHTTPCachePurged` (bisher schrieb nur Sparkle `SU*`-Schlüssel) |
| `README.md` | Doku | Absatz „Xtream-Codes-Zugang nutzen": Schlüsselbund, Resolver, https statt „Rekonstruktion aus sourceURL" |
| `web/app/privacy/page.tsx` | **B10** | **von diesem Build nicht geändert; der Stand vom Build-Beginn ist jetzt veraltet:** „rewrites an https:// host to plain HTTP" und die Aussage zur Speicherung stimmen nicht mehr – für die B10-Reparatur |
| `CLAUDE.md` | Doku | nicht geändert; der Architekturteil erwähnt `StreamURLResolver`, Schlüsselbund und `AppPersistence` noch nicht (Vorschlag für den Orchestrator) |
| `features/B01-xtream-login/spec.md`, `design.md` | Doku | nur *Offene Fragen* ergänzt (OF-01, OF-02, OF-04 mit Vermerk; OF-08 bis OF-12 neu). Die Rekonstruktion beschreibt weiter das Ist von `c01f1cf` (z. B. `XtreamCredentials(playerAPIURL:)`, heute `init?(legacyPlayerAPIURL:)`, nur noch für die Umstellung) – Nachführen ist Sache von QA-Durchlauf 2 |
| `Tests/Support/MockXtreamServer.swift`, `B01TestSupport.swift` | Tests | Antwortart `.unsized`; Hilfen `playable`, `shortIdleLimits`, `B01TestClock`; Aufräumen des Test-Schlüsselbunddienstes je Test |

Nicht angefasst: `project.yml`, `MikaPlusPlayer.entitlements`, `Info.plist` (ATS bleibt offen, weil Streams ohne Schema
weiter über HTTP laufen), `SparkleUpdater.swift`, `appcast.xml`, `features/index.md`, `features/befunde.md`.
Während des Builds sind im Arbeitsbaum Änderungen unter `web/` entstanden (u. a. `package.json`/`package-lock.json`
Next 16.2.12 → 16.3.3, `app/privacy/page.tsx`, `lib/site.ts`, neu `lib/metadata.ts`) — **nicht durch diesen Build**;
offenbar parallel zur Zusage „Repository allein". Bitte vor dem Commit zuordnen.

## Unabhängiges Review

Ein `code-reviewer`-Agent hat die Quelltext-Änderungen ohne Kenntnis dieser Bewertung gelesen. Drei Funde:

| Fund | Bewertung | Folge |
|---|---|---|
| Abbruch während des blockweisen Speicherns wirkt nicht (`Task.detached` erbt den Abbruch nicht) | zutreffend; war als Annahme dokumentiert, widerspricht aber dem Sinn von BUG-11 | behoben: Abbruch wird an die Hintergrund-Aufgabe weitergereicht, Prüfung je Block, Aufräumen wie im Fehlerfall. Test `testBUG11_AbbruchWaehrendDesSpeicherns` (Abbruch nach dem ersten gespeicherten Block von 40.000 Sendern) |
| Rennen Abbruch/Start im `XtreamHTTPLoader`: Abbruch vor `resume()` könnte die Continuation nie auflösen | plausibel, Zeitfenster eng | behoben: Start und Abbruch unter derselben Sperre, Abbruch vor dem Start löst selbst auf. Test `testBUG11_LoaderEndetBeiAbbruchImmer` (200 Abbrüche zu wechselnden Zeitpunkten) |
| `VACUUM` synchron beim Start blockiert den Main-Thread | zutreffend, einmalig und gemessen (17.000 Sender: 2,4 s inkl. Umstellung) | nicht geändert, siehe Annahme 5 |

## Verifikation

Stand 2026-09-16, letzter Lauf nach allen Änderungen einschließlich der Review-Funde. Ausgaben gefiltert.

**Baseline vor der Reparatur** (`clean build-for-testing` macOS, `clean build` iOS): macOS
`** TEST BUILD SUCCEEDED **`, Warnungen nur in den QA-Testdateien (3 × `accessibilityAttributeValue` deprecated in
`B01OberflaecheTests.swift`, 1 × Sendable in `MockXtreamServer.swift`) und `appintentsmetadataprocessor`; iOS
`** BUILD SUCCEEDED **` mit `LSSupportsOpeningDocumentsInPlace`-Hinweis und `appintentsmetadataprocessor`. Keine
Warnung in `Sources/`.

**1 · Projekt erzeugen**

```
$ xcodegen generate            → exit 0
```

**2 · macOS-Tests** — `xcodebuild clean test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test`

```
Test Suite 'B01AdressbildungTests' passed   Executed 16 tests, with 0 failures (0 unexpected)
Test Suite 'B01ImportTests' passed          Executed 18 tests, with 0 failures (0 unexpected)
Test Suite 'B01LangsamTests' passed         Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'B01OberflaecheTests' passed     Executed 10 tests, with 0 failures (0 unexpected)
Test Suite 'B01ReparaturTests' passed       Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B01SicherheitTests' passed      Executed 10 tests, with 1 test skipped and 0 failures (0 unexpected)
Test Suite 'M3UParserTests' passed          Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'PlaybackEngineTests' passed     Executed 6 tests, with 0 failures (0 unexpected)
Test Suite 'XtreamCodesTests' passed        Executed 4 tests, with 0 failures (0 unexpected)
	 Executed 83 tests, with 1 test skipped and 0 failures (0 unexpected) in 177.796 (177.832) seconds
** TEST SUCCEEDED **
Expected failure in -[MikaPlusPlayerTests.B01ImportTests testAK09_DoppelterImportLegtZweitePlaylistAn]   (1 ×, BUG-09 Teil Dublette)
Test Case '-[MikaPlusPlayerTests.B01SicherheitTests testAK27_KeinPasswortImSystemprotokoll]' skipped
```

Warnungen im Lauf (`^/.*warning:`), unverändert gegenüber der Baseline, keine in `Sources/`:

```
Tests/B01/B01OberflaecheTests.swift:24:12: warning: 'accessibilityAttributeValue' was deprecated in macOS 10.10 …
Tests/B01/B01OberflaecheTests.swift:28:19: warning: 'accessibilityAttributeValue' was deprecated in macOS 10.10 …
Tests/B01/B01OberflaecheTests.swift:65:30: warning: 'accessibilityAttributeValue' was deprecated in macOS 10.10 …
Tests/Support/MockXtreamServer.swift:108:51: warning: capture of 's' with non-Sendable type 'NSArray' … (vorher Zeile 106)
```

Messwerte aus dem Lauf (`B01BUILD|…`, erfundene Zugangsdaten):

```
B01BUILD|EC-20|sender=1500|bytes=203681|gesamt=0.16s|maxMainThreadBlockade=0.00s|playlistID=1500|beziehung=1500
B01BUILD|EC-20|sender=3000|bytes=411811|gesamt=0.31s|maxMainThreadBlockade=0.00s|playlistID=3000|beziehung=3000
B01BUILD|EC-20|sender=6000|bytes=828061|gesamt=0.70s|maxMainThreadBlockade=0.00s|playlistID=6000|beziehung=6000
B01BUILD|MIGRATION|CredentialMigrationResult(migratedPlaylists: 3, rewrittenChannels: 5, failedPlaylists: 0)|dauer=0.09s
B01BUILD|MIGRATION|rawBytesOffen=["legacy.store-wal": 0, "legacy.store-shm": 0, "legacy.store": 0]
B01BUILD|MIGRATION-17000|CredentialMigrationResult(migratedPlaylists: 1, rewrittenChannels: 17000, failedPlaylists: 0)|dauer=2.38s|rawBytes=["legacy.store": 0, "legacy.store-wal": 0, "legacy.store-shm": 0]|favoriten=17
B01BUILD|AK-24|sourceRows=0|channelRowsWithPass=0/4|channelRowsWithUser=0|rawBytes=["b01-qa.store-wal": 0, "b01-qa.store-shm": 0, "b01-qa.store": 0]
B01BUILD|AK-12|https gegen Klartext-Mock|Netzwerkfehler: The request timed out.|anfragen=0
B01BUILD|AK-25|db=<Caches>/lu.daumedia.MikaPlusPlayer/Cache.db|keysOnDisk=0|bodiesWithPass=0|cachedResponses=0
B01BUILD|AK-25|nachLoeschenDerPlaylist|keysOnDisk=0
B01BUILD|AK-26|fremdesZiel|Netzwerkfehler: Der Anbieter leitet auf einen anderen Server weiter. Die Zugangsdaten wurden dorthin nicht gesendet.|quelle=1|ziel=0
B01BUILD|FB-04|versuche=10|beimPanelAngekommen=3|dauer=0.00s|meldungen=[… „Anmeldung fehlgeschlagen …", „Zu viele fehlgeschlagene Anmeldungen. Bitte in 30 Sekunden erneut versuchen." …]
B01BUILD|FB-05|antwortBytes=24000353|angelegt=8|gespeicherteNamensbytes=4096|dauer=0.0s
B01BUILD|EC-17|trickle|bytes=42|25.1s|Netzwerkfehler: Der Anbieter hat nicht innerhalb von 25 Sekunden vollständig geantwortet.|anfragen=["(ohne)"]
B01BUILD|BUG-11|speichern|CancellationError|senderVorAbbruch=5000|playlists=0|sender=0
B01BUILD|BUG-11|dienst|CancellationError|anfragen=1
B01BUILD|BUG-11|loaderAbbruch|beendet=200/200
```

**3 · Einzelmessung BUG-12 mit 17.000 erfundenen Sendern gegen den Mock** —
`TEST_RUNNER_B01_QA_EC20_SIZES=17000 xcodebuild test … -only-testing:MikaPlusPlayerTests/B01LangsamTests/testEC20_GrosseSenderlisteBlockiertMainThreadNicht`

```
B01BUILD|EC-20|sender=17000|bytes=2382311|gesamt=2.25s|maxMainThreadBlockade=0.01s|playlistID=17000|beziehung=17000
** TEST SUCCEEDED **
```

→ **17.000 Sender: 2,25 s gesamt, längste Main-Thread-Blockade 0,01 s (vorher 285,0 s / 284,88 s).** Debug-Build,
In-Memory-Store, gleiche Messmethode wie QA 1. In einer Vorab-Messung auf einer Store-Datei (statt In-Memory) mit
blockweiser Beziehung: 17.000 Sender 1,5 s.

**4 · iOS-Simulator-Build** — `xcodebuild clean build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
** BUILD SUCCEEDED **
warning: The application supports opening files, but doesn't declare whether it supports opening them in place. … (in target 'MikaPlusPlayer')   ← wie Baseline
appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found           ← wie Baseline
```

Keine neuen Warnungen auf beiden Plattformen. Protokolle vollständig nur im Scratchpad der Session.
Aufräumen: Die Tests löschen ihre Schlüsselbund-Einträge (eigener Dienst je Lauf bzw. je Test) und ihre Temp-Ordner.
Die Datenbank `~/Library/Application Support/default.store` und der Schlüsselbund-Dienst der App wurden weder gelesen
noch beschrieben; der Test-Host arbeitet jetzt im Speicher.
