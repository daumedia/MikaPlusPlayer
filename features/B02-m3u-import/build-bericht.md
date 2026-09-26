# B02 · M3U-Import und B03 · Playlist-Verwaltung — Build-Bericht (gemeinsam)

Durchlauf 1 · 2026-09-26 · Eingang: Fehlerauftrag (`qa-report.md` von B02 und B03, je Durchlauf 1), dazu B05 · BUG-01 und
BUG-11 (gleicher Pfad) · Branch `sdd/rueckerfassung`, nicht committet

> Gleicher Inhalt in `features/B02-m3u-import/build-bericht.md` und `features/B03-playlist-verwaltung/build-bericht.md`.
> B02 und B03 teilen Abruf, Anlegen, Aktualisieren und Löschen; nach dem Muster „Reparaturen je Importweg statt im
> gemeinsamen Pfad" (`features/befunde.md`) ist beides **einmal** repariert, nicht je Importweg.

## 1 · Umgesetzt

Alle Importwege (Xtream, M3U per URL, M3U-Datei, „Öffnen mit") und Aktualisieren und Löschen laufen jetzt über **einen**
Weg:

- **Abruf:** `PlaylistHTTPLoader` (bisher `XtreamHTTPLoader`, jetzt für alle): `ephemeral`-Session ohne Plattencache und
  ohne gemeinsamen Zugangsdatenspeicher, Cookies nur im Arbeitsspeicher, Größen- und Zeitgrenzen, bei M3U zusätzlich ein
  Mindestdurchsatz. Parsen, Aufbereiten und Datei-Lesen laufen abseits des Main-Actors.
- **Zugangsdaten:** Xtream wie seit B01. Neu: M3U-Adressen mit `username`/`password` oder `user:pass@` → Schlüsselbund
  (`M3USecret`), in Datenbank und Stream-Adressen nur Platzhalter (`M3UCredentials`); `StreamURLResolver` setzt sie beim
  Abspielen ein; vorhandene Datenbanken stellt `AppPersistence.migrateCredentials` beim Start um.
- **Schreiben:** nur noch `PlaylistStore` (Actor, eigener `ModelContext`): Anlegen in Blöcken mit Abbruch, Ersetzen in
  einem Speichervorgang mit Favoriten-Übernahme nach `FavoriteCarryOver`, Löschen der Sender im Hintergrund. Der Kontext
  der Ansicht holt danach nur die Playlist neu ab bzw. entfernt ihre Zeile (Millisekunden) – das stößt `@Query` an.
- **Löschen an einer Stelle** (`PlaylistImporter.delete`): Ansichten beenden Wiedergabe und Verbindungen
  (`PlaylistEvents`), Sender und Playlist werden entfernt, dann Schlüsselbund-Eintrag, Cache-Einträge der Adresse und
  Cookies des Hosts; zuletzt wird die Datei verdichtet. Fehler werden gemeldet. „Alle Daten entfernen" nutzt denselben Weg.

17.000 Sender (Debug, Store-Datei, gleiche Messung wie die QA): Import per URL 2,36 s, per Datei 2,42 s, Xtream 2,22 s;
Aktualisieren 4,09 s (M3U) / 4,13 s (Xtream); Löschen 1,47–1,53 s. Längste Main-Thread-Blockade **0,02 s**
(vorher: Import 282 s, Aktualisieren 280 s, Löschen 41–133 s). Tabelle unter *Verifikation*.

| BUG | Grad | Ergebnis | Wo | Nachweis (Test) |
|---|---|---|---|---|
| B02 BUG-01 | hoch | behoben | `M3UCredentials` (neu), `XtreamCredentialStore` (`saveM3U`/`loadM3U`), `PlaylistImporter`, `StreamURLResolver`, `AppPersistence.migrateCredentials` | `B02SicherheitTests.testAK34_…ImSchluesselbund` ×2, `B02ReparaturTests.testBUG01_*` ×4 (inkl. Temp-Datenbank und v1.1-Vorlage) |
| B02 BUG-04 | hoch | behoben | `PlaylistImporter` (`loadM3U`/`loadFile`/`prepare` `nonisolated`), `PlaylistStore.create` | `B02LangsamTests.testAK40_…` (17.000: 0,00 s), `B02ReparaturTests.testBUG04_…` |
| B02 BUG-02 | mittel | behoben | `PlaylistHTTPLoader` (neu benannt, Weiterleitungsregel je Anfrage), Merker `B02.legacyHTTPCachePurged`, `PlaylistImporter.delete` | `testAK35_KeinPlattencacheFuerM3UAbrufe`, `testAK42_…`, `B02URLImportTests.testAK36_…` |
| B02 BUG-03 | mittel | behoben | `PlaylistImporter.M3ULimits`, `M3UParser.Limits`, `PlaylistHTTPLoader.Throughput` | `testAK37_…MitGrenze`, `B02LangsamTests.testAK12_AK28_AK38_EC17_…`, `B02ParserTests.testEC13_…`, `B02ReparaturTests.testBUG03_…` |
| B02 BUG-05 | mittel | behoben | `M3UParser.streamSchemes`/`logoSchemes` | `testAK39_NurErlaubteSchemataWerdenGespeichert`, `B02ParserTests.testEC10_…`/`testEC11_…`, `B02DateiImportTests.testEC10_…` |
| B02 BUG-06 | mittel | behoben | `PlaylistDocumentHandler` (neu), `MikaPlusPlayerApp` (`handlesExternalEvents`), `Info.plist` | `B02OberflaecheTests.testAK31_OeffnenEreignisImportiertImOffenenFenster` |
| B02 BUG-08 | mittel | behoben | `ImportPlaylistView.startImport`, `PlaylistStore.create` (Abbruch je Block) | `testAK29_EC21_AbbrechenBrichtURLImportAb`, `testAK16_AK27_AK29_DateiImportUeberDialog` |
| B02 BUG-07 | niedrig | behoben | `Info.plist` (`public.text` entfernt) | `testAK31d_AK32_OeffnerRegistrierung` |
| B02 BUG-09 | niedrig | behoben | `ImportPlaylistView.startImport` | `testAK30_DoppelklickAufVonURLImportierenEinImport` |
| B03 BUG-01 | hoch | behoben | `PlaylistStore` (neu), `PlaylistImporter.refresh`/`delete` | `B03LeistungTests.testAK37_AK38_…BlockierenDenMainThreadNicht` (17.000: 0,02 s / 0,00 s) |
| B03 BUG-02 | mittel | behoben | `FavoriteCarryOver` (in `PlaylistStore.swift`), `Channel.favoriteKey(name:tvgID:)` | `B03AktualisierenTests.testAK10_EinFavoritBleibtEinFavorit`, `B03ReparaturTests.testBUG02_…` |
| B03 BUG-03 | mittel | behoben | `PlaylistsView` (`refreshingIDs`) | `B03OberflaecheTests.testAK12_AK13_EC09_…` |
| B03 BUG-04 | mittel | behoben | `PlaylistImporter.refreshing`, `PlaylistsView` (Eintrag gesperrt) | `B03AktualisierenTests.testAK14_…Gesperrt`, `B03OberflaecheTests.testAK14_Angriff3_…Gesperrt` |
| B03 BUG-05 | mittel | behoben (Löschen; Aktualisieren: „Erneut versuchen") | `PlaylistEvents` (neu), `PlayerView`, `MultiviewSession`, `ChannelListView`, `PlaybackEngine.stop()`, `StreamURLResolver` | `B03OberflaecheTests.testAK27_…`, `testAK28_…EndenMitDemLoeschen`, `testAK28_AK29_…`, `B03AktualisierenTests.testAK29_…`, `B03ReparaturTests.testBUG05_…` |
| B03 BUG-06 | mittel | behoben | wie B02 BUG-02 | `B03LoeschenTests.testAK33_M3UAdresseUndAntwortNichtImPlattencache` |
| B03 BUG-09 | mittel | behoben | `AppDataReset` (neu), Menü „Alle Daten entfernen …" (macOS App-Menü, iOS Übersicht) | `B03LoeschenTests.testAK36_WegAlleDatenZuEntfernen`, `B03ReparaturTests.testBUG09_AlleDatenEntfernen` |
| B03 BUG-07 | niedrig | behoben | `PlaylistStore.compact` nach jedem Löschen | `B03LoeschenTests.testAK34_KeineBytesGeloeschterSenderInDerDatei` |
| B03 BUG-08 | niedrig | behoben | `PlaylistStore.replaceChannels` (Schlüsselbund nur bei existierender Playlist), `PlaylistsView` (Fehler anzeigen) | `B03AktualisierenTests.testAK35_…OhneVerwaistenEintrag` |
| B03 BUG-10 | niedrig | **nicht behoben** | — | wartet auf OF-01; `XCTExpectFailure` bleibt |
| B03 BUG-11 | niedrig | **nicht behoben** | — | wartet auf OF-02; `XCTExpectFailure` bleibt |
| B03 BUG-12 | niedrig | **nicht behoben** | — | wartet auf OF-06; `XCTExpectFailure` bleibt |
| B05 BUG-01 (= B03 BUG-02, BF-53) | mittel | behoben | wie B03 BUG-02 | `B05AktualisierenTests.testAK15_…M3U`/`…Xtream`, `testAK19_…`, `B05TabTests.testEC01_…` |
| B05 BUG-11 (BF-90) | mittel | behoben | `PlaylistStore.replaceChannels` (ein Speichervorgang, Rückrollen im eigenen Kontext), `PlaylistStoreError` | `B05AktualisierenTests.testAK17_Randfall_…` mit Datenträgerabbild (siehe *Verifikation*) |

Reihenfolge der Arbeit: hoch (B02 BUG-01, BUG-04, B03 BUG-01) zuerst, weil der gemeinsame Pfad alle anderen trägt;
dann mittel, dann niedrig. Jeder BUG war vor der Änderung über seinen QA-Test reproduziert (Ausgangslauf, siehe
*Verifikation*: die `XCTExpectFailure`-Blöcke schlugen erwartungsgemäß fehl) und ist danach mit dem umgestellten Test
erneut ausgeführt.

**Tests.** Entfernt: alle 12 `XCTExpectFailure`-Blöcke von B02, 13 von 16 in B03 (es bleiben BUG-10, -11, -12), in B05
die Blöcke zu BUG-01 (3) und BUG-11 (1) sowie die nicht strikte Erwartung zu BUG-10 (gleiche Ursache wie B03 BUG-07),
in B08 der Block zu BUG-05 (Teil Löschen). Die Assertions stehen auf dem behobenen Verhalten; Ist-Assertions, die den
Fehler festschrieben, sind ersetzt, nicht gelockert. Neu: `Tests/B02/B02ReparaturTests.swift` (7 Tests),
`Tests/B03/B03ReparaturTests.swift` (3 Tests). Umbenannt (Name beschrieb den Fehler): siehe Annahme 20.

## 2 · Offene Kriterien und nicht behobene BUGs

- **B03 BUG-10, BUG-11, BUG-12** — nicht behoben, wartet auf die Nutzerentscheidungen OF-01 (Rückfrage/Rückgängig beim
  Löschen), OF-02 (kürzere Liste, Favoriten aufbewahren) und OF-06 (Zugangsdaten neu eingeben). Produktverhalten mit
  spürbarer Folge. Belegt: die drei Tests behalten ihr `XCTExpectFailure` und schlagen darin weiter fehl.
- **B02 AK-13, AK-15** (OF-02, OF-01) — zurückgestellt wie in der QA, unverändert.
- **Laufende Wiedergabe beim Aktualisieren** (Teil von B03 BUG-05, B08 BUG-05): Player und Multiview-Kacheln spielen die
  alte Adresse weiter; nur „Erneut versuchen" nimmt den neuen Stand (mit Zugangsdaten). Ob laufende Streams umschalten
  oder enden sollen, ist Produktverhalten → B03 spec.md OF-09. `B08SessionTests.testAK28_…` behält sein `XCTExpectFailure`.
- **iOS nur gebaut, nicht bedient:** Dokument-Handler („Öffnen in"), das Menü „…" mit „Alle Daten entfernen …" und die
  Rückfrage sind unter iOS nicht zur Laufzeit geprüft (keine Tipp-Automatisierung, wie in der QA).
- **Finder-Doppelklick:** Die App importiert jetzt, wenn sie eine Datei bekommt. Ob ein Doppelklick Mika+Player oder
  Music.app startet, entscheidet LaunchServices (Rang `Default` unverändert) → B02 spec.md OF-13; die Website-Aussage
  gehört zu B10.
- **CFNetwork-Protokollzeilen mit Zugangsdaten** bei aktivem Private-Data-Logging (B02 H-4, B01 BF-43) — nicht in der App
  lösbar, solange Anbieter Zugangsdaten in URLs verlangen.
- **Website** (B10, Teil 2): Datenschutzseite (M3U-Zugangsdaten, Cache, Cookies, „deleting the app removes all of it",
  neuer Weg „Alle Daten entfernen") und die Doppelklick-Aussage sind hier nicht geändert.
- **Schlüsselbund-Waisen aus der Zeit vor dieser Reparatur** entfernt nur „Alle Daten entfernen" (→ B03 spec.md OF-08).
- **Release-Messung** der QA (Konfiguration Release) nicht wiederholt; gemessen ist Debug wie die QA-Standardläufe.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus), zur Bestätigung durch den Nutzer.

1. **Welche M3U-Zugangsdaten:** Query `password` (nicht leer) samt `username`, oder Benutzerinfo mit Passwort. `token=`
   und ähnliche Parameter bleiben in der Adresse (→ B02 OF-10).
2. **Platzhalter statt Streichen:** In `sourceURL` und Stream-Adressen stehen `_mikaplus_{pfad,query,info}_{benutzer,passwort}_`
   (nur nicht reservierte Zeichen). Ersetzt wird jeder Pfadabschnitt und Query-Wert, der dem Passwort entspricht, der
   Benutzername nur direkt vor dem Passwort, in `username`/`user` oder in der Benutzerinfo. Die Wiederherstellung kodiert
   kanonisch (Pfad wie `XtreamURLEncoding.pathSegment`, Query ohne `& = + #`); ungewöhnlich kodierte Originale können
   dadurch anders kodiert zurückkommen. Die eingegebene Adresse selbst liegt unverändert im Schlüsselbund und wird beim
   Aktualisieren genau so abgerufen.
3. **Ein Schlüsselbund-Dienst für alle Playlists** (`lu.daumedia.MikaPlusPlayer.xtream`, Name aus B01 beibehalten), Label
   „Mika+Player – Playlist-Zugang" für M3U. Kein Schemawechsel: Umstellung ist eine reine Datenmigration (wie B01), der
   `SchemaMigrationPlan` bleibt bei V1; geprüft mit Temp-Datenbank und v1.1-Vorlage.
4. **Grenzen M3U:** 64 MB je Antwort/Datei (Datei vor dem Lesen), 100.000 Sender, 180 s Gesamtfrist, 60 s Leerlauf
   (unverändert, AK-28), Mindestdurchsatz 2 KiB/s ab 20 s nach Beginn der Antwort (sonst endet eine tröpfelnde Antwort
   erst nach der Gesamtfrist), Name/Gruppe/tvg-ID 512 Zeichen, Stream-Adresse 4.096, Logo 2.048 (→ B02 OF-11).
5. **Schemata:** Streams `http https rtsp rtsps rtmp rtmps rtp udp mms mmsh`, Logos `http https`; gilt auch für lokale
   Dateien (→ B02 OF-12).
6. **Weiterleitungen M3U** folgen wie bisher auch zu anderen Hosts (AK-11); nur Xtream bleibt beim selben Panel.
7. **Cookies** bleiben für die Laufzeit im Arbeitsspeicher des Loaders (AK-36: „beim nächsten Abruf desselben Hosts"),
   nicht mehr im gemeinsamen `HTTPCookieStorage`; beim Löschen einer Playlist werden die Cookies ihres Hosts entfernt.
8. **Cache:** Merker für das einmalige Leeren umbenannt (`B02.legacyHTTPCachePurged`), damit Einträge, die M3U-Abrufe bis
   heute geschrieben haben, einmal mehr entfernt werden; Löschen entfernt zusätzlich einen Alt-Eintrag der Adresse aus
   `URLCache.shared`. Im Test-Host ist das der Cache-Ordner der installierten App (dort nur Einträge der Test-Adressen auf
   127.0.0.1 mit Zufallsports).
9. **Hintergrund-Schreibweg:** ein globaler Actor für alle Schreibvorgänge (serialisiert Löschen und Ersetzen). Anlegen in
   Blöcken zu 5.000 (wie B01); Ersetzen in **einem** Speichervorgang, damit ein Fehler die alte Liste vollständig lässt
   (AK-18, B05 BUG-11).
10. **Ansicht nach dem Hintergrund-Schreiben:** Der Kontext der Ansicht ruft die Playlist neu ab (aktualisiert Attribute und
    Beziehung des gehaltenen Objekts), setzt die angezeigten Werte (`channelCount`, `sourceURL`, `lastRefreshed`) noch
    einmal – das meldet die Änderung an Ansichten, die die Playlist beobachten (Kopfzeile der offenen Senderliste) – und
    speichert, damit `@Query`-Ansichten neu laden. Scheitert nur dieses Speichern, wird es verworfen; die Daten sind dann
    schon gespeichert.
11. **Löschen in zwei Schritten:** Sender im Hintergrund (schwer), die Playlist-Zeile im Kontext der Ansicht (leicht, stößt
    `@Query` an). Scheitert der zweite Schritt, bleibt eine Playlist mit 0 Sendern und eine Meldung; erneutes Löschen geht.
12. **Favoriten-Übernahme** (`FavoriteCarryOver`): Schlüssel wie bisher (AK-09), je Schlüssel höchstens so viele Favoriten
    wie vorher; Auswahl gleiche Stream-Adresse → gleicher Name → erster Kandidat in Anbieterreihenfolge. Sender-IDs werden
    weiter bei jedem Aktualisieren neu vergeben (AK-07 unverändert).
13. **Sperre beim Aktualisieren:** global je Playlist-ID; ein zweiter Aufruf kehrt still zurück (keine Meldung). Der
    Indikator bleibt je Fenster (EC-09); der Menüeintrag ist in dem Fenster gesperrt, das die Aktualisierung gestartet hat,
    und wird schon vor dem Start der Aufgabe gesperrt (wie `isImporting` im Sheet).
14. **Beim Löschen** meldet `PlaylistEvents.willDelete` die Playlist; Player: Engine beendet (`stop()`: AVKit gibt das
    Element frei, VLC `stop()`), Meldung „Die Playlist dieses Senders wurde gelöscht.", „Erneut versuchen" bleibt sichtbar
    und meldet dasselbe ohne Anfrage. Multiview: Kacheln der Playlist entfernt. Senderliste: Zustand „Playlist gelöscht"
    ohne Kopfzeile und Chips, Fenstertitel „Playlist gelöscht". Während des Löschens öffnet kein Sender der Playlist eine
    Wiedergabe mehr (Resolver).
15. **Resolver:** Die Beziehung bleibt maßgeblich (kein Sender bekommt Zugangsdaten einer anderen Playlist, auch nicht über
    eine manipulierte `playlistID`, B06-Angriffstest); ob die Playlist noch existiert, wird über die `persistentModelID`
    nachgeschlagen, ohne Attribute einer gelöschten Playlist zu lesen.
16. **„Öffnen mit"/Doppelklick** importiert sofort (ohne Sheet), im offenen Fenster; nur `public.m3u-playlist` (deckt
    `.m3u`/`.m3u8`), Rolle `Viewer`, Rang `Default` unverändert. `LSSupportsOpeningDocumentsInPlace = YES` (NO lehnt Xcode
    für macOS ab); eine etwaige iOS-Kopie in `Documents/Inbox` wird nach dem Import entfernt. Fehler als Alert „Import
    fehlgeschlagen".
17. **„Alle Daten entfernen"**: macOS im App-Menü nach „Einstellungen" (Position von „Nach Updates suchen …" unverändert,
    B09 AK-01), iOS im Menü „…" der Übersicht; Warnung mit zerstörender Standardtaste, kein Rückgängig. Umfang: alle
    Playlists (Datei danach verdichtet), alle Einträge des Schlüsselbund-Dienstes, `URLCache.shared`, Cookies des Loaders,
    Ordner `Beiseitegelegt` (B09), Einstellungen der App (Domäne der Bundle-ID, auch Sparkle). Im Test-Host bleiben
    Einstellungen und Cache der installierten App unangetastet (→ B03 OF-07).
18. **Verdichten nach jedem Löschen**, nicht nach dem Aktualisieren (→ B03 OF-10). 17.000 Sender: Löschen einschließlich
    `VACUUM` 1,5 s im Hintergrund.
19. **Fehlertexte** neu: „Die Playlist konnte nicht gespeichert werden. Die bisherige Senderliste bleibt erhalten. Bitte
    freien Speicherplatz prüfen und erneut versuchen.", „Die Zugangsdaten dieser Playlist fehlen auf diesem Gerät. …",
    „Netzwerkfehler: Die Playlist ist zu groß (mehr als 64 MB).", „Die Datei ist zu groß (mehr als 64 MB).", „Netzwerkfehler:
    Der Server hat die Playlist nicht innerhalb von 180 Sekunden vollständig geliefert.", „Netzwerkfehler: Der Server
    liefert die Playlist zu langsam.", „Die Senderliste ist zu groß (mehr als 100.000 Sender).", „Die Playlist wurde
    gelöscht, ihre Zugangsdaten konnten aber nicht aus dem Schlüsselbund entfernt werden. …", „Die Playlist dieses Senders
    wurde gelöscht."
20. **QA-Tests angepasst**, wo sie das fehlerhafte Ist festschrieben (Ist-Assertion → behobenes Verhalten):
    umbenannt `testAK34_…ImKlartext` → `…ImSchluesselbund` (×2), `testAK35_PlattencacheBehaelt…` →
    `testAK35_KeinPlattencacheFuerM3UAbrufe`, `testAK37_…OhneGrenze` → `…MitGrenze`, `testAK39_BeliebigeSchemata…` →
    `testAK39_NurErlaubteSchemata…`, `testAK42_…ErstNachDemSchliessen` → `testAK42_LoeschenLaesstKeineZugangsdatenZurueck`,
    `testEC13_…Ungekuerzt` → `…WerdenBegrenzt`, `testAK29_EC21_…NichtAb` → `…Ab`, `testAK30_…` → `…EinImport`,
    `testAK31_OeffnenEreignisErzeugtLeeresFenster…` → `…ImportiertImOffenenFenster`, `testAK10_EinFavoritWirdZuMehreren` →
    `…BleibtEinFavorit`, `testAK14_…OhneSperre`/`…BleibtWaehrendDesLaufsWaehlbar` → `…Gesperrt`, `testAK35_…Hinterlaesst…`
    → `…OhneVerwaistenEintrag`, `testAK29_…OhneZugangsdaten` → `…MitZugangsdaten`, `testAK28_PlayerUndMultiviewLaufen…` →
    `…EndenMitDemLoeschen`, `testAK33_…BleibenNachLoeschenImPlattencache` → `…NichtImPlattencache`, `testAK34_NamenUndAdressen…
    BleibenAlsBytes` → `testAK34_KeineBytesGeloeschterSenderInDerDatei`, `testAK36_KeinWeg…` → `testAK36_Weg…`,
    `testAK37_AK38_…BlockierenDenMainThread` → `…Nicht`. Angepasste Abläufe: `delete` ist jetzt `async` (alle Aufrufer
    `try await`, B04 über `B04QA.run`); AK-22 (UI) wartet bis 10 s auf die leere Datenbank; der Datei-Abbruch in AK-29 nimmt
    40.000 statt 3.000 Sender, weil der Import sonst schon vor dem Klick fertig ist; der Anbieter in AK-14 (UI) antwortet
    je Anfrage 45 s (M3U) bzw. 3 × 55 s (Xtream: neue Verzögerungen `authDelay`/`categoriesDelay` im Test-Mock, je unter
    der Leerlaufgrenze von 60 s), damit alle Menüwahlen *während* der ersten Aktualisierung fallen, und zwischen zwei Wahlen
    liegen 0,3 s (das Menü ist sonst noch nicht neu gezeichnet); in AK-12/AK-13 antwortet der Anbieter 45 s / 55 s statt
    25 s / 50 s, weil synthetische Kontextmenüs unter Last bis zu 14 s dauern und der zweite Start sonst nach dem Ende des
    ersten lag; AK-32 prüft die Dokumenttypen
    des gebauten Bundles statt aller je gebauten Kopien in LaunchServices; AK-33 lenkt `URLCache.shared` auf einen
    Temp-Ordner um, statt den Cache der installierten App zu lesen. Angriff 7 (B02): ein Name aus nur NUL kommt jetzt so
    zurück, wie die Datenbank ihn speichert (leer, bekannter Befund B05 · BUG-09).

## 4 · Systemweite Änderungen

Über B02/B03 hinaus wirksam:

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Services/PlaylistHTTPLoader.swift` (vormals `XtreamHTTPLoader.swift`) | **B01** | Typ heißt `PlaylistHTTPLoader`, `typealias XtreamHTTPLoader` bleibt; Weiterleitungsregel und Mindestdurchsatz je Anfrage (Xtream unverändert `.sameOrigin`, kein Durchsatz); Cookie-Hilfen |
| `Sources/Services/XtreamClient.swift` | B01 | neuer Fehlerfall `tooSlow` des Loaders auf die bestehende Fristmeldung abgebildet (nie ausgelöst, weil Xtream keinen Durchsatz setzt) |
| `Sources/Services/PlaylistImporter.swift` | **B01** | Xtream-Import speichert über `PlaylistStore.create` statt `persistXtreamPlaylist` (gleiches Verhalten: Blöcke, Abbruch, Aufräumen); `delete` ist `async` |
| `Sources/Services/XtreamCredentialStore.swift` | B01 | hält auch `M3USecret`; `deleteAll` dient „Alle Daten entfernen" |
| `Sources/Services/StreamURLResolver.swift` | **B06, B07, B08** | Playlist wird je Aufruf nachgeschlagen (Beziehung, Existenz über `persistentModelID`); M3U-Platzhalter; neue Meldungen `playlistDeleted`, `missingPlaylistCredentials` |
| `Sources/Services/PlaybackEngine.swift`, `AVKitPlaybackEngine.swift`, `VLCPlaybackEngine.swift` | **B06, B07, B08** | neue Protokollmethode `stop()` (Standard: `pause()`); AVKit gibt das Element frei und beendet Bild-in-Bild, VLC `stop()`. Nur beim Löschen benutzt – „Zurück" pausiert weiter (B06 BUG-02 unverändert) |
| `Sources/Views/PlayerView.swift` | **B06, B07** | reagiert auf `PlaylistEvents.willDelete` (Engine beenden, Meldung) |
| `Sources/Services/MultiviewSession.swift` | **B08** | `Slot.playlistID`, eigenes `init` mit Beobachter, `removeSlots(ofPlaylists:)` |
| `Sources/Views/ChannelListView.swift` | **B04** | Zustand „Playlist gelöscht" |
| `Sources/Models/Channel.swift` | B05 | `static func favoriteKey(name:tvgID:)` (gleiche Regel, Kommentar); kein Schemawechsel |
| `Sources/Services/AppPersistence.swift` | alle, B01, B09 | M3U-Umstellung in `migrateCredentials`; Merker des einmaligen Cache-Leerens umbenannt; Kommentar Backup |
| `Sources/App/MikaPlusPlayerApp.swift` | alle, **B09** | Dokument-Handler, `handlesExternalEvents` (Hauptszene bevorzugt, Multiview-Fenster ausgenommen), Menübefehl „Alle Daten entfernen …" nach „Einstellungen" |
| `Sources/Resources/Info.plist` | alle | `public.text` entfernt, `CFBundleTypeRole Viewer`, `LSSupportsOpeningDocumentsInPlace = YES` (beseitigt die iOS-Build-Warnung der Ausgangslage) |
| neu: `PlaylistStore.swift`, `M3UCredentials.swift`, `PlaylistEvents.swift`, `AppDataReset.swift`, `Views/PlaylistDocumentHandler.swift` | alle | siehe oben |
| Schlüsselbund | alle | neuer Eintragstyp (M3U) im bestehenden Dienst, Label „Mika+Player – Playlist-Zugang" |
| `UserDefaults` | alle | neuer Merker `B02.legacyHTTPCachePurged` (der B01-Merker wird nicht mehr gelesen) |
| Tests anderer Features | B01, B04, B05, B06, B07, B08 | `try await …delete(…)` überall; **B01** `B01QA2Tests`: eigenes Cookie aufräumen (verschmutzte im Gesamtlauf B03 Angriff 5 – vorbestehender Fehlschlag der Ausgangslage); **B04** `B04SicherheitTests.testEC09_…`: Leerzustand → „Playlist gelöscht"; **B05** siehe Tabelle, dazu `testAK28_…` (BUG-10); **B06** `B06PlayerViewTests.testEC11_…`: Meldung „Playlist gelöscht" statt Engine-Fehler, kein Abruf; **B07** `B07DatenschutzTests.testAK23_…`: zählt nur Protokolleinträge seit Testbeginn (vorbestehender Fehlschlag der Ausgangslage im Gesamtlauf); **B08** `B08SessionTests.testAK27_…`: Kacheln enden mit dem Löschen |
| `Tests/B02/B02Support.swift`, `Tests/B03/B03QASupport.swift` | Tests | Aufräumen des Test-Schlüsselbunddienstes (M3U legt jetzt Einträge an) und der Loader-Cookies |
| `features/B02-m3u-import/spec.md`, `features/B03-playlist-verwaltung/spec.md` | Doku | nur *Offene Fragen* ergänzt (B02 OF-10 bis OF-13, B03 OF-07 bis OF-10) |
| `features/B05-favoriten/qa-report.md` | Doku | Vermerke unter BUG-01, BUG-10, BUG-11 |

Nicht angefasst: `project.yml` (keine neue Abhängigkeit), `appcast.xml`, `features/index.md`, `features/befunde.md`,
`web/`, `CLAUDE.md` (der Architekturteil nennt `PlaylistStore`, `M3UCredentials`, `PlaylistEvents` und `AppDataReset`
noch nicht – Vorschlag für den Orchestrator), `README.md`.
Hinweis: Die QA-Tests schreiben bei jedem Lauf Belegzeilen und Aufnahmen nach `features/*/qa/`. Die durch die Läufe
dieser Reparatur entstandenen Änderungen dort sind auf den Stand vor der Reparatur zurückgesetzt.

## Verifikation

VERIFIKATION_PLATZHALTER
