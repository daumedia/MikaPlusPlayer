# B01 · Xtream-Codes-Login — Testbericht

Durchlauf 2 · Stand: 2026-09-16 · Geprüft gegen `spec.md` vom 2026-09-15 (Offene Fragen ergänzt 2026-09-16) ·
Code-Stand `c01f1cf` + Reparatur B01 + Reparatur B09 (Arbeitsbaum, nicht committet)

Durchlauf 1 steht unverändert weiter unten. Dort ist unter jedem BUG das Ergebnis der erneuten Prüfung vermerkt.

## Fazit (Durchlauf 2)

**Production-ready: ja** — höchster offener Schweregrad **mittel**; kein kritischer oder hoher Befund.

Die drei Funde mit dem Grad *hoch* aus Durchlauf 1 sind behoben, geprüft mit den ursprünglichen Reproduktionen und
nicht nur mit den umgestellten Tests. Nach Import und Umstellung steht in keiner Datei der Datenbank ein Passwort oder
Benutzername, auch nicht in `-wal`/`-shm`, weder bei offenem noch bei geschlossenem Container. Das gilt auch über den echten
Startpfad: Übernahme der `default.store`, dann Öffnen mit dem versionierten Schema aus B09, dann Umstellung. Auf iOS ist
das im Simulator an der laufenden App belegt, samt Zugriffsklasse `cku` im Schlüsselbund. Bei `HTTPS://` sieht ein
Server, der jedes Byte mitschreibt, nur noch einen TLS-Handshake (erstes Byte `0x16`), keinen Klartext. 17.000 Sender
brauchen 2,1 s und blockieren den Main-Thread höchstens 0,01 s (vorher 285 s). Die neuen Grenzen greifen genau:
64 MiB auf das Byte, 100.000 Sender auf den Sender, 180 s auf die Zehntelsekunde. Die 64-MiB-Grenze hält auch gegen
eine gzip-Bombe.

Zwei neue Befunde, beide *mittel*, beide im Umfeld der neuen Schlüsselbund- und Migrationslogik:
- **BUG-13** — Hat ein Nutzer in v1.1 Xtream-Playlists gelöscht und ist keine übrig, kopiert die Übernahme den Klartext
  aus den freigegebenen Seiten in die neue Datenbank und verdichtet nicht. Nach dem Start stehen dort 878 Vorkommen des
  Passworts.
- **BUG-14** — Stammt der Schlüsselbund-Eintrag einer Playlist von einem anderen Build, entfernt „Löschen" nur die
  Playlist. Bei ad hoc signierten Updates ist das der Normalfall (OF-08). Das Passwort bleibt im Schlüsselbund
  (`-25244`), und die Oberfläche verschluckt den Fehler.

Die B09-Reparatur hat kein B01-Verhalten verschlechtert: Die v1.1-Vorlage wird übernommen und geöffnet, und die
Umstellung läuft über `openStore` fehlerfrei. Eine Nebenwirkung ohne Fehlerwert (H-8): Legt B09 eine nicht lesbare
Datenbank beiseite, bleiben die Schlüsselbund-Einträge ihrer Playlists stehen. Die App bietet keinen Weg, sie zu entfernen.

Nicht als Fehler gewertet, aber offen (Entscheidung des Nutzers):
- **OF-01** · Dublette beim erneuten Import — BUG-09 nur im Teil Doppelklick behoben; `testAK09` behält `XCTExpectFailure`.
- **OF-02** · „Abbrechen" bricht jetzt ab (belegt, EC-18). Beim URL-Import (B02) desselben Sheets tut es das nicht (H-10).
- **OF-04** · Weiterleitungen nur innerhalb desselben Panels. Abgelehnt wird auch `http`→`https` auf demselben Host,
  mit der Meldung „leitet auf einen anderen Server weiter".
- **OF-08** · Nach einem Update fragt macOS beim ersten Lesen nach dem Schlüsselbund-Passwort. Ohne Oberfläche
  nachgestellt: Ein neu übersetzter Build am selben Pfad liest den Eintrag nicht (`-25293`). BUG-14 hängt daran.
- **OF-09** · `…ThisDeviceOnly` — iOS-Eintrag mit `cku` belegt; Wiederherstellung auf neuem Gerät nicht nachgestellt.
- **OF-10** · Kein HTTP-Rückfall bei TLS-Fehler. Die Meldung lautet „A TLS error caused the secure connection to fail." (belegt mit Sonde).
- **OF-11** · Multiview fügt ohne Zugangsdaten stillschweigend nichts hinzu — nicht bedient.
- **OF-12** · Grenzen 64 MB / 100.000 / 180 s / 512 Zeichen genau belegt, aber ohne Vorgabe gewählt.

Nicht prüfbar bleiben:
- **AK-04** · iOS-Tastatur; es gibt keine Tipp-Automatisierung.
- **AK-27** · Systemprotokoll der App selbst. Ersatzbeleg: Der App-Netzwerkcode lief in einem regulär gestarteten
  Prozess, mit 0 Treffern und 17 × `<private>`.
- **AK-29** · Negativaussage über das Kontextmenü.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 27 von 30 |
| davon bestanden | 26 |
| davon durchgefallen | 1 (AK-09 — Befund zurückgestellt bis OF-01, laut Auftrag nicht als Fehler gewertet) |
| **nicht prüfbar** | 3 (AK-04, AK-27, AK-29) |
| Edge Cases belegt | 22 von 22 |
| BUGs aus Durchlauf 1 | 11 behoben ✅ · 1 teilweise (BUG-09: Doppelklick ✅, Dublette zurückgestellt → OF-01) · 0 nicht behoben ❌ |
| Neue BUGs | 2 (BUG-13 mittel, BUG-14 mittel) |
| Tests neu geschrieben | 29 in 3 Dateien |
| Tests grün | Gesamtlauf B01 + Bestand: **112 ausgeführt, 0 Fehlschläge** (`** TEST EXECUTE SUCCEEDED **`, 288 s); 2 übersprungen (AK-27 wie Durchlauf 1; 180-s-Grenzwert nur mit Umgebungsvariable, separat ausgeführt: bestanden in 180,2 s); 3 erwartete Fehlschläge als Belege (AK-09/OF-01, BUG-13, BUG-14). Von den 29 neuen: 26 grün, 2 belegen BUG-13/BUG-14 per `XCTExpectFailure`, 1 separat grün |

## Prüfumgebung (Durchlauf 2)

| Was | Wie |
|---|---|
| Build/Test | eigener DerivedData-Pfad `build/dd-qa-b01`; `xcodegen generate` nur nach Anlegen der drei neuen Testdateien. Gesamtlauf: `xcodebuild test-without-building … -derivedDataPath build/dd-qa-b01 -only-testing:` alle `B01*`-Klassen, `XtreamCodesTests`, `M3UParserTests`, `PlaybackEngineTests` (B09-Tests gehören der parallelen B09-QA). Parallel liefen QA 2 von B09 (`build/dd-qa-b09`) und ein B08-Lauf — **Messwerte unter Last** |
| Panel | `MockXtreamServer` (Durchlauf 1) und neu `B01QA2RawServer`: TCP auf 127.0.0.1, schreibt **alle** Bytes je Verbindung mit (auch TLS), antwortet mit frei gebauten Kopfzeilen (`Set-Cookie`, `Cache-Control`, `Content-Encoding`) |
| Datenbanken | nur Temp-Ordner bzw. In-Memory; „Application Support" für die Übernahme ist ein Temp-Ordner. Die Datenbank des Nutzers (`~/Library/Application Support/default.store` bzw. die neue App-Datenbank) wurde weder gelesen noch beschrieben |
| Schlüsselbund | nur eigene Dienste `lu.daumedia.MikaPlusPlayer.qa2.…` bzw. der Test-Dienst des Laufs. „Fremder Prozess" bzw. „anderer Build" ist eine vom Test selbst übersetzte, ad hoc signierte Sonde (`kcprobe`) ohne Oberfläche. Der Dienst der App wurde nie abgefragt. Zwei Rückstände früher Läufe dieses Durchlaufs wurden mit einer byte-gleich neu übersetzten Sonde (gleicher cdhash) entfernt. Nach dem Gesamtlauf: 0 Einträge unter Test-Diensten (`testQA2_ZZ_…`) |
| Systemprotokoll | Sonde `b01logprobe` aus den Quelltexten `XtreamCodes`, `XtreamClient`, `XtreamHTTPLoader`, `XtreamLoginThrottle`, `M3UParser`, regulär aus der Shell gestartet (nicht aus Xcode), gegen Python-Mocks; danach `/usr/bin/log show --predicate 'process == "b01logprobe"' --info --debug` |
| iOS | `xcodebuild build -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-qa-b01-ios` → `** BUILD SUCCEEDED **`; einzige Warnung wie in der Baseline (`LSSupportsOpeningDocumentsInPlace`). Laufzeit im Simulator iPhone 17 (iOS 27.0): App installiert, eine v1.1-artige `default.store` mit erfundenen Zugangsdaten in den App-Container gelegt, `simctl launch` (keine Wiedergabe, kein Ton), danach App deinstalliert und Simulator heruntergefahren |
| Oberfläche macOS | Methode wie Durchlauf 1 (Fenster im Test-Host, synthetische Mausklicks, Feld-Editor, Accessibility); zusätzlich Fenster-Server (`CGWindowListCopyWindowInfo`) statt Klassennamen |
| Codequalität | `code-reviewer`-Agent über alle B01-Dateien einschließlich der B09-Änderungen am Start. Zwei Funde, beide verifiziert: der eine → BUG-14, der andere gehört zu B02 → H-10. Ein als Verdacht gemeldeter dritter ist nicht erfasst: Schlüsselbund geschrieben, aber DB-Speichern scheitert; das heilt der nächste Start laut Code selbst |
| Kein Ton | keine Wiedergabe, keine Tastaturereignisse, keine Testtöne; Schlüsselbund-Zugriffe ohne Dialog |

## Akzeptanzkriterien im Einzelnen (Durchlauf 2)

Testnamen ohne Pfad liegen unter `Tests/B01/`. Kriterien mit ⚠ beschreiben in der Spec das **alte** Ist. Ist der
Befund behoben, steht hier „bestanden (Befund behoben)"; die Spec ist nachzuführen (siehe unten).

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | `B01OberflaecheTests.testAK01_SheetFelderUndMindestgroesse` (Gesamtlauf 2026-09-16) |
| AK-02 | ✅ bestanden | `testAK02_FormatStandardUndHinweis` |
| AK-03 | ✅ bestanden | `testAK03_ButtonNurMitAllenDreiFeldern` |
| AK-04 | ⚠️ nicht prüfbar | macOS-Teil bestanden (`testAK04_KeineAutokorrekturMacOS`). iOS-Teil: Die App lief im Simulator, aber ohne Tipp-Automatisierung lässt sich das Sheet nicht öffnen |
| AK-05 | ✅ bestanden | `testAK05_EC21_ZustandWaehrendDesImports` |
| AK-06 | ✅ bestanden | `testAK06_ErfolgSchliesstSheetNeuePlaylistOben` (macOS); iOS nach Umstellung: `qa/QA2-iOS-Umstellung-Playlists.png` (Globus, „50 Sender") |
| AK-07 | ✅ bestanden | `testAK07_NameAusHostOderEingabeUngekuerzt` |
| AK-08 | ✅ bestanden | `testAK08_SenderZuordnungAusLiveStreams` |
| AK-09 ⚠ | ❌ durchgefallen | Ist unverändert: `testAK09_DoppelterImportLegtZweitePlaylistAn` → 2 Playlists (erwarteter Fehlschlag). BUG-09 Teil Dublette offen, zurückgestellt bis OF-01 (laut Auftrag nicht als Fehler gewertet) |
| AK-10 | ✅ bestanden | `testAK10_DreiAnfragenInReihenfolgeOhneGetPhp`, `testAK10_NachFehlschlagKeineWeitereAnfrage` |
| AK-11 | ✅ bestanden | `testAK11_HostNormalisierungAmPayload` (gespeichert jetzt `http://<host>/player_api.php` ohne Query) |
| AK-12 ⚠ | ✅ bestanden (Befund behoben) | `B01QA2Tests.testQA2_BUG02_HTTPSGegenKlartextServerRoheBytes`: `HTTPS://127.0.0.1:<port>` → 1 Verbindung, erstes Byte `0x16`, 1.514 Byte, **0×** Passwort, 0× Benutzer, 0× `player_api`; Gegenprobe ohne Schema: 3× Passwort im Klartext. Hinweis im Sheet: `B01QA2OberflaecheTests.testQA2_BUG02_HinweisVarianten` → BUG-02 |
| AK-13 | ✅ bestanden | `testAK13_EC09_EC10_TrimNurLeerzeichen` |
| AK-14 ⚠ | ✅ bestanden (Befund behoben) | `testQA2_BUG05_SonderzeichenInAnfrageUndStreamPfad`: `qa+pass`, `a#b`, `a?b`, `a/b`, `a%2Fb`, `a@b:c;d`, `a\b`, `😀 x`, Tabulator, `+` → PHP-dekodierendes Panel meldet an; Stream-Pfad hat genau einen Abschnitt mit dem Wert, ohne Query/Fragment → BUG-05 |
| AK-15 | ✅ bestanden | `testAK15_StreamAdresseUndFormat` — abspielbare Adresse `http://<host>/live/<u>/<p>/<id>.<ext>` wie beschrieben; **gespeichert** wird jetzt `http://<host>/live/<id>.<ext>` (Spec nachführen) |
| AK-16 | ✅ bestanden | `B01ImportTests.testAK16_AuthUngleichEinsOderOhneUserInfo` |
| AK-17 | ✅ bestanden | `testAK17_HTTPStatusAusserhalb2xx` |
| AK-18 | ✅ bestanden | `testAK18_UnerwarteteServerantwort` |
| AK-19 | ✅ bestanden | `testAK19_LeereStreamliste` |
| AK-20 | ✅ bestanden | `testAK20_HostNichtErreichbar`; `B01LangsamTests.testAK20_AK23_TimeoutNach60Sekunden` → 60,05 s, „Netzwerkfehler: The request timed out." |
| AK-21 | ✅ bestanden | `testAK21_UngueltigerHostOhneAnfrage` |
| AK-22 | ✅ bestanden | `testAK22_FehlschlagLegtNichtsAn`, `testAK16bis22_FehlerAlertEingabenBleibenButtonSofortAktiv`; zusätzlich kein Schlüsselbund-Eintrag nach Fehlschlag oder Abbruch (`testQA2_BUG02_…`, `testQA2_BUG08_Hunderttausend`, `testQA2_BUG11_…`) |
| AK-23 | ✅ bestanden | `B01SicherheitTests.testAK23_FehlermeldungenOhneZugangsdatenUndAdresse` (inkl. der neuen Meldungen); Resolver- und Schlüsselbund-Meldungen ohne Zugangsdaten: `testQA2_Resolver_…`, `testQA2_Schluesselbund_FremderProzessUndAndererBuild` |
| AK-24 ⚠ | ✅ bestanden (Befund behoben) | `testQA2_BUG01_OriginalReproduktionKeinKlartextInDateien`: SQLite `ZPLAYLIST`/`ZCHANNEL` mit Passwort bzw. Benutzer **0**; Bytefolgen (Passwort, Benutzer, kodiertes Sonderzeichen-Passwort, Benutzerinfo) in allen Dateien des Ordners **0**, bei offenem wie geschlossenem Container; der Schlüsselbund enthält `host` inkl. `qa-u:…@`. Rest aus v1.1 → **BUG-13** |
| AK-25 ⚠ | ✅ bestanden (Befund behoben) | `testQA2_BUG03_KeinCacheKeineCookiesBeimLoader`: cachebare Antworten (`max-age=3600`) mit Passwort in `user_info`, eigener `URLCache.shared` im Temp-Ordner → 0 Treffer, 0 Bytefolgen; Loader-Session mit `urlCache = nil`, `urlCredentialStorage = nil` und eigenem Cookie-Speicher. Altbestand: `testQA2_BUG03_LeerenEntferntBytefolgenAufDerPlatte` → vorher 17× in `Cache.db-wal` + 1× in `fsCachedData`, nachher 0 |
| AK-26 ⚠ | ✅ bestanden (Befund behoben) | `testQA2_BUG10_WeiterleitungsVarianten`: 302/307 auf anderen Port, 308 auf `https` am gleichen Port, schemarelativ, `127.0.0.1:<p>@127.0.0.1:<q>`, `[::1]`, Kette A→A→B → Ziel **0** Anfragen, Meldung „…leitet auf einen anderen Server weiter…" (OF-04) |
| AK-27 | ⚠️ nicht prüfbar | Am Test-Host ist Private-Data-Logging aktiv (`testAK27_…` übersprungen, 1 CFNetwork-Treffer; Durchlauf 1: 9). Die App selbst lässt sich nicht regulär mit einem Import starten, ohne die Datenbank des Nutzers zu öffnen. Ersatzbeleg `b01logprobe` mit dem App-Netzwerkcode, regulär gestartet (Erfolg, Fehlanmeldung, Port zu, `https` gegen Klartext, Host unbekannt, Weiterleitung): 544 Zeilen, **0×** Passwort, 0× Benutzer, 17× `<private>`, alle 4 CFNetwork-Fehlerzeilen geschwärzt |
| AK-28 ⚠ | ✅ bestanden (Befund behoben) | `testAK28_SpeicherortUndBackup`; `testQA2_BUG01_BUG04_UmstellungKlartextDatenbankUeberStartpfad` (Übernahme → `…/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store`, alte `default.store`/-wal/-shm weg); `testQA2_BUG04_FremdeDefaultStoreBleibtUnangetastet`; iOS: `Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store` im Container, `default.store` weg. Backup bewusst nicht ausgeschlossen (die Datei enthält keine Zugangsdaten mehr) |
| AK-29 | ⚠️ nicht prüfbar | Negativaussage über das Kontextmenü (wie Durchlauf 1). Löschweg selbst belegt: `testQA2_BUG01_OriginalReproduktion…` (Eintrag weg) und `testQA2_Schluesselbund_A_LoeschenEintragAndererBuild` (Eintrag bleibt → **BUG-14**) |
| AK-30 | ✅ bestanden | `git log -p --all` über **19** Commits: `username=` nur `demo`, `u`, `…`; `password=` nur `secret`, `p`, `…`; `/live/…` nur `user/pass`, `\(user)/\(pass)`. Arbeitsbaum (neu, ungetrackt): nur `qa-…`- und Beispielwerte |

## Edge Cases (Durchlauf 2)

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | `testEC01_FragmentImHost` (jetzt mit `http://`, weil `https` erhalten bleibt) — Fragment bleibt an der Basis, `/live/…` landet im Fragment |
| EC-02 | ✅ belegt | `testEC02_FremdesSchema` |
| EC-03 | ✅ belegt (Ist geändert) | `testEC03_BenutzerinfoImHost`; Benutzerinfo nur im Schlüsselbund, nicht in der DB (`testQA2_BUG01_…`: `sourceURL` ohne `qa-u:`) |
| EC-04 | ✅ belegt | `testEC04_IDNHost` |
| EC-05 | ✅ belegt | `testEC05_IPv6Host` |
| EC-06 | ✅ belegt | `testEC06_UnterpfadWirdVerworfen` |
| EC-07 | ✅ belegt (Ist geändert) | `https://…:8443` bleibt `https`; gegen einen Klartext-Port kommt nur ein TLS-Handshake an (`testQA2_BUG02_…`). Erfolg gegen einen echten TLS-Server nicht nachgestellt (lokal kein vertrauenswürdiges Zertifikat) |
| EC-08 | ✅ belegt | `testEC08_DoppelterSchraegstrichOhneSchema` |
| EC-09 | ✅ belegt | `testAK13_EC09_EC10_…` (Einfügen von Zeilenumbrüchen per Zwischenablage weiter ungeprüft) |
| EC-10 | ✅ belegt | ebenda |
| EC-11 | ✅ belegt (Ist geändert) | `testQA2_BUG06_OriginalReproduktion`: `category_id: 1` → Gruppe „News" |
| EC-12 | ✅ belegt (Ist geändert) | ebenda: `name: null` neben einem gültigen Stream → 2 Sender |
| EC-13 | ✅ belegt | `testEC13_EC15_KommazahlIdUndLeererName` |
| EC-14 | ✅ belegt | `testEC14_StreamIdMitSchraegstrich` (`stream_id` weiterhin unkodiert) |
| EC-15 | ✅ belegt | `testEC13_EC15_…` |
| EC-16 | ✅ belegt | `testEC16_AbgelaufenesKontoWirdImportiert` (OF-03) |
| EC-17 | ✅ belegt (Ist geändert) | `testQA2_BUG08_Frist180SekundenGenau` mit Standardfrist, drei Importe gleichzeitig: A tröpfelt 175,5 s → gelingt nach 175,7 s; B tröpfelt 185 s → Abbruch nach **180,1 s**; C 95 s + 95 s → Abbruch nach 180,1 s in der Kategorien-Anfrage (Anfragen `(ohne)`, `get_live_categories`) |
| EC-18 | ✅ belegt (Ist geändert, OF-02) | `testQA2_BUG11_AbbrechenOriginalReproduktion` (siehe BUG-11) |
| EC-19 | ✅ belegt | `testEC19_DoppelklickAufAnmelden` → 1 Anfrage, 1 Playlist |
| EC-20 | ✅ belegt (Ist geändert) | `testQA2_BUG12_SiebzehntausendSender` (siehe BUG-12) |
| EC-21 | ✅ belegt | `testAK05_EC21_…` |
| EC-22 | ✅ belegt | `testEC22_HLSGesperrtImportGelingtTrotzdem` |

## BUGs aus Durchlauf 1 — erneut geprüft

Jeweils mit der **ursprünglichen Reproduktion** aus Durchlauf 1, dazu Angriffe auf die neue Umsetzung.

| BUG | Grad | Ergebnis | Nachweis (Durchlauf 2) |
|---|---|---|---|
| BUG-01 | hoch | ✅ behoben | Import in Store-Datei → SQLite 0/0, Bytefolgen 0 in allen Dateien, offen und geschlossen. **Startpfad** mit Klartext-`default.store` (3 Xtream-Playlists mit `+&= ä`, `%41/`, Benutzerinfo; 900 Sender, 18 Favoriten; dazu eine in v1.1 gelöschte Xtream-Playlist) → `prepareStore` `.adopted` → `openStore` `.opened` → `migrateCredentials` (3/900/0, 0,17 s): 903 Vorkommen → **0**, offen und geschlossen; dieselben Sender-IDs, 19 Favoriten, 0 abweichende abspielbare Adressen (`testQA2_BUG01_BUG04_UmstellungKlartextDatenbankUeberStartpfad`). iOS-Simulator: 50 Sender umgestellt, 0 Dateien mit Passwort oder Benutzer im Container, `ZSOURCEURL` = `http://127.0.0.1:18765/player_api.php`, Schlüsselbund-Zeile `agrp=CWJM4J4HFN.lu.daumedia.MikaPlusPlayer`, `pdmn=cku`, `sync=0`. **Rest:** BUG-13 |
| BUG-02 | hoch | ✅ behoben | Rohe Mitschrift: nur TLS-Handshake, kein Klartext (AK-12). Hinweis im Sheet, 9 Eingaben per UI: sichtbar bei `https://` (ohne Host), `https:/…`, `ftp://…`, `http://https.…`, `…:443`, `http://…`; verschwunden bei ` https://…`, `hTtPs://…:8443/panel/?x=1`, `https://qa-u:qa-pw@…` |
| BUG-03 | mittel | ✅ behoben | AK-25: nichts im Cache, eigene Session ohne Cache und ohne Zugangsdatenspeicher, Panel-Cookie nicht im gemeinsamen Speicher. Das einmalige Leeren entfernt auch die Bytefolgen in `Cache.db-wal` und `fsCachedData`. iOS: Merker `B01.legacyHTTPCachePurged = true` im App-Container nach dem Start |
| BUG-04 | mittel | ✅ behoben | Fremde `default.store` mit **gleichen Entitätsnamen** `Playlist`/`Channel` und anderen Feldern, dazu SQLite mit `ZPLAYLIST`/`ZCHANNEL` ohne Core-Data-Metadaten → `.notOurs`, keine Kopie. Nach vollem Startpfad und zweitem Start sind `default.store` und `-wal` nach SHA-256 und Datum unverändert (H-9: `-shm` neu geschrieben). Echte v1.1-Vorlage aus B09 (Temp-Kopie) → `.adopted`, `.opened`, Playlist „B09 v1.1 Testliste" (`testQA2_BUG04_…`) |
| BUG-05 | mittel | ✅ behoben | AK-14; Hinweis H-12 (Passwort `..`) |
| BUG-06 | mittel | ✅ behoben | EC-11/EC-12 (Originalreproduktion) |
| BUG-07 | mittel | ✅ behoben | Standardweg der App (`PlaylistImporter(modelContext:)` mit `XtreamLoginThrottle.shared`): 10 Fehlanmeldungen → **3** beim Panel. Sperren 0/0/30/60/120/240/300/300 s; bei 299,9 s gesperrt, bei 300,0 s frei. Aktualisieren (B03) nach 3 Fehlanmeldungen → 0 Anfragen, Sperrmeldung. Benutzerinfo oder ein anderer Benutzer umgehen die Sperre nicht; eine andere Schreibweise des Hosts und ein Neustart schon → H-7 (`testQA2_BUG07_…`) |
| BUG-08 | mittel | ✅ behoben | 64 MiB genau (67.108.864 Byte) angenommen, +1 Byte abgelehnt — mit und ohne `Content-Length`. gzip-Bombe: 71.425 Byte, entpackt 73.400.320 → abgelehnt. 100.000 Streams importiert (100.000 gespeichert, 25,6 s, Main-Thread 0,00 s); 100.001 abgelehnt, ohne Playlist und ohne Schlüsselbund-Eintrag. 180 s genau (EC-17). Text 512 Zeichen (auch Emoji); Logo mit 2.048 Zeichen erlaubt, mit 2.049 verworfen |
| BUG-09 | niedrig | teilweise | Doppelklick ✅ (`testEC19` → 1 Anfrage, 1 Playlist). Dublette unverändert (`testAK09`, erwarteter Fehlschlag), zurückgestellt bis OF-01 |
| BUG-10 | niedrig | ✅ behoben | AK-26, sieben Weiterleitungsvarianten |
| BUG-11 | mittel | ✅ behoben | Originalreproduktion per UI, ohne Klassennamen-Filter: Panel antwortet nach 2 s mit `auth: 0`, „Abbrechen" nach 0,4 s. 4 s später: **0** neue Prozessfenster auf dem Bildschirm (Fenster-Server), kein „Anmeldung fehlgeschlagen"/„Fehler" in einem sichtbaren Fenster, 1 Anfrage, 0 Playlists, 0 Schlüsselbund-Einträge. Zweite Runde, Abbruch nach erfolgreicher Anmeldung (Kategorien verzögert): 0 neue Fenster, keine Streams-Anfrage, 0 Playlists, 0 Einträge (`testQA2_BUG11_AbbrechenOriginalReproduktion`, `testQA2_BUG11_AbbruchNachAnmeldungHinterlaesstNichts`) |
| BUG-12 | hoch | ✅ behoben | 17.000 Sender (2,38 MB JSON) über den echten Pfad: In-Memory **2,13 s**, Store-Datei **2,14 s**; längste Main-Thread-Blockade **0,01 s** bzw. **0,00 s** (Gesamtlauf unter Parallellast; Einzellauf 2,34 s / 2,17 s, beide 0,00 s) — `testQA2_BUG12_SiebzehntausendSender`. Standardgrößen 1.500/3.000/6.000: 0,16/0,31/0,66 s, 0,00 s (`testEC20_…`). Umstellung eines Altbestands mit 17.000 Sendern: 2,34 s synchron beim Start, einmalig (`testBUG01_MigrationMit17000Sendern`). Aktualisieren blockiert weiter → H-11 (B03) |

### Sind die umgestellten Tests weicher geworden?

Alle 56 Tests aus Durchlauf 1 sind noch da, 13 davon umbenannt. Keiner der entfernten `XCTExpectFailure`-Blöcke ist
ohne Ersatz-Assertion verschwunden. Assertions, die gar nichts mehr prüfen, gibt es nicht. Einige Tests belegen das
neue Verhalten aber nur schwach. Diese Stellen ergänzen die QA-2-Tests:

| Test | Schwäche | Ergänzt durch |
|---|---|---|
| `testAK12_HTTPSBleibtErhalten`, `testEC07_HTTPSNurTLSPanel` | zählen nur **geparste** HTTP-Anfragen am Mock. Einen TLS-Handshake zählt der Mock nie, „0 Anfragen" ist also fast zwangsläufig. Der 400-Handler in EC-07 ist toter Code | Roh-Mitschrift aller Bytes (`testQA2_BUG02_…`) |
| `testAK25_…` | prüft nur `URLCache.shared` des Test-Hosts, den der neue Loader gar nicht benutzt | eigener `URLCache.shared` + Session-Konfiguration des Loaders (`testQA2_BUG03_KeinCache…`) |
| `testBUG03_AlterHTTPCacheWirdEinmaligGeleert` | nur API (`cachedResponse == nil`), keine Bytes auf der Platte | Bytefolgen in `Cache.db`/`-wal`/`fsCachedData` (`testQA2_BUG03_Leeren…`) |
| Hilfe `B01.importXtream` | gibt jedem Aufruf eine **frische** Bremse, der Standardweg mit `.shared` ist nirgends geprüft | `testQA2_BUG07_BremseStandardweg…` |
| `testBUG04_…` | fremde Stores nur mit anderen Entitätsnamen | gleiche Entitätsnamen, SQLite ohne Metadaten, voller Startpfad (`testQA2_BUG04_Fremde…`) |
| `testBUG01_Migration…` | Container ohne versioniertes Schema (nicht der B09-Startpfad); gesucht wird nur das Passwort, nicht der Benutzername | `testQA2_BUG01_BUG04_Umstellung…` |
| `testEC18_AbbrechenBrichtImportAb` | findet Alerts/Sheets nur über Klassennamen (`"Alert"`, `"SheetPresentationWindow"`) | Fenster-Server und Text aller Fenster (`testQA2_BUG11_AbbrechenOriginalReproduktion`) |
| `testEC17_…`, `testFB05_…` | Grenzen im Test verkleinert (25 s, 1 MB, 3 Sender) | Standardgrenzen genau (`B01QA2GrenzenTests`) |
| `testEC20_…` | nur In-Memory-Store | Store-Datei (`testQA2_BUG12_…`) |

## Sicherheitsprüfung (Durchlauf 2)

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | trifft nicht zu; Ersatzprüfung bestanden | Kein Server, keine Konten. Ersatz: manipulierte Datenbank-Adressen (`http://evil.example/live/101.ts`, `…/live/@evil.example/1.ts`, `…/live///evil.example/…`, `..%2F..%2Fevil`, `?u=http://evil.example`, `#@evil.example`) → abspielbare Adresse immer `panel.example:8080` aus dem Schlüsselbund; Adresse ohne `/live/` → „ungültig" statt Durchreichen; vorgetäuschter Altbestand reicht nur die gespeicherte Adresse ohne Geheimnis durch (`testQA2_Resolver_…`) |
| 2 · Zugriffsregeln (Betriebssystem) | bestanden, **BUG-13**, Hinweis H-6 | Datenbank ohne Zugangsdaten (BUG-01). Schlüsselbund macOS, Zugriffsliste: `Decrypt/Derive/ExportClear/ExportWrapped/MAC/Sign` nur für `<Test-Host>`, `Encrypt/Integrity/PartitionID` für alle, `ChangeACL` für niemanden. Ein fremder Prozess liest ohne Freigabe **nicht** (`READ status=-25293`) und löscht nicht (`-25244`). Lesbare Attribute nur `acct` (Playlist-UUID), `labl` „Mika+Player – Xtream-Zugang", `svce`, Datum — kein Host, kein Benutzer. `pdmn` wird im Anmelde-Schlüsselbund nicht gespeichert. iOS: `pdmn=cku`, `agrp=CWJM4J4HFN.lu.daumedia.MikaPlusPlayer`, `sync=0`. Rest-Klartext nach Übernahme ohne Xtream-Playlist: BUG-13 |
| 3 · Rate Limit greift | bestanden, Hinweis H-7 | Standardweg: 10 Fehlanmeldungen → 3 beim Panel. Sperrdauern auf die Zehntelsekunde genau; Aktualisieren gesperrt. Umgehung nur über eine andere Schreibweise desselben Hosts (`localhost`, `127.1`, `0x7f.0.0.1`, `[::ffff:127.0.0.1]` je 1 Anfrage) und über einen Neustart |
| 4 · PII in Protokollen | teils bestanden (H-2 bleibt) | Meldungen der App ohne Zugangsdaten (AK-23, neue Meldungen, Resolver, Schlüsselbund). Regulär gestarteter Prozess mit App-Netzwerkcode: 0 Treffer, 17 × `<private>`. Im xcodebuild-Lauf mit aktivem Private-Data-Logging steht weiterhin 1 CFNetwork-Zeile mit der URL samt Zugangsdaten im Protokoll (H-2). `AppPersistence` protokolliert Öffnungsfehler als `.private`, ohne Zugangsdaten |
| 5 · PII an externe Dienste | bestanden | Tatsächlicher Payload: bei `https` nur TLS-Handshake, 0 Klartext. Bei `http` 3 Anfragen mit Passwort (protokollbedingt, Hinweis im Sheet). Weiterleitungen in 7 Varianten → 0 Anfragen am Ziel. Panel-Cookies bleiben im eigenen Speicher der Loader-Session (beim zweiten Import zurückgeschickt, nur an dasselbe Panel) |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` (19 Commits) und Arbeitsbaum: nur Beispiel- und `qa-`-Werte. Gebautes Bundle `build/dd-qa-b01/…/MikaPlusPlayer.app` (`strings`): kein `password=`, `sk_live_`, `service_role`, `qa-pass`, kein privater Schlüssel; eingebettet sind nur die Dienstnamen `lu.daumedia.MikaPlusPlayer.xtream` und `….xtream.tests.` |
| 7 · Eingaben | bestanden, Hinweis H-12 | `testAngriff07_EingabenInJedemFeld` (0 fehlerhafte Fälle); BUG-05-Varianten. Schlüsselbund mit allen druckbaren ASCII-Zeichen, `ä ö 😀`, `\0\n\r`, leer und 10.000 Zeichen → Pfad mit genau zwei Abschnitten, die die Werte tragen; Host unverändert |
| 8 · Löschen | teils bestanden, **BUG-14**, Hinweis H-8 | Löschen über `PlaylistImporter.delete`: Zeilen 0, Schlüsselbund-Eintrag weg, nach dem Schließen 0 Bytefolgen. Stammt der Eintrag von einem anderen Build: Datenbankzeile weg, Eintrag bleibt (`-25244`), `PlaylistsView` verwirft den Fehler (BUG-14). Nach dem Beiseitelegen (B09) bleibt der Eintrag der nicht mehr sichtbaren Playlist (H-8) |

## Neue Fehler (Durchlauf 2)

### BUG-13 · Übernommene v1.1-Datenbank behält Klartext-Passwörter gelöschter Xtream-Playlists — mittel

**Betrifft:** AK-24, BUG-01 (Rest), FB-01
**Reproduktion:**
1. Mit dem Schema von v1.1 (`[Playlist, Channel]`) eine Xtream-Playlist mit 2.000 Sendern und Passwort `qa-pass-qa2free-<n>` anlegen, dazu eine M3U-Playlist. Die Xtream-Playlist wieder löschen, wie beim „löschen und neu importieren" nach einem Passwortwechsel (OF-05). Die Datei als `Application Support/default.store` ablegen → 878 Vorkommen des Passworts in freigegebenen Seiten
2. Startpfad der neuen App: `AppPersistence.prepareStore` → `.adopted`; `openStore` → `.opened`; `migrateCredentials` → `migratedPlaylists: 0`
3. Bytefolge in `…/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store` suchen (Container geschlossen)
**Erwartet:** Nach der Umstellung steht kein Passwort mehr in einer Datei der App (Build-Bericht: „0 Bytefolgen")
**Tatsächlich:** **878** Vorkommen in `MikaPlusPlayer.store` (drei Läufe: 855, 901, 878), lesbar für jeden Prozess des Nutzers. `replacePersistentStore` kopiert die freigegebenen Seiten mit, die alte `default.store` wird gelöscht. Verdichtet wird nur, wenn mindestens eine Playlist umgestellt wurde. Gegenprobe: Ist noch eine Xtream-Playlist übrig, wird verdichtet und es bleibt nichts zurück (0, `testQA2_BUG01_BUG04_…`)
**Ort:** `Sources/Services/AppPersistence.swift:309-311` (`compactStore` nur bei `migratedPlaylists > 0`), `:220-234` (Kopie per `replacePersistentStore`)
**Vorschlag:** Nach einer Übernahme (`.adopted`) immer verdichten, unabhängig vom Ergebnis der Umstellung.
**Test:** `B01QA2Tests.testQA2_BUG01_KlartextInFreigegebenenSeitenOhneXtreamPlaylist` (`XCTExpectFailure("BUG-13 …")`, solange Vorkommen > 0)

### BUG-14 · Nach einem Update entfernt „Löschen" das Xtream-Passwort nicht aus dem Schlüsselbund; der Fehler wird verschluckt — mittel

**Betrifft:** AK-29, Angriff 8, PRD („Löschen einer Playlist entfernt … die darin gespeicherten Zugangsdaten"); hängt an OF-08
**Reproduktion:**
1. Den Schlüsselbund-Eintrag einer Xtream-Playlist (Dienst, Konto = Playlist-UUID) von einem **anderen** ad hoc signierten Programm anlegen lassen. So sieht der Eintrag nach jedem Update der ad hoc signierten App aus: Partition `cdhash:<alter Build>`
2. In der App (Test-Host, Freigabe-Oberfläche erlaubt, also der Normalfall) die Playlist über den App-Weg löschen: `PlaylistImporter(modelContext:credentialStore:).delete(playlist)`; `PlaylistsView.delete` ruft das mit `try?` auf
**Erwartet:** Playlist und Schlüsselbund-Eintrag sind weg, oder die App meldet, dass der Eintrag bleibt
**Tatsächlich:** Die Datenbankzeile ist gelöscht (0 Playlists), der Eintrag bleibt (**1**). Der Aufruf wirft ohne Dialog „Der Schlüsselbund hat den Zugriff auf die Zugangsdaten verweigert (Code -25244)", aber erst **nach** dem Speichern. `PlaylistsView` verwirft den Fehler. Für den Nutzer ist die Playlist gelöscht. Das Passwort liegt verwaist im Anmelde-Schlüsselbund, und die App bietet keinen Weg mehr, es zu entfernen. Gegenprobe: Ein byte-gleich neu übersetztes Programm (gleicher cdhash) löscht solche Einträge sofort (`DELETE status=0`)
**Ort:** `Sources/Services/PlaylistImporter.swift:270-278` (erst Datenbank speichern, dann Schlüsselbund), `Sources/Views/PlaylistsView.swift:104-107` (`try?`)
**Einschränkung:** Der „alte Build" ist eine vom Test übersetzte Sonde, kein echtes Update der App. Ob macOS beim echten Update statt `-25244` einen Dialog zeigt, ist nicht nachgestellt.
**Vorschlag:** Fehler beim Löschen des Eintrags anzeigen, statt ihn zu verwerfen: Hinweis, dass das Passwort im Schlüsselbund bleibt. Die eigentliche Lösung über den Schlüsselbund-Zugriff gehört zu OF-08.
**Test:** `B01QA2Tests.testQA2_Schluesselbund_A_LoeschenEintragAndererBuild` (`XCTExpectFailure("BUG-14 …")`, solange ein Eintrag bleibt)

## Hinweise (Durchlauf 2, kein Kriterium durchgefallen)

- **H-2 bleibt** — siehe Sicherheitsprüfung 4.
- **H-6 · Schlüsselbund-Attribute ohne Freigabe lesbar.** Jeder Prozess des Nutzers sieht Label, Konto (Playlist-UUID)
  und Datum der Einträge. Damit weiß er, dass und wie viele Xtream-Zugänge es gibt; Host und Benutzer sieht er nicht. Ein fremder
  Prozess kann den Inhalt außerdem ohne Dialog überschreiben (`Encrypt` für alle Programme). In einer Scratchpad-Sonde
  lieferte das `UPDATE status=0`, danach las auch der Ersteller nicht mehr (`-25293`): Sabotage ohne Abfluss, nicht als
  dauerhafter Test abgelegt.
- **H-7 · Anmeldebremse umgehbar durch Schreibweise.** Derselbe Server unter `localhost`, `127.1`, `0x7f.0.0.1` oder
  `[::ffff:127.0.0.1]` hat je einen eigenen Zähler. Ein Neustart setzt zurück (Annahme 10). Umgekehrt gilt die Sperre je
  Panel, trifft also auch einen anderen Benutzer desselben Panels.
- **H-8 · B09 × B01.** Legt `openStore` eine unlesbare Datenbank beiseite, bleiben die Schlüsselbund-Einträge ihrer
  Playlists stehen (`testQA2_B09Wiederherstellung_…`: Eintrag vorhanden, beiseitegelegte Datei ohne Klartext). Das
  passt zu „nichts löschen", aber kein Weg in der App entfernt diese Einträge.
- **H-9 · Die Übernahme-Prüfung schreibt die `-shm`-Datei einer fremden `default.store` neu**, weil das Lesen der
  Metadaten SQLite öffnet. Datenbank und `-wal` bleiben byte- und datumsgleich.
- **H-10 · Für B02:** „Abbrechen" bricht einen Import über den Reiter „URL" desselben Sheets **nicht** ab; nach 2 s
  Verzögerung erscheint die Playlist trotzdem (`testQA2_HinweisB02_AbbrechenBeiURLImport`: 1 Playlist). Fund des
  `code-reviewer`, verifiziert. Der Build-Bericht formuliert „Abbrechen bricht wirklich ab" allgemein.
- **H-11 · Für B03:** Aktualisieren einer Xtream-Playlist mit 3.000 Sendern blockiert den Main-Thread **9,39 s**
  (`testQA2_HinweisB03_…`). Das ist derselbe quadratische Pfad wie vor BUG-12.
- **H-12 · Passwort `..` (oder `.`)** ergibt ein Punktsegment im Stream-Pfad (`/live/qa-user/../101.ts`). Server
  normalisieren das zu `/live/101.ts`, der Sender spielt dann nicht. Sehr selten; Punkte sind in Pfadabschnitten erlaubt.
- **Umstellung beim Start** blockiert den Main-Thread einmalig (17.000 Sender 2,34 s inklusive `VACUUM`), wie in
  Annahme 5 des Build-Berichts beschrieben.

### Korrekturen an der Spec (die Rekonstruktion beschreibt noch `c01f1cf`)

| Stelle | Spec sagt | Ist nach Reparatur (belegt) |
|---|---|---|
| AK-12, FB-02, EC-07 | `https` → `http`, kein Hinweis | `https` bleibt; Hinweis im Sheet ohne `https://`; kein HTTP-Rückfall (OF-10) |
| AK-14, FB-06 | `+`, `#`, `?`, `/` zerlegen Anfrage bzw. Pfad | korrekt kodiert |
| AK-15, AK-24, FB-01 | Zugangsdaten in `sourceURL` und jeder `streamURL` | gespeichert ohne Zugangsdaten; abspielbar nur über `StreamURLResolver` aus dem Schlüsselbund; Rest → BUG-13 |
| AK-25, FB-03 | Einträge im HTTP-Cache | eigene Session ohne Cache; Altbestand einmalig geleert |
| AK-26 | Weiterleitungen werden befolgt | nur innerhalb von Schema/Host/Port |
| AK-28, FB-08, FB-09 | `~/Library/Application Support/default.store` | `Application Support/<Bundle-ID>/MikaPlusPlayer.store`, Übernahme nur bei eigenem Schema |
| EC-11, EC-12, FB-07 | ein Eintrag kippt den ganzen Import | defekte Einträge übersprungen |
| EC-17, EC-20, FB-04, FB-05 | keine Grenzen, keine Bremse, Anlegen auf dem Main-Actor | 180 s / 64 MiB / 100.000 / 512 Zeichen; Bremse ab 3 Fehlversuchen 30 s bis 5 min; Hintergrund-Kontext |
| EC-18 | „Abbrechen" bricht nicht ab | bricht ab (OF-02) |
| neue Bausteine | — | Schlüsselbund, Resolver, Übernahme/Umstellung, Grenzen, Bremse und HTTPS-Hinweis haben kein AK, nur BUG-Nachweise. Vorschlag: nachtragen |
| `design.md` | Aufrufkette, Datenmodell, Zugriffsregeln, Missbrauchsschutz | beschreibt den Stand vor der Reparatur |

## Neue Tests (Durchlauf 2)

| Datei | Fälle | Deckt ab |
|---|---|---|
| `Tests/B01/B01QA2Tests.swift` | 20 | BUG-01 (Datei, Startpfad mit B09-Schema, freigegebene Seiten → BUG-13), BUG-02 (Roh-Bytes), BUG-03 (Cache/Cookies/Session, Bytes nach Leeren), BUG-04 (fremde Stores, v1.1-Vorlage), BUG-05, BUG-06, BUG-07 (Standardweg, Umgehungen, Grenzwerte, Aktualisieren), BUG-08 (Text), BUG-10 (7 Varianten), BUG-11 (Abbruch nach Anmeldung), Resolver, Schlüsselbund aus Sicht eines fremden Prozesses und eines anderen Builds (→ BUG-14), B09-Wiederherstellung, Rückstände. Enthält `B01QA2RawServer` und die Hilfen `B01QA2` |
| `Tests/B01/B01QA2GrenzenTests.swift` | 6 | 64 MiB genau, gzip-Bombe, 100.000 genau, 180 s genau (nur mit `TEST_RUNNER_B01_QA2_FRIST=1`, ≈ 3 min), 17.000 Sender, Hinweis B03 |
| `Tests/B01/B01QA2OberflaecheTests.swift` | 3 | HTTPS-Hinweis (9 Eingaben), EC-18/BUG-11 Originalreproduktion (2 Runden), Hinweis B02 |

Beleg: `features/B01-xtream-login/qa/QA2-iOS-Umstellung-Playlists.png` (iOS-Simulator nach Übernahme und Umstellung).
Die vollständigen Protokolle liegen nur im Scratchpad der Session (`b01qa2/`).

## Für befunde.md

Neue Befunde:

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Übernommene v1.1-Datenbank behält Klartext-Passwörter gelöschter Xtream-Playlists in freigegebenen Seiten (kein Verdichten ohne umgestellte Playlist) | mittel | `AppPersistence.swift:309-311, 220-234` | BUG-13 |
| Nach einem Update (Schlüsselbund-Eintrag eines anderen Builds) entfernt „Löschen" das Xtream-Passwort nicht; der Fehler `-25244` wird verschluckt | mittel | `PlaylistImporter.swift:270-278`, `PlaylistsView.swift:104-107` | BUG-14 |
| Schlüsselbund-Attribute (Label, Playlist-UUID) ohne Freigabe lesbar; Inhalt von fremdem Prozess überschreibbar | niedrig | macOS-Anmelde-Schlüsselbund, `XtreamCredentialStore.swift:46-58` | — (H-6) |
| Anmeldebremse je Host-Schreibweise und nur im Arbeitsspeicher | niedrig | `XtreamLoginThrottle.swift:35-39` | — (H-7) |
| Schlüsselbund-Einträge beiseitegelegter Datenbanken (B09) bleiben ohne Weg zum Entfernen | niedrig | `AppPersistence.swift:87-109` | — (H-8) |
| „Abbrechen" bricht den URL-Import (B02) im selben Sheet nicht ab | niedrig | `ImportPlaylistView.swift:105-106, 132-137, 192-202` | — (H-10, für B02) |
| Aktualisieren großer Xtream-Playlists blockiert weiter den Main-Thread (3.000 Sender 9,4 s) | mittel | `PlaylistImporter.swift:252-305` | — (H-11, für B03) |

Statusänderungen aus Durchlauf 1:

| Befund | BUG-Nr. | Status |
|---|---|---|
| Xtream-Passwort im Klartext in der Datenbank | BUG-01 | behoben 2026-09-16 (Rest → BUG-13) |
| `https` → `http` ohne Hinweis | BUG-02 | behoben 2026-09-16 |
| Import blockiert den Main-Thread | BUG-12 | behoben 2026-09-16 |
| HTTP-Plattencache | BUG-03 | behoben 2026-09-16 |
| `default.store` generisch, nicht app-eigen | BUG-04 | behoben 2026-09-16 |
| keine Prozentkodierung | BUG-05 | behoben 2026-09-16 |
| strenge Dekodierung | BUG-06 | behoben 2026-09-16 |
| keine Drosselung | BUG-07 | behoben 2026-09-16 |
| keine Größen- und Zeitgrenzen | BUG-08 | behoben 2026-09-16 |
| Sheet taucht nach „Abbrechen" wieder auf | BUG-11 | behoben 2026-09-16 |
| Weiterleitungen zu fremdem Host | BUG-10 | behoben 2026-09-16 |
| Dublette / Doppelklick | BUG-09 | Doppelklick behoben 2026-09-16; Dublette offen bis OF-01 |
| Rekonstruktion verliert Benutzerinfo | H-1 | entfällt 2026-09-16 |
| Zugangsdaten im Unified Log bei Private-Data-Logging | H-2 | offen (in der App nicht behebbar) |

„Behoben" heißt hier: im Arbeitsbaum behoben und in QA 2 belegt, **noch nicht ausgeliefert**.

## Nächster Schritt (Durchlauf 2)

Kein Fund ist *kritisch* oder *hoch*. BUG-13 und BUG-14 (*mittel*) kommen nach `features/befunde.md`; die Erfassung
muss nicht warten. Vor dem Abschluss von B01 bleibt dreierlei offen:
- Der reparierte Stand ist noch nicht ausgeliefert: Arbeitsbaum committen und ausliefern (`/sdd-deploy B01`, hängt am
  Release-Weg von B09).
- Die Spec muss nachgeführt werden (*Korrekturen an der Spec*).
- Über OF-01, OF-02, OF-04 und OF-08 bis OF-12 muss entschieden werden.

Wer BUG-13 und BUG-14 gleich mitbehebt: Beide Änderungen sind klein. Nach einer Übernahme immer verdichten; Fehler beim
Löschen des Eintrags sichtbar machen.

---

# Durchlauf 1


Durchlauf 1 · Stand: 2026-09-16 · Geprüft gegen `spec.md` vom 2026-09-15 (Status `rekonstruiert`)

## Fazit

**Production-ready: nein**

Der fachliche Kern von B01 arbeitet wie in der Rekonstruktion beschrieben: Adressbildung, die drei
`player_api.php`-Anfragen, die Sendezuordnung, alle sieben Fehlermeldungen und das Sheet selbst sind
ausgeführt und bestätigt. Durchgefallen sind genau die Punkte, die die Rückerfassung als ⚠ markiert
oder als Fehler eingestuft hatte — sie sind jetzt mit Nachweis belegt, nicht mehr nur behauptet.
Zwei davon wiegen schwer: Das Passwort steht im Klartext in der Datenbank (in `sourceURL` **und** in
jeder `streamURL`, belegt per SQLite-Abfrage), und ein ausdrücklich eingegebenes `https://` wird
stillschweigend auf `http://` herabgestuft — der Klartext-Mock hat alle drei Anfragen samt Passwort
gelesen. Dazu kommt ein bisher nicht dokumentierter Fund: Der Import legt die Sender auf dem
Main-Actor an, und zwar überproportional teuer — 6 000 Sender blockieren die Oberfläche 35 s,
17 000 Sender (die Größenordnung, die das PRD ausdrücklich verspricht) 285 s.

Nächster Schritt: `/sdd-build B01` mit BUG-01 bis BUG-12. Die Erfassung der weiteren Bestandsfeatures
wartet, bis die Funde mit dem Grad *hoch* behoben und erneut geprüft sind.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 27 von 30 |
| davon bestanden | 20 |
| davon durchgefallen | 7 |
| **nicht prüfbar** | 3 |
| Edge Cases belegt | 22 von 22 (einer weicht von der Spec ab → BUG-11) |
| Tests neu geschrieben | 56 |
| Tests grün | 69 von 70 · 1 übersprungen (AK-27), **0 Fehlschläge**; darin 25 als `XCTExpectFailure` markierte Belege für die Fehler unten |

## Prüfumgebung

| Was | Wie |
|---|---|
| Testlauf | `xcodegen generate` · `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test` · 2026-09-16 09:32–09:36 · Ergebnis `** TEST SUCCEEDED **`, `Executed 70 tests, with 1 test skipped and 0 failures (0 unexpected) in 237.4 seconds` |
| Panel | `Tests/Support/MockXtreamServer.swift` — HTTP-Server im Testprozess, nur Loopback (127.0.0.1 bzw. ::1), schreibt jede Anfrage **roh** mit (Request-Zeile, Kopfzeilen). Kein Zugriff auf echte Anbieter |
| Zugangsdaten | ausschließlich erfunden (`qa-user` / `qa-pass-…`) |
| Datenbank | eigener `ModelContainer` in-memory bzw. eine Store-Datei im Temp-Verzeichnis. `~/Library/Application Support/default.store` des Nutzers wurde **nicht** beschrieben und nicht ausgelesen (nur Metadaten und die 15 Byte Dateikopf) |
| Oberfläche | macOS: `ImportPlaylistView`/`PlaylistsView` in einem echten Fenster des Test-Hosts, bedient über synthetische **Maus**-Ereignisse und den Feld-Editor, Zustand über AppKit-Accessibility. Keine Tastaturereignisse, keine Wiedergabe — der Lauf ist **tonlos** |
| iOS | nicht bedient: für den Simulator stehen in dieser Umgebung nur Build-/Screenshot-Werkzeuge zur Verfügung, keine Tipp- oder Gesten-Automatisierung (siehe *nicht prüfbar*) |
| Plattencache | Die Tests erzeugen Einträge im Cache des Test-Hosts (`~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db`) und entfernen **nur ihre eigenen** wieder (`testZZ_AufraeumenEigenerCacheEintraege`, Filter `127.0.0.1`/`[::1]` + `qa-`). Gegenprobe nach dem Lauf: `select count(*) … → 0` |
| Codequalität | `code-reviewer`-Agent über die B01-Dateien; seine zwei Funde wurden nachgeprüft (einer bestätigt → Hinweis H-1, einer nicht reproduzierbar → verworfen) |

## Akzeptanzkriterien im Einzelnen

Abgehakt ist nur, was ausgeführt wurde. Testnamen ohne Pfadangabe liegen unter `Tests/B01/`.

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | `B01OberflaecheTests.testAK01_SheetFelderUndMindestgroesse` — „+“ und „Playlist importieren“ öffnen das Sheet, Reiter „Xtream" vorausgewählt (AX-Wert 1), alle Beschriftungen vorhanden, viertes Feld ist ein `NSSecureTextField` (AX-Wert = 12 × U+F79A, kein Klartext), Inhaltsgröße `470 × 425` ≥ 420 × 360 |
| AK-02 | ✅ bestanden | `testAK02_FormatStandardUndHinweis` — Standard „MPEG-TS (.ts)" ausgewählt (AX-Wert 1) mit „Originalformat des Anbieters – benötigt VLCKit.“; nach Klick auf HLS: „Spielt direkt mit AVKit – kein VLCKit nötig.“ |
| AK-03 | ✅ bestanden | `testAK03_ButtonNurMitAllenDreiFeldern` — 9 Feldkombinationen über den Feld-Editor eingegeben; Button aktiv genau dann, wenn Host, Benutzer und Passwort je ein Nicht-Leerzeichen enthalten (Leerzeichen und Tabulatoren zählen nicht); in keinem Fall ging eine Anfrage raus |
| AK-04 | ⚠️ nicht prüfbar | macOS-Teil bestanden (`testAK04_KeineAutokorrekturMacOS`: Autokorrektur Host = `false`, Benutzer = `false`, Namensfeld zum Vergleich `true`). Der iOS-Teil (keine automatische Großschreibung, URL-Tastatur) ist ohne UI-Automatisierung im Simulator nicht ausführbar |
| AK-05 | ✅ bestanden | `testAK05_EC21_ZustandWaehrendDesImports` — während des Imports: `AXBusyIndicator` + „Importiere…“, „Anmelden & importieren“ deaktiviert, „Abbrechen“ aktiv |
| AK-06 | ✅ bestanden | `testAK06_ErfolgSchliesstSheetNeuePlaylistOben` (Sheet schließt selbst, „QA Zweite, 4 Sender“ vor „QA Erste, 4 Sender“, Screenshot `qa/AK-06-playlists.png` mit Globus-Symbol) und `B01ImportTests.testAK06_ErfolgreicherImportLegtPlaylistMitNSendernAn` (N = 4, `isXtream`, `channelCount`) |
| AK-07 | ✅ bestanden | `testAK07_NameAusHostOderEingabeUngekuerzt` — leer → `127.0.0.1` (ohne Schema/Port), `"  Mein Anbieter "` und `"   "` unverändert gespeichert |
| AK-08 | ✅ bestanden | `testAK08_SenderZuordnungAusLiveStreams` — 4 Sender aus 4 Streams; Gruppe „News“ (erste Kategorie gewinnt gegen „News-Duplikat“), unbekannte/fehlende `category_id` → ohne Gruppe; `stream_icon`/`epg_channel_id` leer oder `null` → `nil`; keine VOD-/Serien-Anfrage |
| AK-09 ⚠ | ❌ durchgefallen | Ist-Verhalten reproduziert und als Befund erfasst: `testAK09_DoppelterImportLegtZweitePlaylistAn` → 2 Playlists, 8 Sender, keine Warnung → **BUG-09** |
| AK-10 | ✅ bestanden | `testAK10_DreiAnfragenInReihenfolgeOhneGetPhp` — mitgeschriebener Payload: `GET /player_api.php?username=qa-user&password=qa-pass-ak10`, `…&action=get_live_categories`, `…&action=get_live_streams`; kein `get.php`. `testAK10_NachFehlschlagKeineWeitereAnfrage`: nach Fehler folgt keine weitere Anfrage |
| AK-11 | ✅ bestanden | `B01AdressbildungTests.testAK11_HostNormalisierungAmPayload` — Eingabe `" \n127.0.0.1:<port>/panel/sub/?x=1 \n"` → alle drei Anfragen auf `/player_api.php`, kein `x=1`; zusätzlich `" example.com:8080/panel/?x=1 \n"` → `http://example.com:8080/player_api.php?username=u&password=p` |
| AK-12 ⚠ | ❌ durchgefallen | `testAK12_HTTPSWirdAufHTTPHerabgestuft` — Eingabe `HTTPS://127.0.0.1:<port>`: der **Klartext**-Mock empfängt alle drei Anfragen inkl. `password=qa-pass-ak12`, gespeicherte Adressen mit Schema `http`, Port bleibt → **BUG-02** |
| AK-13 | ✅ bestanden | `testAK13_EC09_EC10_TrimNurLeerzeichen` — `" qa-user "` / `"  qa-pass-ak13 "` kommen getrimmt an (Anfrage und Stream-Pfad); Zeilenumbruch bleibt und geht als `%0A` raus |
| AK-14 ⚠ | ❌ durchgefallen | (a) bestanden: `testAK14a_SonderzeichenDieUnveraendertAnkommen` (Leerzeichen, Umlaute, `%`, `&`, `=` unverändert). (b) `testAK14b_PlusWirdAlsLeerzeichenGelesen`: `qa+pass` geht unkodiert raus, das PHP-Panel liest `qa pass`, Anmeldung scheitert. (c)/(d) `testAK14cd_…`: `a#b` → Pfad `/live/qa-user/a`, Rest im Fragment; `a?b` → Rest in der Query; `a/b` → `/live/qa-user/a/b/101.ts` → **BUG-05** |
| AK-15 | ✅ bestanden | `testAK15_StreamAdresseUndFormat` — `http://127.0.0.1:<port>/live/qa-user/qa-pass-ak15/101.ts` bzw. `.m3u8`, `stream_id` als Zahl und als Text gleich, `server_info.url = evil.example` wird ignoriert |
| AK-16 | ✅ bestanden | `B01ImportTests.testAK16_AuthUngleichEinsOderOhneUserInfo` — `auth: 0`, `auth: 2`, ohne `user_info`, leeres `user_info` → „Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen.“ |
| AK-17 | ✅ bestanden | `testAK17_HTTPStatusAusserhalb2xx` — 401, 407, 500, 300 → „Netzwerkfehler: HTTP <Status>“; Grenzwert 299 gilt als Erfolg |
| AK-18 | ✅ bestanden | `testAK18_UnerwarteteServerantwort` — HTML, leerer Inhalt, `auth` als Text, Kategorien `null`, Streams als Objekt → „Netzwerkfehler: Unerwartete Serverantwort (…)“ mit englischem Systemtext |
| AK-19 | ✅ bestanden | `testAK19_LeereStreamliste` → „Die Playlist enthält keine gültigen Sender.“ |
| AK-20 | ✅ bestanden | `testAK20_HostNichtErreichbar` (geschlossener Port → „Could not connect to the server.“, unbekannter Name → „A server with the specified hostname could not be found.“) und `B01LangsamTests.testAK20_AK23_TimeoutNach60Sekunden` (Verbindung steht, keine Daten → nach **60,0 s** „The request timed out.“) |
| AK-21 | ✅ bestanden | `testAK21_UngueltigerHostOhneAnfrage` — `exa mple.com`, `http://`, `127.0.0. 1:<port>` → „Host ungültig. Bitte prüfe die Eingabe.“, **0** Anfragen am Mock |
| AK-22 | ✅ bestanden | `testAK22_FehlschlagLegtNichtsAn` — nach sechs verschiedenen Fehlschlägen 0 Playlists, 0 Sender, kein offener Kontext-Änderungsstand; ergänzend in der Oberfläche `testAK16bis22_FehlerAlertEingabenBleibenButtonSofortAktiv` (Alert „Fehler“ + „OK“, danach stehen alle vier Eingaben unverändert im Formular, Button sofort wieder aktiv, Sheet bleibt offen, 0 Playlists) |
| AK-23 | ✅ bestanden | `B01SicherheitTests.testAK23_FehlermeldungenOhneZugangsdatenUndAdresse` — alle sieben Meldungen (inkl. Timeout in `B01LangsamTests`) enthalten weder Benutzer noch Passwort noch `player_api`/Host |
| AK-24 ⚠ | ❌ durchgefallen | `testAK24_KlartextInDatenbankUndRestNachLoeschen` — SQLite auf der Test-Store-Datei: `ZPLAYLIST` mit Passwort in `ZSOURCEURL` = **1 von 1**, `ZCHANNEL` mit Passwort in `ZSTREAMURL` = **4 von 4** → **BUG-01** |
| AK-25 ⚠ | ❌ durchgefallen | `testAK25_ZugangsdatenImHTTPPlattencache` — 3 Cache-Schlüssel mit `username`/`password` auf der Platte, 1 gespeicherter **Antwortkörper** enthält das Passwort ebenfalls; nach dem Löschen der Playlist weiterhin 3 → **BUG-03** |
| AK-26 ⚠ | ❌ durchgefallen | `testAK26_WeiterleitungTraegtZugangsdatenZumZiel` — 302 auf einen zweiten Mock: Ziel erhält alle drei Anfragen inkl. `qa-user`/`qa-pass-ak26`; Stream-Adressen zeigen weiter auf den eingegebenen Port → **BUG-10** |
| AK-27 | ⚠️ nicht prüfbar | `testAK27_KeinPasswortImSystemprotokoll` (übersprungen, Grund im Testbericht): Am Test-Host ist Private-Data-Logging aktiv (Sonde: `Logger`-Eintrag mit `privacy: .private` erscheint im Klartext). Im Unified Log des Laufs stehen **9** Zeilen mit dem Testpasswort, alle aus `com.apple.CFNetwork` (`NSErrorFailingURLStringKey=http://…?username=…&password=…`), keine einzige `<private>`. Vergleichssonde mit derselben API, **nicht** aus Xcode gestartet: 0 Treffer, `NSErrorFailingURLStringKey=<private>`. Die App selbst protokolliert nichts. Ob ein regulär gestarteter Release-Build schweigt, ließ sich nicht an der App selbst prüfen, weil ihr Start die echte Nutzerdatenbank öffnet → Hinweis H-2 |
| AK-28 ⚠ | ❌ durchgefallen | `testAK28_SpeicherortUndBackup` — Standardkonfiguration ergibt `/Users/<nutzer>/Library/Application Support/default.store` (nicht app-eigen), `isExcludedFromBackup = false`; `tmutil isexcluded … → [Included]` → **BUG-04** |
| AK-29 | ⚠️ nicht prüfbar | Der einzige Löschweg liegt im Kontextmenü der Playlist-Karte. Ein Kontextmenü lässt sich im Testprozess nicht ohne modale Menü-Schleife öffnen; die Aussage „es gibt keinen anderen Weg“ ist eine Negativaussage über die Oberfläche und nicht ausführbar. Der Löschvorgang selbst ist in der Sicherheitsprüfung (Nr. 8) belegt |
| AK-30 | ✅ bestanden | `git log -p --all` über alle **19** Commits: `username=` nur `demo`, `u`, `…`; `password=` nur `secret`, `p`, `…`; `/live/…` nur `user/pass` und `\(user)/\(pass)`. Keine echten Zugangsdaten, kein Anbieter-Host (nur der Markenname „Telecasty“ in einem Kommentar) |

## Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ✅ belegt | `testEC01_FragmentImHost` — Anfragen gehen, Stream-Adresse `http://127.0.0.1:<port>#f/live/qa-user/<pass>/103.ts`, Pfad leer |
| EC-02 | ✅ belegt | `testEC02_FremdesSchema` — `ftp://example.com` → `http://ftp`, `httpx://…` → `http://httpx`; Anfrage endet mit „Netzwerkfehler: A server with the specified hostname could not be found.“ |
| EC-03 | ✅ belegt | `testEC03_BenutzerinfoImHost` — `qa-u:qa-pw@…` bleibt in `sourceURL` und in jeder Stream-Adresse; kein `Authorization`-Header. Nebenbefund: die Rekonstruktion für B03 verliert die Benutzerinfo (Hinweis H-1) |
| EC-04 | ✅ belegt | `testEC04_IDNHost` — `müller.de` → `xn--mller-kva.de` |
| EC-05 | ✅ belegt | `testEC05_IPv6Host` — Mock auf `::1`: 3 Anfragen, Name `::1`, Adresse `http://[::1]:<port>/live/…`, Rekonstruktion `http://[::1]:<port>` |
| EC-06 | ✅ belegt | `testEC06_UnterpfadWirdVerworfen` — Anfrage geht an `/player_api.php`, das Panel unter `/panel/` antwortet mit 404 → „Netzwerkfehler: HTTP 404“ |
| EC-07 | ✅ belegt | `testEC07_HTTPSNurTLSPanel` — Adresse `https://example.com:8443` → `http://example.com:8443`; das Verhalten gegen einen TLS-Port ist **simuliert** (Mock antwortet wie nginx mit 400) → „Netzwerkfehler: HTTP 400“ |
| EC-08 | ✅ belegt | `testEC08_DoppelterSchraegstrichOhneSchema` — Basis `http://` ohne Host; Meldung (in der Spec noch offen): „Netzwerkfehler: Could not connect to the server.“, 0 Anfragen am Mock |
| EC-09 | ✅ belegt | `testAK13_EC09_EC10_TrimNurLeerzeichen` — Benutzer nur aus Zeilenumbruch gilt als ausgefüllt, Zeilenumbruch geht als `%0A` raus (ob die Textfelder Zeilenumbrüche annehmen, bleibt offen — Einfügen per Zwischenablage nicht geprüft) |
| EC-10 | ✅ belegt | ebenda — Passwort mit Rand-Leerzeichen wird still gekürzt |
| EC-11 | ✅ belegt | `testEC11_CategoryIdAlsZahlKipptGanzenImport` — `category_id` als Zahl in Kategorien **oder** in Streams: „…(The data couldn’t be read because it isn’t in the correct format.)“ → BUG-06 |
| EC-12 | ✅ belegt | `testEC12_EinStreamOhneNamenKipptGanzenImport` — ein `name: null` verhindert den Import auch des zweiten, gültigen Senders → BUG-06 |
| EC-13 | ✅ belegt | `testEC13_EC15_KommazahlIdUndLeererName` — `stream_id: 5.0` → `5.ts` |
| EC-14 | ✅ belegt | `testEC14_StreamIdMitSchraegstrich` — `abc/def` → `/live/qa-user/<pass>/abc/def.ts` |
| EC-15 | ✅ belegt | `testEC13_EC15_…` — leerer Name bleibt leer, kein Ersatzname |
| EC-16 | ✅ belegt | `testEC16_AbgelaufenesKontoWirdImportiert` — `auth: 1` + `status: "Expired"` → Import gelingt ohne Hinweis (OF-03) |
| EC-17 | ✅ belegt | `B01LangsamTests.testEC17_…` — Panel tröpfelt die Anmeldeantwort in 7 Stücken alle 10 s: Import läuft **70,1 s** durch und gelingt; der 60-s-Timeout greift nicht → BUG-08 |
| EC-18 | ❌ weicht ab | `B01OberflaecheTests.testEC18_AbbrechenBrichtImportNichtAb` — „Abbrechen“ schließt das Sheet, der Import läuft weiter (Playlist erscheint danach). **Anders als in der Spec** bleibt ein späterer Fehler nicht unsichtbar: das geschlossene Sheet taucht losgelöst vom Hauptfenster wieder auf dem Bildschirm auf, mit dem Alert „Fehler“ darauf (`CGWindowList`: on screen, `sheetParent = nil`) → **BUG-11** |
| EC-19 | ✅ belegt | `testEC19_DoppelklickAufAnmelden` — zwei Klicks im selben Durchlauf: 2 Anmeldeanfragen, 2 Playlists; echter Doppelklick mit 150 ms Abstand: 1 Anfrage, 1 Playlist → BUG-09 |
| EC-20 | ✅ belegt (Ausmaß neu) | `testEC20_GrosseSenderlisteBlockiertMainThread` — Main-Thread blockiert: 1 500 Sender **2,3 s**, 3 000 **9,1 s**, 6 000 **35,4 s**; Einzelmessung mit 17 000 Sendern: **284,9 s** (`qa/EC-20-messung.txt`; Stichprobe `sample`: Hotspot `PlaylistImporter.attach`, Zeile 170/171) → **BUG-12** |
| EC-21 | ✅ belegt | `testAK05_EC21_…` — Reiterwechsel während des Imports: „Importiere…“ auf jedem Reiter sichtbar, „Von URL importieren“ und „Datei auswählen“ deaktiviert, Import läuft weiter |
| EC-22 | ✅ belegt | `testEC22_HLSGesperrtImportGelingtTrotzdem` — Import gelingt, kein `/live/`-Abruf während des Imports |

## Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md` (Stufe B), übertragen auf
eine lokale App ohne Backend.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| 1 · Zugriff auf fremde ID (IDOR) | trifft nicht zu | Die App hat keinen Server, keine Konten und keine per ID abrufbare Ressource; alle Daten liegen lokal. Ersatzprüfung: Zeile 2. `XtreamClient`/`PlaylistImporter` nehmen keine fremde Kennung entgegen |
| 2 · Zugriffsregeln (hier: Betriebssystem statt Datenbank) | **BUG-01, BUG-04** | `~/Library/Application Support/default.store`, `mode = -rw-r--r--`, Eigentümer `michaelferreira:staff`; von einer **fremden Prozessinstanz** (Shell) gelesen: Dateikopf `SQLite format 3` — unverschlüsselt, ohne Sandbox für jeden Prozess desselben Nutzers lesbar. Schutz nur durch `~/Library` (`drwx------`) gegenüber anderen macOS-Nutzern |
| 3 · Rate Limit greift | **BUG-07** | `testFB04_WiederholteFehlanmeldungenOhneDrosselung`: 10 Fehlanmeldungen in Folge, **10 von 10** erreichen das Panel, Gesamtdauer **0,01 s**, keine Wartezeit, keine Warnung. In der Oberfläche ist der Button nach dem Alert sofort wieder aktiv (`testAK16bis22_…`) |
| 4 · PII in Protokollen | teils bestanden, Hinweis H-2 | Fehlermeldungen der App enthalten keine Zugangsdaten (AK-23, sieben Fälle). Im Unified Log des Test-Hosts stehen 9 CFNetwork-Fehlerzeilen mit Benutzer und Passwort im Klartext — beim regulär gestarteten Vergleichsprozess schwärzt das System dieselbe Stelle (`<private>`, 0 Treffer). Keine Absturzberichte zur App in `~/Library/Logs/DiagnosticReports` |
| 5 · PII an externe Dienste | **BUG-02, BUG-10** | Tatsächlicher Payload am Mock: `GET /player_api.php?username=qa-user&password=qa-pass-ak10 HTTP/1.1`, Kopfzeilen `accept`, `accept-encoding`, `accept-language: de-DE,de;q=0.9`, `connection`, `host`, `user-agent: Mika+Player/2 CFNetwork/3896.100.1.1.1 Darwin/27.0.0` — kein weiterer Inhalt, aber auch nichts entfernt. Bei `HTTPS://`-Eingabe geht derselbe Payload **unverschlüsselt** raus (BUG-02); bei einer 302-Weiterleitung erhält der fremde Port denselben Payload (BUG-10) |
| 6 · Geheimnisse im Repository | bestanden | `git log -p --all` über 19 Commits: nur Beispielwerte (AK-30). Im ausgelieferten Bundle `build/MikaPlusPlayer.app` (v1.1): keine Schlüssel, keine Zugangsdaten (`strings`, `grep` auf `password=…`, `sk_live_`, `service_role` → 0 Treffer) |
| 7 · Eingaben | teils bestanden, **BUG-05** | `testAngriff07_EingabenInJedemFeld`: je Feld leer, 1 Zeichen, 10 000 Zeichen, Emoji, `'; drop table --`, `<script>alert(1)</script>`, `../../etc/passwd`, `#?/%&`, Umlaute. Kein Absturz, keine rohe Systemmeldung, Name in allen Fällen exakt gespeichert (10 000 Zeichen inklusive), Host ohne gültige Form → „Host ungültig“. **Falsch** werden die Stream-Adressen, sobald Benutzer oder Passwort `/`, `#` oder `?` enthalten (Script-, Pfad- und Sonderzeichen-Eingabe) — derselbe Kern wie BUG-05 |
| 8 · Löschen | teils bestanden, **BUG-03** | Nach `delete(playlist)` + `save()` auf der Test-Store-Datei: `ZPLAYLIST` = 0, `ZCHANNEL` = 0, Zeilen mit Passwort = 0. Als Bytefolge stand das Passwort danach noch 5 × in der `-wal`-Datei; nach dem Schließen des Containers (Checkpoint) in keiner Datei mehr (0/0/0). **Nicht** gelöscht werden die Plattencache-Einträge: nach dem Löschen weiterhin 3 Schlüssel mit Zugangsdaten (BUG-03) |

## Fehler

### BUG-01 · Xtream-Passwort im Klartext in der Datenbank, keine Keychain — hoch

**Betrifft:** AK-24 (FB-01, DM-01)
**Reproduktion:**
1. Xtream-Playlist mit Host `127.0.0.1:<port>`, Benutzer `qa-user`, Passwort `qa-pass-ak24` importieren
2. Store-Datei mit SQLite öffnen:
   `select count(*) from ZPLAYLIST where instr(cast(ZSOURCEURL as text), 'qa-pass-ak24') > 0` → **1**
   `select count(*) from ZCHANNEL where instr(cast(ZSTREAMURL as text), 'qa-pass-ak24') > 0` → **4 von 4**
**Erwartet:** Das Passwort steht in der Keychain, nicht in der Datenbank
**Tatsächlich:** Es steht einmal in `Playlist.sourceURL` und zusätzlich in **jeder** `Channel.streamURL`; bei 17 000 Sendern also 17 001 Kopien in einer Datei, die jeder Prozess desselben macOS-Nutzers lesen kann (Sicherheitsprüfung 2)
**Ort:** `Sources/Services/XtreamCodes.swift:85-95` (`playerAPIURL()`), `Sources/Services/XtreamClient.swift:46` (Interpolation), `Sources/Services/PlaylistImporter.swift:76, 160-171`
**Vorschlag:** Zugangsdaten je Playlist in die Keychain legen, `sourceURL` und `streamURL` ohne Geheimnis speichern und die Adresse erst beim Abspielen bilden.
**Test:** `B01SicherheitTests.testAK24_KlartextInDatenbankUndRestNachLoeschen` (mit `XCTExpectFailure`)
**Behoben 2026-09-16:** Benutzername, Passwort und die normalisierte Basisadresse liegen je Playlist im Schlüsselbund
(`Services/XtreamCredentialStore.swift`, Dienst `lu.daumedia.MikaPlusPlayer.xtream`, Konto = `Playlist.id`,
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). `sourceURL` ist jetzt `http[s]://host[:port]/player_api.php`,
`streamURL` `http[s]://host[:port]/live/<stream_id>.<ext>` – beide ohne Geheimnis und ohne Benutzerinfo. Abspielbar
wird eine Adresse nur an einer Stelle: `Services/StreamURLResolver.swift` (benutzt von `PlayerView` und
`MultiviewSession`). Aktualisieren (B03) liest den Schlüsselbund; Löschen (`PlaylistImporter.delete`, aus
`PlaylistsView`) entfernt den Eintrag. Vorhandene Datenbanken werden beim ersten Start umgestellt
(`AppPersistence.migrateCredentials`: Zugangsdaten → Schlüsselbund, Adressen bereinigt, dieselben Sender-Objekte,
Favoriten bleiben, danach `wal_checkpoint(TRUNCATE)`). Nachweis: AK-24 jetzt 0 von 1 / 0 von 4 Zeilen, 0 Bytefolgen in
Store/-wal/-shm, Eintrag im Test-Schlüsselbund, nach Löschen weg; Migration auf Temp-Datenbank mit drei Alt-Playlists
(Sonderzeichen, Benutzerinfo, Passwort mit `/`) und einer M3U-Playlist: 3 umgestellt, 5 Sender umgeschrieben,
Favoriten und Sender-IDs unverändert, abspielbare Adressen identisch mit den alten, 0 Bytefolgen bei offenem Container
(`B01ReparaturTests.testBUG01_MigrationVorhandenerDatenbankOhneDatenverlust`), nicht umgestellter Altbestand bleibt
spielbar und wird beim Aktualisieren umgestellt (`testBUG01_AltbestandBleibtSpielbarUndWirdBeimAktualisierenUmgestellt`).
`XCTExpectFailure` entfernt.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — keine Bytefolge von Passwort/Benutzer in Store/-wal/-shm, auch über den Startpfad mit B09-Schema und auf iOS; Rest aus gelöschten v1.1-Playlists → BUG-13 (`testQA2_BUG01_…`, `testQA2_BUG01_BUG04_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-02 · Eingegebenes `https://` wird ohne Hinweis auf `http://` herabgestuft — hoch

**Betrifft:** AK-12 (FB-02)
**Reproduktion:**
1. Host `HTTPS://127.0.0.1:<port>` eingeben, Benutzer `qa-user`, Passwort `qa-pass-ak12`, importieren
2. Den mitschreibenden **Klartext**-Server ansehen
**Erwartet:** Entweder TLS-Versuch oder Abbruch mit Hinweis — jedenfalls keine Zugangsdaten im Klartext
**Tatsächlich:** Alle drei Anfragen kommen unverschlüsselt an, jede mit `password=qa-pass-ak12` in der Request-Zeile; gespeicherte `sourceURL` und alle Stream-Adressen haben Schema `http`, der Port bleibt erhalten. Kein Hinweis in der Oberfläche
**Ort:** `Sources/Services/XtreamCodes.swift:69-74`; ATS global offen in `Sources/Resources/Info.plist:39-40`
**Vorschlag:** Eingegebenes `https` beibehalten; bei Fehlschlag nur nach ausdrücklicher Bestätigung auf HTTP zurückfallen, und das in der App benennen.
**Test:** `B01AdressbildungTests.testAK12_HTTPSWirdAufHTTPHerabgestuft` (mit `XCTExpectFailure`)
**Behoben 2026-09-16:** `XtreamCredentials.baseURL()` behält ein eingegebenes `https://` (jede Schreibweise);
ohne Schema bleibt `http://` (gewollt laut Kommentar/README). Das Sheet zeigt unter „Xtream-Codes-Zugang", solange
der Host nicht mit `https://` beginnt: „Ohne „https://“ gehen Benutzername und Passwort unverschlüsselt über das
Netz." Kein Rückfall auf HTTP (Rückfrage-Variante → OF-10). Nachweis: `testAK12_HTTPSBleibtErhalten` –
`HTTPS://127.0.0.1:<port>` gegen den Klartext-Mock: **0** Anfragen angekommen, Meldung „Netzwerkfehler: The request
timed out.", nichts angelegt; Adressen/Stream-URLs mit `https`. Hinweis: `B01OberflaecheTests.testBUG02_HinweisAufUnverschluesselteUebertragung`
(sichtbar bei leer, ohne Schema, `http://`; weg bei `HTTPS://`). Test umbenannt, `XCTExpectFailure` entfernt;
`XtreamCodesTests.testDowngradesHTTPS` → `testKeepsHTTPS`.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — rohe Mitschrift: nur TLS-Handshake (`0x16`), 0 × Passwort; Hinweis im Sheet bei 9 Eingaben korrekt (`testQA2_BUG02_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-03 · Zugangsdaten und Antworten im HTTP-Plattencache, überstehen das Löschen — mittel

**Betrifft:** AK-25 (FB-03)
**Reproduktion:**
1. Import gegen ein Panel, dessen `user_info` (wie bei echten Panels) Benutzer und Passwort zurückmeldet
2. `~/Library/Caches/<Bundle-ID>/Cache.db`: `select count(*) from cfurl_cache_response where instr(request_key, '<passwort>') > 0` → **3**; ein gespeicherter Antwortkörper enthält das Passwort ebenfalls (**1**)
3. Playlist löschen, Schritt 2 wiederholen → weiterhin **3**
**Erwartet:** Keine Zugangsdaten auf der Platte; spätestens beim Löschen der Playlist verschwinden sie
**Tatsächlich:** `cachePolicy = .reloadIgnoringLocalCacheData` verhindert nur das Lesen, nicht das Schreiben; kein Code der App räumt den Cache
**Ort:** `Sources/Services/XtreamClient.swift:75-78` (`URLSession.shared`)
**Vorschlag:** Eigene `URLSession` mit `.ephemeral`-Konfiguration (`urlCache = nil`) für `player_api.php`.
**Test:** `B01SicherheitTests.testAK25_ZugangsdatenImHTTPPlattencache` (mit `XCTExpectFailure`; entfernt seine eigenen Einträge wieder)
**Behoben 2026-09-16:** `player_api.php` läuft über eine eigene `ephemeral`-Session mit `urlCache = nil`
(`Services/XtreamHTTPLoader.swift`). Vorhandene Einträge: `AppPersistence.purgeLegacyHTTPCacheOnce` leert beim ersten
Start einmalig `URLCache.shared` – das ist ausschließlich der Cache-Ordner der Bundle-ID –, Merker in `UserDefaults`
(`B01.legacyHTTPCachePurged`); im Test-Host ohne Wirkung. Nachweis: AK-25 jetzt 0 Schlüssel, 0 Antwortkörper, 0 im
Speicher, auch nach dem Löschen; Leeren einmalig und nur einmal (`B01ReparaturTests.testBUG03_AlterHTTPCacheWirdEinmaligGeleert`,
eigener `URLCache` im Temp-Ordner). `XCTExpectFailure` entfernt.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — Loader ohne Cache/Zugangsdatenspeicher, 0 Bytefolgen; einmaliges Leeren entfernt auch `Cache.db-wal`/`fsCachedData` (`testQA2_BUG03_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-04 · Datenbank generisch benannt, nicht app-eigen, nicht vom Backup ausgeschlossen — mittel

**Betrifft:** AK-28 (FB-08, FB-09, DM-02, DM-03)
**Reproduktion:**
1. `ModelConfiguration(schema:, isStoredInMemoryOnly: false).url` → `/Users/<nutzer>/Library/Application Support/default.store`
2. `isExcludedFromBackup` der Datei → `false`; `tmutil isexcluded …` → `[Included]`
**Erwartet:** App-eigener Name bzw. Ordner und Ausschluss vom Backup für eine Datei mit Zugangsdaten
**Tatsächlich:** Standardname im gemeinsamen Application-Support-Ordner (die Website verspricht „They stay in the app’s own storage“), Inhalt wandert in Time Machine bzw. ins Geräte-Backup. Nebenwirkung: Der Test-Host benutzt dieselbe Datei wie die echte App
**Ort:** `Sources/App/MikaPlusPlayerApp.swift:7-15`, `Sources/Resources/MikaPlusPlayer.entitlements:7-8`
**Vorschlag:** `ModelConfiguration` mit eigener URL unter `Application Support/lu.daumedia.MikaPlusPlayer/` und `isExcludedFromBackup = true` setzen — zusammen mit BUG-01 (dann ist der Backup-Ausschluss nur noch zweite Verteidigungslinie).
**Test:** `B01SicherheitTests.testAK28_SpeicherortUndBackup` (mit `XCTExpectFailure`)
**Hinweis:** Der HTTP-Cache ist entgegen `design.md` **nicht** im Backup (`tmutil isexcluded … → [Excluded]`).
**Behoben 2026-09-16:** Datenbank unter `Application Support/<Bundle-ID>/MikaPlusPlayer.store`
(`AppPersistence.configuration`, eingebunden in `MikaPlusPlayerApp`). Eine vorhandene `Application Support/default.store`
wird nur übernommen, wenn ihre Metadaten genau die Entitäten `Playlist` und `Channel` nennen und zum Modell passen;
sie wird per `replacePersistentStore` **kopiert**, die Kopie geprüft und erst dann die alte Datei entfernt. Sonst bleibt
sie unangetastet. Der Test-Host öffnet nur noch einen In-Memory-Container. **Backup:** bewusst **nicht** ausgeschlossen –
nach BUG-01 enthält die Datenbank keine Zugangsdaten mehr, ein Ausschluss nähme beim Wiederherstellen nur die Playlists.
Nachweis: `testAK28_SpeicherortUndBackup` (Pfad app-eigen, Test-Host im Speicher, frische Datei nicht ausgeschlossen) und
`B01ReparaturTests.testBUG04_UebernahmeNurBeiEigenemSchemaKopierenDannLoeschen` (Temp-Ordner: eigenes Schema →
übernommen, Daten und Favoriten vollständig, alte Datei weg; zusätzliche fremde Entität bzw. nur fremde Entität bzw.
keine SQLite-Datei → unangetastet, byte-gleich, keine Kopie; neue Datei vorhanden → alte bleibt). Die echte Datei des
Nutzers wurde nicht geöffnet. `XCTExpectFailure` entfernt.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — fremde `default.store` mit gleichen Entitätsnamen bleibt byte-gleich (nur `-shm` neu, H-9); v1.1-Vorlage wird übernommen (`testQA2_BUG04_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-05 · Benutzername und Passwort werden nicht prozentkodiert — mittel

**Betrifft:** AK-14 (FB-06)
**Reproduktion:** Import mit Passwort …
1. `qa+pass` → beim Panel kommt `qa pass` an (PHP-Dekodierung), Anmeldung scheitert mit „Anmeldung fehlgeschlagen…“
2. `a#b` → Stream-Adresse `…/live/qa-user/a` + Fragment `b/101.ts`
3. `a?b` → `…/live/qa-user/a` + Query `b/101.ts`
4. `a/b` → `…/live/qa-user/a/b/101.ts`
   Dasselbe gilt für den Benutzernamen und für Eingaben wie `<script>alert(1)</script>` oder `../../etc/passwd` (Sicherheitsprüfung 7)
**Erwartet:** `/live/<benutzer>/<passwort>/<id>.<ext>` mit korrekt kodierten Segmenten; Anmeldung mit `+` funktioniert
**Tatsächlich:** Reine String-Interpolation in den Pfad, `URLQueryItem` lässt `+` unkodiert. Der Import „gelingt“, aber kein Sender ist abspielbar
**Ort:** `Sources/Services/XtreamClient.swift:46` sowie `:67-68`, `Sources/Services/XtreamCodes.swift:91-92`
**Vorschlag:** Segmente mit `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"]))` bilden und `+` in Query-Werten kodieren.
**Tests:** `B01AdressbildungTests.testAK14b_…`, `testAK14cd_…`, `B01SicherheitTests.testAngriff07_EingabenInJedemFeld` (je mit `XCTExpectFailure`)
**Behoben 2026-09-16:** Query: `XtreamURLEncoding.setQueryItems` kodiert zusätzlich `+` als `%2B` (Anfragen und
`get.php`-Link). Pfad: Benutzer und Passwort werden in `XtreamStreamAddress.playable` je als ein Abschnitt kodiert
(`urlPathAllowed` ohne `/`). Nachweis: `qa+pass` geht als `password=qa%2Bpass` raus, das PHP-dekodierende Panel liest
`qa+pass`, Import gelingt; `a#b`/`a?b`/`a/b` → `/live/qa-user/a%23b/101.ts` usw., keine Query, kein Fragment;
Angriff 7: 0 fehlerhafte Fälle (vorher 6). `XCTExpectFailure` entfernt.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — 11 Sonderzeichen-Varianten in Anfrage und Stream-Pfad korrekt (`testQA2_BUG05_…`); Hinweis H-12. Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-06 · Strenge Dekodierung: `category_id` als Zahl oder ein Eintrag ohne Namen kippt den ganzen Import — mittel

**Betrifft:** EC-11, EC-12 (FB-07)
**Reproduktion:**
1. Panel liefert `[{"category_id": 1, "category_name": "News"}]` → Import scheitert mit „Netzwerkfehler: Unerwartete Serverantwort (The data couldn’t be read because it isn’t in the correct format.)“
2. Panel liefert einen Stream mit `"name": null` und einen gültigen → kein einziger Sender wird angelegt („…because it is missing.“)
**Erwartet:** Was der Code-Kommentar zusagt — `stream_id`/`category_id` als Zahl **oder** Text; ein defekter Eintrag wird übersprungen
**Tatsächlich:** `FlexibleID` wird nur für `stream_id` benutzt, `category_id` ist fest `String`, `name` nicht optional; die Dekodierung bricht komplett ab
**Ort:** `Sources/Services/XtreamClient.swift:103, 112, 116, 126-134`
**Vorschlag:** `FlexibleID` auch für `category_id`, `name` optional mit Ersatzwert, Streams einzeln dekodieren und fehlerhafte überspringen.
**Tests:** `B01ImportTests.testEC11_…`, `testEC12_…` (mit `XCTExpectFailure`)
**Behoben 2026-09-16:** `category_id` über `FlexibleID` (Zahl oder Text) in Kategorien und Streams; Listen werden
eintragsweise dekodiert (`LossyList`), defekte Einträge übersprungen; Pflicht ist nur `stream_id`; `name: null` wird
wie ein leerer Name `""`; `stream_icon`/`epg_channel_id` tolerant. Ist die Antwort selbst keine Liste, bleibt es bei
„Unerwartete Serverantwort" (AK-18 unverändert grün). Nachweis: `testEC11_CategoryIdAlsZahlWirdImportiert` (beide Fälle
importiert, Gruppe „News"), `testEC12_DefekteEintraegeKippenImportNichtMehr` (5 Einträge: 3 Sender, ohne ID und ID als
Objekt übersprungen; defekte Kategorien übersprungen). `XCTExpectFailure` entfernt.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — Originalreproduktion importiert (`testQA2_BUG06_OriginalReproduktion`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-07 · Keine Drosselung wiederholter Fehlanmeldungen — mittel

**Betrifft:** Fehlbestand FB-04, Katalogfrage 4.1
**Reproduktion:** Zehn Importe mit falschem Passwort hintereinander auslösen → alle zehn Anmeldeanfragen gehen innerhalb von 0,01 s an das Panel; in der Oberfläche ist „Anmelden & importieren“ nach jedem Alert sofort wieder aktiv
**Erwartet:** Nach einigen Fehlversuchen eine Wartezeit oder wenigstens ein Hinweis
**Tatsächlich:** Keine Zählung, keine Sperre. Viele Panels sperren IP oder Konto — der Nutzer sperrt sich selbst aus
**Ort:** `Sources/Views/ImportPlaylistView.swift:86, 152-166`
**Vorschlag:** Fehlversuche je Host zählen und den Button nach dem dritten Fehlschlag für einige Sekunden sperren, mit sichtbarer Begründung.
**Test:** `B01SicherheitTests.testFB04_WiederholteFehlanmeldungenOhneDrosselung` (mit `XCTExpectFailure`)
**Behoben 2026-09-16:** `Services/XtreamLoginThrottle.swift`, geprüft in `XtreamClient` vor der Anmeldung (gilt für
Import und Aktualisieren): je Panel (Schema, Host, Port) nach 3 abgelehnten Anmeldungen in Folge (`auth ≠ 1`, HTTP 401/403)
30 s Sperre, jede weitere Ablehnung verdoppelt bis höchstens 5 min, Erfolg setzt zurück. Gesperrte Versuche erreichen
das Panel nicht; das Sheet zeigt „Zu viele fehlgeschlagene Anmeldungen. Bitte in 30 Sekunden erneut versuchen."
Nachweis: `testFB04_WiederholteFehlanmeldungenWerdenGebremst` – 10 Versuche → **3** beim Panel, danach 30 s bzw. 60 s
Sperre, anderes Panel unberührt, Erfolg setzt zurück; `B01ReparaturTests.testBUG07_BremseZaehltJePanel`. Test umbenannt,
`XCTExpectFailure` entfernt.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — Standardweg 10 → 3 beim Panel, Grenzwerte genau, Aktualisieren gebremst; umgehbar durch Host-Schreibweise/Neustart (H-7) (`testQA2_BUG07_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-08 · Keine Größen-, Mengen- und Gesamtzeitgrenze für Panel-Antworten — mittel

**Betrifft:** EC-17, Fehlbestand FB-05, Katalogfrage 4.4
**Reproduktion:**
1. Panel antwortet mit 24 MB (8 Streams mit je 3 MB langem Namen) → vollständig geladen, dekodiert und gespeichert (24 000 000 Byte Namen in der Datenbank)
2. Panel tröpfelt die Anmeldeantwort in 7 Stücken alle 10 s → Import läuft 70,1 s und gelingt; `timeoutInterval = 60` begrenzt nur die Leerlaufzeit
**Erwartet:** Obergrenze für Antwortgröße und Gesamtdauer eines Imports
**Tatsächlich:** Keine; ein bösartiges oder defektes Panel kann Speicher und Zeit unbegrenzt binden
**Ort:** `Sources/Services/XtreamClient.swift:77-82`, `Sources/Services/PlaylistImporter.swift:154-175`
**Vorschlag:** Antwortgröße begrenzen (z. B. 50 MB, Abbruch mit eigener Meldung) und den gesamten Import in eine Zeitgrenze fassen.
**Tests:** `B01SicherheitTests.testFB05_KeineGroessengrenzeFuerAntwortDesPanels`, `B01LangsamTests.testEC17_…` (mit `XCTExpectFailure`)
**Behoben 2026-09-16:** `XtreamClient.Limits`: je Antwort höchstens 64 MB (geprüft an `Content-Length` und am
tatsächlich empfangenen Datenstrom, `XtreamHTTPLoader`), höchstens 100.000 Einträge je Liste, gemeinsame Frist von
180 s für alle Anfragen eines Imports (zusätzlich zur unveränderten 60-s-Leerlaufgrenze), Name/Gruppe/tvg-ID auf 512
Zeichen gekürzt, Logo-Adressen über 2.048 Zeichen verworfen. Eigene Meldungen ohne Zugangsdaten. Nachweis: 24-MB-Antwort
mit 3-MB-Namen → 8 × 512 statt 24.000.000 Byte gespeichert; 1-MB-Grenze greift mit und ohne `Content-Length`;
Mengengrenze greift; `testEC17_TroepfelndesPanelWirdVonGesamtfristGestoppt` – Frist im Test auf 25 s gesetzt, Import
bricht nach 25,0 s mit Meldung ab (vorher 70,1 s offen). Tests umbenannt, `XCTExpectFailure` entfernt. Die Werte sind
ohne Vorgabe gewählt → OF-12.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — 64 MiB, 100.000 Sender und 180 s mit Standardwerten auf den Grenzwert genau, gzip-Bombe abgelehnt (`B01QA2GrenzenTests`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-09 · Zweiter Import desselben Zugangs legt eine zweite Playlist an; Doppelklick genügt — niedrig

**Betrifft:** AK-09, EC-19 (OF-01)
**Reproduktion:**
1. Denselben Zugang zweimal importieren → zwei unabhängige Playlists mit doppelten Sendern, keine Warnung
2. Oder: zweimal auf „Anmelden & importieren“ klicken, bevor die Ansicht neu gezeichnet ist → 2 Anmeldeanfragen, 2 Playlists. Bei einem echten Doppelklick (150 ms Abstand) tritt das nicht auf: 1 Anfrage, 1 Playlist
**Erwartet:** Hinweis auf die vorhandene Playlist oder Aktualisierung; ein zweiter Klick startet keinen zweiten Import
**Tatsächlich:** Keine Dublettenprüfung; der Button wird erst deaktiviert, wenn die gestartete Aufgabe den Zustand gesetzt hat
**Ort:** `Sources/Services/PlaylistImporter.swift:61-85`, `Sources/Views/ImportPlaylistView.swift:81-86, 157`
**Vorschlag:** `isImporting` **vor** dem Start der Aufgabe im Button-Handler setzen; vor dem Anlegen auf gleiche `sourceURL` prüfen.
**Tests:** `B01ImportTests.testAK09_…`, `B01OberflaecheTests.testEC19_DoppelklickAufAnmelden` (mit `XCTExpectFailure`)
**Behoben 2026-09-16 (Teil Doppelklick):** `ImportPlaylistView.startXtreamImport` setzt `isImporting` **vor** dem Start
der Aufgabe und ignoriert weitere Klicks. Nachweis: `testEC19_DoppelklickAufAnmelden` – zwei Klicks im selben Durchlauf
→ 1 Anmeldeanfrage, 1 Playlist (vorher 2/2). `XCTExpectFailure` dort entfernt.
**Nicht behoben (Teil Dublette):** Ob ein zweiter Import desselben Zugangs verhindert, gemeldet oder als Aktualisierung
behandelt werden soll, ist eine Produktentscheidung (OF-01). `testAK09_…` behält `XCTExpectFailure` mit diesem Grund.

**QA-Durchlauf 2 (2026-09-16):** teilweise — Doppelklick ✅ (1 Anfrage, 1 Playlist); Dublette unverändert, zurückgestellt bis OF-01. Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-10 · Zugangsdaten folgen HTTP-Weiterleitungen zu fremdem Host — niedrig

**Betrifft:** AK-26 (OF-04)
**Reproduktion:** Panel antwortet auf jede Anfrage mit `302 Location: http://127.0.0.1:<anderer Port><selbe Adresse>` → der zweite Server erhält alle drei Anfragen inklusive `username`/`password`; die gespeicherten Stream-Adressen zeigen weiter auf den eingegebenen Port
**Erwartet:** Laut PRD: „Zugangsdaten gehen ausschließlich an den Host, den der Nutzer eingegeben hat“
**Tatsächlich:** `URLSession.shared` folgt Weiterleitungen ohne Delegate und ohne Rückfrage
**Ort:** `Sources/Services/XtreamClient.swift:75-78` (kein `URLSessionTaskDelegate`)
**Vorschlag:** Delegate, das eine Weiterleitung auf einen anderen Host oder Port ablehnt oder die Zugangsdaten dabei entfernt.
**Test:** `B01SicherheitTests.testAK26_WeiterleitungTraegtZugangsdatenZumZiel` (mit `XCTExpectFailure`)
**Behoben 2026-09-16:** `XtreamHTTPLoader` (Session-Delegate) folgt nur Weiterleitungen mit gleichem Schema, Host und
Port und bricht sonst vor der Anfrage ab: „Netzwerkfehler: Der Anbieter leitet auf einen anderen Server weiter. Die
Zugangsdaten wurden dorthin nicht gesendet." Nachweis: `testAK26_WeiterleitungZuFremdemZielWirdAbgebrochen` – 302 auf
anderen Port: Ziel erhält **0** Anfragen (vorher 3), nichts angelegt; `localhost` statt `127.0.0.1`: ebenfalls blockiert;
Pfadwechsel im selben Panel wird befolgt, Import gelingt. Test umbenannt, `XCTExpectFailure` entfernt. OF-04 mit Vermerk.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — 7 Weiterleitungsvarianten, Ziel erhält 0 Anfragen (`testQA2_BUG10_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-11 · Nach „Abbrechen“ taucht das geschlossene Sheet mit dem Fehler-Alert wieder auf — mittel

**Betrifft:** EC-18 (OF-02); **weicht von der Spec-Rekonstruktion ab**
**Reproduktion:**
1. Zugangsdaten eingeben, „Anmelden & importieren“ drücken (Panel antwortet verzögert mit `auth: 0`)
2. Während des Imports „Abbrechen“ drücken — das Sheet schließt sich
3. Warten, bis die Antwort eintrifft
**Erwartet:** Entweder der Import wird abgebrochen (OF-02) oder der Fehler erscheint an einer sinnvollen Stelle
**Tatsächlich:** Das bereits geschlossene Sheet-Fenster wird wieder sichtbar — losgelöst vom Hauptfenster (`sheetParent = nil`, `CGWindowList`: auf dem Bildschirm, `alpha = 1.0`) — und trägt den Alert „Fehler / Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen. / OK“. Das Hauptfenster ist nicht blockiert, ein neues Import-Sheet lässt sich parallel öffnen. Im Erfolgsfall erscheint die Playlist später kommentarlos in der Übersicht
**Ort:** `Sources/Views/ImportPlaylistView.swift:81-82` (ungebundener `Task`), `:124` (`dismiss()` ohne Abbruch), `:134-138` (Alert an `.constant(errorMessage != nil)`)
**Vorschlag:** Die Aufgabe an die Ansicht binden (`.task`/`cancel()` beim Abbrechen) und nach dem Schließen keinen Alert mehr setzen.
**Test:** `B01OberflaecheTests.testEC18_AbbrechenBrichtImportNichtAb` (mit `XCTExpectFailure`)
**Einschränkung:** Reproduziert in einem `NSHostingView`-Fenster des Test-Hosts, nicht im `WindowGroup`-Fenster der ausgelieferten App.
**Behoben 2026-09-16:** Der Import läuft als gebundene Aufgabe (`xtreamImportTask`); „Abbrechen" und das Verschwinden des
Sheets (`onDisappear`, unter iOS auch Wegwischen) brechen sie ab. `PlaylistImporter` prüft vor dem Speichern auf Abbruch,
`XtreamHTTPLoader` bricht die laufende Anfrage ab; nach einem Abbruch setzt die Ansicht weder `dismiss` noch einen Alert.
Wird erst während des blockweisen Speicherns abgebrochen, entfernt der Import bereits gespeicherte Blöcke und den
Schlüsselbund-Eintrag wieder. Nachweis: `testEC18_AbbrechenBrichtImportAb` – (a) keine Playlist, keine weitere Anfrage;
(b) 0 neue Alerts, 0 verwaiste Sheet-Fenster, Sheet lässt sich normal neu öffnen;
`B01ReparaturTests.testBUG11_AbgebrochenerImportLegtNichtsAn` – `CancellationError`, 0 Playlists, 0 Sender;
`testBUG11_AbbruchWaehrendDesSpeicherns` (40.000 Sender, Abbruch nach dem ersten Block) und
`testBUG11_LoaderEndetBeiAbbruchImmer` (200 Abbrüche, keine hängende Anfrage). Test umbenannt, `XCTExpectFailure` entfernt. Verhaltensänderung → OF-02 mit Vermerk.

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — Originalreproduktion ohne Klassennamen-Filter: 0 neue Fenster, kein Fehlertext, 0 Playlists, 0 Schlüsselbund-Einträge (`testQA2_BUG11_…`). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

### BUG-12 · Import blockiert den Main-Thread; der Aufwand wächst überproportional — hoch

**Betrifft:** EC-20, FB-05; widerspricht dem PRD („bleibt auch bei Anbieterlisten mit mehr als 17.000 Sendern bedienbar“)
**Reproduktion:** Import mit N Sendern, dabei die Reaktionszeit des Main-Threads messen:

| Sender | Gesamtdauer | längste Blockade des Main-Threads |
|---|---|---|
| 1 500 | 2,3 s | 2,26 s |
| 3 000 | 9,1 s | 9,08 s |
| 6 000 | 35,4 s | 35,37 s |
| 17 000 | 285,0 s | 284,88 s |

**Erwartet:** Die Oberfläche bleibt bedienbar; der Aufwand wächst linear
**Tatsächlich:** Vervierfachung bei Verdopplung — quadratisches Verhalten. Während des Imports reagiert die Oberfläche gar nicht (kein Spinner-Update, kein Klick). Stichprobe (`sample`) während eines Laufs: fast die gesamte Zeit in `PlaylistImporter.attach` (`PlaylistImporter.swift:170-171`, `playlist.channels.append` samt SwiftData-Beziehungsbuchhaltung)
**Ort:** `Sources/Services/PlaylistImporter.swift:154-175` (Anlegen auf dem `@MainActor`), `:82`
**Vorschlag:** Sender in einem Hintergrund-`ModelContext` in Stapeln anlegen und speichern; `playlist.channels.append` je Objekt vermeiden (Beziehung über `Channel.playlist`/`playlistID` setzen, `channelCount` separat führen).
**Test:** `B01LangsamTests.testEC20_GrosseSenderlisteBlockiertMainThread` (mit `XCTExpectFailure`, misst 1 500/3 000/6 000). Der 17-000-Wert ist wegen der Laufzeit nicht Teil der Suite, aber reproduzierbar: `TEST_RUNNER_B01_QA_EC20_SIZES=1500,3000,6000,17000 xcodebuild test … -only-testing:MikaPlusPlayerTests/B01LangsamTests/testEC20_GrosseSenderlisteBlockiertMainThread` — Ausgabe in `qa/EC-20-messung.txt`
**Einschränkung:** Gemessen im Debug-Build des Test-Hosts mit In-Memory-Store. Der Hotspot liegt in SwiftData selbst (bereits optimierter Framework-Code), eine Release-Messung dürfte daher in derselben Größenordnung liegen — nachzumessen bei der Reparatur.
**Behoben 2026-09-16:** `PlaylistImporter.importFromXtream` legt Playlist und Sender in einem eigenen `ModelContext`
in einer abgelösten Aufgabe an (`persistXtreamPlaylist`), in Blöcken zu 5.000 Sendern mit je einem Speichervorgang.
Die Beziehung wird blockweise über `channels.append(contentsOf:)` gesetzt statt je Sender (`Channel(playlist:)` bzw.
`channels.append(_:)` je Objekt war der quadratische Teil; Vorversuch 3.000 → 6.000 Sender: 1,9 s → 7,3 s). Dekodieren
lief schon abseits des Main-Actors. `channelCount` stimmt nach jedem Block, `playlistID` wird je Sender gesetzt; scheitert
ein Block, wird die Playlist wieder entfernt. Nachweis (Debug-Build, In-Memory-Store, gleiche Messmethode wie oben):

| Sender | Gesamtdauer vorher | Gesamtdauer jetzt | längste Blockade des Main-Threads jetzt |
|---|---|---|---|
| 1 500 | 2,3 s | 0,19 s | 0,00 s |
| 3 000 | 9,1 s | 0,32 s | 0,00 s |
| 6 000 | 35,4 s | 0,71 s | 0,00 s |
| 17 000 | 285,0 s | **2,26 s** | **0,01 s** |

`testEC20_GrosseSenderlisteBlockiertMainThreadNicht` prüft Blockade < 0,5 s je Größe, lineares Wachstum
(6.000 < 3 × 3.000 + 1 s) sowie `channelCount`, `playlistID` und Beziehung je Größe; die 17.000er-Messung mit
`TEST_RUNNER_B01_QA_EC20_SIZES=17000` (Ausgabe im Build-Bericht). `XCTExpectFailure` entfernt. Nicht umgestellt: M3U-Import
(B02) und Aktualisieren (B03) legen Sender weiter auf dem Main-Actor an (nicht Teil dieses Fehlers, siehe Build-Bericht).

**QA-Durchlauf 2 (2026-09-16):** ✅ behoben — 17.000 Sender 2,13 s (In-Memory) / 2,14 s (Store-Datei), Main-Thread höchstens 0,01 s (`testQA2_BUG12_…`); Aktualisieren (B03) weiter blockierend (H-11). Details im Abschnitt „BUGs aus Durchlauf 1 — erneut geprüft" oben.

## Hinweise (kein Kriterium durchgefallen)

- **H-1 · Rekonstruktion der Zugangsdaten verliert die Benutzerinfo.** `XtreamCredentials(playerAPIURL:)`
  baut den Host aus Schema, Host und Port neu zusammen; `u:pw@` aus der gespeicherten Adresse fällt weg
  (`testEC03_BenutzerinfoImHost`: gespeichert `http://qa-u:qa-pw@127.0.0.1:<port>/…`, rekonstruiert
  `http://127.0.0.1:<port>`). Wirkt sich beim Aktualisieren aus → gehört zu **B03**.
  Fundstelle: `Sources/Services/XtreamCodes.swift:50-61`. (Fund des `code-reviewer`, hier verifiziert.)
  **Entfällt 2026-09-16 durch BUG-01:** Aktualisieren liest die Basisadresse samt Benutzerinfo aus dem Schlüsselbund;
  die Rekonstruktion aus `sourceURL` gibt es nur noch für die einmalige Umstellung, und dort bleibt die Benutzerinfo
  erhalten (`B01ReparaturTests.testBUG01_AktualisierenLiestSchluesselbundUndBehaeltFavoriten`, `…MigrationVorhandenerDatenbankOhneDatenverlust`).
- **H-2 · Zugangsdaten im Systemprotokoll, sobald Private-Data-Logging aktiv ist.** Weil Benutzer und
  Passwort in der URL stehen, tauchen sie in CFNetwork-Fehlermeldungen auf
  (`NSErrorFailingURLStringKey`). Regulär gestartet schwärzt macOS diese Werte (`<private>`, mit Sonde
  belegt); im Xcode-/`xcodebuild`-Lauf nicht — dort standen im Protokoll dieses Testlaufs 9 Zeilen mit
  dem Testpasswort. Wer die App aus Xcode mit echten Zugangsdaten startet, hinterlässt sie im
  persistenten Unified Log. Mit BUG-01/BUG-02 verwandt, aber nicht allein in der App behebbar.
- **H-3 · Gelöschte Zugangsdaten bleiben bis zum Checkpoint in der `-wal`-Datei** (5 Vorkommen nach dem
  Löschen, 0 nach dem Schließen des Containers). Fällt mit BUG-01 weg.
  **Entfällt 2026-09-16 durch BUG-01:** Neue Importe schreiben keine Zugangsdaten in die Datenbank (0 Bytefolgen);
  nach der Umstellung eines Altbestands wird die Datei verdichtet und das Log geleert (17.000 Sender: 0 Vorkommen
  bei offenem Container, `B01LangsamTests.testBUG01_MigrationMit17000Sendern`).
- **H-2 bleibt:** Die Anfragen an `player_api.php` und die Stream-Adressen tragen Benutzer und Passwort weiterhin in der
  URL (Protokoll des Anbieters); CFNetwork-Fehlerzeilen enthalten sie bei aktivem Private-Data-Logging. Nicht in der App
  behebbar (Stand 2026-09-16 unverändert).
- **H-4 · `design.md` korrigieren:** Der HTTP-Cache ist **nicht** im Time-Machine-Backup
  (`tmutil isexcluded … → [Excluded]`); betroffen ist nur die Datenbank.
- **H-5 · Der zweite Fund des `code-reviewer`** (verlorene Fehlermeldung, wenn zwei gleichzeitige
  Importe unterschiedlich scheitern, wegen `.alert(isPresented: .constant(...))`) ließ sich **nicht**
  reproduzieren und ist deshalb nicht als Fehler erfasst.

### Korrekturen an der Spec-Rekonstruktion

| Stelle | Rekonstruktion sagt | Ausgeführt ergibt |
|---|---|---|
| EC-18 | „ein Fehler wird nirgends angezeigt“ (gelesen) | Das geschlossene Sheet erscheint wieder mit dem Alert → BUG-11 |
| EC-08 | Meldung nicht ausgeführt | „Netzwerkfehler: Could not connect to the server.“ |
| EC-20 | „die Oberfläche kann dabei stocken“ (nicht gemessen) | 17 000 Sender = 285 s Blockade → BUG-12 |
| AK-27 | „nicht ausgeführt, die QA weist es am laufenden Build nach“ | Schwärzung hängt am Systemzustand, nicht an der App → nicht prüfbar, Hinweis H-2 |
| `design.md`, Abschnitt *Zugriffsregeln* | Backup umfasst „Datenbank und Cache“ | nur die Datenbank (H-4) |

## Neue Tests

Alle unter `Tests/`, dauerhaft, Testnamen mit AK-/EC-Nummer. Die Tests, die einen Fehler belegen,
tragen `XCTExpectFailure("BUG-NN …")` — 25 erwartete Fehlschläge im Lauf; die Reparatur entfernt die
Markierung.

| Datei | Fälle | Deckt ab |
|---|---|---|
| `Tests/Support/MockXtreamServer.swift` | — | lokaler `player_api.php`-Mock (Loopback, Payload-Mitschrift, Weiterleitung, Stillstand, Tröpfeln) |
| `Tests/Support/B01TestSupport.swift` | — | In-Memory- und Temp-Datei-Container, SQLite-Abfragen, Cache-Aufräumen |
| `Tests/B01/B01ImportTests.swift` | 18 | AK-06 … AK-10, AK-16 … AK-22, EC-11 … EC-16, EC-22 |
| `Tests/B01/B01AdressbildungTests.swift` | 16 | AK-11 … AK-15, EC-01 … EC-10, EC-14 |
| `Tests/B01/B01OberflaecheTests.swift` | 9 | AK-01 … AK-06, AK-16 … AK-22 (Alert), EC-18, EC-19, EC-21 |
| `Tests/B01/B01SicherheitTests.swift` | 10 | AK-23 … AK-28, Angriff 3/7/8, FB-04, FB-05, Cache-Aufräumen |
| `Tests/B01/B01LangsamTests.swift` | 3 | AK-20 (Timeout), AK-23, EC-17, EC-20 — Laufzeit zusammen rund drei Minuten |

Belege im Ordner `qa/`: `AK-06-playlists.png` (Screenshot) und `EC-20-messung.txt` (Messreihe). Screenshot: `features/B01-xtream-login/qa/AK-06-playlists.png` (Playlist-Übersicht nach zwei Importen,
Globus-Symbol und Badge „4 Sender“). Sheets und Alerts liefern über `cacheDisplay` keinen
vollständigen Abzug — deren Nachweis ist die Accessibility-Prüfung im Test, kein Bild.

## Für befunde.md

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| Xtream-Passwort im Klartext in `Playlist.sourceURL` und in jeder `Channel.streamURL`, keine Keychain | hoch | `XtreamCodes.swift:85-95`, `XtreamClient.swift:46`, `PlaylistImporter.swift:76, 160-171` | BUG-01 |
| Eingegebenes `https://` wird ohne Hinweis auf `http://` herabgestuft; Zugangsdaten gehen im Klartext durchs Netz | hoch | `XtreamCodes.swift:69-74`, `Info.plist:39-40` | BUG-02 |
| Import blockiert den Main-Thread, Aufwand wächst quadratisch (17 000 Sender = 285 s) | hoch | `PlaylistImporter.swift:154-175` | BUG-12 |
| Anfragen mit Zugangsdaten und Antwortkörper landen im HTTP-Plattencache und überstehen das Löschen der Playlist | mittel | `XtreamClient.swift:75-78` | BUG-03 |
| Datenbank liegt als generische `default.store` im gemeinsamen Application-Support-Ordner und ist nicht vom Backup ausgeschlossen | mittel | `MikaPlusPlayerApp.swift:7-15`, `MikaPlusPlayer.entitlements:7-8` | BUG-04 |
| Benutzername und Passwort werden nicht prozentkodiert: `+` scheitert an PHP-Panels, `/ # ?` zerlegen die Stream-Adresse | mittel | `XtreamClient.swift:46, 67-68`, `XtreamCodes.swift:91-92` | BUG-05 |
| Dekodierung strenger als zugesagt: `category_id` als Zahl oder ein Eintrag ohne Namen verhindert den gesamten Import | mittel | `XtreamClient.swift:103, 112, 116, 126` | BUG-06 |
| Keine Drosselung wiederholter Fehlanmeldungen (10 von 10 Versuchen in 0,01 s beim Panel) | mittel | `ImportPlaylistView.swift:86, 152-166` | BUG-07 |
| Keine Größen- und Gesamtzeitgrenze für Panel-Antworten (24 MB angenommen, Import 70 s offen gehalten) | mittel | `XtreamClient.swift:77-82`, `PlaylistImporter.swift:154-175` | BUG-08 |
| Nach „Abbrechen“ erscheint das geschlossene Import-Sheet losgelöst wieder, mit Fehler-Alert | mittel | `ImportPlaylistView.swift:81-82, 124, 134-138` | BUG-11 |
| Zweiter Import desselben Zugangs legt eine zweite Playlist an; zwei Klicks vor dem Neuzeichnen starten zwei Importe | niedrig | `PlaylistImporter.swift:61-85`, `ImportPlaylistView.swift:81-86` | BUG-09 |
| Zugangsdaten folgen HTTP-Weiterleitungen zu fremdem Host/Port (PRD sagt: nur an den eingegebenen Host) | niedrig | `XtreamClient.swift:75-78` | BUG-10 |
| Rekonstruktion aus `sourceURL` verliert die Benutzerinfo (`u:pw@…`) — wirkt beim Aktualisieren (B03) | niedrig | `XtreamCodes.swift:50-61` | — (H-1) |
| Zugangsdaten stehen bei aktivem Private-Data-Logging im Klartext im Unified Log (CFNetwork-Fehler) | niedrig | Folge von `XtreamClient.swift:61-72` (Zugangsdaten in der URL) | — (H-2) |

## Nächster Schritt

`/sdd-build B01` mit dem Auftrag, BUG-01 bis BUG-12 zu beheben — zuerst die drei Funde mit dem Grad
*hoch* (BUG-01, BUG-02, BUG-12). Danach erneut `/sdd-qa B01` (Durchlauf 2): Die `XCTExpectFailure`-
Markierungen in den neuen Tests fallen dabei weg, die Tests müssen ohne sie grün werden.
**Die Rückerfassung der übrigen Bestandsfeatures wartet**, bis das erledigt ist — der Code läuft bereits.

Nicht abschließend geprüft und offen für Durchlauf 2: die iOS-Oberfläche (AK-04, und alle
Oberflächen-Kriterien nur auf macOS ausgeführt), der Löschweg im Kontextmenü (AK-29) und das
Systemprotokoll eines regulär gestarteten Release-Builds (AK-27).
