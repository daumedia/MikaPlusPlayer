# B02 · M3U-Import und B03 · Playlist-Verwaltung — Build-Bericht (gemeinsam)

Durchlauf 1 · geschrieben 2026-09-26, abgeschlossen und verifiziert 2026-09-27 · Eingang: Fehlerauftrag (`qa-report.md` von
B02 und B03, je Durchlauf 1), dazu B05 · BUG-01 und BUG-11 (gleicher Pfad) · Code geschrieben auf Branch `sdd/rueckerfassung`,
committet als `27be161` (mit PR #9 auf `main`); verifiziert auf Branch `sdd/reparaturen` mit unverändertem Code-Stand `27be161`

> Gleicher Inhalt in `features/B02-m3u-import/build-bericht.md` und `features/B03-playlist-verwaltung/build-bericht.md`.
> B02 und B03 teilen Abruf, Anlegen, Aktualisieren und Löschen; nach dem Muster „Reparaturen je Importweg statt im
> gemeinsamen Pfad" (`features/befunde.md`) ist beides **einmal** repariert, nicht je Importweg.

> **Was wann entstand.** Die Abschnitte 1 bis 4 sind am **2026-09-26** geschrieben; die Reparatur wurde damals in ihrer
> Schlussverifikation angehalten (belegt war nur, dass macOS mit Testtarget und iOS kompilieren), der Abschnitt
> *Verifikation* war ein Platzhalter und `features/B03-playlist-verwaltung/build-bericht.md` fehlte trotz des Hinweises oben.
> Am **2026-09-27** ist ohne Änderung am Produkt- oder Testcode verifiziert worden: volle macOS-Suite, iOS-Build, jede
> ursprüngliche Reproduktion der BUGs aus den QA-Berichten, die Release-Messung mit 17.000 Sendern, der Speicherfehler-Lauf
> (B05 · BUG-11) auf einem Datenträgerabbild. Ergänzungen und Korrekturen von heute sind mit **„2026-09-27"** markiert;
> Korrekturen stehen an der Stelle, die sie betreffen. Die B03-Datei ist heute als Kopie dieses Berichts angelegt.

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

> **Korrektur 2026-09-27:** Für die Zahlen des vorigen Absatzes gibt es kein erhaltenes Protokoll, und die dort
> angekündigte Tabelle fehlte. Heute gemessen (Tabelle unter *Verifikation*, Abschnitt 4): **Release** 17.000 Sender –
> Import per URL 2,98–3,19 s, per Datei 3,01 s, Aktualisieren M3U 4,94–5,36 s / Xtream 5,27–6,43 s, Löschen 1,69–2,48 s;
> längste Main-Thread-Blockade **0,01 s** (Debug 0,04 s). Die Gesamtzeiten liegen über den Angaben vom 26.09.; gemessen wurde
> unter hoher Fremdlast (Last-Mittel 38–177 bei 16 Kernen). Das Messziel – Oberfläche bleibt bei 17.000 Sendern bedienbar,
> keine Blockade über 1 s – ist erreicht; vorher 280–282 s Blockade (Release).

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

**Verifikation 2026-09-27:** Jede Zeile der Tabelle ist heute mit der ursprünglichen Reproduktion aus dem QA-Bericht erneut
ausgeführt und im jeweiligen `qa-report.md` unter dem BUG mit „**Behoben 2026-09-27:** …" bzw. „**Nicht behoben (geprüft
2026-09-27):** …" vermerkt (B02 BUG-01 bis BUG-09, B03 BUG-01 bis BUG-12, B05 BUG-01, BUG-10, BUG-11). Ergebnis: alle als
„behoben" geführten BUGs greifen nicht mehr; B03 BUG-10/-11/-12 bestehen unverändert (wartet auf OF-01/-02/-06). Drei Vermerke
vom 26.09. waren zu korrigieren: die Messzahlen bei B02 BUG-04 und B03 BUG-01 (nicht belegt, heute neu gemessen; das gilt auch
für die 17.000er-Werte in der Spalte „Nachweis" oben – heute Release ≤ 0,01 s, Debug ≤ 0,04 s) und der Lauf mit 40-MB-Abbild
bei B05 BUG-11 (nicht belegt, heute mit 8-MB-Abbild ausgeführt). Zusätzlich über den Auftrag hinaus geprüft,
weil die Reparatur ihn berührt: B05 BUG-10 (elf Wiederholungen, 0 Reste).

Reihenfolge der Arbeit: hoch (B02 BUG-01, BUG-04, B03 BUG-01) zuerst, weil der gemeinsame Pfad alle anderen trägt;
dann mittel, dann niedrig. Jeder BUG war vor der Änderung über seinen QA-Test reproduziert (Ausgangslauf, siehe
*Verifikation*: die `XCTExpectFailure`-Blöcke schlugen erwartungsgemäß fehl) und ist danach mit dem umgestellten Test
erneut ausgeführt. **Korrektur 2026-09-27:** Ein Protokoll dieses Ausgangslaufs steht nicht unter *Verifikation* (dort war
bis heute ein Platzhalter) und ist nicht erhalten; das Verhalten vor der Reparatur belegen die QA-Berichte (Durchlauf 1). Die
Ausführung nach der Reparatur ist heute belegt.

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
  **Korrektur 2026-09-27:** am 27.09. wiederholt (`-configuration Release -derivedDataPath build/dd-release`), siehe
  *Verifikation*, Abschnitt 4.
- **2026-09-27 · Unabhängiges Review fehlt weiterhin.** Der Auftrag vom 27.09. war Abschluss und Verifikation; ein
  Code-Review der Reparatur (wie bei B01) ist nicht gemacht und bleibt vor bzw. in QA-Runde 2 offen.
- **2026-09-27 · Grenzen nur mit verkleinerten Werten ausgeführt:** Die Ablehnung über 64 MB und die Gesamtfrist von 180 s
  sind mit denselben Codepfaden, aber verkleinerten Werten belegt (`testBUG03_…`: 2.000 Byte, 3 Sender, 4 s); eine echte
  Antwort über 64 MB und ein 180-s-Lauf mit Standardwerten wurden nicht ausgeführt.
- **2026-09-27 · Aussagen zur Ausgangslage nicht nachgeprüft:** Abschnitt 4 nennt für `B01QA2Tests` (Cookie) und
  `B07DatenschutzTests.testAK23_…` „vorbestehende Fehlschläge der Ausgangslage im Gesamtlauf". Die Ausgangslage (`76caeb0`)
  wurde heute nicht erneut gebaut und nicht als Gesamtlauf ausgeführt; belegt ist nur, dass beide Tests mit den Änderungen
  im heutigen Gesamtlauf grün sind.
- **2026-09-27 · Finder-Doppelklick** nur über `open -a` an einer Kopie mit eigener Bundle-ID nachgestellt (siehe
  *Verifikation*); ein Doppelklick im Finder öffnet auf dem Prüfrechner weiter Music.app (OF-13).

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

Ergänzt 2026-09-27 (Annahmen der Verifikation, ohne Änderung am Code):

21. **Messung unter Fremdlast.** Während aller Läufe liefen fremde Prozesse (u. a. acht verwaiste Shell-Prozesse anderer
    Projekte mit je 100 % CPU seit 14:43 Uhr und ein iOS-Testlauf eines anderen Projekts); sie wurden nicht angefasst.
    Last-Mittel 38–177 bei 16 Kernen. Gesamtzeiten sind deshalb eher zu hoch; die Blockade-Messung (Wachhund alle 20 ms)
    ist davon kaum betroffen.
22. **Release-Messbuild** wie in QA 1 mit `ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`, nur damit der Test-Host das Test-Bundle laden kann; Optimierung `-O` und
    `-whole-module-optimization` im Protokoll belegt.
23. **Nachweisdateien.** Die Tests schreiben bei jedem Lauf nach `features/*/qa/` (B02 immer, andere Features teils). Alle
    dadurch entstandenen Änderungen – auch an B02/B03 – sind nach jedem Lauf mit `git checkout -- features/` zurückgenommen,
    damit die Belege von QA 1 erhalten bleiben; die heutigen Messzeilen stehen gefiltert unter *Verifikation* und in den
    `qa-report.md`-Vermerken.

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

**2026-09-27:** Keine weitere systemweite Änderung. Am Produkt- und Testcode ist heute nichts geändert; geändert sind nur
Dokumente: Vermerke „2026-09-27" in `features/B02-m3u-import/qa-report.md`, `features/B03-playlist-verwaltung/qa-report.md`
und `features/B05-favoriten/qa-report.md` (BUG-01, BUG-10, BUG-11), dieser Bericht und die neu angelegte Kopie
`features/B03-playlist-verwaltung/build-bericht.md`. `features/index.md` und `features/befunde.md` sind nicht angefasst.
Nicht mehr offen ist die iOS-Build-Warnung zu `LSSupportsOpeningDocumentsInPlace` (heute nicht mehr in der Ausgabe).

## Verifikation

Stand **2026-09-27**, Branch `sdd/reparaturen`, Code-Stand `27be161` ohne Änderung. Am 26.09. stand hier nur ein Platzhalter;
alles in diesem Abschnitt ist heute ausgeführt. Ausgaben gefiltert auf `** (BUILD|TEST) (SUCCEEDED|FAILED) **`,
`Executed N tests`, `error:` und die Messzeilen der Tests (`B02QA|…`, `B03QA|…`, `B05QA|…`; Temp-Pfade gekürzt).
Rechner: Apple M3 Max, 16 Kerne, macOS 27 (Darwin 27.0.0), Xcode 27A266a. Fremdlast siehe Annahme 21.

**1 · Projekt erzeugen**

```
$ xcodegen generate
Created project at ~/DEV/macOS/MikaPlusPlayer/MikaPlusPlayer.xcodeproj
```

**2 · macOS-Gesamtlauf** (frischer DerivedData-Ordner, also vollständiger Build) —
`xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test -collect-test-diagnostics never`,
15:15–16:07 Uhr, erster und einziger Gesamtlauf, **ohne Fehlschlag** (keine Wiederholung, kein Einordnen nötig):

```
B01AdressbildungTests   Executed 16 tests, with 0 failures (0 unexpected)
B01ImportTests          Executed 18 tests, with 0 failures (0 unexpected)
B01LangsamTests         Executed 4 tests, with 0 failures (0 unexpected)
B01OberflaecheTests     Executed 10 tests, with 0 failures (0 unexpected)
B01QA2GrenzenTests      Executed 6 tests, with 1 test skipped and 0 failures (0 unexpected)
B01QA2OberflaecheTests  Executed 3 tests, with 0 failures (0 unexpected)
B01QA2Tests             Executed 20 tests, with 0 failures (0 unexpected)
B01ReparaturTests       Executed 11 tests, with 0 failures (0 unexpected)
B01SicherheitTests      Executed 10 tests, with 1 test skipped and 0 failures (0 unexpected)
B02DateiImportTests     Executed 7 tests, with 0 failures (0 unexpected)
B02LangsamTests         Executed 2 tests, with 0 failures (0 unexpected)
B02OberflaecheTests     Executed 13 tests, with 0 failures (0 unexpected)
B02ParserTests          Executed 18 tests, with 0 failures (0 unexpected)
B02ReparaturTests       Executed 7 tests, with 0 failures (0 unexpected)
B02SicherheitTests      Executed 11 tests, with 0 failures (0 unexpected)
B02URLImportTests       Executed 14 tests, with 0 failures (0 unexpected)
B03AktualisierenTests   Executed 20 tests, with 1 test skipped and 0 failures (0 unexpected)
B03LeistungTests        Executed 1 test, with 0 failures (0 unexpected)
B03LoeschenTests        Executed 10 tests, with 0 failures (0 unexpected)
B03OberflaecheTests     Executed 11 tests, with 0 failures (0 unexpected)
B03ReparaturTests       Executed 3 tests, with 0 failures (0 unexpected)
B04AufbauTests          Executed 7 tests, with 0 failures (0 unexpected)
B04ErgaenzungTests      Executed 4 tests, with 2 tests skipped and 0 failures (0 unexpected)
B04ErkundungTests       Executed 1 test, with 0 failures (0 unexpected)
B04GruppenTests         Executed 11 tests, with 0 failures (0 unexpected)
B04LeistungTests        Executed 2 tests, with 0 failures (0 unexpected)
B04LogoTests            Executed 11 tests, with 0 failures (0 unexpected)
B04SicherheitTests      Executed 7 tests, with 0 failures (0 unexpected)
B04SucheTests           Executed 5 tests, with 0 failures (0 unexpected)
B05AktualisierenTests   Executed 10 tests, with 1 test skipped and 0 failures (0 unexpected)
B05DatenschutzTests     Executed 5 tests, with 1 test skipped and 0 failures (0 unexpected)
B05LeistungTests        Executed 2 tests, with 0 failures (0 unexpected)
B05LoeschenTests        Executed 2 tests, with 0 failures (0 unexpected)
B05SicherheitTests      Executed 4 tests, with 0 failures (0 unexpected)
B05SternTests           Executed 6 tests, with 0 failures (0 unexpected)
B05TabTests             Executed 7 tests, with 0 failures (0 unexpected)
B06DeadlockTests        Executed 1 test, with 1 test skipped and 0 failures (0 unexpected)
B06EngineWahlTests      Executed 5 tests, with 0 failures (0 unexpected)
B06EngineZustandTests   Executed 10 tests, with 2 tests skipped and 0 failures (0 unexpected)
B06ErkundungTests       Executed 1 test, with 1 test skipped and 0 failures (0 unexpected)
B06PlayerViewTests      Executed 17 tests, with 1 test skipped and 0 failures (0 unexpected)
B06SteuerungTests       Executed 5 tests, with 0 failures (0 unexpected)
B07AngriffTests         Executed 4 tests, with 0 failures (0 unexpected)
B07AppOberflaecheTests  Executed 1 test, with 0 failures (0 unexpected)
B07DatenschutzTests     Executed 5 tests, with 0 failures (0 unexpected)
B07ImportHinweisTests   Executed 1 test, with 0 failures (0 unexpected)
B07KnopfTests           Executed 11 tests, with 0 failures (0 unexpected)
B07SystemfensterTests   Executed 7 tests, with 5 tests skipped and 0 failures (0 unexpected)
B07VerlassenTests       Executed 6 tests, with 0 failures (0 unexpected)
B08AbsturzTests         Executed 8 tests, with 8 tests skipped and 0 failures (0 unexpected)
B08HauptfensterTests    Executed 1 test, with 0 failures (0 unexpected)
B08NachtragTests        Executed 4 tests, with 1 test skipped and 0 failures (0 unexpected)
B08NeustartTests        Executed 1 test, with 1 test skipped and 0 failures (0 unexpected)
B08OberflaecheTests     Executed 14 tests, with 1 test skipped and 0 failures (0 unexpected)
B08SessionTests         Executed 18 tests, with 0 failures (0 unexpected)
B09PersistenzTests      Executed 7 tests, with 0 failures (0 unexpected)
B09QA2Tests             Executed 7 tests, with 0 failures (0 unexpected)
B09ReleaseConfigTests   Executed 11 tests, with 0 failures (0 unexpected)
B09ReleaseSkriptTests   Executed 7 tests, with 0 failures (0 unexpected)
B09UpdaterTests         Executed 3 tests, with 0 failures (0 unexpected)
M3UParserTests          Executed 4 tests, with 0 failures (0 unexpected)
PlaybackEngineTests     Executed 6 tests, with 0 failures (0 unexpected)
XtreamCodesTests        Executed 4 tests, with 0 failures (0 unexpected)
	 Executed 468 tests, with 28 tests skipped and 0 failures (0 unexpected) in 3035.246 (3035.483) seconds
** TEST SUCCEEDED **
```

- **Erwartete Fehlschläge** (`XCTExpectFailure`, 102 Meldungen, alle bekannte Befunde): B02 **keine mehr**; B03 genau drei –
  `testAK22_AK24_…` (BUG-10, OF-01), `testAK11_…` (BUG-11, OF-02), `testAK21_…` (BUG-12, OF-06); B05 nur noch Befunde außerhalb
  dieses Auftrags (BUG-02 bis BUG-09); `B08SessionTests.testAK28_AktualisierenAlteAdresseUndZweiteKachel` (Teil Aktualisieren,
  OF-09). Die übrigen gehören zu B01, B04, B06–B09 und sind unverändert.
- **Übersprungen** (28): alle aus Schaltern, die ein Gesamtlauf nicht setzt (lange oder den Test-Host beendende Läufe, Helfer,
  SQL-Debug) bzw. aus bekannten Gründen (`B03AktualisierenTests.testEC03_…`: Schreibkonflikt nicht provozierbar, wie in QA 1;
  `B01SicherheitTests.testAK27_…`: Private-Data-Logging am Test-Host). Für diesen Auftrag relevant nur
  `B05AktualisierenTests.testAK17_Randfall_…` (braucht ein Datenträgerabbild) → einzeln ausgeführt, Abschnitt 5.
- **Warnungen:** keine in `Sources/`. Alle Warnungen des Laufs stehen in Testdateien (`Tests/B01`–`B08`, `Tests/Support`;
  u. a. veraltetes `CGWindowListCreateImage`, `accessibilityAttributeValue`, `kSecUseAuthenticationUIFail`, Sendable-Hinweise)
  und liegen laut `git blame` ausnahmslos auf Zeilen aus `76caeb0`, also vor dieser Reparatur; `27be161` hat keine davon
  geändert. Die Warnungsarten sind zeilenlokal. **Keine neue Warnung.**

**3 · iOS-Simulator-Build** (frischer DerivedData-Ordner) —
`xcodebuild build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`

```
appintentsmetadataprocessor[…] warning: Metadata extraction skipped, no AppIntents.framework dependency found   ← wie Baseline B01
** BUILD SUCCEEDED **
```

Die Warnung zu `LSSupportsOpeningDocumentsInPlace` der Ausgangslage erscheint nicht mehr. iOS ist gebaut, nicht bedient.

**4 · Messziel 17.000 Sender** (Import per URL, Aktualisieren, Löschen; Gesamtzeit und längste Main-Thread-Blockade, Wachhund
alle 20 ms, Store-Datei über `AppPersistence.diskContainer`, 17 Favoriten)

Release-Messbuild —
`xcodebuild build-for-testing -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -configuration Release -derivedDataPath build/dd-release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`
→ `** TEST BUILD SUCCEEDED **`, im Protokoll 18 × `-O`, 18 × `-whole-module-optimization`. Läufe mit
`xcodebuild test-without-building … -configuration Release -derivedDataPath build/dd-release` und
`TEST_RUNNER_B02_QA_SIZES=17000 TEST_RUNNER_B02_QA_STORE_SIZES=17000 TEST_RUNNER_B03_SIZES=17000 TEST_RUNNER_B03_KINDS=m3u,xtream TEST_RUNNER_B03_RESTART_DELETE=1`,
`-only-testing:` `B02LangsamTests/testAK40_GrosseListeBlockiertMainThread` und `B03LeistungTests`; Datei-Import mit
`TEST_RUNNER_B02_REP_DATEI=17000` über `B02ReparaturTests/testBUG04_…`. Debug dasselbe mit `build/dd-test`.

| 17.000 Sender | Release Lauf 1 | Release Lauf 2 | Debug | vorher (QA 1, Release) |
|---|---|---|---|---|
| Import per URL, Datenbank im Speicher | 3,04 s · **0,00 s** | 3,10 s · **0,01 s** | 4,22 s · 0,01 s | 282,54 s · 282,51 s |
| Import per URL, Store-Datei | 3,19 s · 0,01 s | 2,98 s · 0,00 s | 4,72 s · 0,00 s | — |
| Import per Datei | 3,01 s · 0,01 s | — | 3,29 s · 0,02 s | (Debug, 3.000 Sender: 9,23 s Blockade) |
| M3U: Import (im Aktualisier-Test) | 2,62 s | 2,58 s | 4,39 s | — |
| M3U aktualisieren | 5,36 s · 0,00 s | 4,94 s · 0,01 s | 7,51 s · 0,04 s | — |
| M3U löschen nach Aktualisieren | 1,85 s · 0,00 s | 1,69 s · 0,00 s | 2,51 s · 0,00 s | — |
| M3U löschen nach Neustart | 1,90 s · 0,00 s | 1,87 s · 0,00 s | 2,17 s · 0,00 s | — |
| Xtream aktualisieren | 6,43 s · 0,00 s | 5,27 s · 0,00 s | 5,26 s · 0,02 s | 280,48 s · 280,38 s |
| Xtream löschen nach Aktualisieren | 2,48 s · 0,01 s | 1,97 s · 0,00 s | 1,86 s · 0,01 s | 132,60 s |
| Xtream löschen nach Neustart | 2,26 s · 0,00 s | 2,05 s · 0,01 s | 2,00 s · 0,00 s | 41,31 s |

Jeweils Gesamtzeit · längste Blockade. Favoriten jeweils 17 → 17, nach dem Löschen `ZPLAYLIST=0`, `ZCHANNEL=0`.
**Längste Blockade über alle 17.000er-Läufe: Release 0,01 s, Debug 0,04 s** (Grenze der Tests 0,5 s bzw. 1 s; vorher
41–282 s). Last-Mittel während der Läufe 38–177. Ausgabe Release, Lauf 1 (Lauf 2 und Debug gleich aufgebaut):

```
B02QA|AK-40|inMemory|sender=17000|bytes=2484318|gesamt=3.04s|maxMainThreadBlockade=0.00s|playlistID=17000|beziehung=17000|build=Release|cpuKerne=16|last=37.9/45.9/45.2
B02QA|AK-40|storeDatei|sender=17000|bytes=2484318|gesamt=3.19s|maxMainThreadBlockade=0.01s|playlistID=17000|beziehung=17000|build=Release|cpuKerne=16|last=37.2/45.7/45.1
B02QA|AK-40|laengsteBlockade=0.00s|build=Release
B03QA|AK-37-38|…|Release|m3u|sender=17000|import=2.62s|aktualisieren=5.36s|mainThreadBlockade=0.00s|speicher=63→77MB|favoriten=17→17|ZPLAYLIST=1|ZCHANNEL=17000|…
B03QA|AK-37-38|…|Release|m3u|sender=17000|loeschenNachAktualisieren=1.85s|mainThreadBlockade=0.00s|ZPLAYLIST=0|ZCHANNEL=0|…
B03QA|AK-37-38|…|Release|m3u|sender=17000|loeschenNachNeustart=1.90s|mainThreadBlockade=0.00s|ZPLAYLIST=0|ZCHANNEL=0|…
B03QA|AK-37-38|…|Release|xtream|sender=17000|import=3.44s|aktualisieren=6.43s|mainThreadBlockade=0.00s|speicher=160→190MB|favoriten=17→17|…
B03QA|AK-37-38|…|Release|xtream|sender=17000|loeschenNachAktualisieren=2.48s|mainThreadBlockade=0.01s|ZPLAYLIST=0|ZCHANNEL=0|…
B03QA|AK-37-38|…|Release|xtream|sender=17000|loeschenNachNeustart=2.26s|mainThreadBlockade=0.00s|ZPLAYLIST=0|ZCHANNEL=0|…
B03QA|AK-37-38|…|Release|ergebnis|laengsteBlockade aktualisieren=0.00s loeschen=0.01s
** TEST EXECUTE SUCCEEDED **
B02QA|BUG-04|datei|sender=17000|gesamt=3.01s|maxMainThreadBlockade=0.01s|build=Release
** TEST EXECUTE SUCCEEDED **
```

Standardgrößen im Gesamtlauf (Debug): URL-Import 1.500/3.000/6.000 Sender 0,22/0,55/1,16 s, Blockade 0,00 s, Wachstum
3.000 → 6.000 Faktor 2,09 (vorher 3,98); Aktualisieren/Löschen 1.000/2.000 Sender 0,12–0,67 s, Blockade 0,00–0,01 s.

**5 · Reproduktionen außerhalb des Gesamtlaufs**

B05 · BUG-11 (Speicherfehler beim Aktualisieren) — 8-MB-HFS+-Abbild im Scratchpad, `hdiutil attach -nobrowse -mountpoint …`,
`TEST_RUNNER_B05_FULL_VOLUME=<Mountpoint> xcodebuild test … -derivedDataPath build/dd-test -only-testing:MikaPlusPlayerTests/B05AktualisierenTests/testAK17_Randfall_SpeicherfehlerBeimAktualisieren`:

```
SwiftData.DefaultStore save failed with error: Error Domain=NSSQLiteErrorDomain Code=13 …
B05QA|AK-17-randfall-speicherfehler.txt|tab vorher=["ZDF HD, Deutschland"]|meldung=Die Playlist konnte nicht gespeichert werden. Die bisherige Senderliste bleibt erhalten. Bitte freien Speicherplatz prüfen und erneut versuchen.|tab danach=["ZDF HD, Deutschland"]|kontext-favoriten=["ZDF HD@QA Voll Aktualisieren"]|dieselben objekte=true|hasChanges=false|datei (neustart)=["ZDF HD@QA Voll Aktualisieren"]
B05QA|AK-17-randfall-speicherfehler.txt|nach platz + nächstem stern|datei=["ZDF HD@QA Voll Aktualisieren", "arte@QA Voll Aktualisieren"]|sender in datei=3
	 Executed 1 test, with 0 failures (0 unexpected) in 3.028 (3.030) seconds
** TEST SUCCEEDED **
```

Nach dem Test meldet SwiftData noch Lesefehler der offenen Tab-Abfrage, weil der Test seinen Ordner auf dem Abbild entfernt,
solange das Fenster lebt (Laufzeitmeldung, keine Build-Warnung, kein Fehlschlag). Abbild danach ausgehängt und gelöscht.

B05 · BUG-10 / B03 · BUG-07 (Reste gelöschter Sender, in QA 1 nicht deterministisch) — `-test-iterations 11` für
`B05LoeschenTests/testAK28_…`, `-test-iterations 5` für `B03LoeschenTests/testAK34_…`:

```
11 × Test Case '-[… B05LoeschenTests testAK28_NamenGeloeschterFavoritenInDatenbankdateien]' passed
11 × B05QA|AK-28-restbytes.txt|nach-neustart|[store: 0, -wal: 0, -shm: 0]|["secure_delete=2", "journal_mode=wal", "freelist_count=0", …]
** TEST SUCCEEDED **
 5 × B03QA|AK-34|nachNeustart|m3uSendernamen=0|streamAdressen=0|xtreamSendernamen=0|playlistName=0|token=0|freieSeiten=0|secure_delete(neue Verbindung)=2
** TEST SUCCEEDED **
```

B02 · BUG-06 (a)(b) an einer Kopie der Debug-App (Bundle-ID `lu.daumedia.MikaPlusPlayer.b02probe27`, Sparkle-Prüfung aus,
Feed auf Port 9, ad hoc neu signiert; vorab leere Store-Datei der Kopie angelegt, sodass eine vorhandene `default.store` nie
übernommen wird; Fenster über `CGWindowListCopyWindowInfo`, Ebene 0, auf dem Bildschirm):

```
== Datenbank im Speicher (open --env XCTestSessionIdentifier=…)
kaltstart qa-doppelklick.m3u            prozesse=1  fensterOnScreen=1
qa-doppelklick.m3u8 bei laufender App   prozesse=1  fensterOnScreen=1      (QA 1: 2)
qa-doppelklick.txt  bei laufender App   prozesse=1  fensterOnScreen=1      (QA 1: 3)
qa-doppelklick.m3u  bei laufender App   prozesse=1  fensterOnScreen=1      (QA 1: 4)
storeDateiBytes=0
== umgebogene Datenbank (eigene Store-Datei der Kopie), Import über sqlite3 -readonly geprüft
kaltstart            fensterOnScreen=1  ZPLAYLIST: qa-doppelklick|2 Sender|sourceURL NULL
nach m3u8, txt, m3u  fensterOnScreen=1  ZPLAYLIST: 4 × qa-doppelklick|2   ZCHANNEL: 8
```

Danach Prozess beendet, `lsregister -u`, Kopie, Einstellungen, Cache und Datenbank der Kopie entfernt (keine Spur unter
`~/Library` mit `b02probe27`).

B02 · BUG-07 — `NSWorkspace.urlsForApplications(toOpen:)` für Probedateien, ausgewertet für den heutigen Debug-Build:

```
LS|m3u|dieserBuild=ja|mikaKandidatenGesamt=2|standardApp=Music.app
LS|m3u8|dieserBuild=ja|mikaKandidatenGesamt=2|standardApp=Music.app
LS|txt|json|html|csv|swift|md|log|pls|xspf|(ohne Endung)  →  dieserBuild=nein|mikaKandidatenGesamt=0
```

(Die zwei Kandidaten bei `m3u`/`m3u8` sind der Debug- und der Release-Build dieser Prüfung.)

**6 · Aufräumen** — `git status features/` nach jedem Lauf; alle durch Tests geänderten Nachweise (B02–B08, auch B02/B03) mit
`git checkout -- features/` zurückgenommen. Datenträgerabbild ausgehängt und gelöscht, App-Kopie samt Spuren entfernt,
`build/dd-release` gelöscht; keine eigenen Prozesse, Simulatoren oder Mock-Server übrig. Kein Ton: Die Testmedien der Suite sind ohne Tonspur
(`ffmpeg -an`, von der QA so angelegt), die App-Kopie spielte nichts (Streams auf Port 9). Die Datenbank `~/Library/Application Support/default.store`, die
Daten unter `~/Library/Application Support/lu.daumedia.MikaPlusPlayer/` und der Schlüsselbund-Dienst der App wurden weder
gelesen noch beschrieben (Test-Host im Speicher, Testdienst im Schlüsselbund, Kopie mit eigener Bundle-ID und vorab
angelegter eigener Store-Datei). Protokolle vollständig nur im Scratchpad der Session.

## Review 2026-09-27

Unabhängiges Review der Reparatur B02+B03 (`git diff 76caeb0 27be161`), ausgeführt in einem eigenen Git-Worktree auf
`27be161` (`/private/tmp/claude-501/review-b0203`, DerivedData `build/dd`, danach entfernt). Am Produkt- und Testcode des
Repositorys ist nichts geändert; zusätzliche Prüftests (`Tests/Review/ReviewB0203Tests.swift`, 13 Tests) lagen nur im
Worktree. Nur erfundene Daten, Loopback-Server, eigener Schlüsselbund-Testdienst (`…xtream.tests.review-b0203`, danach
geleert), kein Ton. Parallel lief im Hauptarbeitsbaum die B06-Reparatur mit eigenen Testläufen (Folgen siehe 6).

**Urteil: Nacharbeit nötig** – wegen R-01 (wichtig): Sterne, die während eines Aktualisierens gesetzt werden, gehen ohne
Meldung verloren; das ist durch die Reparatur neu entstanden. Alle übrigen Funde sind gering.

### Funde

| ID | Art | Ort | Beleg | Schwere |
|---|---|---|---|---|
| R-01 | Nebenläufigkeit, Verlust von Nutzerdaten | `Sources/Services/PlaylistStore.swift:151` (Favoriten aus dem Stand beim Lesen, danach alle Sender in einem Speichervorgang ersetzt, `:170`) mit `Sources/Views/ChannelRowView.swift:60-62` (Stern: umschalten + `try? modelContext.save()`) | Review-Test C3: 17.000 Sender per URL, Store-Datei, Debug. Während das Aktualisieren im Hintergrund ersetzt, werden im Kontext der Ansicht Sterne gesetzt und gespeichert – jedes Speichern ohne Fehler, Aktualisieren meldet nichts. Danach fehlen in der Datenbank 8 von 10 der während des Laufs gesetzten Sterne (gesetzt 0,4–4,0 s nach der Anfrage; fertig nach 4,16 s). Wiederholung: 6 von 10 verloren (fertig nach 4,70 s); 3.000 Sender: 2 verloren (0,87 s). Sterne vor dem Lesen und nach dem Ende bleiben. Vorher unmöglich, weil die Oberfläche während des Ersetzens blockiert war (B03 BUG-01); gilt für M3U und Xtream (gleicher Weg). Widerspricht „Nutzerdaten nie verlieren" und B05 AK-15. Vorschlag: Stern der betroffenen Playlist während des Laufs sperren oder Stern-Änderungen aus dem Zeitraum nach dem Lesen nachziehen | **wichtig** |
| R-02 | Konsistenz bei vollem Datenträger | `PlaylistStore.swift:101-133` (`create`: Blöcke zu 5.000 einzeln gespeichert, Aufräumen mit `try? cleanup.save()`, `:132`) | Review-Test V1: 6-MB-HFS+-Abbild, 40.000 Sender per URL → Meldung „The operation couldn't be completed. (NSSQLiteErrorDomain error 13.)" (technisch, englisch – für das Aktualisieren mit B05 BUG-11 behoben, für den Import nicht); danach steht eine halbe Playlist „Voll" mit 20.000 von 40.000 Sendern in der Datei, im Kontext der Ansicht sichtbar und nach dem Neuöffnen `Voll=20000/20000`. Der Kommentar zu `create` („wird die Playlist samt bereits gespeicherter Sender wieder entfernt") gilt hier nicht. Nur im Code gelesen, nicht ausgeführt: bei einem M3U-Link mit Zugangsdaten entfernt `PlaylistImporter.persist` (`PlaylistImporter.swift:189`) danach den Schlüsselbund-Eintrag, die Reste wären nicht abspielbar | gering |
| R-03 | Zugangsdaten in `sourceURL` | `Sources/Services/M3UCredentials.swift:40-42, 61` | Review-Test K1: `http://qa-user:qa-pass-info@h.example/get.php?username=qa-user&password=qa-pass-query` → gespeichert `http://_mikaplus_info_benutzer_:qa-pass-info@h.example/…`: Trägt die Adresse Benutzerinfo **und** ein anderes `password=`, bleibt das Passwort der Benutzerinfo im Klartext. Seltene Form | gering |
| R-04 | „Alle Daten entfernen" unvollständig im Rückfall | `Sources/Services/AppDataReset.swift:26-27` (`setAsideFolder` über `PlaylistStore.storeURL(of:)`, bei Datenbank im Speicher `nil`) | Review-Test D1: `setAsideFolder=nil` für einen Container im Speicher. Im B09-Rückfall `inMemoryFallback(movedTo:)` liegt eine vollständige alte Datenbank unter `Beiseitegelegt/`, die „Alle Daten entfernen" dann nicht erreicht | gering |
| R-05 | Test prüft den Befund nicht mehr wörtlich | `Tests/B02/B02OberflaecheTests.swift:629-633` (`testAK31d_AK32_OeffnerRegistrierung`) | Die LaunchServices-Kandidatenliste (Reproduktion von B02 BUG-07) wird noch berechnet, aber verworfen (`_ = offered`); geprüft werden nur die `LSItemContentTypes` des gebauten Info.plist. Andere Registrierungswege (z. B. `CFBundleTypeExtensions`) fielen nicht auf. Die wörtliche Reproduktion ist am 27.09. außerhalb des Tests ausgeführt (Vermerk unter BUG-07) | gering |
| R-06 | Test lässt ein überzähliges Fenster zu | `Tests/B02/B02OberflaecheTests.swift:594` (`testAK31_…ImportiertImOffenenFenster`) | `XCTAssertLessThanOrEqual(created.count, 1)` gilt unabhängig davon, ob vorher ein Fenster offen war; genau ein zusätzliches leeres Fenster je Lauf (Kern von B02 BUG-06) bliebe unentdeckt. Heute 0 neue Fenster (Vermerk vom 27.09.) | gering |
| R-07 | Tests anderer Features eingeschränkt | `Tests/B07/B07DatenschutzTests.swift:155`, `Tests/B02/B02SicherheitTests.swift:245` | Beide zählen nur noch Protokolleinträge ab Testbeginn. Fachlich vertretbar (Zeitfenster des eigenen Tests), aber die Begründung „vorbestehender Fehlschlag der Ausgangslage" ist laut Build-Bericht nicht nachgeprüft, und welche früheren Einträge die Nadeln (u. a. `/live/`) trafen, ist nicht dokumentiert | gering |
| R-08 | Klartext-Rest nach Abbruch vor dem Verdichten | `Sources/Services/AppPersistence.swift:271-320` (Verdichten nur, wenn in diesem Start umgestellt wurde) | Umstellung ohne Verdichten (= Abbruch nach dem letzten Speichern), dann nächster Start: `migratedPlaylists: 0`, kein Verdichten; in zwei Läufen 1 bzw. 0 Vorkommen eines Passworts in der Datei | gering |
| R-09 | Keine Typprüfung bei „Öffnen mit" | `Sources/Views/PlaylistDocumentHandler.swift:17-20` | Jede übergebene Datei-URL wird importiert, wenn sie Einträge mit erlaubtem Schema hat; der eigene Test importiert `.txt` (`B02OberflaecheTests.swift:556`), der Datei-Reiter beschränkt dagegen auf `.m3u`/`.m3u8`. LaunchServices bietet die App nur für M3U an; `open -a` umgeht das. Bei abgeschalteter Sandbox liest die App nur, was ein Prozess desselben Nutzers ohnehin lesen darf – eine Rechteausweitung ist nicht belegt | gering |
| R-10 | Blockierender Start während der Umstellung | `AppPersistence.swift:197-199` aus `MikaPlusPlayerApp.init` | Review-Test M2: 30 M3U-Playlists × 3.000 Sender mit Zugangsdaten + 1.000 Xtream-Sender: `umstellungAufMainThread=11,19 s` (Debug, M3 Max) vor dem ersten Fenster. Einmalig; Abbruch ist sicher (siehe 2). iOS (Start-Wachhund) nicht gemessen | gering |
| R-11 | Gemeinsamer Cookie-Speicher nicht geleert | `AppDataReset.swift:56-64` | „Alle Daten entfernen" leert Loader-Cookies, nicht `HTTPCookieStorage.shared`; bis `76caeb0` legten M3U-Abrufe Cookies dort ab (B02 QA AK-42: 1 Cookie). Ob dort Cookies dauerhaft gespeichert sind, ist nicht geprüft (Speicher der echten App nicht gelesen) | gering |

Hinweis ohne Schwere: Commit `27be161` enthält auch Änderungen an `features/befunde.md` (BF-01, B09, Konto-Umbenennung) und
`features/index.md` – Statusverwaltung, nicht Teil der Reparatur.

### Belege je Prüfpunkt

**1 · Tests nicht aufgeweicht.** Zwischen den Commits 31 `XCTExpectFailure` entfernt (B02 12, B03 13, B05 5, B08 1),
0 hinzugefügt; in B03 bleiben genau BUG-10/-11/-12. Jeder entfernte Block ist durch dieselbe Assertion außerhalb ersetzt,
meist ergänzt (z. B. AK-34: auch Rohbytes 0 und Schlüsselbund = 1; B05 BUG-10: jetzt schon bei offener Datei 0 statt nur
nach Neustart; B03 Leistung: Grenze 1 s jetzt immer statt nur bei Überschreitung). Kein neues `XCTSkip` außer der
Vorlagen-Wache in `testBUG01_UmstellungAufDerV11Vorlage` (Vorlage vorhanden). Grenzwerte unverändert (0,5 s / 1 s); erhöht
sind nur Wartezeiten und Anbieterverzögerungen in UI-Tests, die Datei in AK-29 hat 40.000 statt 3.000 Sender (strenger).
Nachgiebiger: R-05, R-06, R-07. Die 64-MB-Grenze prüft die Suite nur mit verkleinerten Werten – mit Standardwerten
hier nachgeholt (Punkt 4).

**2 · Datenverlust-Risiko Migration.** Keine Schemaänderung (Modelle: nur `favoriteKey` als statische Funktion; die
v1.1-Vorlage öffnet mit `.opened`). Datenbank im Speicherformat von `76caeb0` (identisches Schema, Inhalt wie `76caeb0`
M3U speichert; erfundene Daten): 30 M3U-Playlists × 3.000 Sender mit Passwort in `sourceURL` und ¾ der Stream-Adressen
(Query-, Pfad-, Benutzerinfo-Form), Xtream-Altbestand (1.000), M3U ohne Passwort, Datei-Playlist, Favoriten.

```
REVIEW|M1|angelegt|playlists=33|m3uMitPasswort=30x3000|dateiBytes=17051648|klartextVorkommen=[store: 68535, -wal: 0, -shm: 0]
REVIEW|M2|outcome=opened|umstellungAufMainThread=11.19s|ergebnis=(migratedPlaylists: 31, rewrittenChannels: 68500, failedPlaylists: 0)|verdichten=true
REVIEW|M3|vorNeustart|zustaende=[file: 1, m3u-neu: 30, plain: 1, xtream-neu: 1]|klartextBytes(alle)=[0, 0, 0]|probleme=[]
REVIEW|M3|abspielbar|geprueft=4498|abweichend=0
-- Abbruch (SIGKILL) 5 s nach Beginn der Umstellung, dann nächster Start --
REVIEW|M2|SIGKILL nach 5000 ms
REVIEW|M3|vorNeustart|zustaende=[file: 1, m3u-alt: 17, m3u-neu: 13, plain: 1, xtream-alt: 1]|schluesselbundBeiAltbestand=1|probleme=[]
REVIEW|M3|neustart|umstellung=6.54s|ergebnis=(migratedPlaylists: 18, rewrittenChannels: 39250, failedPlaylists: 0)
REVIEW|M3|nachNeustart|zustaende=[file: 1, m3u-neu: 30, plain: 1, xtream-neu: 1]|klartextBytes(alle)=[0, 0, 0]|probleme=[]
REVIEW|M3|abspielbar|geprueft=4498|abweichend=0
-- v1.1-Vorlage + 10 × 3.000 M3U mit Zugangsdaten + Xtream-Altbestand, SIGKILL nach 1,8 s, dann nächster Start --
REVIEW|M3|vorNeustart|zustaende=[file: 1, fixture: 1, m3u-alt: 5, m3u-neu: 5, plain: 1, xtream-alt: 1]|probleme=[]
REVIEW|M3|neustart|umstellung=1.98s|ergebnis=(migratedPlaylists: 6, rewrittenChannels: 12250, failedPlaylists: 0)
REVIEW|M3|nachNeustart|zustaende=[file: 1, fixture: 1, m3u-neu: 10, plain: 1, xtream-neu: 1]|klartextBytes(alle)=[0, 0, 0]|probleme=[]
REVIEW|M3|abspielbar|geprueft=1540|abweichend=0
```

„probleme=[]" heißt je Playlist: vorhanden, Senderzahl und `channelCount` gleich, dieselben Sender-IDs, dieselben Favoriten,
Zustand entweder vollständig alt oder vollständig neu (kein gemischter Zustand). Der eine Schlüsselbund-Eintrag beim
Altbestand gehört zur Playlist, die beim Abbruch gerade umgestellt wurde; der nächste Start überschreibt ihn. Die
Vorlagen-Playlist „B09 v1.1 Testliste" (3 Sender, Favorit „Sender 2") bleibt unverändert. Umstellung beim Aktualisieren
(Altbestand, Start-Umstellung nicht gelaufen, Review-Test M4): 0 Zeilen mit Passwort, Favorit bleibt, nach dem Schließen
0 Bytes. Rest: R-08, R-10.

**3 · Nebenläufigkeit `PlaylistStore`.**

```
REVIEW|C1|durchlaeufe=24|abweichungen=0      (Aktualisieren + Löschen derselben Playlist, 4.000 Sender mit Zugangsdaten;
                                              Anbieter 0/0,15/0,4 s verzögert, Löschen nach 0–1,3 s, jeder dritte Lauf
                                              zweimal gleichzeitig gelöscht; danach je 0 Playlists, 0 Sender, kein
                                              Schlüsselbund-Eintrag, keine Meldung)
REVIEW|C2|drei Importe gleichzeitig in 2.20 s|A: 6000/6000/6000 fremd=0 | B: 9000 (mit Zugangsdaten, Schlüsselbund) | C: 5000 (Datei)
REVIEW|C2|aktualisieren=ok|loeschen=ok|playlists=["B", "C", "D"]|favoritB=["Sender B7"]|sender gesamt=17000   (gleichzeitig)
REVIEW|C3|sender=17000|aktualisieren=ok|fertigNach=4.16s|gesetzt=13|inDatenbank=5|verloren=[Sender 3 … Sender 10]   → R-01
REVIEW|C5|leser=4.00s|nachLoeschenOffen=[-wal: 8469]|nachSchliessen=[0, 0, 0]|nachNeustart=[0, 0, 0]
```

C5: Hält eine andere Verbindung 4 s lang eine Leseabfrage offen, stehen die Namen gelöschter Sender bis zum Schließen im
`-wal`; ohne Leser sofort 0. Das Kriterium von B03 BUG-07 („nach Neustart 0") bleibt erfüllt – kein Fund.

**4 · Sicherheit.** Grenzen mit Standardwerten (Review-Test L1):

```
REVIEW|L1|mitLaenge=… zu groß (mehr als 64 MB). in 0.02 s|ohneLaenge=… zu groß (mehr als 64 MB). in 0.03 s speicher 298→420 MB
         |gzipBombe(97221 Byte gepackt)=… zu groß (mehr als 64 MB). in 0.04 s|datei65MB=Die Datei ist zu groß … in 0.00 s
         |symlink=Die Datei ist zu groß … in 0.00 s
```

Die Größenvorprüfung der Datei greift bei Symlinks nicht (`isRegularFile=false`), die Nachprüfung nach dem Einlesen
(`mappedIfSafe`) lehnt ab. `/dev/zero`, `/dev/urandom` und eine FIFO lehnt dieselbe Lesefunktion
(`Data(contentsOf:options:.mappedIfSafe)`) sofort mit „keine Berechtigung" ab (eigenes Kommandozeilenprogramm, gleiche
Aufrufe). Die 180-s-Frist mit Standardwerten ist nicht ausgeführt. Loader laut Code `ephemeral`, `urlCache = nil`,
`urlCredentialStorage = nil`. Im Diff keine neuen Protokollaufrufe; neu in `UserDefaults` nur der Merker
`B02.legacyHTTPCachePurged` (Bool). `AppDataReset` berührt nur den Schlüsselbund-Dienst `lu.daumedia.MikaPlusPlayer.xtream`,
die Einstellungs-Domäne der eigenen Bundle-ID, `URLCache.shared` der App, den Ordner `Beiseitegelegt` im App-Ordner und die
Loader-Cookies – nichts anderer Apps. Funde: R-03, R-04, R-09, R-11.

**5 · Außerhalb des Auftrags.** Systemweite Änderungen sind im Build-Bericht vollständig aufgeführt und entsprechen dem Diff
(Loader-Umbenennung, `stop()` in den Engines nur beim Löschen, Resolver, Multiview, Senderliste, Menüeinträge,
Info.plist, Testanpassungen). Darüber hinaus: R-07 und der Hinweis zu `features/befunde.md`/`index.md`.

**6 · Gesamtlauf** (`xcodebuild test`, `-derivedDataPath …/review-b0203/build/dd`, 20:36–21:53 Uhr, 468 Tests):

```
1. Start:  311 gestartet, 300 bestanden, 10 übersprungen, 0 nicht bestanden;
           hängt in B06EngineZustandTests.testAK10 (Hauptthread in VLCMediaPlayer.init → config_GetFloat →
           _pthread_rwlock_lock_wait, per `sample` aufgenommen) = bekannter B06 BUG-07 (libVLC), Prozess beendet
2. Start:  157 gestartet, 135 bestanden, 18 übersprungen, 4 nicht bestanden
** TEST FAILED **  – 435 bestanden, 28 übersprungen, 5 nicht bestanden
```

Alle Suiten B01 bis B05 (auch alle B02-/B03-Tests) bestanden. Nicht bestanden: B06 `testAK10_…` (Hänger, s. o.),
B06 `testAK24_GruenerKnopfVerstimmtPlayer`, B07 `testAK03_AK04_…`, B07 `testAK05_…`, B09 `testBUG02_…`
(„hdiutil: create failed – Ressource ist belegt"). Einzeln wiederholt: B09 bestanden; B06 AK-24 und B07 AK-03/AK-05
übersprungen („Test-Host wurde nicht aktiv (keyWindow=nil)"), weil gleichzeitig der Test-Host der B06-Reparatur lief.
Ein Zusammenhang mit B02/B03 ist nicht belegt; grün belegen konnte ich diese drei UI-Tests in dieser Umgebung nicht
(der Gesamtlauf der Verifikation vom 27.09. meldet sie bestanden). iOS-Build nicht wiederholt.

Aufgeräumt: Review-Worktree samt DerivedData entfernt, Datenträgerabbild ausgehängt und gelöscht, Test-Datenbanken und
Schlüsselbund-Testdienst gelöscht, eigene Prozesse beendet; keine Simulatoren angelegt.

## Nacharbeit nach Review 2026-09-27

Eingang: die Funde R-01 bis R-11 des Abschnitts *Review 2026-09-27* (oben), dazu die QA-Berichte von B02, B03 und B05
(BUG-01, BUG-11) · Fehlerauftrag-Eingang wie Durchlauf 1 · begonnen 2026-09-27, abgeschlossen 2026-09-28.

**Arbeitsweise.** Weil im Hauptarbeitsbaum gleichzeitig die Reparaturen von B06 und B07 Code ändern, ist der Code
ausschließlich in einem eigenen Git-Worktree auf `27be161` geändert und geprüft, DerivedData im Worktree; Vergleiche mit dem
Ausgangsstand in einem zweiten Worktree auf `27be161`. Beide sind am Ende entfernt. Ergebnis ist ein Patch gegen `27be161`,
den der Orchestrator einspielt:
`<Sitzungsordner>/nacharbeit-b0203.patch`
(Umfang unter *Patch*). Im Hauptarbeitsbaum sind nur diese beiden Berichte geändert. `PlayerView.swift`, die Engines,
`PlaybackEngine.swift`, `MultiviewSession.swift`, `ContentView.swift` und `XtreamCodes.swift` (Arbeitsgebiet B06/B07) sind
nicht angefasst. Nur erfundene Daten (`qa-user`, `qa-pass-nb-…`), Loopback-Server, Test-Schlüsselbunddienst des Laufs,
Temp-Datenbanken, ein eigenes 6-MB-Datenträgerabbild; kein Ton.

> **Unterbrechung.** Am 27.09. war die Nacharbeit bis auf den Gesamtlauf fertig – er lief gerade –, als die Sitzung abbrach
> und `/private/tmp` geleert wurde – mit dem damaligen Worktree (unter `/private/tmp`), allen Änderungen und Protokollen; ein Patch war noch
> nicht geschrieben. Am 28.09. ist dieselbe Lösung aus dem Verlauf neu aufgesetzt (dauerhafter Worktree unter
> `~/.claude/projects/…/wt/`), jede Reproduktion und jeder Test neu ausgeführt. Alle Messzeilen unten stammen vom 28.09.;
> Zahlen vom 27.09. stehen nur dort, wo sie ausdrücklich so markiert sind.

**Urteil je Fund:** alle elf bestätigt – durch eigene Reproduktion auf `27be161`; R-11 durch Reproduktion mit einem
Sitzungs-Cookie im Test-Host (ob beim Nutzer tatsächlich Cookies im gemeinsamen Speicher liegen, ist wie im Review nicht
geprüft, der Speicher der echten App wird nicht gelesen). Alle elf sind durch die Reparatur entstanden oder betreffen ihre
Tests; alle sind behoben bzw. (R-07) mit Belegen nachgeholt. Zurückgewiesen: keiner.

### 1 · Umgesetzt

| Fund | Reproduktion auf `27be161` (28.09.) | Änderung | Nachweis nachher (28.09.) |
|---|---|---|---|
| **R-01** (wichtig) | `NBAltR01…` (derselbe Test wie `B03NacharbeitTests.testR01_…`, Stern wie `ChannelRowView` auf `27be161`: umschalten + speichern), 17.000 Sender, 10 Sterne während des Aktualisierens und ein entfernter: **3, 2, 3 von 10** (M3U) und **2, 1 von 10** (Xtream) erhalten; in 2 von 5 Läufen ist zusätzlich der während des Laufs entfernte Stern wieder da | `FavoriteEdits` (neu, `PlaylistStore.swift`) ist der eine Weg für den Stern (`ChannelRowView`) und hält während eines Aktualisierens jede Stern-Änderung an Sendern dieser Playlist fest. `replaceChannels` liefert zusätzlich, welche alten Sender beim Lesen Favorit waren (`FavoriteCarryOver.State`); `refresh` zieht danach alle festgehaltenen Änderungen über `PlaylistStore.reconcileFavorites` auf die neuen Sender nach – wiederholt, bis keine neue mehr dazukommt – und erst dann holt die Ansicht die neuen Sender ab. Das Ersetzen läuft unverändert im Hintergrund | `testR01_…` in **9 Läufen (5 × M3U, 4 × Xtream) je 10 von 10** erhalten, der entfernte Stern bleibt entfernt, Kontrollfavorit bleibt, 17.000 Sender, 0 ohne Playlist, Blockade ≤ 0,01 s; `testR01b_…` trifft über einen Test-Haken genau den Moment „Ersetzen gespeichert, Ansicht zeigt noch die alten Sender": 3 Sterne und eine Entfernung übernommen, Ansicht ohne offene Änderungen. Gegenprobe am 27.09.: mit abgeschaltetem Nachziehen schlagen beide Tests fehl (3/10 bzw. 0/3) |
| R-02 | 6-MB-Abbild, 3 MB belegt, 40.000 Sender per URL: Meldung „The operation couldn’t be completed. (NSSQLiteErrorDomain error 13.)“, Playlist „Voll“ mit 10.000 von 40.000 Sendern in Ansicht und Datei (auch nach dem Neuöffnen) | `PlaylistStore.create`: Die Playlist trägt bis zum letzten Block `channelCount = -1` („unfertig"), die Übersicht blendet sie aus (`Playlist.isUnfinished`); Fehler außer Abbruch werden zu „Die Playlist konnte nicht gespeichert werden. Bitte freien Speicherplatz prüfen und erneut versuchen." (`PlaylistStoreError.createFailed`); misslingt auch das sofortige Aufräumen (Datenträger voll), entfernt `removeUnfinished` den Rest beim nächsten Anlegen bzw. beim nächsten Start. Kommentar zu `create` berichtigt | deutsche Meldung, Übersicht leer (vor und nach dem Neuöffnen), kein Schlüsselbund-Eintrag; nach Freigabe von Platz und nächstem Start 0 Playlists, 0 Sender in der Datei; `testR02_UnfertigePlaylistWirdEntfernt` (ohne Abbild): ein unfertiger Rest verschwindet beim nächsten Import bzw. bei der Wartung beim Start, die fertige Playlist bleibt |
| R-03 | `split` für `http://qa-info:qa-pass-info@h.example/get.php?username=qa-user&password=qa-pass-query` → gespeichert `http://qa-info:qa-pass-info@…` (Benutzerinfo im Klartext) | `M3USecret` mit optionalen `infoUsername`/`infoPassword` (ältere Schlüsselbund-Einträge lesen sich unverändert), eigene Platzhalter `_mikaplus_info2_benutzer_`/`_mikaplus_info2_passwort_` für eine Benutzerinfo mit eigenem Passwort; `restore` setzt beide wieder ein | gespeichert `http://_mikaplus_info2_benutzer_:_mikaplus_info2_passwort_@…?username=_mikaplus_query_benutzer_&password=_mikaplus_query_passwort_…`, Wiederherstellung ergibt exakt die Eingabe; Stream-Adressen aller Formen verlustfrei; Import + Aktualisieren über den echten Weg: 0 Bytes beider Passwörter in der Datei, Aktualisieren ruft `GET /get.php?username=qa-user&password=qa-pass-nb-query` ab, Schlüsselbund hält die Adresse wie eingegeben |
| R-04 | Container im Speicher → `storeURL = nil`, `Targets.app(…).setAsideFolder = nil` | `AppDataReset.Targets.setAsideFolder(container:appStoreURL:)`: ohne Datei-Container der Speicherort der App (`AppPersistence.appStoreURL()`, legt nichts an); im Test-Host weiter `nil` | `testR04_…`: Rückfall nachgestellt (Datei beiseitegelegt, Sitzung im Speicher), „Alle Daten entfernen" entfernt `Beiseitegelegt/` samt Datei; im Test-Host `nil` |
| R-05 | Test verwarf die LaunchServices-Liste (`_ = offered`) | `testAK31d_AK32_…` prüft wieder wörtlich, ob LaunchServices **dieses** gebaute Bundle als Öffner anbietet (`.m3u`/`.m3u8` ja, zehn andere Arten nein), dass es registriert ist (sonst registriert der Test es für die Dauer der Prüfung selbst und nimmt das danach mit `lsregister -u` zurück) und dass das Info.plist keinen weiteren Registrierungsweg (`CFBundleTypeExtensions`, `…OSTypes`, `…MIMETypes`) trägt | im Gesamtlauf bestanden; LaunchServices bietet dieses Bundle für `m3u`, `m3u8` an, für die zehn anderen Arten nicht (Bundle war registriert, der Test musste nicht selbst registrieren) |
| R-06 | `XCTAssertLessThanOrEqual(created.count, 1)` | `testAK31_…`: genau 0 neue Fenster, wenn vorher ein Fenster der Hauptszene offen war, sonst genau 1; Meldungs-Sheets zählen nicht als Fenster | Hauptfenster vorher offen, 0 neue Fenster bei drei Ereignissen; im Gesamtlauf bestanden |
| R-07 | Begründung nicht nachgeprüft, Treffer nicht dokumentiert | beide Tests protokollieren jetzt, was das Zeitfenster ausschließt (`AK-23\|R-07\|…`, `AK-41\|R-07\|…`), B07 zusätzlich die Quellen der ausgeschlossenen Treffer; Assertions unverändert | siehe *Verifikation*, R-07 |
| R-08 | Umstellung ohne Verdichten, danach Klartext in freien Seiten, nächster Start: `migratedPlaylists: 0`, kein Verdichten, **2.456 Bytes** Klartext bleiben (41 freie Seiten) | Merker `B02.credentialCompactionPending` (Einstellungen der App): gesetzt vor dem ersten Speichern einer Umstellung, entfernt nach gelungenem `VACUUM` (`compactStore` meldet jetzt Erfolg); steht er, verdichtet der nächste Start auch ohne neue Umstellung | Merker gesetzt, nächster Start verdichtet: 0 Bytes in Store, `-wal`, `-shm`; Merker danach entfernt |
| R-09 | alter `testAK31_…` importierte eine `.txt` über „Öffnen mit" | `PlaylistDocumentHandler` nimmt nur `.m3u`/`.m3u8` (wie der Datei-Reiter), sonst Alert „Import fehlgeschlagen" mit „Nur M3U-Playlists (.m3u, .m3u8) lassen sich importieren." (`ImportError.unsupportedFile`); eine iOS-Kopie in `Inbox` wird auch dann entfernt | `testAK31_…` (Ereignis an den Test-Host): `.m3u` und `.m3u8` importiert, `.txt` mit Meldung abgelehnt, Meldung bestätigt, keine offen; `testR09_…` |
| R-10 | wie `finishLaunch` beim Start, 10 × 3.000 M3U + 1.000 Xtream mit Zugangsdaten (Debug): Umstellung auf dem Main-Thread **4,25 s**, Blockade 4,25 s (Review mit 91.000 Sendern: 11,19 s) | `LaunchMaintenance` (neu, `AppPersistence.swift`): Die Umstellungen beim Start (Reste entfernen, Zugangsdaten umstellen und verdichten, alten Cache leeren) laufen im Hintergrund auf `PlaylistStore`, also nie gleichzeitig mit Anlegen, Aktualisieren oder Löschen. Das Fenster erscheint sofort; solange die Umstellung läuft, deckt `LaunchMaintenanceCover` die Oberfläche ab (gesperrt, für Bedienungshilfen verborgen) und zeigt nach 0,4 s „Gespeicherte Playlists werden aktualisiert …" | `testR10_…`, gleiche Daten: `start` kehrt nach 0,00 s zurück, Umstellung 4,2–4,4 s im Hintergrund, **Blockade 0,00 s**, alles umgestellt (11 Playlists, 31.000 Adressen, 0 Bytes Klartext, 10 Favoriten, 11 Schlüsselbund-Einträge); Testfenster zeigt während der Umstellung nur den Hinweis, danach nur den Inhalt |
| R-11 | Sitzungs-Cookie im gemeinsamen Speicher des Test-Hosts, „Alle Daten entfernen“ (Standardziele) → Cookie bleibt (1) | `AppDataReset.Targets.sharedCookies` (App: `HTTPCookieStorage.shared`; Test-Host und Standard: `nil`) – alle Cookies dort werden entfernt | `testR11_…` mit eigenem Speicher im Arbeitsspeicher: 2 → 0 Cookies; im Test-Host bleibt der Speicher der App unangetastet |

Neue Tests: `Tests/B02/B02NacharbeitTests.swift` (7), `Tests/B03/B03NacharbeitTests.swift` (4). Geänderte Tests:
`B02OberflaecheTests.testAK31_…` (R-06, R-09) und `testAK31d_AK32_…` (R-05) – beide strenger als vorher;
`B02SicherheitTests.testAK41_…` und `B07DatenschutzTests.testAK23_…` nur um Protokollzeilen ergänzt (R-07). Kein
`XCTExpectFailure` hinzugefügt; einziges neues `XCTSkip` ist der Abbild-Schalter von `testR02_ImportAufVollemDatentraeger…`
(wie `B05AktualisierenTests.testAK17_Randfall_…`), im Gesamtlauf gesetzt.

### 2 · Offen

- **R-10, Anzeige in der echten App nicht gesehen:** Die App wurde nach den Regeln nicht regulär gestartet (sie würde die
  Datenbank des Nutzers übernehmen). Belegt sind die Hintergrund-Umstellung und die Abdeckung in einem Testfenster
  (`testR10_…`: Hinweis während der Umstellung, Inhalt verdeckt, danach Inhalt ohne Hinweis). Unter iOS gilt wie für die übrige
  Reparatur: gebaut, nicht bedient.
- **R-02 bei dauerhaft vollem Datenträger:** Der unfertige Rest bleibt unsichtbar in der Datei, bis wieder Platz ist; SQLite
  braucht auch zum Löschen Platz im Write-Ahead-Log. Auch „Alle Daten entfernen" braucht dann Platz.
- **Ausgangslage `76caeb0` (R-07):** nicht erneut als Gesamtlauf ausgeführt. Belegt ist stattdessen, was das Zeitfenster
  heute ausschließt (siehe *Verifikation*): Es sind Einträge früherer Tests desselben Prozesses (darunter zwei
  App-Protokollzeilen der B09-Wiederherstellung aus `B01QA2Tests`), keiner aus dem jeweiligen Test selbst.
- **Oberflächentests von B06, B07, B08 nicht grün belegt:** In den Gesamtläufen vom 28.09. scheiterten je Lauf andere
  Oberflächentests dieser Features (Schlüsselfenster, Tastatur, Klicks); einzeln wiederholt wurden sie übersprungen, weil der
  Test-Host nicht nach vorn kam – auf `27be161` ebenso. Kein Bezug zum Patch nachweisbar, siehe *Verifikation*, Abschnitt 3.
  Im abgebrochenen Lauf vom 27.09. hing außerdem `B06EngineZustandTests.testAK10_…` im bekannten libVLC-Hänger (B06 BUG-07,
  per `sample`: Hauptthread in `VLCMediaPlayer.init` → `config_GetFloat` → `_pthread_rwlock_lock_wait`), und
  `B07AngriffTests.testAngriff3_…` fiel einmal durch (zwei PiP-Fenster); am 28.09. trat beides nicht auf. Die Protokolle vom
  27.09. sind mit `/private/tmp` verloren.
- **Belege der QA:** Die Tests schreiben bei jedem Lauf nach `features/*/qa/`; im Worktree ist das vor dem Erzeugen des
  Patches zurückgenommen, der Patch enthält keine Nachweisdateien.

### 3 · Getroffene Annahmen

1. **R-01, Nachziehen statt Sperren.** Gewählt ist das Festhalten und Nachziehen, nicht das Sperren des Sterns. Grund: Ein
   Aktualisieren dauert bis zum Ende des Abrufs – bei langsamen Anbietern bis zur Gesamtfrist von 180 s, bei Xtream drei
   Anfragen –, und der Stern wäre so lange für die ganze Playlist gesperrt, auch im Favoriten-Tab. Das Nachziehen hält den
   Stern bedienbar, das Aktualisieren läuft unverändert im Hintergrund (Blockade im Test ≤ 0,01 s). Nachgezogen wird so, als
   wäre die Änderung vor dem Lesen gespeichert worden: dieselbe Regel `FavoriteCarryOver` (Adresse → Name → erster Kandidat),
   berechnet aus dem tatsächlich gelesenen Stand je Sender. Eine Änderung, die das Lesen schon gesehen hat, ändert also
   nichts, und es entstehen keine zusätzlichen Sterne (B03 BUG-02 bleibt behoben). Scheitert das Speichern des Nachziehens,
   meldet das Aktualisieren „Die Playlist wurde aktualisiert, aber Sterne, die während des Aktualisierens gesetzt oder
   entfernt wurden, konnten nicht gespeichert werden. Bitte die Favoriten dieser Playlist prüfen."
2. **R-01, Restfenster.** Zwischen dem Abholen durch die Ansicht (`synchronizeView`) und dem Neuzeichnen der Liste liegt
   kein Ereignis-Durchlauf; ein Klick auf eine alte Zeile nach dem Ende des Festhaltens ist damit praktisch ausgeschlossen,
   aber nicht durch einen Test belegt. Sender ohne `playlistID` (nur in beschädigten Beständen denkbar) werden nicht
   festgehalten.
3. **R-01, Test-Haken.** `PlaylistStore.setAfterReplaceSavedForTesting` (nur Tests) trifft den Moment nach dem Speichern des
   Ersetzens deterministisch; im Betrieb ist er `nil`.
4. **R-02, Markierung `channelCount = -1`.** Kein Schemawechsel. Folge über R-02 hinaus: Wird die App während eines Imports
   beendet (Absturz, Abmelden), verschwindet der halbe Import beim nächsten Start, statt als unvollständige Playlist sichtbar
   zu bleiben; während eines Imports ist die entstehende Playlist in der Übersicht nicht zu sehen (sie erschien vorher
   blockweise wachsend). Die Meldung gilt auch für den Xtream-Import (gleicher Weg).
5. **R-03:** Nur wenn Benutzerinfo und Query verschiedene Passwörter tragen, bekommt der Schlüsselbund-Eintrag die zwei
   neuen Felder; sonst bleibt er wie bisher. Adressen, die ein Entwicklungsstand seit `27be161` schon so gespeichert hat (mit
   Klartext in der Benutzerinfo, Platzhaltern in der Query), stellt der nächste Start nicht um, weil `split` sie wegen der
   Platzhalter als umgestellt ansieht; ein neuer Import speichert sie richtig. Eine veröffentlichte Version war nicht
   betroffen.
6. **R-05:** Ist das gebaute Bundle bei LaunchServices nicht registriert (heute: war es), registriert der Test es für die
   Dauer der Prüfung und hebt das danach auf. Nur dieser eine Pfad, keine anderen Kopien.
7. **R-08:** Merker in den Einstellungen der App (entfernt auch „Alle Daten entfernen"). Der Test stellt den Rest eines
   abgebrochenen Laufs deterministisch her (Klartext in freien Seiten über eine eigene Verbindung ohne `secure_delete`),
   weil ein echter Abbruch nur zufällig einen Rest hinterlässt (Review: 1 bzw. 0 Vorkommen).
8. **R-09:** Prüfung über die Endung wie beim Datei-Reiter (`.m3u`, `.m3u8`, Groß-/Kleinschreibung egal).
9. **R-10:** Hinweis erst nach 0,4 s, damit der Normalfall (nichts umzustellen, Millisekunden) nicht flackert. „Öffnen mit",
   Aktualisieren, Löschen und „Alle Daten entfernen" warten während der Umstellung hinter ihr (gleicher Actor), statt
   gleichzeitig zu schreiben; die Oberfläche ist in dieser Zeit abgedeckt. Das Leeren des alten HTTP-Caches läuft danach,
   ebenfalls im Hintergrund. **Als Überlagerung, nicht als Weiche:** Die erste Fassung setzte an die Wurzel des Fensters
   eine Weiche „Hinweis oder `ContentView`“. Mit ihr fiel `B03OberflaecheTests.testAK12_AK13_…` wiederholt durch: Ein
   Kontextmenü, das der Test während einer laufenden Aktualisierung öffnet und sofort wieder schließt, blieb 45–68 s offen
   (auf `27be161` 0,4–3,7 s). Mit `ContentView` direkt an der Wurzel bzw. mit der Überlagerung war derselbe Test grün. Ein
   ursächlicher Zusammenhang ist aber **nicht belegt**: Zur selben Zeit liefen Test-Hosts anderer Agenten, und derselbe Effekt
   trat später einmal auch mit der Überlagerung auf (`B02OberflaecheTests.testAK16_…`, Kontextmenü 924 s offen, Test grün),
   während die Gesamtläufe 2 und 3 mit der Überlagerung ohne ihn blieben. Beibehalten ist die
   Überlagerung – `ContentView` bleibt immer im Baum, der Zustand der Ansichten geht nicht verloren.
10. **R-11:** Entfernt werden alle Cookies in `HTTPCookieStorage.shared` der App, also auch solche, die AVPlayer beim
    Abspielen dort ablegt – passend zu „Alle Daten entfernen".

### 4 · Systemweite Änderungen

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Services/PlaylistStore.swift` | B02, B03, B05, **B01** | `FavoriteCarryOver.State`, `FavoriteEdit`, `FavoriteEdits` (Stern-Weg), `ReplaceOutcome.replaced(channelCount:carryOver:)` (nicht mehr `Equatable`), `reconcileFavorites`, `unfinishedChannelCount`, `removeUnfinished`, `launchMaintenance`, Test-Haken; `create` wirft `PlaylistStoreError.createFailed` statt SQLite-Fehlern (**auch beim Xtream-Import, B01**); neue Fälle `createFailed`, `favoritesNotSaved`; `Playlist.isUnfinished` (berechnet, kein Schemafeld) |
| `Sources/Views/ChannelRowView.swift` | **B04, B05** | Stern über `FavoriteEdits.toggle` (gleiches Verhalten, zusätzlich festgehalten) |
| `Sources/Views/PlaylistsView.swift` | B03 | Übersicht blendet unfertige Playlists aus |
| `Sources/Services/PlaylistImporter.swift` | B02, B03, B01 | `refresh` hält Sterne fest und zieht sie nach; `ImportError.unsupportedFile` |
| `Sources/Services/M3UCredentials.swift` | B02 | `M3USecret.infoUsername`/`infoPassword`, zwei Platzhalter |
| `Sources/Services/AppPersistence.swift` | alle, **B01, B09** | `openAppStore` (`@MainActor`) startet die Umstellungen im Hintergrund (`LaunchStore.maintenance`, `LaunchMaintenance`); `finishLaunch` ist `async` und parametrisiert; `migrateCredentials(…, defaults:)` mit Merker; `compactStore` meldet Erfolg; `appStoreURL()` |
| `Sources/App/MikaPlusPlayerApp.swift` | alle | `ContentView` mit `launchMaintenanceCover` (Abdeckung während der Umstellung) |
| `Sources/Services/AppDataReset.swift` | B03, **B09** | `sharedCookies`, `setAsideFolder(container:appStoreURL:)` |
| `Sources/Views/PlaylistDocumentHandler.swift` | B02 | Typprüfung; Typ nicht mehr `private` (Test) |
| `UserDefaults` | alle | neuer Merker `B02.credentialCompactionPending` (Bool) |
| Tests anderer Features | B07 | `B07DatenschutzTests.testAK23_…`: nur Protokollzeilen (R-07) |

Nicht angefasst: `project.yml`, `Info.plist`, Modelle und Schema, `PlayerView.swift`, Engines, `PlaybackEngine.swift`,
`MultiviewSession.swift`, `ContentView.swift`, `XtreamCodes.swift`, `features/index.md`, `features/befunde.md`, QA-Berichte.
Die neuen Dateien sind Testdateien (von `xcodegen` über `path: Tests` erfasst; nach dem Einspielen `xcodegen generate`).

### Verifikation

Stand **2026-09-28**, Worktree auf `27be161` mit den Änderungen des Patches. Ausgaben gefiltert auf
`** (BUILD|TEST) (SUCCEEDED|FAILED) **`, `Executed N tests`, `error:` und die Messzeilen der Tests (Temp-Pfade gekürzt).
Rechner: Apple M3 Max, 16 Kerne, macOS 27, Xcode 27A266a. Während der Läufe liefen Test-Hosts und Builds anderer Agenten
(B06, B07, Review B06) im Hauptarbeitsbaum bzw. eigenen Worktrees; der Gesamtlauf hat mitgeschrieben, wann (`fremd: …`).

**1 · Reproduktion auf `27be161`** (zweiter Worktree, derselbe Testcode, Stern wie `ChannelRowView` dort):

```
B03QA|ALT|R-01|ergebnis|m3u#1: 3/10 · m3u#2: 2/10 · m3u#3: 3/10 · xtream#1: 2/10 · xtream#2: 1/10
B03QA|ALT|R-01|m3u|runde=2|…|gesetztWaehrendDesLaufs=10|erhalten=2|entferntBleibtEntfernt=false|kontrolle=true|…
B02QA|ALT|R-02|meldung=The operation couldn’t be completed. (NSSQLiteErrorDomain error 13.)|ansicht=["Voll=10000"]|nachNeuoeffnen=["Voll=10000"]|sender=10000
B02QA|ALT|R-03|gespeichert=http://qa-info:qa-pass-info@h.example/get.php?username=_mikaplus_query_benutzer_&password=_mikaplus_query_passwort_&type=m3u|klartextInfo=true
B02QA|ALT|R-04|storeURL(imSpeicher)=nil|setAsideFolder=nil
B02QA|ALT|R-08|ersterStart=(migratedPlaylists: 3, rewrittenChannels: 600, failedPlaylists: 0)|klartextInFreienSeiten=2456|naechsterStart=(migratedPlaylists: 0, …)|klartextDanach=2456|freieSeiten=41
B02QA|ALT|R-10|sender=31000|umstellungAufMainThread=4.25s|mainThreadBlockade=4.25s|ergebnis=(migratedPlaylists: 11, rewrittenChannels: 31000, failedPlaylists: 0)|build=Debug
B02QA|ALT|R-11|cookieImGemeinsamenSpeicherNachAlleDatenEntfernen=1
```

**2 · Nachher, Einzelläufe** (`-only-testing:`):

```
B03QA|R-01|ergebnis|m3u#1: 10/10 · m3u#2: 10/10 · m3u#3: 10/10 · m3u#4: 10/10 · m3u#5: 10/10 · xtream#1: 10/10 · xtream#2: 10/10 · xtream#3: 10/10 · xtream#4: 10/10
B03QA|R-01|m3u|runde=1|sender=17000|import=2.21s|aktualisieren=3.96s|gesetztWaehrendDesLaufs=10|erhalten=10|entferntBleibtEntfernt=true|kontrolle=true|favoritenDatei=11|sender=17000|ohnePlaylist=0|mainThreadBlockade=0.00s|build=Debug
   (Runde 2 und 4 der M3U-Läufe setzen die Sterne über 3,2 s bis in die zweite Hälfte des Aktualisierens)
Test Case '-[MikaPlusPlayerTests.B03NacharbeitTests testR01_SterneWaehrendDesAktualisierensBleibenErhalten]' passed (72.378 seconds).
B03QA|R-01b|senderMitNameInDatei=1|speichernDerAnsichtOhneFehler=true|favoritenDatei=["Sender 11", "Sender 22", "Sender 33"]|sender=5000|ohnePlaylist=0|alterSenderInDatei=0|kontextHatAenderungen=false
B02QA|NB|R-02|meldung=Die Playlist konnte nicht gespeichert werden. Bitte freien Speicherplatz prüfen und erneut versuchen.|kontext=["Voll=-1"]|uebersicht=[]|dateiNachNeuoeffnen=["Voll=-1"]|uebersichtNachNeuoeffnen=[]|schluesselbund=0|nachPlatzUndStart(playlists,sender)=["0", "0"]
B02QA|NB|R-08|…|merker=true|klartextInFreienSeiten=2456|freieSeiten=41|naechsterStart=(migratedPlaylists: 0, …)|klartextDanach=[store: 0, -wal: 0, -shm: 0]|merkerDanach=false
B02QA|NB|R-10|sender=31000|startKehrtZurueckNach=0.00s|laeuftDanach=true|dauer=4.39s|mainThreadBlockade=0.00s|fensterWaehrendDerUmstellung=["Gespeicherte Playlists werden aktualisiert …"]|fensterDanach=["QA Inhalt R-10"]|klartext=[0, 0, 0]|schluesselbund=11|favoriten=10
AK-31|testHost|qa-oeffnen.txt|meldung=["AXStaticText:Import fehlgeschlagen", "AXStaticText:Nur M3U-Playlists (.m3u, .m3u8) lassen sich importieren."]
AK-31|testHost|szenenfensterVorher=1|neueFenster=0|importiertSichtbar=2|txtAbgelehnt=true|fehler=[]|offeneMeldungen=0
AK-31d/AK-32|diesesBundle|launchServices|angeboten=["m3u", "m3u8"]|registriert=true|vomTestRegistriert=false
** TEST EXECUTE SUCCEEDED **   (je Einzellauf)
```

R-02 lief mit einem eigenen 6-MB-HFS+-Abbild (`hdiutil create -size 6m -fs HFS+`, eingehängt mit `-nobrowse`,
`TEST_RUNNER_B02_NB_VOLUME=<Mountpoint>`), danach ausgehängt und gelöscht.

**3 · macOS-Gesamtläufe** – `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd -collect-test-diagnostics never`,
`TEST_RUNNER_B02_NB_VOLUME` gesetzt. Ein Wachhund hätte nur den bekannten libVLC-Hänger (6 min ohne Fortschritt in B06)
beendet – er musste in keinem Lauf eingreifen. Mitgeschrieben: fremde Test-Hosts und Bildschirmsperre.

```
Lauf 2 (18:34–19:25, fremder Test-Host 18:41–19:14):
	 Executed 479 tests, with 27 tests skipped and 2 failures (0 unexpected) in 3041.129 (3041.369) seconds
** TEST FAILED **      B06PlayerViewTests: testAK23_ZweiFensterVollbildTrifftSchluesselfenster, testAK24_GruenerKnopfVerstimmtPlayer
Lauf 3 (20:00–20:52, kein fremder Test-Host, Bildschirm entsperrt):
	 Executed 479 tests, with 28 tests skipped and 7 failures (0 unexpected) in 3053.725 (3054.026) seconds
** TEST FAILED **      B06PlayerViewTests: testAK01_AK14_…, testAK21_AK19_EC07_… („SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:“)
                       B07KnopfTests: testAK06_PWaehrendDesLadens_… (dasselbe)
                       B08NachtragTests: testAK14_AK15_AK16_KlicksBeiAktiverApp (Klick fokussiert die Kachel nicht)
```

In **beiden** Läufen bestanden alle Suiten von B01 bis B05 (auch alle B02-/B03-Oberflächentests, `B02NacharbeitTests` 7/7,
`B03NacharbeitTests` 4/4 mit R-01 je 10/10), B09, `M3UParserTests`, `PlaybackEngineTests`, `XtreamCodesTests`. 479 Tests =
468 vom 27.09. + 11 neue; übersprungen 27 bzw. 28 aus denselben Schaltern wie am 27.09.; der Unterschied liegt nur in `B06PlayerViewTests`
(Lauf 3: `testAK22_HoverAmOberenRandImVollbild` übersprungen – „Synthetische Mausbewegung erreicht
onContinuousHover nicht“). Die Fehlschläge sind Oberflächentests von B06,
B07 und B08, die das Schlüsselfenster, Tastatur- oder Mausereignisse brauchen – **in jedem Lauf andere**: Was in Lauf 2
scheiterte, bestand in Lauf 3 und umgekehrt. Einzeln wiederholt (20:52 Uhr, reparierter Stand) wurden alle sechs
*übersprungen* („Test-Host wurde nicht aktiv bzw. Fenster nicht Schlüsselfenster“): vorne blieb die App, in der die Agenten
laufen; auch ein Helfer über `B06_ACTIVATE_REQ` (`osascript`, „frontmost“) holte den Test-Host nicht nach vorn. Auf `27be161`
verhielten sich `testAK23_…` und `testAK24_…` einzeln genauso (übersprungen); zwischen 19:31 und etwa 20:00 Uhr war der
Bildschirm außerdem gesperrt. Grün belegen ließen sich diese Oberflächentests hier nicht. Der Patch ändert keinen Code von
B06, B07 oder B08; im Test-Host ändert er am Hauptfenster nur die Überlagerung aus R-10, die ohne laufende Umstellung leer
ist. Der libVLC-Hänger B06 BUG-07 trat am 28.09. in keinem Lauf auf.

**Nach Lauf 3 geändert (nur Test):** `testR08_…` benutzte eine eigene Einstellungs-Suite; `cfprefsd` legte deren Datei
nach dem Test wieder unter `~/Library/Preferences` ab (sechs Dateien `lu.daumedia.MikaPlusPlayerTests.nb.*.plist`, entfernt).
Jetzt nimmt der Test Einstellungen nur im Arbeitsspeicher (`NBMemoryDefaults`). Danach `B02NacharbeitTests` einzeln mit
Abbild: 7 Tests, 0 Fehlschläge, keine Datei unter `~/Library/Preferences`, keine neue Warnung; der Patch ist danach neu
erzeugt und geprüft.

Erster Anlauf (17:49 Uhr, abgebrochen): `B02OberflaecheTests.testAK16_DateiPlaylistSymbolUndKontextmenue` bestand, brauchte
aber 924 s, weil das Kontextmenü des Tests offen blieb (siehe Annahme 9); abgebrochen, um die Ursache zu prüfen. In Lauf 2
und 3 dieselbe Suite in 2 Minuten, ohne Fehlschlag.

**R-07 · was das Zeitfenster ausschließt** (aus Lauf 2; Lauf 3 gleich aufgebaut):

```
B02QA|AK-41|R-07|vorStart=29852|davonDerApp=2|ohneZeitfenster eintraegeDerApp=2
B02QA|AK-41|R-07|ausgeschlossen|…|lu.daumedia.MikaPlusPlayer|Persistenz|Datenbank ließ sich nicht öffnen: SwiftData.SwiftDataError 1 …
B02QA|AK-41|R-07|ausgeschlossen|…|lu.daumedia.MikaPlusPlayer|Persistenz|Datenbank beiseitegelegt und neu angelegt
B07QA|AK-23|R-07|vorStart=121041|davonMitNadel=276|fruehester=2026-09-28T16:34:04Z
B07QA|AK-23|R-07|ohneZeitfenster|quellen=[(key: "netzwerk", value: 272), (key: "sonstige:com.apple.coremedia", value: 4)]
B07QA|AK-23|app=0 pip/avkit=0 netzwerk=1 sonstige=0
```

Die zwei App-Einträge, die AK-41 ohne Zeitfenster mitzählen würde, schreibt `B01QA2Tests.testQA2_B09Wiederherstellung_…`
(B09-Wiederherstellung, lief um 18:37:42 Uhr im selben Prozess) – mit `appSubsystem == 0` schlüge AK-41 daran fehl. Bei
AK-23 kämen 276 ältere Treffer hinzu: 272 Netzwerkzeilen und 4 Zeilen von `com.apple.coremedia` aus früheren
Wiedergabe-Tests; die Assertion „keine weiteren Quellen“ schlüge an den `coremedia`-Zeilen fehl. Keiner der ausgeschlossenen
Einträge stammt aus dem jeweiligen Test oder von der App während dieses Tests. Beide Quellen (B01QA2, B06/B07-Wiedergabe)
sind älter als `27be161`; die Aussage „vorbestehender Fehlschlag“ ist damit belegt, ohne dass `76caeb0` neu gebaut wurde.

**4 · iOS-Simulator-Build** – `xcodebuild build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`:

```
appintentsmetadataprocessor[…] warning: Metadata extraction skipped, no AppIntents.framework dependency found   ← wie Baseline
** BUILD SUCCEEDED **
```

**5 · Warnungen** – sauberer macOS-Build mit Tests (eigener DerivedData-Ordner): 32 Warnungen, dieselben wie im Build von
`27be161` (verglichen ohne Zeilennummern), keine in `Sources/`, keine auf einer geänderten oder neuen Zeile. **Keine neue
Warnung.**

**6 · Zusammenspiel mit B06/B07** – Stand des Hauptarbeitsbaums vom 28.09. (B06-/B07-Änderungen in `Sources/` und `Tests/`)
in einem Hilfs-Worktree auf `HEAD`, darauf der Patch: `git apply` ohne Konflikt, macOS `build-for-testing` und iOS-Build
`** … SUCCEEDED **`. Nur gebaut, nicht getestet (die B06/B07-Arbeit läuft noch).

### Patch

`<Sitzungsordner>/nacharbeit-b0203.patch`
(1.733 Zeilen, SHA-256 `81d978581a45090dc496203146abfb342c3bc41c33937ea861c977fed572cdeb`), erzeugt mit `git diff` im Worktree
(neue Dateien vorher `git add -N`), Nachweisdateien unter `features/` vorher zurückgenommen:

```
$ git apply --stat nacharbeit-b0203.patch
 Sources/App/MikaPlusPlayerApp.swift         |   52 ++++
 Sources/Services/AppDataReset.swift         |   33 ++-
 Sources/Services/AppPersistence.swift       |  118 ++++++++-
 Sources/Services/M3UCredentials.swift       |   48 +++-
 Sources/Services/PlaylistImporter.swift     |   31 ++
 Sources/Services/PlaylistStore.swift        |  230 +++++++++++++++++-
 Sources/Views/ChannelRowView.swift          |    4
 Sources/Views/PlaylistDocumentHandler.swift |   14 +
 Sources/Views/PlaylistsView.swift           |    3
 Tests/B02/B02NacharbeitTests.swift          |  354 +++++++++++++++++++++++++++
 Tests/B02/B02OberflaecheTests.swift         |   73 +++++-
 Tests/B02/B02SicherheitTests.swift          |   14 +
 Tests/B03/B03NacharbeitTests.swift          |  245 +++++++++++++++++++
 Tests/B07/B07DatenschutzTests.swift         |   19 +
 14 files changed, 1178 insertions(+), 60 deletions(-)
$ git apply --check nacharbeit-b0203.patch      # frischer Worktree auf 27be161        → ohne Ausgabe (OK)
$ git -C <Hauptarbeitsbaum> apply --check …     # Stand 28.09. mit B06/B07-Änderungen → ohne Ausgabe (OK)
```

Einspielen: `git apply nacharbeit-b0203.patch`, dann `xcodegen generate` (zwei neue Testdateien). Keine der 14 Dateien ist im
Hauptarbeitsbaum von B06/B07 geändert.
