# B09 · Auto-Update — Testbericht

Stand: 2026-09-16 · **Durchlauf 2** (nach der Reparatur) · Geprüft gegen `spec.md` vom 2026-09-15 (Offene Fragen ergänzt am 2026-09-16) und `build-bericht.md` vom 2026-09-16 · Code-Stand `c01f1cf` + Reparatur B01 + Reparatur B09 (nicht committet)

Durchlauf 1 (2026-09-15) steht unverändert weiter unten, samt den Reparaturvermerken aus `sdd-build`.

> **Wie geprüft wurde.** Eigenes DerivedData `build/dd-qa-b09` (macOS) und `build/dd-qa-b09-ios` (iOS-Simulator);
> `scripts/build-macos.sh`, `build/MikaPlusPlayer.app` und `dist/` blieben unberührt. Release-Build des
> Arbeitsstands zweimal gebaut: mit der echten Bundle-ID (nur für `codesign`/`spctl`) und mit
> `PRODUCT_BUNDLE_IDENTIFIER=lu.daumedia.MikaPlusPlayer.qa09b` für alle Starts. Varianten für Gegenproben
> (`qa09c` ohne `SUVerifyUpdateBeforeExtraction`, `qa09d` wie v1.1 signiert, `qa09e` ohne
> `disable-library-validation`, `qa09g` mit `SURequireSignedFeed` und Test-Schlüssel) sind Kopien dieses Builds,
> ad hoc mit denselben Entitlements neu signiert. Alle Starts mit `CFFIXED_USER_HOME` im Scratchpad (Datenbank,
> Caches) – vorher per Sonde belegt, dass `Application Support` dorthin zeigt; Einstellungen landen trotzdem in der
> eigenen `qa09*`-Domäne unter `~/Library/Preferences` und wurden danach gelöscht. Feed, DMGs und Teststreams
> lieferte ein lokaler Mock auf `127.0.0.1:18909` mit Protokoll inkl. User-Agent. Bedienung und Ablesen der
> Oberfläche über die Bedienungshilfen-Schnittstelle (eigene Sonde), Fensterbilder nur einzelner Fenster
> (`screencapture -l`). Release-Skripte nur in Attrappen-Repositories im Scratchpad mit Wegwerf-Schlüsseln
> (CryptoKit). **Nicht verändert:** `appcast.xml`, Schlüsselbund-Einträge des Nutzers, `default.store`
> (Zeitstempel vor/nach allen Läufen `2026-09-15 23:00:34`), Produktcode. **Kein Ton:** Teststreams ohne Tonspur
> (`ffprobe`: nur `h264`-Videospur), keine Wiedergabe mit Audio.

## Fazit (Durchlauf 2)

**Production-ready: nein** — höchster offener Schweregrad **kritisch** (BUG-01, braucht Nutzer/GitHub/Release).

Die Reparatur wirkt dort, wo sie Code ist, und hält Angriffen stand: Das Release läuft mit Hardened Runtime,
`lldb`-Attach und `DYLD_INSERT_LIBRARIES` werden abgewiesen (die wie v1.1 signierte Gegenprobe lässt beides
zu); ein manipuliertes DMG wird **vor** dem Einhängen abgewiesen (belegt über `/Volumes`-Beobachtung gegen eine
Kontrollkopie, die es einhängt); ein gültiges Update installiert weiterhin; die Build-Nummer 3 und die
Gegenprüfungen blocken falschen Schlüssel, gleiche Build-Nummer, unsauberen Git-Stand, fehlendes/verändertes DMG,
fremd signierte Bundles und `get-task-allow`; der von `release.sh` signierte Feed wird von Sparkle mit
`SURequireSignedFeed` angenommen. Eine v1.1-Datenbank öffnet im Release-Build, eine kaputte wird beiseitegelegt
(Hinweis auf macOS und iOS gesehen, zweiter Start ohne Hinweis). VLCKit (`.ts`) und AVKit (`.m3u8`) spielen
unter Hardened Runtime stumme lokale Streams ab.

Nicht behoben ist **BUG-18**: In der echten Menüleiste bleibt „Nach Updates suchen …" während der Prüfung aktiv
(zwei Läufe, auch bei geöffnetem Menü). Neu: **BUG-19** (Gegenprüfung blockiert ab dem dritten weiteren Release
jedes Release, weil `generate_appcast` alte Einträge kürzt), **BUG-20** (Zugangsdaten beiseitegelegter Playlists
bleiben ohne Löschweg im Schlüsselbund), **BUG-23** (fremde Download-Adresse in einem bestehenden Feed-Eintrag
wird nicht erkannt und beim nächsten Release mitsigniert), dazu **BUG-21, BUG-22, BUG-24** (niedrig).
Offen und korrekt begründet bleiben BUG-01, 03, 05, 06, 07, 09 sowie der Feed-Teil von BUG-08; BUG-12/16 liegen
bei B10. Zum Nutzerweg für BUG-01 gibt es eine Ergänzung (GitHub-Richtlinie gegen Namensreservierung, siehe dort).

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 30 von 30 (alle in Durchlauf 2 ausgeführt) |
| davon bestanden | 24 (davon 6, deren Ist sich durch die Reparatur gewollt geändert hat: AK-10, 15, 17, 20, 21, 22) |
| davon ⚠-Kriterium reproduziert, Befund offen | 5 (AK-14 → BUG-03, AK-16 → BUG-09, AK-27 → BUG-01, AK-28 → BUG-06, AK-30 → BUG-05) |
| davon durchgefallen | 1 (AK-19 → BUG-24) |
| **nicht prüfbar** | 0 |
| Edge Cases belegt | 8 von 13 (EC-01, 02, 05, 07, 09, 10, 11, 12); nicht prüfbar: EC-03, 04, 06, 08, 13 |
| BUGs aus Durchlauf 1 | 8 behoben ✅ (02, 04, 10, 11, 13, 14, 15, 17) · 1 teilweise (08) · 1 nicht behoben ❌ (18) · 6 offen mit bestätigter Begründung (01, 03, 05, 06, 07, 09) · 2 an B10 (12, 16) |
| Neue BUGs | 6 (BUG-19 bis BUG-24: 3 × mittel, 3 × niedrig) |
| Tests neu geschrieben | 7 (`Tests/B09/B09QA2Tests.swift`) |
| Tests grün | 7 von 7 (5 davon `XCTExpectFailure` für offene Befunde) · Gesamtlauf 147 Tests, 0 Fehlschläge, 2 übersprungen (B01) |

## Durchlauf 2 · BUGs aus Durchlauf 1 erneut ausgeführt

| BUG | Grad | Ergebnis | Nachweis (ursprüngliche Reproduktion, erneut ausgeführt) |
|---|---|---|---|
| BUG-01 | kritisch | **offen** – Begründung stimmt, Nutzerweg mit Ergänzung | `gh api users/Mukaarts` → 404 (2026-09-16); `curl -sL` alte Raw-Adresse → 200, 0 Weiterleitungen, SHA-256 `fb2cc3fd…` = Repo-`appcast.xml`; `github.com/Mukaarts/MikaPlusPlayer` → 301 auf daumedia. In `SUFeedURL` der Kopie (Nutzereinstellung) eine fremde Adresse gesetzt → die App ruft sie ab und verarbeitet sie (Mock-Protokoll, AK-12) – der Angriff bleibt möglich, im Code nicht lösbar. Details unten |
| BUG-02 | kritisch | **behoben ✅** | Release-Bundle: `flags=0x10002(adhoc,runtime)` an App, Sparkle, VLCKit, Autoupdate, Updater.app, Downloader.xpc, Installer.xpc; Entitlements nur `app-sandbox=false`, `disable-library-validation=true`; `codesign --verify --deep --strict` gültig. **Angriff gegen die eigene Kopie** (`qa09b`, Nicht-Root, EUID 501): `lldb process attach` → „attach failed (Not allowed to attach to process.)“; `DYLD_INSERT_LIBRARIES` mit eigener Bibliothek (Konstruktor schreibt Markierungsdatei) → nicht geladen. **Gegenprobe** `qa09d` (ad hoc ohne Runtime, `get-task-allow=true` wie v1.1): Attach gelingt („Process 34082 stopped“), Bibliothek geladen. Wiedergabe unter Runtime siehe OF-09 |
| BUG-03 | hoch | **offen** – Begründung stimmt | `spctl -a -vv` Release-Bundle → rejected; `codesign -dv` → `Signature=adhoc`, `TeamIdentifier=not set`; Gegenprüfung meldet `[ offen] ad-hoc signiert`, `[ offen] DMG ohne verwertbare Signatur`. Braucht Apple-Team |
| BUG-04 | hoch | **behoben ✅** (Build-Nummer) · Anzeigeversion offen (OF-06) | Release-Bundle `CFBundleVersion=3`; Attrappe mit Build 2 und 1: `[BEFUND] CURRENT_PROJECT_VERSION=2 ist nicht größer als …` bzw. `=1`, Abbruch **vor** dem Build, `appcast.xml` byte-gleich; Sparkle vergleicht nur die Build-Nummer (gleiche Nummer → kein Angebot, AK-07; höhere → Angebot, AK-06). Lücke: leere Anzeigeversion geht durch → BUG-22 |
| BUG-05 | hoch | **offen** – Begründung stimmt, jetzt ausgeführt belegt | DR des Release `cdhash H"069cec2b…" or cdhash H"5dd60cc7…"`. Beim Update-Versuch (BUG-08, Variante A) protokolliert Sparkle: „Failed to validate update archive with Developer ID code signing fallback … The team identifier could not be retrieved from the original app“ – der Rückfallweg für einen Schlüsselwechsel existiert bei ad-hoc-Signatur nicht. Die im Build-Bericht beschriebenen Schritte decken sich mit `SUUpdateValidator.m` (Rückfall verlangt ein **Developer-ID-signiertes Archiv** derselben Team-ID und `SUVerifyUpdateBeforeExtraction`) |
| BUG-06 | hoch | **offen** – Begründung stimmt | `SUPublicEDKey eauiHgP4PM9y…` weiterhin identisch in Mika+FileScope, Flow, Grid, ScreenSnap, MikaPlusMediaFetch, MikaPlusPlayer (`/Applications`, nur `Info.plist` gelesen) |
| BUG-07 | hoch | **offen** – Begründung stimmt | `gh api repos/daumedia/MikaPlusPlayer/branches/main --jq .protected` → `false`; `…/rulesets --jq length` → `0`; Raw-Feed `cache-control: max-age=300`. Verschärft durch BUG-23 |
| BUG-08 | hoch | **teilweise ✅** – Prüfung vor dem Einhängen behoben; Feed-Pflicht offen (Begründung stimmt) | **Variante A** (Release `qa09b`, `SUVerifyUpdateBeforeExtraction=true`): Update mit manipuliertem DMG (andere App, v1.1-Signatur) angeboten, „Install Update“ gedrückt; `/Volumes` alle 2 ms beobachtet (8 967 Abfragen): **kein** Einhängen; Sparkle: „(Ed)DSA signature validation before unarchiving failed … Failed to unarchive file“; Dialog „The update is improperly signed …“; CDHash der App vorher = nachher (`BUG-08-A-vor-dem-mount-abgewiesen.png`). **Variante B** (Kontrolle ohne den Schlüssel): `/Volumes/D70EABE7-…` 21:56:56.182 eingehängt, 21:56:56.580 wieder weg, dann abgewiesen; App unverändert (`BUG-08-B-kontrolle-ohne-key-abgewiesen.png`). Gültiges Update wird weiter installiert (AK-09). **Feed-Pflicht:** Kopie `qa09g` mit `SURequireSignedFeed`: von `release.sh` signierter Feed → angenommen (Update angeboten, `BUG-08-feedpflicht-signierter-feed-angenommen.png`); nach dem Signieren veränderter Feed und die heutige unsignierte `appcast.xml` → „The update feed is improperly signed …“ (`BUG-08-feedpflicht-manipulierter-feed-abgewiesen.png`). Die Begründung im Build-Bericht (heute gesetzt, würde der veröffentlichte Feed jede Installation abweisen) ist damit ausgeführt bestätigt |
| BUG-09 | mittel | **offen** – Begründung stimmt | Kopie `qa09e` (Runtime, ohne `disable-library-validation`): Start bricht ab, Exit 134, `dyld: Library not loaded: …/VLCKit.framework/Versions/A/VLCKit … code signature … not valid for use in process`; VLCKit und Sparkle tragen `TeamIdentifier=not set`. Mit dem Entitlement bleibt `DYLD_INSERT_LIBRARIES` trotzdem blockiert (BUG-02-Angriff) |
| BUG-10 | hoch | **behoben ✅** | Attrappe mit echtem `release.sh`, echtem Alt-`dist/appcast.xml` und Test-Schlüssel: Titel „Mika+Player“, Einträge 2 und 3, keine Mukaarts-URL, Eintrag 2 unverändert, `dist/appcast.xml` nicht gelesen; Kette über drei Releases auf dem jeweils signierten Feed: je ein Signaturblock, Feed-Signatur gültig. Lücke ab dem dritten Folge-Release → BUG-19 |
| BUG-11 | mittel | **behoben ✅** (mit neuen Lücken BUG-19, 22, 23, 24) | Angriffsmatrix in Attrappen (je `appcast.xml` vorher/nachher per SHA-256): falscher Schlüssel → Exit 1, unverändert; gleiche/kleinere Build-Nummer → Exit 1 vor dem Build; unversionierte Datei bzw. geänderte `appcast.xml` im Arbeitsverzeichnis → `[BEFUND] Arbeitsverzeichnis nicht sauber`; Tag vorhanden → Befund; kein DMG → `[BEFUND] kein DMG`; Bundle mit fremdem `SUPublicEDKey` → Befund; Bundle mit `get-task-allow`/ohne Runtime → zwei Befunde; veraltetes Bundle (Build 2) → Befund; DMG nach Signatur um 1 Byte verändert → `[BEFUND] EdDSA-Signatur des DMG passt NICHT`; Feed nach Signatur verändert → `[BEFUND] Feed-Signatur ungültig`. Durchgelassen: leere Anzeigeversion (BUG-22), fremde URL im Feed (BUG-23), zusätzliche Datei im DMG (Hinweis H-3) |
| BUG-12 | mittel | **offen, an B10** | `web/app/privacy/page.tsx:57-59` unverändert (nennt IP, nicht User-Agent `Mika+Player/1.1 Sparkle/2.9.3` – jetzt am Mock mitgeschnitten, AK-23) |
| BUG-13 | hoch | **behoben ✅** (neuer Befund BUG-20) | Tests `B09PersistenzTests` (7) grün. **Release-Build, echte Starts:** v1.1-Vorlage als Datenbank → Playlist „B09 v1.1 Testliste“ mit 3 Sendern sichtbar, nichts beiseitegelegt (`BUG-13-macOS-v11-datenbank-offen.png`); Vorlage hat dieselben Entitäts-Hashes (`Channel 44b6f62e…`, `Playlist e99e00f3…`, `1.0.0`) wie eine aus `git show v1.1:Sources/Models` frisch erzeugte Datenbank. Kaputte Datei (Kopf überschrieben) → Hinweis „Datenbank neu angelegt“ mit Ordner und „Im Finder zeigen“/„OK“ (`qa/durchlauf-2/BUG-13-macOS-hinweis-erster-start.png`), Datei unter `Beiseitegelegt/2026-09-16_22-00-28/` byte-gleich (SHA-256 `31b031a8…` vorher/nachher); **zweiter Start**: kein Hinweis, leere Datenbank, weiter genau ein beiseitegelegter Ordner (`BUG-13-macOS-zweiter-start-ohne-hinweis.png`). **iOS-Simulator:** gleicher Hinweis ohne Finder-Knopf mit dem Container-Pfad (`BUG-13-iOS-hinweis.png`), Datei beiseitegelegt. Test `testEC07_BUG13_ZweiterStartOhneHinweisUndNichtsWirdUeberschrieben`: dritter Fehlschlag mit gleichem Zeitstempel → Ordner `…-2`, beide Dateien unverändert. **Schlüsselbund:** Einträge bleiben verwaist → BUG-20 |
| BUG-14 | mittel | **behoben ✅** | `project.yml` `exactVersion: "2.9.3"`; `Package.resolved` nach `xcodegen generate` → `sparkle` `2.9.3`; `Sparkle.framework` im Release `CFBundleShortVersionString=2.9.3`; `testFB12_sparklePinnedExactly` grün |
| BUG-15 | mittel | **behoben ✅** (Dokumentation; Ausführung nicht möglich) | README *Öffentliche Distribution* gelesen: App mit Developer ID bauen → notarisieren/heften → DMG aus gehefteter App → DMG signieren/notarisieren/heften → `spctl` → erst dann Feed; kein `codesign --deep`; `notarytool` über Keychain-Profil. Nicht ausgeführt (kein Apple-Team) |
| BUG-16 | niedrig | **offen, an B10** | `web/app/changelog/page.tsx:21` („checks this list for itself“) und `web/content/features.ts:42` („Updates that install themselves“) unverändert |
| BUG-17 | mittel | **behoben ✅** | `Tests/B09/` mit 5 Dateien, 35 Tests; Lauf `-only-testing` B09: 35 Tests, 0 Fehlschläge; Gesamtlauf 147 Tests grün |
| BUG-18 | mittel | **nicht behoben ❌** | Unit-Tests `B09UpdaterTests` grün, aber **an der echten Menüleiste** (Release `qa09b`, Feed mit 5 bzw. 8 s Verzögerung, Zustand über Bedienungshilfen gelesen): vor dem Klick `enabled=true`; +1 s, +2 s, +3 s bei sichtbarem „Checking for updates…“ weiter `enabled=true`; auch **bei geöffnetem App-Menü** `enabled=true`, obwohl Sparkle `canCheckForUpdates` beim Start der Prüfung auf `NO` setzt (`SPUUpdater.m:723`). Erst mit dem Ergebnisfenster wechselt der Eintrag, in zwei von drei Läufen, auf `false`. Details BUG-18 unten |

### BUG-01 · Nachprüfung des Nutzerwegs (nur gelesen, nichts bei GitHub angelegt)

- **Stimmt:** GitHub-Doku *Changing your GitHub username*: „After changing your username, your old username becomes
  available for anyone else to claim.“ – „If the new owner of your old username creates a repository with the same
  name as your repository, that will override the redirect entry and your redirect will stop working.“ Ein selbst
  registriertes `Mukaarts` **ohne** Repository `MikaPlusPlayer` lässt die Weiterleitung laut Doku bestehen; die
  Anleitung im Build-Bericht („kein Repository `MikaPlusPlayer` anlegen“) ist richtig.
- **Ergänzung 1 – Richtlinie gegen Namensreservierung:** *GitHub Username Policy*: „account names may not be reserved
  or inactively held for future use.“ – „Accounts violating this name squatting policy may be removed or renamed
  without notice.“ Ein nur zum Blockieren angelegtes, leeres Konto kann GitHub also ohne Vorwarnung wieder
  freigeben. Das Konto sollte tatsächlich genutzt werden (z. B. Profil mit Umzugshinweis auf `daumedia`) – und der
  eigentliche Ausweg bleibt das Übergangs-Release, das die v1.1-Installationen auf den daumedia-Feed bringt, **bald**.
- **Ergänzung 2 – Raw-Adressen:** Die Doku nennt Web-Links und Git-Remotes, nicht `raw.githubusercontent.com`. Beobachtet
  (heute): Die alte Raw-Adresse liefert 200 **ohne** sichtbare Weiterleitung und den aktuellen Inhalt. Dass das nach
  einer Registrierung von `Mukaarts` so bleibt, ist nicht dokumentiert und nicht prüfbar, ohne den Namen zu registrieren.
- **Ergänzung 3 – Namespace-Retirement:** Hatte das Repository in der Woche vor der Umbenennung mehr als 100 Klone,
  ist `Mukaarts/MikaPlusPlayer` dauerhaft gesperrt („The repository … has been retired and cannot be reused“) – das
  würde den Angriffsweg schließen. Von außen nicht prüfbar (Klonzahlen nur 14 Tage rückwirkend, nur für den Inhaber).
- Mika+FileScope hängt an demselben Namensraum (Build-Bericht) – der Nutzerweg gilt für beide Apps.

## Durchlauf 2 · Akzeptanzkriterien

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ✅ bestanden | Release `qa09b` über Bedienungshilfen: App-Menü `[0] About Mika+Player`, `[1] Nach Updates suchen … enabled=true`, danach Services/Hide/Quit (englisch). Test `B09QA2Tests.testAK01_MenueeintragDirektUnterAboutUndAktiv` (Test-Host): Index 1, aktiv |
| AK-02 | ✅ bestanden (Spec-Wortlaut ungenau, H-1) | Menü gedrückt → Fenster „Software Update“ mit „Checking for updates…“ und „Cancel“ → „You’re up to date!“ + „Mika+Player 1.1 (2) is currently the newest version available. (You are currently running version 1.1 (3).)“, Schaltfläche „OK“ (`qa/durchlauf-2/AK-02-up-to-date.png`); `SULastCheckTime` auf die Abrufzeit gesetzt. Mit gleicher Build-Nummer im Feed (AK-07) exakt „Mika+Player 1.1 is currently the newest version available.“ „Version History“ erscheint in keinem Lauf – laut `SPUStandardUserDriver.m:666-695` nur, wenn der Feed-Eintrag Release-Notes-Links hat |
| AK-03 | ✅ bestanden | Erster Start ohne `SULastCheckTime`/`SUHasLaunchedBefore` → 2 s nach Start `GET /feeds/uptodate.xml`, kein Dialog; danach `SUHasLaunchedBefore=1`, `SULastCheckTime` = Abrufzeit |
| AK-04 | ✅ bestanden | `SULastCheckTime` = jetzt − 1 h → 15 s nach Start **0** Anfragen, Wert unverändert; = jetzt − 25 h → sofort **1** Anfrage, Wert aktualisiert |
| AK-05 | ✅ bestanden | Release-Bundle `SUFeedURL=https://raw.githubusercontent.com/daumedia/…`; `curl -sI` beide Adressen HTTP 200, `max-age=300`; Inhalt der alten Adresse SHA-256 `fb2cc3fd…` = Repo |
| AK-06 | ✅ bestanden | Feed mit `sparkle:version` 99 → „A new version of Mika+Player is available!“, „Mika+Player 9.9 is now available—you have 1.1. …“, Kontrollkästchen „Automatically download and install updates in the future“, „Remind Me Later“, „Install Update“, „Skip This Version“, keine Versionshinweise (`AK-06-EC-10-update-angebot-nach-skip.png`). Mit `SUEnableAutomaticChecks=NO` fehlen Kontrollkästchen und „Remind Me Later“ (H-2) |
| AK-07 | ✅ bestanden | Feed-Eintrag `shortVersionString` 9.9, `version` 3 = Build der App → „You’re up to date!“, kein Angebot |
| AK-08 | ✅ bestanden | Manuell, Feed 404 → „Update Error!“ / „An error occurred in retrieving update information. Please try again later.“ / „Cancel Update“. Automatisch beim Start, Feed 404 → Anfrage im Mock, **kein** Fenster außer dem Hauptfenster |
| AK-09 | ✅ bestanden | Kopie `qa09g` (Test-Schlüssel, `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`), signierter Feed mit gültig signiertem DMG (Minimal-App Build 99, im DMG mit `com.apple.quarantine`): „Install Update“ → Sparkle „OK: EdDSA signature is correct for update“ (22:12:32.065) → **danach** eingehängt (22:12:32.202–.413) → „Ready to Install“ / „Install and Relaunch“ (`AK-09-update-bereit-zur-installation.png`) → App beendet, Bundle ersetzt (Build 99, 9.9-qa), **Quarantäne-Attribut entfernt**. Neustart startete die Minimal-App (`/usr/bin/true`, sofort beendet) |
| AK-10 | ✅ bestanden (Ist gewollt geändert) | Manipuliertes DMG → „The update is improperly signed and could not be validated. Please try again later or contact the app developer.“ (`AK-10-manipuliertes-dmg-abgewiesen.png`), App unverändert. Abweichend von der Spec jetzt **vor** dem Entpacken (BUG-08) |
| AK-11 | ✅ bestanden | `xcrun swift scripts/b09_ed25519.swift archiv <SUPublicEDKey> dist/MikaPlusPlayer-v1.1.dmg <Signatur aus appcast.xml>` → „gültig … (36455860 Byte)“; SHA-256 `8da0620e…`; Länge = Feed |
| AK-12 | ✅ bestanden → Befund BUG-08 (Feed-Teil) | `qa09b` verarbeitete unsignierte lokale Feeds (uptodate/newer/samebuild/minos) ohne Prüfung |
| AK-13 | ✅ bestanden | Release: `Signature=adhoc`, `TeamIdentifier=not set`, `valid on disk`, `satisfies its Designated Requirement`, `app-sandbox=false` |
| AK-14 ⚠ | reproduziert → BUG-03 offen | `spctl -a -vv` Release-Bundle → rejected |
| AK-15 ⚠ | ✅ bestanden (Befund behoben, Ist besteht nicht mehr) | Kein `get-task-allow`, `flags=0x10002(adhoc,runtime)`; Attach/Injektion abgewiesen (BUG-02) |
| AK-16 ⚠ | reproduziert → BUG-09 offen | `disable-library-validation=true` – jetzt bei **aktiver** Runtime und nachweislich nötig |
| AK-17 | ✅ bestanden (Ablauf gewollt geändert, Spec veraltet) | `release.sh` in Attrappe (Build/DMG als Stubs, echtes `generate_appcast`/`sign_update` 2.9.3): vor-build-Prüfung → Build → DMG → nach-build-Prüfung → Feed im temporären Ordner aus versionierter `appcast.xml` → `sign_update` → feed-Prüfung → Kopie nach `appcast.xml` → Hinweise mit Reihenfolge. `dist/` nur noch für das DMG |
| AK-18 | ✅ bestanden | `make-dmg.sh` (unverändert seit `c01f1cf`) mit `PATH` ohne `create-dmg`: DMG mit Volume „Mika+Player“, `MikaPlusPlayer.app`, Symlink `Applications`, `Format: UDZO` |
| AK-19 | ❌ durchgefallen → BUG-24 | `make-dmg.sh` ohne App → „FEHLER: … fehlt. Erst scripts/build-macos.sh ausführen.“, Exit 1 ✅. **Aber** `release.sh` ohne `generate_appcast` → Exit 1 **ohne** „FEHLER: generate_appcast nicht gefunden.“ (`bash -x`: Abbruch in der Zuweisung `GEN=…`) |
| AK-20 ⚠ | ✅ bestanden (Befund behoben) | siehe BUG-10 |
| AK-21 ⚠ | ✅ bestanden (Befund behoben) | siehe BUG-04 |
| AK-22 | ✅ bestanden (Ist gewollt geändert) | Sparkle exakt 2.9.3 (BUG-14) |
| AK-23 | ✅ bestanden | Mock-Protokoll jeder Feed- und DMG-Anfrage: `UA='Mika+Player/1.1 Sparkle/2.9.3'`, keine Query-Parameter (kein Systemprofil), keine Nutzer- oder Playlistdaten |
| AK-24 | ✅ bestanden | Domäne `qa09b` nach dem Lauf: `SUHasLaunchedBefore`, `SULastCheckTime`, `SUUpdateGroupIdentifier` (+ QA-Override `SUFeedURL`, Fensterposition); nach „Skip This Version“ `SUSkippedVersion=4` |
| AK-25 | ✅ bestanden | Offene Sockets der Kopie während einer Prüfung, 16 Stichproben in 8 s (`lsof -i -p`): nur `127.0.0.1:…->127.0.0.1:18909` (konfigurierter Feed); DMG-Abruf nur an den Enclosure-Host (Mock-Protokoll). Datenschutzseite weiter unvollständig → BUG-12 |
| AK-26 | ✅ bestanden → Befund BUG-07 | `protected: false`, Rulesets `0` |
| AK-27 ⚠ | reproduziert → BUG-01 offen | `users/Mukaarts` → 404 |
| AK-28 ⚠ | reproduziert → BUG-06 offen | 6 Apps mit demselben Schlüssel |
| AK-29 | ✅ bestanden | `git log -p --all -S 'BEGIN PRIVATE KEY'` und `-- '*.pem' '*.key' '*ed25519*'` → leer; `scripts/b09_ed25519.swift` nutzt nur den öffentlichen Schlüssel; Test-Schlüssel entstehen zur Laufzeit; Vorlage `v1.1-schema.store` enthält nur „B09 v1.1 Testliste“ und `127.0.0.1`-Adressen (`strings`) |
| AK-30 ⚠ | reproduziert → BUG-05 offen | DR = CDHash; Sparkle-Protokoll „team identifier could not be retrieved from the original app“ |

## Durchlauf 2 · Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ❌ bestätigt → BUG-21 | `B09QA2Tests.testEC01_BUG21_…`: Test-Host `Bundle.main.bundleIdentifier = lu.daumedia.MikaPlusPlayer`, `Sparkle` geladen, Updater gestartet (`canCheckForUpdates` wahr), `SUFeedURL` = echter Feed. `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` (nur Zeitstempel und `SULastCheckTime` gelesen): mtime 15:21:35 → 21:47:16 (B09-Lauf) → 22:08:46 (Gesamtlauf); `SULastCheckTime` blieb `2026-09-15 21:10:19Z`, weil < 24 h – ab 24 h prüft Sparkle beim Start sofort (AK-04, am Release belegt) und schreibt den Zeitpunkt in diese Datei (so am 2026-09-15 von `sdd-erfassen` beobachtet). Bewusst **nicht** nach Ablauf der 24 h erneut ausgelöst, um den Prüfzeitpunkt der installierten App nicht zu verschieben |
| EC-02 | ✅ belegt | Gleiche Build-Nummer: Gegenprüfung bricht vor dem Build ab (BUG-04); für Installationen kein Angebot (AK-07) |
| EC-03 | ⚠️ nicht prüfbar | bräuchte `build-macos.sh` (überschreibt `build/MikaPlusPlayer.app`) |
| EC-04 | ⚠️ nicht prüfbar | wie EC-03 |
| EC-05 | ✅ belegt (Befund behoben) | Feed entsteht aus der versionierten `appcast.xml` im temporären Ordner, unabhängig von `dist/` (BUG-10) |
| EC-06 | ⚠️ nicht prüfbar | Veröffentlichen erfolgt von Hand bei GitHub; `release.sh` nennt die Reihenfolge, erzwingt sie nicht |
| EC-07 | ✅ belegt (Befund behoben) → neuer Befund BUG-20 | siehe BUG-13 |
| EC-08 | ⚠️ nicht prüfbar | Update während Wiedergabe nicht gefahren |
| EC-09 | ✅ belegt (Wortlaut ergänzt, H-2) | `minimumSystemVersion 99.0`, manuell: kein Angebot, aber Dialog „Your macOS version is too old“ / „Mika+Player 9.9 is available but your macOS version is too old to install it. At least macOS 99.0 is required.“ |
| EC-10 | ✅ belegt | „Skip This Version“ → `SUSkippedVersion=4`; eine manuelle Prüfung bietet 1.3 (Build 4) erneut an. Verhalten der automatischen Prüfung bei übersprungener Version nicht separat beobachtet |
| EC-11 | ❌ bestätigt → BUG-18 nicht behoben | siehe BUG-18 |
| EC-12 | ✅ belegt | `SUEnableAutomaticChecks = NO` in der Nutzerdomäne → 10 s nach Start 0 Anfragen |
| EC-13 | ⚠️ nicht prüfbar | Start aus dem eingehängten DMG nicht gefahren |

**OF-09 (Wiedergabe unter Hardened Runtime), ausgeführt:** Release `qa09b` mit eigener Datenbank (zwei Sender auf
`127.0.0.1`), Sender über Bedienungshilfen geöffnet. `.ts` → Anfrage mit `UA='VLC/3.0.21 LibVLC/3.0.21'`, Bild im
Fenster, zwei Aufnahmen 3 s auseinander unterschiedlich (`OF-09-release-ts-vlc-1/2.png`). `.m3u8` → `AppleCoreMedia`
lädt Playlist und 23 Segmente, Bild, Aufnahmen unterschiedlich (`OF-09-release-hls-avkit-1/2.png`). Beide Medien ohne
Tonspur. Nicht geprüft: HEVC, AC-3, verschlüsseltes HLS, echte Anbieter-Streams.

## Durchlauf 2 · Sicherheitsprüfung

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| Fremder Zugriff auf die Update-Kette (IDOR-Analog) | **BUG-01, BUG-07, BUG-23** | `users/Mukaarts` 404; `main` ungeschützt; fremde Download-Adresse in bestehendem Feed-Eintrag passiert alle Prüfungen und wird mitsigniert |
| Zugriffsregeln „serverseitig“ (Integrität) | **BUG-02 behoben ✅**, BUG-08 teilweise | `lldb`-Attach und `DYLD_INSERT_LIBRARIES` gegen das Release abgewiesen (Gegenprobe wie v1.1: beides möglich); manipuliertes DMG vor dem Einhängen abgewiesen; signierter Feed mit `SURequireSignedFeed` angenommen, veränderter/unsignierter abgewiesen |
| Rate Limit | n/a (bestanden) | kein eigener Endpunkt; automatischer Abruf höchstens alle 24 h (AK-04) |
| PII in Logs | bestanden | `log show … subsystem == "lu.daumedia.MikaPlusPlayer"`: Release zeigt „Datenbank ließ sich nicht öffnen: `<private>`“; Sparkle protokolliert Pfade und URLs, keine Zugangsdaten. Nebenbefund außerhalb B09: siehe H-7 |
| PII an externe Dienste | bestanden, BUG-12 offen (B10) | tatsächlicher Payload am Mock: `GET /feeds/…` mit `User-Agent: Mika+Player/1.1 Sparkle/2.9.3`, keine Parameter; Sockets nur zum konfigurierten Host |
| Geheimnisse | bestanden, BUG-05/06 offen | keine Privatschlüssel in Historie/Arbeitsbaum; Test-Schlüssel nur zur Laufzeit bzw. im Scratchpad |
| Eingaben (Feed, DMG, Release-Parameter) | **BUG-19, 22, 23, 24**; sonst bestanden | manipuliertes DMG, Feed 404, `minimumSystemVersion` 99, gleiche Build-Nummer, veränderter/unsignierter Feed sauber abgewiesen; Release-Parameter siehe BUG-11-Matrix |
| Löschen | **BUG-20** | beiseitegelegte Datenbank wird nie gelöscht (gewollt, belegt); ihre Xtream-Zugangsdaten bleiben ohne Löschweg im Schlüsselbund |

## Durchlauf 2 · Fehler (BUG-18 erneut, BUG-19 bis BUG-24 neu)

### BUG-18 · Menü „Nach Updates suchen …“ zeigt während der Prüfung weiter „aktiv“ — mittel (aus Durchlauf 1, nicht behoben)
**Betrifft:** EC-11
**Reproduktion:**
1. Release-Build (hier `qa09b`) starten, Feed mit 8 s Verzögerung ausliefern (`SUFeedURL`).
2. „Nach Updates suchen …“ wählen; Fenster „Checking for updates…“ erscheint.
3. Nach 1, 2 und 3 s `AXEnabled` des Menüeintrags lesen; dann das App-Menü öffnen und erneut lesen.
**Erwartet:** `enabled=false` während der Prüfung, danach wieder `true`.
**Tatsächlich:** durchgehend `enabled=true`, auch im geöffneten Menü (zwei Läufe). Erst wenn das Ergebnisfenster erscheint, wechselt der Wert – in zwei von drei Läufen auf `false`, im dritten blieb er `true`; nach „OK“ wieder `true`. Die Unit-Tests belegen nur, dass der Wrapper `SparkleUpdater` Änderungen meldet – nicht, dass die `Commands` im `App.body` neu ausgewertet werden.
**Ort:** `Sources/App/MikaPlusPlayerApp.swift:39-45` (`.disabled(!updater.canCheckForUpdates)` im `CommandGroup` des `App.body`).
**Vorschlag:** den Menüeintrag als eigene `View` mit dem beobachteten Objekt bauen (Muster aus Sparkles SwiftUI-Doku: `CheckForUpdatesView` mit eigenem Modell im `CommandGroup`) und das Verhalten an der Menüleiste nachprüfen.

### BUG-19 · Feed-Gegenprüfung blockiert jedes Release, sobald `generate_appcast` alte Einträge kürzt — mittel
**Betrifft:** AK-17, BUG-11
**Reproduktion:**
1. Attrappe mit echtem `release.sh`, `LSMinimumSystemVersion 14.0` im Bundle, versionierter `appcast.xml` (nur v1.1, Build 2).
2. Releases nacheinander: 1.2/3 → Exit 0; 1.3/4 → Exit 0; 1.4/5 → **Exit 1**.
3. Ausgabe: `generate_appcast`: „Wrote 1 new update, updated 0 existing updates, and removed 1 old update“; Gegenprüfung: `[BEFUND] Einträge weichen ab: 3 4 5 statt 2 3 4 5 (Altstand zurück oder Eintrag verloren?)`, `[BEFUND] bestehender Eintrag 2 verändert`.
**Erwartet:** Ein korrekt signierter Feed mit dem neuen Build wird akzeptiert.
**Tatsächlich:** `generate_appcast` behält standardmäßig 3 Versionen je Zweig (`--maximum-versions`, `main.swift:77`, `Appcast.swift:144-145`); `b09_release_check.sh feed` verlangt alle bisherigen Einträge. Ab dem dritten Release nach dem nächsten (Build 5) bricht jedes Release ab, die Meldung legt einen Altstand nahe. Test `B09QA2Tests.testBUG19_…` (`XCTExpectFailure`).
**Ort:** `scripts/b09_release_check.sh:173-180`; `scripts/release.sh:57-59` (ohne `--maximum-versions`).
**Vorschlag:** `--maximum-versions 0` übergeben oder die Prüfung auf „neuer Eintrag vorhanden, verbleibende Einträge unverändert, entfernte nur die ältesten“ umstellen.

### BUG-20 · Zugangsdaten beiseitegelegter Playlists bleiben ohne Löschweg im Schlüsselbund — mittel
**Betrifft:** EC-07, BUG-13 · Katalog *Löschen*
**Reproduktion:**
1. Datenbank mit Xtream-Playlist (ID X) anlegen, Zugangsdaten `qa-user`/`qa-pass-123` unter X im Schlüsselbund (eigener Testdienst).
2. Datenbank unlesbar machen, `AppPersistence.openStore` → `.recovered`, neue Datenbank leer.
3. Dieselben Zugangsdaten neu importieren (neue ID).
**Erwartet:** Zugangsdaten ohne zugehörige Playlist sind löschbar oder werden mit der beiseitegelegten Datenbank verbunden gemeldet.
**Tatsächlich:** Eintrag X bleibt lesbar, danach zwei Einträge; keine Playlist in der App verweist auf X, „Löschen“ ist dafür nicht erreichbar; der Hinweis erwähnt den Schlüsselbund nicht. Test `B09QA2Tests.testEC07_BUG20_…` (`XCTExpectFailure`).
**Ort:** `Sources/Services/AppPersistence.swift:87-109` (Wiederherstellung ohne Blick auf `XtreamCredentialStore`), `Sources/Views/StoreRecoveryAlert.swift`.
**Vorschlag:** Beim Beiseitelegen die Playlist-IDs der alten Datei lesen und die Einträge entweder beim späteren Aufräumen mitlöschen oder im Hinweis/einer Einstellung anbieten (Zusammenhang OF-08) – nicht stillschweigend löschen, solange die Datei wiederherstellbar sein soll.

### BUG-21 · Test-Host startet Sparkle in der Einstellungsdomäne der installierten App — niedrig
**Betrifft:** EC-01, OF-10
**Reproduktion:** `xcodebuild test … -scheme MikaPlusPlayer-macOS`; Test `B09QA2Tests.testEC01_BUG21_…`; Zeitstempel von `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` vor/nach dem Lauf.
**Erwartet:** Tests verändern weder Update-Zeitplan noch Einstellungen der installierten App und rufen keinen echten Feed ab.
**Tatsächlich:** Test-Host mit Bundle-ID `lu.daumedia.MikaPlusPlayer` startet den Updater gegen den echten Feed; die Einstellungsdatei der installierten App wird bei jedem Lauf geschrieben (mtime 21:47:16, 22:08:46); liegt die letzte Prüfung ≥ 24 h zurück, fragt der Test-Host GitHub ab und verschiebt `SULastCheckTime` der installierten App.
**Ort:** `Sources/App/MikaPlusPlayerApp.swift:23` (`SparkleUpdater()` unbedingt), `project.yml` (Debug gleiche Bundle-ID).
**Vorschlag:** `SparkleUpdater` im Test-Host (`AppEnvironment.isRunningTests`) nicht starten.

### BUG-22 · Gegenprüfung lässt eine leere Anzeigeversion durch — niedrig
**Betrifft:** BUG-11
**Reproduktion:** Attrappe mit `MARKETING_VERSION: ""`, Build 3 → `release.sh` Exit 0, `dist/MikaPlusPlayer-v.dmg`, Feed-Eintrag mit leerer `shortVersionString` und URL `…/download/v/MikaPlusPlayer-v.dmg`; `vor-build`: `[  ok  ] MARKETING_VERSION= noch nicht im Feed`, `[  ok  ] Tag v noch nicht vorhanden`. Test `testBUG22_…`.
**Erwartet:** Befund, Abbruch vor dem Build.
**Ort:** `scripts/b09_release_check.sh:55, 90-94`.
**Vorschlag:** leere oder nicht numerische Anzeigeversion als `[BEFUND]` werten.

### BUG-23 · Fremde Download-Adresse in bestehendem Feed-Eintrag wird nicht erkannt und mitsigniert — mittel
**Betrifft:** BUG-11, BUG-07, BUG-08 (Feed-Pflicht)
**Reproduktion:**
1. In der versionierten `appcast.xml` die Enclosure-URL des v1.1-Eintrags auf `https://evil.example/download/…` ändern und committen (entspricht einem Push auf das ungeschützte `main`).
2. `release.sh` (Attrappe, Test-Schlüssel) → Exit 0; der neue, **signierte** Feed enthält `evil.example`; `vor-build` meldet keinen Befund (Test `testBUG23_…`).
**Erwartet:** Jede Enclosure-URL im Feed zeigt auf `https://github.com/$GH_REPO/releases/download/…`, sonst Befund.
**Tatsächlich:** geprüft werden nur „Mukaarts“ im Text, der Titel, Einträge-Anzahl und der **neue** Eintrag. Weil `release.sh` den ganzen Feed signiert, legitimiert das nächste Release einen ungeprüft geänderten Altbestand – genau den Fall, gegen den `SURequireSignedFeed` später schützen soll.
**Ort:** `scripts/b09_release_check.sh:70-76` (vor-build) und `176-180` (feed vergleicht nur mit dem ebenfalls veränderten Basis-Feed).
**Vorschlag:** alle Enclosure-URLs gegen das erwartete Präfix prüfen und bestehende Einträge zusätzlich gegen den Stand des letzten Release-Tags vergleichen.

### BUG-24 · `release.sh` bricht ohne `generate_appcast` stumm ab — niedrig
**Betrifft:** AK-19
**Reproduktion:** Attrappe ohne `build/dd/SourcePackages/artifacts`, `GENERATE_APPCAST` nicht gesetzt → nach Build, DMG und nach-build-Prüfung Exit 1 ohne Meldung; `bash -x` endet bei `+ GEN=`.
**Erwartet:** „FEHLER: generate_appcast nicht gefunden.“, Exit 1 (AK-19).
**Tatsächlich:** `set -euo pipefail` beendet das Skript bereits in `GEN="${…:-$(find … | head -1)}"`, weil `find` auf dem fehlenden Ordner scheitert; die Prüfzeile danach wird nie erreicht. Schon in `c01f1cf` so (AK-19 war nur gelesen). `appcast.xml` bleibt unverändert.
**Ort:** `scripts/release.sh:43-44`.
**Vorschlag:** `find … 2>/dev/null || true` in der Ersetzung.

## Durchlauf 2 · Hinweise (kein BUG)

- **H-1 · Spec veraltet:** AK-10 („nach dem Entpacken“), AK-15, AK-17, AK-19 (Reihenfolge), AK-20, AK-21, AK-22 beschreiben
  den Stand vor der Reparatur; AK-02 nennt „Version History“, das Sparkle ohne Release-Notes-Link nicht zeigt, und
  den Text ohne „(Build)“-Zusatz bei höherer eigener Build-Nummer. Vorschlag: Spec bei der nächsten Überarbeitung
  fortschreiben (Aufgabe von `sdd-erfassen`/`sdd-build`, nicht der QA).
- **H-2 · Sparkle-Dialoge je nach Einstellung:** Mit abgeschalteter automatischer Prüfung fehlen im Update-Dialog
  „Remind Me Later“ und das Kontrollkästchen; EC-09 zeigt bei manueller Prüfung einen eigenen Hinweis-Dialog.
- **H-3 · DMG-Inhalt:** Die nach-build-Prüfung vergleicht nur die App im DMG (CDHash). Eine zusätzliche Datei
  (`Installieren.command`) im DMG ging durch (Exit 0). Nur mit Schreibzugriff auf `dist/` während des Releases
  ausnutzbar.
- **H-4 · Nutzereinstellungen überstimmen den Feed:** Sparkle liest `SUFeedURL` aus den Nutzereinstellungen (so in
  dieser QA genutzt, Sparkle warnt im Log). Ein Prozess des Nutzers kann den Feed damit umlenken; Schutz gibt dann
  nur EdDSA fürs Archiv – und künftig `SURequireSignedFeed` (OF-07).
- **H-5 · iOS-Hinweis:** nennt den absoluten Container-Pfad, den Nutzer nicht erreichen (OF-08). Sonst keine
  Nebenwirkung der systemweiten Änderungen auf iOS: Simulator-Build `** BUILD SUCCEEDED **` ohne neue Warnungen
  (nur `LSSupportsOpeningDocumentsInPlace` und `appintentsmetadataprocessor` wie Baseline), `CFBundleVersion=3`,
  kein Sparkle im Bundle, iOS-Release ohne Runtime-Einstellungen (`ENABLE_HARDENED_RUNTIME = NO`), App startet im
  Simulator (`iOS-simulator-start.png`), Wiederherstellung funktioniert.
- **H-6 · Vorfall während der Prüfung:** Beim Öffnen des App-Menüs über die Bedienungshilfen, während ein
  Update-Dialog (manipuliertes DMG) offen war, wurde das Update ausgelöst. Sparkle lud das DMG, wies es ab
  („improperly signed“), die Kopie blieb unverändert (Build 3, `codesign --verify` gültig). Danach nur noch
  gezielte Knopfdrücke. Sparkles Download-Zwischenspeicher lag trotz isoliertem `HOME` unter
  `~/Library/Caches/lu.daumedia.MikaPlusPlayer.qa09*` (Autoupdate läuft ohne die Umgebung der App) – gelöscht.
- **H-7 · Nebenbefund außerhalb B09:** Im Unified Log stand während des Gesamtlaufs eine CFNetwork-Meldung eines
  B01-QA-Tests mit `player_api.php?username=…&password=…` (erfundene Testdaten). Gehört zu B01.

## Durchlauf 2 · Code-Review

`code-reviewer` auf die Reparaturdateien (Updater, App, Schema, Persistenz, Alert, Skripte, Konfiguration) mit
Sparkle-2.9.3-Quellen als Referenz. Funde **selbst verifiziert**:

- **Bestätigt → BUG-19:** Kürzung durch `generate_appcast` – ausgeführt in zwei Release-Ketten und im Test.
- **Bestätigt → BUG-20:** verwaiste Schlüsselbund-Einträge – ausgeführt im Test.
- **Bestätigt, kein Fehler:** KVO→MainActor-Brücke ohne Wettlauf; `SUVerifyUpdateBeforeExtraction` wirkt für DMG
  (ausgeführt, BUG-08); `sign_update` ersetzt beim erneuten Signieren den alten Signaturblock (Kette: immer genau ein
  Block, gültig); `moveStoreAside` mit Rückabwicklung.
- Nicht vom Reviewer gemeldet, von der QA gefunden: BUG-18 an der Menüleiste, BUG-22, BUG-23, BUG-24.

## Durchlauf 2 · Neue Tests

| Datei | Fälle | Deckt ab |
|---|---|---|
| `Tests/B09/B09QA2Tests.swift` | `testEC07_BUG13_ZweiterStartOhneHinweisUndNichtsWirdUeberschrieben` | EC-07/BUG-13: zweiter Start ohne Hinweis, erneuter Fehlschlag legt zweiten Ordner an |
| | `testEC07_BUG20_ZugangsdatenBeiseitegelegterPlaylistsBleibenOhneLoeschweg` (`XCTExpectFailure`) | BUG-20 |
| | `testAK01_MenueeintragDirektUnterAboutUndAktiv` | AK-01 |
| | `testEC01_BUG21_TestHostStartetSparkleInDerDomaeneDerInstalliertenApp` (`XCTExpectFailure`) | EC-01/BUG-21 |
| | `testBUG19_FeedPruefungBlockiertReleaseNachKuerzungDurchGenerateAppcast` (`XCTExpectFailure`) | BUG-19 |
| | `testBUG22_VorBuildLaesstLeereAnzeigeversionDurch` (`XCTExpectFailure`) | BUG-22 |
| | `testBUG23_VorBuildPrueftDownloadAdressenBestehenderEintraegeNicht` (`XCTExpectFailure`) | BUG-23 |

Laufbelege (gefiltert):

```
xcodebuild test … -derivedDataPath build/dd-qa-b09 -only-testing: B09QA2Tests B09PersistenzTests B09ReleaseConfigTests B09ReleaseSkriptTests B09UpdaterTests
B09QA2|AK-01|appMenu=["About Mika+Player", "Nach Updates suchen …", "—", "Services", …]|index=1|enabled=true
B09QA2|BUG-19|generate_appcast|Wrote 1 new update, updated 0 existing updates, and removed 1 old update in appcast.xml|versionen=[3, 4, 5]
B09QA2|BUG-19|feed-check|exit=1|[BEFUND] Einträge weichen ab: 3 4 5  statt 2 3 4 5 … / [BEFUND] bestehender Eintrag 2 verändert …
B09QA2|BUG-22|vor-build|exit=0|[  ok  ] MARKETING_VERSION= noch nicht im Feed / [  ok  ] Tag v noch nicht vorhanden (lokal)
B09QA2|BUG-23|vor-build|exit=0|befunde=[]
B09QA2|EC-01|bundleID=lu.daumedia.MikaPlusPlayer|updaterGestartet=true|SUFeedURL=https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml
B09QA2|EC-07|zweiterStart|opened|notice=nil
B09QA2|EC-07|ordner|2030-03-17_18-46-40|2030-03-17_18-46-40-2
B09QA2|BUG-20|eintraege=2|alterEintragVorhanden=true
Test Suite 'B09QA2Tests' passed      Executed 7 tests, with 0 failures (0 unexpected)
         Executed 35 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **

xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-qa-b09
Test Suite 'All tests' passed        Executed 147 tests, with 2 tests skipped and 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

`xcodegen generate` einmal ausgeführt (neue Testdatei). Fensterbilder: `features/B09-auto-update/qa/durchlauf-2/` (17 Dateien).

## Für befunde.md

(ohne BF-Nummern — die vergibt der Orchestrator; Stand nach Durchlauf 2)

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| v1.1-Feed im freien `Mukaarts`-Namensraum (Hijack: Unterdrücken/Phishing/Replay) – **offen**, braucht Nutzer/GitHub/Release; leeres Blockier-Konto verstößt ggf. gegen GitHubs Name-Squatting-Richtlinie | kritisch | `Info.plist`@v1.1 `SUFeedURL`; `users/Mukaarts`→404 | BUG-01 |
| `get-task-allow` ohne Hardened Runtime – **behoben** (Attach/Injektion am Release abgewiesen) | kritisch | Release-Settings `project.yml` | BUG-02 |
| Keine Developer-ID-Signatur/Notarisierung, DMG unsigniert – **offen** (Apple-Team) | hoch | `project.yml` `CODE_SIGN_IDENTITY "-"`, `make-dmg.sh` | BUG-03 |
| Kein Versionssprung seit v1.1 – **behoben** (Build 3, Gegenprüfung); Anzeigeversion offen (OF-06) | hoch | `project.yml`, `b09_release_check.sh` | BUG-04 |
| Schlüsselwechsel unmöglich (ad-hoc DR = CDHash) – **offen** | hoch | ad-hoc-Signatur | BUG-05 |
| Ein EdDSA-Schlüssel für 6 Mika+-Apps – **offen** | hoch | `Info.plist` `SUPublicEDKey` | BUG-06 |
| `main`-Feed ohne Branch-Schutz/Ruleset – **offen** (GitHub) | hoch | GitHub-Repo | BUG-07 |
| DMG-Prüfung vor dem Einhängen – **behoben**; Feed-Signaturpflicht **offen** (OF-07) | hoch | `Info.plist` | BUG-08 |
| `disable-library-validation` – **offen**, bei ad-hoc-Signatur nachweislich nötig | mittel | `MikaPlusPlayer.entitlements` | BUG-09 |
| `release.sh` überschreibt `appcast.xml` mit Altstand – **behoben** | hoch | `scripts/release.sh` | BUG-10 |
| Keine Release-Gegenprüfungen – **behoben** (Lücken siehe BUG-19/22/23/24) | mittel | `scripts/b09_release_check.sh` | BUG-11 |
| Datenschutzseite nennt User-Agent/Auto-Start nicht – **offen**, bei B10 | mittel | `web/app/privacy/page.tsx:57-59` | BUG-12 |
| Update kann App durch fehlende Schema-Migration unbrauchbar machen – **behoben** | hoch | `AppSchema.swift`, `AppPersistence.openStore` | BUG-13 |
| Sparkle nicht gepinnt – **behoben** | mittel | `project.yml` | BUG-14 |
| Notarisierungsweg im README in falscher Reihenfolge – **behoben** (Doku) | mittel | `README.md` | BUG-15 |
| Website beschreibt Update-Weg ungenau – **offen**, bei B10 | niedrig | `web/app/changelog/page.tsx:21`, `web/content/features.ts:42` | BUG-16 |
| Keine Tests für die Update-Kette – **behoben** | mittel | `Tests/B09/` | BUG-17 |
| Menüeintrag bleibt während der Prüfung aktiv – **nicht behoben** (echte Menüleiste) | mittel | `MikaPlusPlayerApp.swift:39-45` | BUG-18 |
| Feed-Gegenprüfung blockiert Releases ab Build 5, weil `generate_appcast` auf 3 Einträge kürzt | mittel | `b09_release_check.sh:173-180`, `release.sh:57-59` | BUG-19 |
| Zugangsdaten beiseitegelegter Playlists ohne Löschweg im Schlüsselbund | mittel | `AppPersistence.swift:87-109`, `StoreRecoveryAlert.swift` | BUG-20 |
| Test-Host startet Sparkle in der Domäne der installierten App | niedrig | `MikaPlusPlayerApp.swift:23` | BUG-21 |
| Gegenprüfung lässt leere Anzeigeversion durch | niedrig | `b09_release_check.sh:55,90-94` | BUG-22 |
| Fremde Download-Adresse in bestehendem Feed-Eintrag unerkannt und mitsigniert | mittel | `b09_release_check.sh:70-76,176-180` | BUG-23 |
| `release.sh` bricht ohne `generate_appcast` stumm ab | niedrig | `release.sh:43-44` | BUG-24 |

## Nächster Schritt

Zwei QA-Durchläufe sind abgeschlossen. Im Code behebbar und offen: **BUG-18, BUG-19, BUG-20, BUG-23** (mittel) sowie
**BUG-21, BUG-22, BUG-24** (niedrig) → `/sdd-build B09` mit diesem Auftrag, danach erneut `/sdd-qa B09`.
Die höchsten offenen Grade (BUG-01 kritisch; BUG-03, 05, 06, 07 und die Feed-Pflicht aus BUG-08 hoch) lassen sich
nicht im Code beheben: Sie brauchen den Nutzer (GitHub-Konto `Mukaarts`, Branch-Schutz, Anzeigeversion OF-06, ein
Release), ein Apple-Developer-Team bzw. einen neuen Schlüssel. Solange sie offen sind, ist B09 nicht production-ready;
nach den Regeln für Bestandsfeatures pausiert die Erfassung bei kritisch/hoch – ob nach zwei Durchläufen trotzdem
weitergemacht wird, entscheidet der Orchestrator. BUG-12 und BUG-16 gehören zur B10-Reparatur.

---

## Durchlauf 1 (2026-09-15) — unverändert, mit den Reparaturvermerken aus `sdd-build` vom 2026-09-16

Stand: 2026-09-15 · Geprüft gegen `spec.md` vom 2026-09-15 · **Durchlauf 1**

> Sicherheitsaudit eines Bestandsfeatures (`rekonstruiert`). Geprüft wurde ausschließlich in einer
> **Scratchpad-Kopie** mit eigenem Test-EdDSA-Schlüsselpaar, eigener Bundle-ID
> (`lu.daumedia.MikaPlusPlayer.qa09`), lokalem Feed über `python3 -m http.server` auf `127.0.0.1` und
> isoliertem `HOME`. Der familienweite Produktivschlüssel, die Keychain, `appcast.xml`, `project.yml`,
> `Sources/`, `Tests/` und `MikaPlusPlayer.xcodeproj` wurden **nicht** verändert; `xcodegen`/`xcodebuild`
> liefen **nicht** im Repo (B01-QA lief parallel). Nachweis, dass die echten Nutzerdaten unberührt blieben:
> `~/Library/Application Support/default.store` (mtime 23:00) und `…/Preferences/lu.daumedia.MikaPlusPlayer.plist`
> (mtime 23:10) lagen beide **vor** dem QA-Lauf (23:33); die Kopie schrieb nur in die eigene Domäne
> `…qa09`, die anschließend gelöscht wurde. Es wurde **kein** Stream abgespielt (kein Ton).

### Fazit

**Production-ready: nein**

Die Integrität der gesamten Update-Kette hängt an einer einzigen Prüfung (EdDSA über die DMG-Bytes) und
ist an mehreren Stellen aushebelbar. **Kritisch:** (1) Alle **v1.1-Installationen** fragen den Feed aus
dem **freien** GitHub-Namensraum `Mukaarts` ab (`GET /users/Mukaarts` → 404, ausgeführt bestätigt) — wer
den Namen registriert, steuert deren Update-Kanal und kann Updates unterdrücken, per Informations-Update
auf beliebige Links leiten und **bereits signierte Archive unter erhöhter Versionsnummer wiedereinspielen**
(Replay/Downgrade — die wiederverwendete Signatur validiert nachweislich gegen den echten Schlüssel).
(2) Das Release trägt `get-task-allow=true` ohne Hardened Runtime — ein `lldb`-Attach ohne Root gelang
gegen die entitlement-gleiche Kopie, womit ein beliebiger Nutzerprozess den Speicher (inkl. der im Klartext
gehaltenen Xtream-Zugangsdaten, DM-01) auslesen kann. Der einzige Ausweg (FB-01 per Update reparieren)
ist zusätzlich durch den fehlenden Versionssprung (FB-02) und die feed-überschreibende `release.sh`
(FB-10) blockiert. Nächster Schritt: `/sdd-build B09` mit BUG-01…BUG-16 und BUG-18 (BUG-17 ist mit den beiliegenden Tests adressiert) — die Erfassung wartet.

| | Anzahl |
|---|---|
| Akzeptanzkriterien geprüft | 30 von 30 |
| davon bestanden (inkl. der 8 ⚠-AK, die das Ist korrekt reproduzieren) | 22 |
| davon durchgefallen | 0 (alle als *Ist* formulierten AK treffen zu; die Schwächen sind ⚠-AK → Befunde) |
| **nicht prüfbar** | 8 (AK-01, 02, 04, 06, 07, 08, 09, 17 — UI/Zeit/echte Installation) |
| Edge Cases belegt | 4 von 13 (EC-02/OF-03, EC-05 teilweise, EC-11 bestätigt; EC-01 by design) |
| Tests neu geschrieben | 8 (+ 1 Preflight-Skript) |
| Tests grün | 8 von 8 (5 davon `XCTExpectFailure` für offene Befunde) |

Hinweis zur Zählung: Die ⚠-AK (14, 15, 16, 20, 21, 27, 28, 30) beschreiben das heutige Ist korrekt —
sie sind „bestanden" im Sinne von *reproduziert*, aber gleichzeitig als Fehler eingestuft und darum unten
als BUG geführt. „Durchgefallen" im Sinne von *Code weicht von der Spec ab* gibt es nicht, weil die Spec
den Bestand beschreibt.

### Akzeptanzkriterien im Einzelnen

| AK | Ergebnis | Nachweis |
|---|---|---|
| AK-01 | ⚠️ nicht prüfbar | Menüeintrag ist im Code vorhanden (`MikaPlusPlayerApp.swift:35-40`, `CommandGroup(after:.appInfo)`); die Kopie öffnete ihr Fenster (Prefs-Key „NSWindow Frame … ContentView"), aber das macOS-App-Menü ist in dieser Umgebung nicht automatisierbar |
| AK-02 | ⚠️ nicht prüfbar | „You're up to date!"-Dialog ist reine Sparkle-UI; die Versionsvergleich-/Abruf-Kette ist über AK-06 ausgeführt, der Dialog selbst nicht (kein macOS-UI-Automat; kein Screenshot der Nutzer-Sitzung) |
| AK-03 | ✅ bestanden | Kopie mit leeren Prefs gestartet → sofort `GET /appcast.xml` (Server-Log 23:33:12) **ohne** Einwilligungsdialog; `SUHasLaunchedBefore=1`, `SULastCheckTime` gesetzt |
| AK-04 | ⚠️ nicht prüfbar | 24-h-Intervall (Sparkle-Standard `SUScheduledCheckInterval` ungesetzt) in einem kurzen Lauf nicht beobachtbar (bräuchte Zeitmanipulation) |
| AK-05 | ✅ bestanden | `curl -sI`: beide Feeds HTTP 200, `cache-control: max-age=300`; `curl -sL \| shasum` byte-identisch `fb2cc3fd…` = Repo-`appcast.xml`; `main`-Feed = daumedia, v1.1-Tag-`Info.plist` = `…/Mukaarts/…` (git show v1.1) |
| AK-06 | ⚠️ nicht prüfbar | Feed mit `sparkle:version` 3 > Build 2 wurde geladen und verarbeitet (`SULastCheckTime` sprang, kein Fehler); der 4-Knopf-Dialog selbst wurde nicht sichtbar erfasst (Vollbild-Screenshot hätte die aktive Nutzer-Sitzung mitfotografiert → verworfen) |
| AK-07 | ⚠️ nicht prüfbar | „Build-Nummer maßgeblich": Sparkle-Standard; nicht isoliert gegen den Fall short>Build / version≤Build beobachtet |
| AK-08 | ⚠️ nicht prüfbar | Fehlerdialog bei nicht erreichbarem Feed ist UI; der still-bei-automatisch/laut-bei-manuell-Unterschied nicht ausgeführt |
| AK-09 | ⚠️ nicht prüfbar | Erfolgreiche Installation (Quarantäne-Entfernung, Neustart) wurde nicht durchgefahren (bräuchte GUI-Klick „Install" und würde ein Bundle ersetzen); der Signatur-Kern ist über AK-11 belegt |
| AK-10 | ✅ bestanden | Kern der Ablehnung ausgeführt: um 1 Byte verändertes DMG → EdDSA **INVALID** (`openssl pkeyutl -verify`, `EVP_DigestVerify … signature failure`); `sign_update`/`generate_appcast` verweigern bei Schlüssel-Mismatch. Der „improperly signed"-Dialogtext selbst ist Sparkle-Standard (nicht sichtbar gefahren) |
| AK-11 | ✅ bestanden | `openssl pkeyutl -verify` mit `SUPublicEDKey`: DMG-Signatur **gültig**; 1-Byte-Flip **ungültig**; Länge 36455860 = `appcast.xml`; SHA-256 `8da0620e…`; `github.com/Mukaarts/…` → 301 auf daumedia |
| AK-12 | ✅ bestanden | Die Kopie verarbeitete einen **unsignierten** lokalen Feed anstandslos; `SURequireSignedFeed` fehlt in `Info.plist` (→ FB-08) |
| AK-13 | ✅ bestanden | `codesign -dv`: `Signature=adhoc`, `TeamIdentifier=not set`, Entitlement `app-sandbox=false`; `codesign --verify --deep --strict` → exit 0 |
| AK-14 ⚠ | ✅ reproduziert → BUG-03 | `spctl -a -vv` App **rejected**; DMG **rejected, „no usable signature"**; `codesign -dv` DMG „not signed at all" |
| AK-15 ⚠ | ✅ reproduziert → BUG-02 | `codesign -d --entitlements`: `com.apple.security.get-task-allow=true`; `CodeDirectory … flags=0x2(adhoc)` **ohne** `runtime` |
| AK-16 ⚠ | ✅ reproduziert → BUG-09 | Entitlements: `com.apple.security.cs.disable-library-validation=true` bei ausgeschalteter Hardened Runtime |
| AK-17 | ⚠️ nicht prüfbar | `release.sh` nicht end-to-end gefahren (bräuchte Vollbuild + echten Schlüssel); Teilschritte einzeln ausgeführt (generate_appcast, make-dmg-Fallback, `cp`-Overwrite — siehe AK-18/19/20) |
| AK-18 | ✅ bestanden | hdiutil-Fallback ausgeführt: DMG mit Volume „Mika+Player", `Applications`-Symlink, `MikaPlusPlayer.app`, `Format: UDZO` |
| AK-19 | ✅ bestanden | `make-dmg.sh` ohne `build/MikaPlusPlayer.app` → „FEHLER: … fehlt. Erst scripts/build-macos.sh ausführen." und Abbruch |
| AK-20 ⚠ | ✅ reproduziert → BUG-10 | `generate_appcast` (Test-Schlüssel) auf eine Kopie von `dist/appcast.xml`: 1.1 **und** der nie veröffentlichte **1.0**-Eintrag im Ergebnis, 1.0 mit **`Mukaarts`-URL**, Titel „MikaPlusPlayer"; `diff` gegen Repo-`appcast.xml` zeigt genau diese Rückkehr |
| AK-21 ⚠ | ✅ reproduziert → BUG-04 | `project.yml`: `CURRENT_PROJECT_VERSION=2` (= v1.1); `generate_appcast` hält den Build-2-Eintrag; `release.sh:19` liest nur `CFBundleShortVersionString` |
| AK-22 | ✅ bestanden | Framework im Bundle `Sparkle.framework` 2.9.3 / 2058; `project.yml` `from: "2.6.0"`; `.gitignore` enthält `MikaPlusPlayer.xcodeproj/` (Package.resolved unversioniert) |
| AK-23 | ✅ bestanden (mit Vorbehalt) | Die Kopie kontaktierte ausschließlich den konfigurierten Feed-Host (IP-Abfluss); `SUSendProfileInfo` fehlt in `Info.plist` (kein Systemprofil). Exakter User-Agent-String nicht mitgeschnitten (Default-`http.server` loggt keine Header; keine erneute App-Starts auf der Nutzer-Sitzung) — laut Sparkle 2.9.3 `Mika+Player/1.1 Sparkle/2.9.3` |
| AK-24 | ✅ bestanden | Nach dem Lauf (isolierte `…qa09`-Domäne): nur `SUHasLaunchedBefore`, `SULastCheckTime` (21:33:12Z = Abrufzeit), `SUUpdateGroupIdentifier` — **keine** Zugangs-/Nutzerdaten |
| AK-25 | ✅ bestanden | Keine hartcodierten URLs in `SparkleUpdater.swift`; einziger Update-Endpunkt ist `SUFeedURL` (GitHub); der beobachtete Lauf ging nur an den konfigurierten Host. Datenschutzseite unvollständig → FB-15 |
| AK-26 | ✅ bestanden | `gh api …/branches/main` → `protected: false`; `…/rulesets` → `[]` |
| AK-27 ⚠ | ✅ reproduziert → BUG-01 | `gh api users/Mukaarts` → **404**; `daumedia` = umbenannter User (Typ „User", 2017); v1.1-Tag-Feed = Mukaarts. Angriff in der Kopie nachgestellt (siehe BUG-01) |
| AK-28 ⚠ | ✅ reproduziert → BUG-06 | Identischer `SUPublicEDKey eauiHgP4…` in **6** installierten Mika+-Apps (FileScope, Flow, Grid, ScreenSnap, MediaFetch, Player; Command trägt einen Platzhalter); Signatur bindet an DMG-Bytes, nicht an App/Version → Replay validiert |
| AK-29 | ✅ bestanden | `git log -p --all -S 'BEGIN PRIVATE KEY'` / `*.pem` / `*ed25519*` → nichts; im Repo nur der öffentliche Schlüssel + Signaturen |
| AK-30 ⚠ | ✅ reproduziert → BUG-05 | `codesign -d -r-`: Designated Requirement = `cdhash H"a474f9b6…"`; ad-hoc → kein Code-Signing-Identity-Pfad für einen Schlüsselwechsel (Sparkle `SUUpdateValidator.m:373-376`) |

### Edge Cases

| EC | Ergebnis | Nachweis |
|---|---|---|
| EC-01 | ⚠️ nicht prüfbar (by design) | Test-Host teilt die Bundle-ID → verschiebt `SULastCheckTime` der Installation; nicht neu ausgeführt (B01-QA lief parallel, kein Repo-`xcodebuild`) |
| EC-02 / OF-03 | ✅ belegt | Zwei Archive gleicher Build-Nummer → `generate_appcast` bricht mit `SUSparkleErrorDomain Code=1002 "Duplicate update archives are not supported"` ab und schreibt nichts; bei **einem** Archiv aktualisiert es den bestehenden Build-2-Eintrag an Ort und Stelle |
| EC-05 | ✅ teilweise | Der versionierte `appcast.xml` wird unabhängig vom Klonzustand überschrieben (Teil von BUG-10) |
| EC-07 | ⚠️ nicht prüfbar | Absturz bei nicht migrierbarer Schemaänderung (DM-04/FB-16) — kein Update durchgefahren |
| EC-08…EC-13 | ⚠️ nicht prüfbar | Erfordern eine echte Installation/Wiedergabe bzw. Zeitmanipulation; nicht ausgeführt |
| EC-11 | ❌ bestätigt → BUG-18 | `canCheckForUpdates` nicht beobachtbar — `code-reviewer`-Fund selbst verifiziert (Abschnitt *Code-Review*, BUG-18) |

### Sicherheitsprüfung

Aktiv angegriffen, nicht nur gelesen. Grundlage: `~/.claude/sdd/sicherheit.md`, Stufe B.

| Prüfung | Ergebnis | Beleg |
|---|---|---|
| Fremder Zugriff auf die Update-Kette (IDOR-Analog) | **BUG-01, BUG-07, BUG-06** | `main` ungeschützt (`protected:false`); v1.1-Feed im freien `Mukaarts`-Namensraum (404); ein Schlüssel steuert 6 Apps |
| Zugriffsregeln „serverseitig" (Feed-Integrität) | **BUG-08, BUG-07** | Feed unsigniert (`SURequireSignedFeed` fehlt), kein Branch-Schutz; Kopie verarbeitete einen frei erfundenen Feed |
| Rate Limit | n/a (bestanden) | Kein eigener Endpunkt; Feed/DMG liefert GitHub; automatisch höchstens 1×/24 h |
| PII in Logs | bestanden **+ BUG-02** | Unified Log/Prefs zeigten nur `SU*`-Schlüssel + URLs, keine Zugangsdaten. Aber: `get-task-allow` erlaubt einem Nutzerprozess, den Speicher **inkl. Zugangsdaten** zu lesen (lldb-Attach gelang ohne Root) |
| PII an externe Dienste | bestanden (mit Vorbehalt) | Beobachteter Lauf: nur der konfigurierte Feed-Host; kein Systemprofil (`SUSendProfileInfo` aus), keine Zugangs-/Playlistdaten. IP + User-Agent gehen an GitHub; Datenschutzseite nennt den UA/Auto-Start nicht → FB-15 |
| Geheimnisse im Repository | bestanden **+ BUG-05/BUG-06** | Kein Privatschlüssel in der Historie; aber familienweit geteilter Schlüssel und keine Rotation möglich |
| Eingaben (untrusted Feed) | **BUG-08** | Leerer, Informations-, Replay- und Suppress-Feed erzeugt; die Kopie lud/verarbeitete den unsignierten Feed ohne Prüfung |
| Löschen | bestanden | Update-Weg speichert keine Nutzerdaten; nach dem Lauf blieben nur die `SU*`-Prefs (AK-24) |

#### Angriff FB-01 in der Kopie nachgestellt (Test-Schlüssel, `127.0.0.1`)

Vier Feed-Varianten unter der von der App abgefragten URL bereitgestellt; die Kopie ruft den Feed beim
Start automatisch ab (belegt). Was ein Betreiber des `Mukaarts`-Namensraums gegenüber Sparkle 2.9.3
erreicht:

- **Updates unterdrücken:** leerer Kanal → nie ein Angebot (die App findet keine höhere Version).
- **Informations-Update mit Link:** `<item>` ohne Enclosure mit `<link>` → Sparkle zeigt einen Dialog mit
  „Learn More", der die Angreifer-URL im Browser öffnet (Nutzer sind durch die FAQ auf „Rechtsklick →
  Öffnen" trainiert).
- **Replay/Downgrade:** `sparkle:version` 9999 mit Enclosure auf das **bereits signierte** v1.1-DMG und
  dessen echter Signatur — die wiederverwendete Signatur **validiert gegen den echten `SUPublicEDKey`**
  (`openssl pkeyutl -verify` → „Signature Verified Successfully"). Ein neues Binary lässt sich ohne
  Privatschlüssel nicht unterschieben, ein **altes signiertes** aber unter erhöhter Nummer.
- Grenze: Eine **Installation** würde erst nach Nutzerklick „Install" und nur bei App-Namen
  `MikaPlusPlayer.app` im Archiv erfolgen (nicht headless gefahren).

### Fehler

Die folgenden BUGs entsprechen dem in der Spec vorab benannten Fehlbestand, hier **durch Ausführung
bestätigt**. Reihenfolge nach Schweregrad.

#### BUG-01 · v1.1-Installationen hängen an einem freien GitHub-Namensraum — kritisch
**Betrifft:** AK-27, AK-05, AK-12 · **Fehlbestand:** FB-01
**Reproduktion:** `gh api users/Mukaarts` → 404; `git show v1.1:Sources/Resources/Info.plist` → `SUFeedURL = …/Mukaarts/…`; in der Kopie den Feed unter dieser Adresse durch einen eigenen ersetzt (lokal `127.0.0.1`) → App ruft ihn beim Start ab und verarbeitet ihn.
**Erwartet:** Der Update-Kanal einer ausgelieferten Version ist an einen kontrollierten Namensraum gebunden.
**Tatsächlich:** Wer `Mukaarts` registriert und `MikaPlusPlayer/main/appcast.xml` anlegt, steuert den Feed aller v1.1-Installationen (Updates unterdrücken, Informations-Update mit Link, Replay signierter Archive).
**Ort:** `Sources/Resources/Info.plist` (v1.1-Tag, `SUFeedURL`); `SURequireSignedFeed` fehlt.
**Vorschlag:** Übergangs-Release mit daumedia-Feed **und** Build-Sprung ausliefern (BUG-04); den `Mukaarts`-Namensraum defensiv besetzen; `SURequireSignedFeed` setzen.

**Nicht behoben (2026-09-16):** Braucht den Nutzer, GitHub und ein Release – im Code nicht lösbar (der Feed der v1.1 steht in deren Bundle). Vorbereitet ist der Ausweg: Build-Nummer 3 (BUG-04), `release.sh` schreibt den Feed ohne Mukaarts-Altstand fort und prüft ihn (BUG-10/11). Schritte für den Nutzer: (1) GitHub-Konto `Mukaarts` selbst registrieren und halten, darin **kein** Repository `MikaPlusPlayer` anlegen (ein gleichnamiges Repository beendet GitHubs Weiterleitung); 2FA an. (2) Anzeigeversion festlegen (OF-06), committen, `bash scripts/release.sh`, DMG als Asset von `v<version>` hochladen, dann `appcast.xml` auf `main` pushen – v1.1-Installationen erreichen den Feed über die Weiterleitung und wechseln mit dem Update auf den daumedia-Feed. (3) Mika+FileScope fragt ebenfalls `Mukaarts` ab – dort gleich verfahren.

#### BUG-02 · Debug-Berechtigung ohne Hardened Runtime im Release — kritisch
**Betrifft:** AK-15 · **Fehlbestand:** FB-03
**Reproduktion:** `codesign -d --entitlements - build/MikaPlusPlayer.app` → `get-task-allow=true`, `flags=0x2(adhoc)` ohne `runtime`. Gegen die **entitlement-gleiche Kopie** (`…qa09`): als Nicht-Root (EUID 501) `lldb -p <pid>` → „Process … stopped", Thread-Liste, `detach` — ohne sudo. (Kein Speicher ausgelesen; Kopie mit leerem `HOME`.)
**Erwartet:** Kein Prozess des Nutzers kann sich ohne Weiteres an die App hängen.
**Tatsächlich:** Jeder Nutzerprozess kann Debugger anhängen und den Speicher lesen — inkl. der im Klartext gehaltenen Xtream-Zugangsdaten (DM-01). Notarisierung ist so unmöglich.
**Ort:** effektive Release-Settings (`ENABLE_HARDENED_RUNTIME=NO`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`).
**Vorschlag:** Hardened Runtime aktivieren, `get-task-allow` im Release entfernen.

**Behoben 2026-09-16:** `project.yml`, Target `MikaPlusPlayer-macOS`, Konfiguration Release: `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` (Debug unverändert). Vorher reproduziert (Release-Build des Ausgangsstands, eigenes DerivedData): `get-task-allow => true`, `flags=0x2(adhoc)`. Nachher (`build/dd-b09-release`): Entitlements nur `app-sandbox=false` und `disable-library-validation=true`, `flags=0x10002(adhoc,runtime)` an App, Sparkle.framework, VLCKit.framework, Autoupdate und Updater.app; `codesign --verify --deep --strict` gültig. Start des Release-Builds (eigene Bundle-ID, Test-Host-Modus mit In-Memory-Datenbank, automatische Prüfung aus): läuft nach 8 s, Sparkle und VLCKit geladen, 0 Netzverbindungen, sauber beendet. **Angriff erneut nachgestellt:** als Nicht-Root (EUID 501) `lldb` → `process attach --pid …` → „attach failed (Not allowed to attach to process.)“. VLCKit dekodiert unter denselben Signaturbedingungen (Hardened Runtime + `disable-library-validation`, ad hoc) eine stumme H.264-MPEG-TS-Datei (`--no-audio`, `--vout=dummy`): 368 Bilder in 7,9 s, gleich wie ohne Runtime (Stichprobe, OF-09). Tests: `B09ReleaseConfigTests.testFB03_hardenedRuntimeEnabledInRelease`, `B09ReleaseSkriptTests.testBUG02_NachBuildErkenntGetTaskAllowUndFehlendeRuntime` (Gegenprüfung am Bundle).

#### BUG-03 · Keine Developer-ID-Signatur, keine Notarisierung, DMG unsigniert — hoch
**Betrifft:** AK-14 · **Fehlbestand:** FB-05
**Reproduktion:** `spctl -a -vv build/MikaPlusPlayer.app` → rejected; `spctl -a -vv dist/*.dmg` → rejected, „no usable signature"; `codesign -dv dist/*.dmg` → „not signed at all".
**Erwartet:** Erstinstallation über Gatekeeper verifizierbar.
**Tatsächlich:** Erstinstallation nur durch TLS geschützt; Nutzer werden zur Gatekeeper-Umgehung angeleitet und können ein untergeschobenes DMG nicht unterscheiden.
**Ort:** `project.yml:70-71` (`CODE_SIGN_IDENTITY "-"`), `make-dmg.sh` (keine Signatur).
**Vorschlag:** Developer ID + Notarisierung + Stapling; DMG signieren.

**Nicht behoben (2026-09-16):** Braucht Apple-Developer-Team, Zertifikat und Notarisierungszugang. Schritte: (1) Apple Developer Program, Zertifikat „Developer ID Application“ in der Keychain. (2) `xcrun notarytool store-credentials <profil>`. (3) Weg aus dem README-Abschnitt *Öffentliche Distribution* (nach BUG-15 in richtiger Reihenfolge) gehen bzw. `release.sh` darauf umstellen; `CODE_SIGN_IDENTITY` in `project.yml` umstellen, DMG signieren. (4) Danach `disable-library-validation` entfernen (BUG-09) und `XCTExpectFailure` in `testFB05_releaseSignedWithDeveloperID` streichen. Die Gegenprüfung meldet den Zustand bis dahin als `[ offen]` (mit `STRENG=1` blockierend).

#### BUG-04 · Kein Versionssprung seit v1.1, Build-Nummer gilt als optional — hoch
**Betrifft:** AK-21 · **Fehlbestand:** FB-02
**Reproduktion:** `project.yml` `CURRENT_PROJECT_VERSION=2` (= Tag v1.1); `generate_appcast` behält den Build-2-Eintrag. Test `testFB02_…` (XCTExpectFailure).
**Erwartet:** Ein Release erhöht die Build-Nummer.
**Tatsächlich:** Ein Release von `main` erreicht keine bestehende Installation — auch nicht die v1.1-Installationen, die für die FB-01-Reparatur ein Update brauchen.
**Ort:** `project.yml:34-35`, `README.md` („ggf. `CURRENT_PROJECT_VERSION`"), `release.sh:19`.
**Vorschlag:** Build-Nummer im Release erzwingen (Preflight), README-„ggf." streichen.

**Behoben 2026-09-16:** `CURRENT_PROJECT_VERSION` 2 → 3 (`project.yml`, gilt für beide Targets; Release-Build: `CFBundleVersion=3`). `scripts/b09_release_check.sh vor-build` bricht ab, wenn die Build-Nummer nicht größer ist als die höchste `sparkle:version` in `appcast.xml`; `release.sh` und `build-macos.sh` nennen die Build-Nummer; README „ggf.“ gestrichen. Tests: `testFB02_buildNumberAdvancedPastReleasedBuild` (ohne `XCTExpectFailure`), `B09ReleaseSkriptTests.testBUG04_VorBuildBrichtAbWennBuildNummerNichtHoeher`; Attrappen-Lauf mit Build 2 bricht vor dem Build ab. **Offen:** `MARKETING_VERSION` bleibt 1.1 (Produktentscheidung, OF-06) – die Gegenprüfung blockiert ein Release, solange 1.1 schon im Feed steht.

#### BUG-05 · Kein Schlüsselwechsel möglich — hoch
**Betrifft:** AK-30 · **Fehlbestand:** FB-06
**Reproduktion:** `codesign -d -r- build/MikaPlusPlayer.app` → `designated => cdhash H"a474f9b6…"`.
**Tatsächlich:** Bei Verlust/Kompromittierung des Privatschlüssels kann keine bestehende Installation je wieder per Sparkle aktualisiert werden (Sparkle akzeptiert nur gültige EdDSA **oder** passende Code-Signing-Identity; ad-hoc DR = CDHash).
**Ort:** ad-hoc-Signatur (`project.yml:70-71`).
**Vorschlag:** Developer-ID-Signatur (macht den Identity-Pfad und damit Rotation möglich).

**Nicht behoben (2026-09-16):** Hängt an BUG-03. Schritte: (1) Privatschlüssel sichern (`generate_keys -x <datei>`, verschlüsselt offline verwahren; OF-05). (2) Ein Release mit Developer-ID-signierter App **und** signiertem DMG ausliefern, das alle Installationen erreicht. Ab dann greift Sparkles Rückfallweg bei einem Schlüsselwechsel (Archiv mit Developer ID derselben Team-ID, `SUUpdateValidator.m` `validateDownloadPathWithFallbackOnCodeSigning`; setzt `SUVerifyUpdateBeforeExtraction` voraus, das seit BUG-08 gesetzt ist). (3) Im Ernstfall neues Schlüsselpaar, neuer `SUPublicEDKey`, Release mit Developer ID signieren.

#### BUG-06 · Ein EdDSA-Schlüssel für die ganze App-Familie — hoch
**Betrifft:** AK-28 · **Fehlbestand:** FB-07
**Reproduktion:** identischer `SUPublicEDKey` in `/Applications/Mika+FileScope|Flow|Grid|ScreenSnap|MikaPlusMediaFetch|MikaPlusPlayer`. Signatur ist über die DMG-Bytes → Replay eines Fremdarchivs validiert (BUG-01).
**Tatsächlich:** Eine Kompromittierung an einer Stelle betrifft alle Apps; Signaturen sind nicht an App/Version gebunden.
**Ort:** `Info.plist` `SUPublicEDKey` (familienweit).
**Vorschlag:** je App eigener Schlüssel; Feed-Signatur (BUG-08) ergänzen.

**Nicht behoben (2026-09-16):** Braucht einen neuen Schlüssel (Keychain) und ein Release, und laut AK-30 den Wechselweg aus BUG-05. Schritte: nach BUG-03/05 `generate_keys --account mika-plus-player` (eigenes Konto nur für diese App), neuen `SUPublicEDKey` in `Info.plist`, `generate_appcast`/`sign_update` in `release.sh` mit `--account mika-plus-player`, Release mit Developer ID; die übrigen Mika+-Apps einzeln genauso.

#### BUG-07 · Feed ungeschützt direkt aus `main` — hoch
**Betrifft:** AK-26 · **Fehlbestand:** FB-09
**Reproduktion:** `gh api …/branches/main` → `protected:false`; `…/rulesets` → `[]`; `raw` liefert `max-age=300`.
**Tatsächlich:** Jeder Push auf `main` (auch der versehentliche aus BUG-10) erreicht binnen ~5 min alle `main`-Installationen ohne Review.
**Ort:** GitHub-Repo-Einstellungen.
**Vorschlag:** Branch-Schutz/Ruleset für `main`; Feed aus einem geschützten Pfad ausliefern.

**Nicht behoben (2026-09-16):** GitHub-Einstellung, außerhalb des Repos. Schritte: Ruleset bzw. Branch-Schutz für `main` (Pull Request mit Review, kein Force-Push, kein Löschen, Push nur für den Inhaber), 2FA am Konto `daumedia` prüfen (OF-04). Ergänzend wirkt ein signierter Feed (BUG-08, `SURequireSignedFeed`) gegen einen Push ohne Privatschlüssel.

#### BUG-08 · Feed unsigniert, Signaturprüfung erst nach dem Entpacken — hoch
**Betrifft:** AK-12 · **Fehlbestand:** FB-08
**Reproduktion:** `Info.plist` ohne `SURequireSignedFeed`/`SUVerifyUpdateBeforeExtraction`; Kopie verarbeitete einen unsignierten `127.0.0.1`-Feed.
**Tatsächlich:** Feed-Inhalte (Einträge, Links) hängen nur an TLS + GitHub-Zugang; ein DMG wird vor der Signaturprüfung eingehängt.
**Ort:** `Info.plist:27-32`.
**Vorschlag:** `SURequireSignedFeed=YES` und Feed signieren; `SUVerifyUpdateBeforeExtraction`.

**Teilweise behoben 2026-09-16:** `Info.plist`: `SUVerifyUpdateBeforeExtraction = YES` – Sparkle 2.9.3 prüft die EdDSA-Signatur des DMG vor dem Einhängen (`AppInstaller.m:270-296`: `needsPrevalidation` → `validateDownloadPathWithFallbackOnCodeSigning` vor `unarchiveWithCompletionBlock`); einziger Konfigurationsfehler dazu wäre ein fehlender EdDSA-Schlüssel (`SPUUpdater.m:345-356`), der vorhanden ist. Wirkt ab der Version, die den Schlüssel trägt; bestehende Feed-Einträge tragen die nötige `sparkle:edSignature`. `release.sh` signiert den Feed jetzt mit `sign_update` und prüft Feed- und DMG-Signatur allein mit dem öffentlichen Schlüssel (`scripts/b09_ed25519.swift`). Nicht ausgeführt: ein Update-Durchlauf mit manipuliertem DMG (bräuchte eine installierte App und Sparkles Installer-UI). Tests: `testFB08_updateVerifiedBeforeExtraction`, `testBUG10_ReleaseSchreibtVersioniertenFeedFort` (Feed signiert und gültig). **Offen:** `SURequireSignedFeed` – mit ihm verwirft Sparkle jeden unsignierten Feed (`SUAppcastDriver.m:94-160`), die veröffentlichte `appcast.xml` ist unsigniert. Schritte: nächstes Release mit dem neuen `release.sh` veröffentlichen (Feed signiert), danach in einer Folgeversion `SURequireSignedFeed = YES` setzen und `XCTExpectFailure` in `testFB08_signedFeedRequired` streichen (OF-07).

#### BUG-09 · `disable-library-validation` ohne tragfähige Begründung — mittel
**Betrifft:** AK-16 · **Fehlbestand:** FB-04
**Reproduktion:** Entitlement gesetzt, Hardened Runtime aus (Begründung im README/Kommentar bezieht sich auf eben diese Runtime).
**Tatsächlich:** heute wirkungslos; würde nach Aktivieren der Runtime das Laden fremd signierter Bibliotheken erlauben.
**Ort:** `MikaPlusPlayer.entitlements:9-12`.
**Vorschlag:** entfernen oder bei aktivierter Runtime bewusst begründen.

**Nicht behoben, belegt 2026-09-16:** Das Entitlement ist unter ad-hoc-Signatur nötig. Release-Build mit Hardened Runtime **ohne** `disable-library-validation` (eigenes DerivedData, eigene Bundle-ID): Start bricht sofort ab (Exit 134) mit `dyld: Library not loaded: @loader_path/../Frameworks/VLCKit.framework/Versions/A/VLCKit … not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs`. Mit dem Entitlement läuft derselbe Build (siehe BUG-02). Kommentar in `MikaPlusPlayer.entitlements` und README mit dieser Begründung korrigiert; `B09ReleaseConfigTests.testFB04_libraryValidationNotDisabled` hält den Befund mit `XCTExpectFailure` fest. Schritte: nach BUG-03 (gleiche Team-ID für App und Frameworks) entfernen und den Start erneut prüfen.

#### BUG-10 · `release.sh` überschreibt `appcast.xml` mit dem Altstand aus `dist/` — hoch
**Betrifft:** AK-20 · **Fehlbestand:** FB-10
**Reproduktion:** `generate_appcast` (Test-Schlüssel) auf eine Kopie von `dist/appcast.xml` + `dist/*.dmg` → Ergebnis enthält den **1.0**-Eintrag mit **`Mukaarts`-URL** und Titel „MikaPlusPlayer"; `diff` gegen das Repo-`appcast.xml` zeigt genau diese Rückkehr. `release.sh:26-29` `cp`t das über den handkorrigierten Feed.
**Tatsächlich:** Beim nächsten Release kehren stillschweigend alte Einträge, `Mukaarts`-URLs (BUG-01) und der alte Titel zurück.
**Ort:** `scripts/release.sh:26-29`, `dist/appcast.xml`.
**Vorschlag:** Feed nicht aus `dist/` fortschreiben; Preflight-Skript `b09_release_check.sh` in `release.sh` einhängen.

**Behoben 2026-09-16:** `scripts/release.sh` erzeugt den Feed in einem leeren Arbeitsordner aus einer Kopie der **versionierten** `appcast.xml` und dem neuen DMG; `dist/appcast.xml` wird nicht mehr gelesen. Vorher reproduziert (altes `release.sh` in einer Attrappe mit Test-Schlüssel): Titel „MikaPlusPlayer“, 1.0-Eintrag und Mukaarts-URLs zurück. Nachher (neues `release.sh`, gleiche Attrappe inkl. altem `dist/appcast.xml`): Titel „Mika+Player“, Einträge 2 und 3, keine Mukaarts-URL, Eintrag 2 unverändert, Feed signiert. Tests: `B09ReleaseSkriptTests.testBUG10_ReleaseSchreibtVersioniertenFeedFort` (echtes `generate_appcast`/`sign_update`, Wegwerf-Schlüssel), `testBUG10_VorBuildErkenntAltstandImVersioniertenFeed`, `B09ReleaseConfigTests.testFB10_releaseScriptDoesNotUseDistAppcast`. Der QA-Test `testFB10_localDistAppcastNotStale` entfällt: `dist/appcast.xml` (lokal, nicht versioniert) bleibt Altstand, ist aber wirkungslos und wird nur als `[ skip ]` erwähnt; `dist/` wurde nicht angefasst.

#### BUG-11 · Keine Gegenprüfungen im Release-Ablauf — mittel
**Betrifft:** AK-17 · **Fehlbestand:** FB-11 · kein `codesign --verify`/`spctl`/EdDSA-Gegenprobe/Build-Nummer-Prüfung. **Vorschlag:** beiliegendes `b09_release_check.sh`.

**Behoben 2026-09-16:** `scripts/b09_release_check.sh` (aus dem QA-Vorschlag, erweitert) mit drei Phasen, in `release.sh` eingehängt: **vor-build** (Feed-Adresse, sauberer Feed, Build-Nummer > Feed, Anzeigeversion noch nicht veröffentlicht, Härtung, Sparkle-Pin, `SUVerifyUpdateBeforeExtraction`, sauberer Git-Stand, Tag frei), **nach-build** (`codesign --verify --deep --strict`, kein `get-task-allow`, Runtime, Versionen/Schlüssel im Bundle, App im DMG = geprüftes Bundle per CDHash), **feed** (Titel, Einträge = versionierter Feed + neuer Build, bestehende Einträge unverändert, URL, Länge, EdDSA des DMG und des Feeds gegen `SUPublicEDKey`). Jeder Befund bricht ab, bevor `appcast.xml` geschrieben wird; bekannte offene Punkte erscheinen als `[ offen]` (`STRENG=1` blockiert auch sie). Beleg: Attrappe mit falschem Schlüssel – `generate_appcast` warnt nur und schreibt den Eintrag **ohne** Signatur, die Gegenprüfung bricht ab, `appcast.xml` bleibt byte-gleich. Tests: 7 in `B09ReleaseSkriptTests` (u. a. `testBUG11_ReleaseBrichtBeiFalschemSchluesselAbOhneFeedZuAendern`).

#### BUG-12 · Datenschutzseite unvollständig für den Update-Weg — mittel
**Betrifft:** AK-25, AK-23 · **Fehlbestand:** FB-15 · nennt IP, nicht den User-Agent (App+Sparkle-Version) und nicht den einwilligungslosen Auto-Start (Art. 13 DSGVO).

**Nicht behoben (2026-09-16):** Gehört zur Website (B10), `web/` wurde in diesem Build nicht angefasst – an die B10-Reparatur übergeben. Zusätzlich für B10: Die Datenschutzseite sollte nennen, dass ab dem nächsten Release der Feed signiert ist (keine Datenschutzfolge) – nur falls sie Details zum Update-Weg beschreibt.

#### BUG-13 · Update-Risiko durch fehlende Schema-Migration — hoch
**Betrifft:** EC-07 · **Fehlbestand:** FB-16 (DM-04) · Ein Update mit nicht automatisch migrierbarer Modelländerung macht die App unbrauchbar, ohne Rückweg (Sparkle hält keine Vorversion). Nicht ausgeführt (kein Update gefahren), aber Ursache in `MikaPlusPlayerApp.swift:10-14` belegt (`fatalError`).

**Behoben 2026-09-16:** Neues `Sources/Models/AppSchema.swift` (`MikaPlusPlayerSchemaV1` = Schema 1.0.0 mit `Playlist`/`Channel`, `MikaPlusPlayerMigrationPlan`, `AppSchema.current`) mit Anleitung für künftige Versionen. B01 hat das Schema nicht geändert (nur Kommentare, `git diff v1.1`). `AppPersistence.openAppStore()` ist der einzige Einstieg beim Start (B01-Speicherort und -Umstellungen bleiben): Öffnen mit Migrationsplan; scheitert das, wird die Datei samt `-wal`/`-shm` nach `<Ordner>/Beiseitegelegt/<Zeitstempel>/` **verschoben** (nie gelöscht, bei Teilfehler zurückverschoben) und eine neue angelegt; gelingt auch das nicht, läuft die Sitzung im Speicher. `MikaPlusPlayerApp` ohne `fatalError` beim Öffnen; Hinweis-Dialog `StoreRecoveryAlert` („Datenbank neu angelegt“, macOS mit „Im Finder zeigen“). Vorlage `Tests/B09/Fixtures/v1.1-schema.store` mit dem v1.1-Quelltext (`git show v1.1:Sources/Models/`) und dem v1.1-Container-Aufruf von einem eigenen Programm erzeugt, nur erfundene Daten. Tests (`B09PersistenzTests`, 7): Temp-Kopie der v1.1-Datenbank öffnet als `.opened` mit Playlist, 3 Sendern und Favorit, weiter beschreibbar; Metadaten der Vorlage kompatibel zu V1; unversionierte Datei mit 150 Sendern öffnet; beschädigte Datei → beiseite, Bytes gleich, neue Datenbank nutzbar, Hinweis nennt den Ordner; nicht migrierbares Schema (Core Data 134140) → beiseite, alter Datensatz lesbar; schreibgeschützter Ordner → In-Memory, Datei unangetastet; Plan passt zum aktuellen Schema. `fatalError` bleibt nur, wenn selbst ein In-Memory-Container mit dem Modell scheitert (ungültiges Modell – dann scheitert jeder Testlauf).

#### BUG-14 · Sparkle nicht gepinnt, aufgelöste Version unversioniert — mittel
**Fehlbestand:** FB-12 · `project.yml` `from:"2.6.0"`, `.gitignore` `MikaPlusPlayer.xcodeproj/`.

**Behoben 2026-09-16:** `project.yml` `Sparkle: exactVersion: "2.9.3"` (aufgelöste Version seit v1.1, unverändert aufgelöst nach `xcodegen generate`). Gegenprüfung `vor-build` meldet einen fehlenden Pin. Test: `testFB12_sparklePinnedExactly`.

#### BUG-15 · Dokumentierter Notarisierungsweg in falscher Reihenfolge — mittel
**Fehlbestand:** FB-13 · `README.md:237-247`: signiert `build/MikaPlusPlayer.app` **nach** dem DMG und reicht das bereits erzeugte DMG ein; nutzt `codesign --deep`. Folge: DMG enthält weiter die ad-hoc-App; Notarisierung schlägt fehl oder die Feed-Signatur passt nach Neuerzeugung nicht mehr.

**Behoben 2026-09-16:** README-Abschnitt *Öffentliche Distribution* neu: Release direkt mit Developer ID bauen (kein `codesign --deep`, Zeitstempel), prüfen, App notarisieren und heften, DMG aus der gehefteten App bauen, signieren, notarisieren, heften, `spctl`-Prüfung, **erst danach** Feed-Eintrag erzeugen; `notarytool` über Keychain-Profil statt Passwort auf der Kommandozeile. Ausdrücklicher Hinweis, dass `release.sh` diesen Weg noch nicht abbildet. Nicht ausgeführt (kein Apple-Team).

#### BUG-16 · Website beschreibt den Update-Weg ungenau — niedrig
**Fehlbestand:** FB-14 · `web/app/changelog/page.tsx:21`, `web/content/features.ts:42-43` — Feed liest `main`, nicht die Releases; „Updates that install themselves" gilt erst nach Opt-in. (Kernthema von B10.)

**Nicht behoben (2026-09-16):** Website (B10), `web/` nicht angefasst – an die B10-Reparatur übergeben.

#### BUG-17 · Keine Tests für die Update-Kette — mittel (mit Durchlauf 1 adressiert)
**Fehlbestand:** FB-17 · Bisher kein Test für `SUFeedURL`, `SUPublicEDKey`, Entitlements oder Versionsfortschritt. Dieser Durchlauf liefert `B09ReleaseConfigTests.swift` (8 Tests) + `b09_release_check.sh` — der Orchestrator übernimmt sie nach der B01-QA.

**Behoben 2026-09-16:** `Tests/B09/` mit 4 Dateien und 28 Tests: `B09ReleaseConfigTests` (11; aus dem QA-Vorschlag, Plist/YAML strukturiert gelesen; `XCTExpectFailure` entfernt bei FB-02, FB-03; neu FB-08 Teil, FB-10 Skript, FB-12; bleibt bei FB-05/BUG-03, FB-08 Feed-Pflicht, FB-04/BUG-09), `B09PersistenzTests` (7), `B09UpdaterTests` (3), `B09ReleaseSkriptTests` (7). `b09_release_check.sh` liegt in `scripts/` und ist eingehängt.

#### BUG-18 · Menü „Nach Updates suchen …" kann veralteten Aktiv-Zustand zeigen — mittel
**Betrifft:** EC-11
**Reproduktion (Code, selbst verifiziert):** `SparkleUpdater` ist `@Observable`, hält seinen einzigen Zustand aber in `@ObservationIgnored private let controller` (`SparkleUpdater.swift:10`) und stellt `canCheckForUpdates` als **berechnete** Property über diesen ignorierten Speicher bereit (`:22`). SwiftUI registriert beim Lesen in `.disabled(!updater.canCheckForUpdates)` (`MikaPlusPlayerApp.swift:39`) daher **keine** Abhängigkeit; Sparkles `canCheckForUpdates` ist KVO/`@objc dynamic` und nicht in Swifts `Observation`-Registrar gebrückt.
**Erwartet:** Der Menüeintrag deaktiviert sich während einer laufenden Prüfung und aktiviert sich danach.
**Tatsächlich:** Der Aktiv-Zustand ändert sich nur, wenn `body` aus einem **fremden** Grund neu rendert — er kann während/nach einer Prüfung veralten.
**Ort:** `Sources/Services/SparkleUpdater.swift:10,22`; `Sources/App/MikaPlusPlayerApp.swift:39`.
**Vorschlag:** Wert in eine getrackte gespeicherte Property spiegeln (KVO/`publisher(for: \.canCheckForUpdates)` → `var`), statt eine Passthrough-Computed-Property über `@ObservationIgnored`-Speicher.

**Behoben 2026-09-16:** `SparkleUpdater` hält `canCheckForUpdates` als gespeicherte, beobachtete Eigenschaft und spiegelt Sparkles Wert per KVO (`NSKeyValueObservation`, Main-Thread direkt, sonst über den Main-Actor); der Initialisierer nimmt ein beliebiges KVO-fähiges Objekt, in der App `SPUUpdater`. Tests (`B09UpdaterTests`): Reproduktion – das alte Muster meldet über `withObservationTracking` 0 Änderungen, obwohl der Wert wechselt; neu 1 Benachrichtigung bei Beginn und 1 bei Ende der Prüfung, Wert korrekt; Änderung aus einem anderen Thread kommt an; Menüaktion löst die Prüfung aus. Nicht an der echten Menüleiste beobachtet (keine UI-Automatisierung).

### Code-Review

`code-reviewer` auf `SparkleUpdater.swift`, den macOS-`.commands`-Block und die drei Release-Skripte; Funde
**selbst verifiziert**:

- **Bestätigt → BUG-18** (EC-11): `canCheckForUpdates` nicht observierbar (oben; Code-Zeilen geprüft).
- **Bestätigt → BUG-10**: Der Reviewer las zusätzlich die Sparkle-Quellen
  (`build/dd/SourcePackages/checkouts/Sparkle/generate_appcast/FeedXML.swift:213-329`, `main.swift:77`)
  und wies nach, dass `generate_appcast` die vorhandene `dist/appcast.xml` als Editierbasis lädt und
  Einträge ohne lokales Archiv **unverändert** durchreicht (alter Titel, alte `enclosure`-URL). Deckt sich
  mit meiner ausgeführten Reproduktion (AK-20) und dem `diff`.
- **Keine** belastbaren Zusatzfunde in `build-macos.sh`/`make-dmg.sh` (korrekt unter `set -euo pipefail`).

### Neue Tests

| Datei | Fälle | Deckt ab |
|---|---|---|
| `features/B09-auto-update/qa/tests-vorschlag/B09ReleaseConfigTests.swift` | 8 (3 grün als Guard, 5 `XCTExpectFailure`) | AK-05, AK-09, FB-10 (grün); FB-02, FB-03, FB-05, FB-08, FB-10 (erwartet rot) |
| `features/B09-auto-update/qa/tests-vorschlag/b09_release_check.sh` | Preflight (7 Prüfblöcke) | FB-01, FB-02, FB-03, FB-05, FB-08, FB-10 als Release-Gate |

Ausgeführt standalone (`swift test`, `B09_REPO_ROOT` auf das echte Repo, nur lesend): „Executed 8 tests,
with 0 failures (0 unexpected)". Die 5 `XCTExpectFailure`-Tests belegen die offenen Befunde und werden
grün, solange der Befund besteht; ihre Reparatur entfernt später die Markierung. Ablageort ist bewusst
`qa/tests-vorschlag/` (nicht `Tests/`), weil die B01-QA parallel im `Tests/`-Baum arbeitet — der
Orchestrator verschiebt `B09ReleaseConfigTests.swift` nach `Tests/` und `b09_release_check.sh` nach
`scripts/`.

### Für befunde.md

(ohne BF-Nummern — die vergibt der Orchestrator)

| Befund | Grad | Fundstelle | BUG-Nr. |
|---|---|---|---|
| v1.1-Feed im freien `Mukaarts`-Namensraum (Hijack: Suppress/Phishing/Replay) | kritisch | `Info.plist`@v1.1 `SUFeedURL`; `users/Mukaarts`→404 | BUG-01 |
| `get-task-allow` ohne Hardened Runtime → Speicher/Zugangsdaten auslesbar (lldb-Attach ohne Root) | kritisch | Release-Entitlements | BUG-02 |
| Keine Developer-ID-Signatur/Notarisierung, DMG unsigniert | hoch | `project.yml:70-71`, `make-dmg.sh` | BUG-03 |
| Kein Versionssprung seit v1.1 → Releases erreichen keine Installation | hoch | `project.yml:34-35`, `release.sh:19` | BUG-04 |
| Schlüsselwechsel unmöglich (ad-hoc DR = CDHash) | hoch | ad-hoc-Signatur | BUG-05 |
| Ein EdDSA-Schlüssel für 6 Mika+-Apps; Signatur nicht app/versions-gebunden | hoch | `Info.plist` `SUPublicEDKey` | BUG-06 |
| `main`-Feed ohne Branch-Schutz/Ruleset | hoch | GitHub-Repo | BUG-07 |
| Feed unsigniert; DMG-Mount vor Signaturprüfung | hoch | `Info.plist:27-32` | BUG-08 |
| `disable-library-validation` ohne tragfähige Begründung | mittel | `MikaPlusPlayer.entitlements:9-12` | BUG-09 |
| `release.sh` überschreibt `appcast.xml` mit Altstand (1.0 + Mukaarts) | hoch | `release.sh:26-29`, `dist/appcast.xml` | BUG-10 |
| Keine Release-Gegenprüfungen | mittel | `release.sh`/`build-macos.sh`/`make-dmg.sh` | BUG-11 |
| Datenschutzseite nennt User-Agent/Auto-Start nicht (Art. 13) | mittel | `web/app/privacy/page.tsx:57-59` | BUG-12 |
| Update kann App durch fehlende Schema-Migration unbrauchbar machen | hoch | `MikaPlusPlayerApp.swift:10-14` (DM-04) | BUG-13 |
| Sparkle nicht gepinnt, aufgelöste Version unversioniert | mittel | `project.yml:21-23`, `.gitignore` | BUG-14 |
| Notarisierungsweg im README in falscher Reihenfolge | mittel | `README.md:237-247` | BUG-15 |
| Website beschreibt Update-Weg ungenau | niedrig | `web/app/changelog/page.tsx:21`, `web/content/features.ts:42-43` | BUG-16 |
| Keine Tests für die Update-Kette | mittel | `Tests/` (fehlend) — mit Durchlauf 1 adressiert | BUG-17 |
| Menü-Aktiv-Zustand veraltet (`canCheckForUpdates` nicht observierbar) | mittel | `SparkleUpdater.swift:10,22`; `MikaPlusPlayerApp.swift:39` | BUG-18 |

### Nächster Schritt

`/sdd-build B09` mit dem Auftrag, BUG-01…BUG-16 und BUG-18 zu beheben (BUG-17 ist mit den beiliegenden Tests
adressiert), danach erneut `/sdd-qa B09` (Durchlauf 2). **Die Rückerfassung wartet**, weil der höchste
Grad *kritisch* ist und laufenden Code betrifft (v1.1-Installationen, Speicherzugriff).
