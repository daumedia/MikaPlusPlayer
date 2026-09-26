# B09 · Auto-Update — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-15 · Stack-Profil: `swiftui-macos` (Vertrieb) + `swiftui-ios` (Projektstruktur, XcodeGen) · Rekonstruktion aus dem Code (sdd-erfassen)

**Kein Code in diesem Dokument.** Es beschreibt, wie der Bestand aufgebaut ist — nicht, wie er sein sollte.
Abweichungen vom Wünschenswerten stehen in `spec.md` unter *Fehlbestand* und sind hier nur verlinkt.

## Überblick

Die macOS-App bettet das Framework Sparkle 2.9.3 ein. Beim Start erzeugt die App einen dünnen Wrapper,
der Sparkles Standard-Controller startet; ab dann prüft Sparkle selbstständig einmal täglich eine
`appcast.xml`, die im GitHub-Repository auf `main` liegt, und zeigt eigene Dialoge. Ein Update ist ein DMG
aus einem GitHub-Release; Sparkle installiert es nur, wenn dessen EdDSA-Signatur zum öffentlichen Schlüssel
in der `Info.plist` der laufenden App passt. Die App ist ad hoc signiert, nicht notarisiert, ohne Hardened
Runtime — die EdDSA-Signatur ist deshalb die einzige Integritätsprüfung. Auf der Entwicklerseite bauen drei
Shell-Skripte App, DMG und signierten Feed-Eintrag; das Veröffentlichen erfolgt von Hand.

## Seiten und Routen

Keine eigenen Ansichten. Einziger Einstieg in der App:

| Ort | Zweck | Zugang |
|---|---|---|
| App-Menü → „Nach Updates suchen …" (nach „About Mika+Player") | manuelle Prüfung | jeder Nutzer der App; nur macOS |
| Sparkle-Fenster („Checking for updates…", Update-Dialog, „You're up to date!", Fehlerdialoge) | Status, Angebot, Installation | von Sparkle erzeugt, Texte aus Sparkles `Base.lproj` (Englisch) |

## Komponentenstruktur

### In der App (Laufzeit)

```
MikaPlusPlayerApp                         Sources/App/MikaPlusPlayerApp.swift
├── @State updater: SparkleUpdater        nur macOS, lebt so lange wie die App (Z. 19)
└── .commands
    └── CommandGroup(after: .appInfo)     Z. 35-40
        └── Button „Nach Updates suchen …"   → updater.checkForUpdates()
                                              .disabled(!updater.canCheckForUpdates)

SparkleUpdater (@MainActor @Observable)   Sources/Services/SparkleUpdater.swift, #if os(macOS)
├── controller: SPUStandardUpdaterController   @ObservationIgnored
│     startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
├── canCheckForUpdates  → controller.updater.canCheckForUpdates   (nicht beobachtet, EC-11)
└── checkForUpdates()   → controller.checkForUpdates(nil)

Sparkle.framework 2.9.3 (eingebettet, ad hoc + runtime-Flag)
├── SPUUpdater               Zeitplan, Feed-Abruf, Versionsvergleich, Einstellungen in UserDefaults
├── SPUStandardUserDriver    alle sichtbaren Dialoge
├── XPCServices/Downloader.xpc   lädt Feed und DMG
├── XPCServices/Installer.xpc
├── Autoupdate               entpackt, prüft Signatur (SUUpdateValidator), ersetzt die App, entfernt Quarantäne
└── Updater.app              Fortschritt/Neustart
```

Keine Delegates: Feed-URL, Intervall, Kanäle und Dialoge sind vollständig Sparkle-Standard bzw. `Info.plist`.

### Ablauf einer Prüfung

```
Start der App ──▶ SPUStandardUpdaterController startet SPUUpdater
                   │  SUEnableAutomaticChecks in Info.plist gesetzt → keine Einwilligungsfrage
                   ▼
            letzte Prüfung (SULastCheckTime) ≥ 24 h her oder fehlt? ──ja──▶ sofort im Hintergrund prüfen
                   │ nein
                   ▼
            Timer bis 24 h nach letzter Prüfung
                   │
Menü „Nach Updates suchen …" ─────────────────────────────▶ Prüfung mit sichtbarem Statusfenster
                   ▼
   GET SUFeedURL (HTTPS, raw.githubusercontent.com)  ── Fehler: manuell Dialog, automatisch still
                   ▼
   höchste sparkle:version > CFBundleVersion  und  minimumSystemVersion erfüllt?
        │ nein → manuell: „You're up to date!"
        ▼ ja
   Update-Dialog ── Install ──▶ DMG laden (github.com → release-assets) ──▶ einhängen/entpacken
                                   ──▶ EdDSA gegen SUPublicEDKey der laufenden App prüfen
                                        ├─ ungültig → „improperly signed", App unverändert
                                        └─ gültig   → App ersetzen, Quarantäne entfernen, Neustart
```

### Auf der Entwicklerseite (Release)

```
scripts/release.sh            GH_REPO = daumedia/MikaPlusPlayer
├── scripts/build-macos.sh
│   ├── xcodegen generate                         nur wenn installiert
│   ├── xcodebuild build  -scheme MikaPlusPlayer-macOS -configuration Release -derivedDataPath build/dd
│   │     (Xcode bettet Sparkle.framework ein und signiert alles ad hoc)
│   └── cp -R  → build/MikaPlusPlayer.app
├── scripts/make-dmg.sh
│   ├── rm dist/*.dmg
│   └── create-dmg (sonst hdiutil UDZO) → dist/MikaPlusPlayer-v<CFBundleShortVersionString>.dmg
├── generate_appcast dist/ --download-url-prefix https://github.com/daumedia/MikaPlusPlayer/releases/download/v<Version>/
│     Werkzeug aus build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin
│     Schlüssel aus der Keychain (Konto ed25519), liest und erweitert dist/appcast.xml
├── cp dist/appcast.xml → appcast.xml (Repository-Wurzel)
└── Ausgabe: drei manuelle Schritte (Release anlegen, DMG hochladen, appcast.xml auf main pushen)
```

## Datenmodell

Keine eigenen Entitäten. An die Stelle des Datenmodells tritt **Konfiguration**.

### `Sources/Resources/Info.plist` (Sparkle-Schlüssel)

| Schlüssel | Wert (`main`) | Wert (v1.1) | Bedeutung |
|---|---|---|---|
| `SUFeedURL` | `https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml` | `…/Mukaarts/MikaPlusPlayer/main/appcast.xml` | Feed-Adresse; gewechselt in `a67d956` (FB-01) |
| `SUPublicEDKey` | `eauiHgP4PM9ynLekAmo3URrX3ye3HW7D53xOZa5AeYI=` | gleich | EdDSA-Schlüssel, familienweit (FB-07) |
| `SUEnableAutomaticChecks` | `true` | gleich | automatische Prüfung ohne Einwilligungsfrage |
| `CFBundleShortVersionString` / `CFBundleVersion` | `$(MARKETING_VERSION)` 1.1 / `$(CURRENT_PROJECT_VERSION)` 2 | 1.1 / 2 | Anzeigeversion / Vergleichsgrundlage für Sparkle (FB-02) |
| `CFBundleName` / `CFBundleDisplayName` | „Mika+Player" | `MikaPlusPlayer` / — | Name in Dialogen und User-Agent |
| nicht gesetzt | `SUScheduledCheckInterval` (→ 86 400 s), `SUAutomaticallyUpdate` (→ aus), `SUAllowsAutomaticUpdates` (→ Kontrollkästchen sichtbar), `SUSendProfileInfo` (→ aus), `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` (→ aus, FB-08), `SUEnableJavaScript` (→ aus) | | Sparkle-Standardwerte |

### `Sources/Resources/MikaPlusPlayer.entitlements` und effektiv signierte Entitlements

| Entitlement | Datei | im Release-Bundle | Anmerkung |
|---|---|---|---|
| `com.apple.security.app-sandbox` | `false` | `false` | gewollt (README) |
| `com.apple.security.cs.disable-library-validation` | `true` | `true` | FB-04 |
| `com.apple.security.get-task-allow` | — | **`true`** | von Xcode eingefügt (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`), FB-03 |

### `project.yml` und effektive Release-Build-Settings (`MikaPlusPlayer-macOS`)

| Setting | Wert | Quelle |
|---|---|---|
| Paket `Sparkle` | `from: "2.6.0"` → aufgelöst 2.9.3 (Revision `d46d456`) | `project.yml:21-23`, `Package.resolved` (nicht versioniert, FB-12) |
| Abhängigkeit | nur am Target `MikaPlusPlayer-macOS`, nicht im Template | `project.yml:75-79` |
| `CODE_SIGN_STYLE` / `CODE_SIGN_IDENTITY` | `Manual` / `-` (ad hoc) | `project.yml:70-71` |
| `DEVELOPMENT_TEAM` | `CWJM4J4HFN` (bei ad hoc ohne Wirkung, `TeamIdentifier=not set`) | `project.yml:72` |
| `CODE_SIGN_ENTITLEMENTS` | `Sources/Resources/MikaPlusPlayer.entitlements` | `project.yml:74` |
| `ENABLE_HARDENED_RUNTIME` | `NO` | Xcode-Standard, nicht gesetzt |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | `YES` | Xcode-Standard, nicht gesetzt |
| `OTHER_CODE_SIGN_FLAGS` | leer | — |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `1.1` / `2` | `project.yml:34-35` |
| Deployment-Target | macOS 14.0 → `LSMinimumSystemVersion` → `sparkle:minimumSystemVersion` | `project.yml:66` |

### `appcast.xml` (Repository-Wurzel, ausgeliefert von `main`)

| Element | Wert | Herkunft |
|---|---|---|
| `channel/title` | „Mika+Player" | von Hand geändert (`00088ef`) |
| `item/sparkle:version` | `2` | `generate_appcast` |
| `item/sparkle:shortVersionString` | `1.1` | `generate_appcast` |
| `item/sparkle:minimumSystemVersion` | `14.0` | `generate_appcast` |
| `enclosure/@url` | `https://github.com/daumedia/MikaPlusPlayer/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg` | von Hand geändert (`a67d956`); Signatur bleibt gültig, weil sie das DMG signiert, nicht die URL |
| `enclosure/@length` | `36455860` | `generate_appcast` |
| `enclosure/@sparkle:edSignature` | `cVQwA0xr…` | `generate_appcast`, nachgerechnet gültig (AK-11) |
| Versionshinweise, Kanal, Delta, Feed-Signatur | keine | — |

Lokal, nicht versioniert: `dist/appcast.xml` mit Titel „MikaPlusPlayer" und zwei Einträgen (1.1, 1.0), beide
mit `Mukaarts`-URLs — Ausgangspunkt des nächsten `generate_appcast`-Laufs (FB-10).

### Von Sparkle geschriebene Einstellungen

`~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` — geteilt von allen Builds mit dieser Bundle-ID.

| Schlüssel | Typ | Wann |
|---|---|---|
| `SUHasLaunchedBefore` | Bool | erster Start |
| `SULastCheckTime` | Date | jede Prüfung, auch aus dem Test-Host (EC-01) |
| `SUUpdateGroupIdentifier` | Int | zufällig, für gestaffelte Auslieferung |
| `SUSkippedVersion` | String | „Skip This Version" |
| `SUAutomaticallyUpdate` | Bool | Kontrollkästchen im Update-Dialog |
| `SUEnableAutomaticChecks` | Bool | nur, wenn von außen per `defaults` gesetzt (keine Oberfläche) |

Beziehungen, Indizes, Migration: trifft nicht zu. Die SwiftData-Datenbank wird beim Update nicht angefasst;
eine Schema-Migration gibt es nicht (DM-04, FB-16).

## Zugriffsregeln

Wer kann die Update-Kette an welcher Stelle beeinflussen — und was hält ihn auf.

| Wer | Darf lesen | Darf schreiben / auslösen | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | Feed, DMG (öffentlich) | manuelle Prüfung, Update annehmen/überspringen, Auto-Install per Kontrollkästchen | Sparkle-Oberfläche |
| Pusher auf `daumedia/MikaPlusPlayer` `main` | — | Feed-Inhalt für alle `main`-Builds | nur GitHub-Kontozugang; kein Branch-Schutz (FB-09) |
| Inhaber des Namensraums `Mukaarts/MikaPlusPlayer` | — | Feed-Inhalt für alle v1.1-Installationen | nichts — Name derzeit frei (FB-01) |
| Release-Berechtigte des Repos | — | DMG-Assets | GitHub-Kontozugang |
| Inhaber des EdDSA-Privatschlüssels | — | gültige Signaturen für **alle** Mika+-Apps mit diesem Schlüssel | Keychain des Entwicklerrechners; kein Wechsel möglich (FB-06, FB-07) |
| Beliebiger Prozess des Benutzers | Speicher der laufenden App | Debugger anhängen, Bibliotheken per Umgebungsvariable einschleusen | nichts — `get-task-allow`, keine Hardened Runtime (FB-03) |
| Netzwerk dazwischen | — | — | TLS (Feed und DMG über HTTPS); zusätzlich EdDSA für das DMG, nicht für den Feed |

Installiert wird nur, was die EdDSA-Prüfung gegen den Schlüssel der **laufenden** App besteht. Der
Code-Signing-Weg, den Sparkle alternativ zulässt, ist bei ad-hoc-Signatur nie erfüllbar (Designated
Requirement = CDHash).

## Missbrauchsschutz

| Endpunkt | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Feed-Abruf (automatisch) | höchstens einmal je 24 h, Mindestintervall 1 h | — | Sparkle-Standard, `SUScheduledCheckInterval` nicht gesetzt |
| Feed-Abruf (manuell) | keins | — | — |
| DMG-Download | keine Größengrenze; `length` nur für Fehlermeldungen | — | Sparkle-Standard |
| Auslieferung | Limits und Kosten trägt GitHub | — | GitHub |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| GitHub raw (`raw.githubusercontent.com`) | Feed `appcast.xml` aus `main`; v1.1 über den alten Namensraum `Mukaarts` | IP-Adresse, User-Agent `<App-Name>/<Version> Sparkle/2.9.3` | nichts nötig — keine Nutzerdaten; kein Systemprofil |
| GitHub Releases (`github.com` → `release-assets.githubusercontent.com`) | DMG-Download bei Installation | IP-Adresse, User-Agent | wie oben |
| GitHub REST API | **nicht** von der App benutzt; nur von der Website (B10) | — | — |
| Keychain des Entwicklerrechners | EdDSA-Privatschlüssel für `generate_appcast` | — (lokal) | — |

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Zwei App-Targets über ein `targetTemplate`, Sparkle nur am macOS-Target | ein Multiplattform-Target mit `platformFilter` | XcodeGen emittiert bei `platformFilter: macOS` fälschlich `maccatalyst` (CLAUDE.md, `project.yml`-Kommentar) |
| 2 | `SPUStandardUpdaterController` ohne Delegates, Sparkle-Standard-UI | eigene Update-Oberfläche, Delegates für Feed/Kanäle | „analog zu den anderen Mika+ Apps" (Kommentar `SparkleUpdater.swift:5-6`) |
| 3 | Feed als Datei im Repository, ausgeliefert über `raw.githubusercontent.com` von `main` | eigene Domain, GitHub Pages, Release-Asset | kein eigener Server nötig; Grund für `main` statt eines eigenen Zweigs nicht erkennbar |
| 4 | Ad-hoc-Signatur (`CODE_SIGN_IDENTITY "-"`) | Developer ID + Notarisierung | lokal ohne Apple-Team lauffähig (CLAUDE.md, README); Folgen für den Vertrieb nicht mitbedacht (FB-05) |
| 5 | Sandbox aus | Sandbox mit Sparkle-XPC-Diensten | „damit der Sparkle-Updater wie bei den anderen Mika+ Apps funktioniert" (Entitlements-Kommentar); Sparkle 2 unterstützt sandboxed Apps, der Grund ist also Konvention |
| 6 | `disable-library-validation` | weglassen | Kommentar nennt Hardened Runtime, die nicht aktiv ist — Grund für den heutigen Build nicht tragfähig (FB-04) |
| 7 | Ein EdDSA-Schlüssel für die ganze App-Familie | ein Schlüssel je App | Bequemlichkeit, laut README „hier bereits vorhanden und familienweit geteilt" (FB-07) |
| 8 | Automatische Prüfung ohne Einwilligungsfrage | Sparkles Rückfrage beim zweiten Start | ausdrücklich über `SUEnableAutomaticChecks` gesetzt; Begründung nicht erkennbar |
| 9 | `generate_appcast` statt handgeschriebener Einträge | `sign_update` + eigene XML-Pflege | Werkzeug erzeugt Länge, Signatur, Mindestversion; spätere Handänderungen am Feed laufen aber daran vorbei (FB-10) |
| 10 | Veröffentlichen von Hand | `gh release create` im Skript | Grund nicht erkennbar |
| 11 | Sparkle mit `from: 2.6.0`, VLCKit mit `exactVersion` | beide exakt pinnen | Grund für die unterschiedliche Behandlung nicht erkennbar (FB-12) |
| 12 | Feed-Umzug durch schlichtes Ändern von `SUFeedURL` | alten Feed weiter pflegen, Übergangs-Release mit neuer URL | Commit `a67d956` benennt die Folge und verlässt sich auf GitHubs Weiterleitung (FB-01) |

## Abdeckung der Akzeptanzkriterien

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `MikaPlusPlayerApp.swift:35-40` (`CommandGroup(after: .appInfo)`), `SparkleUpdater.canCheckForUpdates` | Menütexte des Systems englisch mangels Lokalisierung |
| AK-02 | `SparkleUpdater.checkForUpdates()` → `SPUStandardUpdaterController`, `SPUNoUpdateFoundInfo`, Sparkle `Base.lproj` | Sprache folgt `CFBundleDevelopmentRegion = en` (OF-01) |
| AK-03 | `SparkleUpdater.init` (`startingUpdater: true`), `Info.plist` `SUEnableAutomaticChecks`, `SPUUpdater.startUpdateCycle` | |
| AK-04 | Sparkle-Standardintervall (`SPUUpdaterSettings.defaultUpdateCheckInterval`) | kein Info.plist-Wert |
| AK-05 | `Info.plist` `SUFeedURL` (`main` bzw. Tag `v1.1`); GitHub raw | Gleichheit hängt an GitHubs Weiterleitung |
| AK-06 | `SPUStandardUserDriver`, `SUUpdateAlert`; `SUAllowsAutomaticUpdates` nicht gesetzt | Feed ohne Versionshinweise |
| AK-07 | Sparkle-Versionsvergleich auf `sparkle:version` ↔ `CFBundleVersion`; `project.yml:35` | |
| AK-08 | `SUAppcastDriver` (Fehlermeldung), Sparkle-Zeitplan | |
| AK-09 | `Autoupdate`: `SUUpdateValidator`, `SUPlainInstaller` (Quarantäne); `SUPublicEDKey` | nicht beobachtet |
| AK-10 | `SUUpdateValidator.validateUpdateForHost` (Z. 336-376), `SPUInstallerDriver` (Z. 108-113); ad-hoc-Signatur aus `project.yml:70-71` | `SUVerifyUpdateBeforeExtraction` nicht gesetzt → Prüfung nach dem Entpacken |
| AK-11 | `appcast.xml` (`edSignature`, `length`), GitHub-Release-Asset `v1.1`, `Info.plist` `SUPublicEDKey` | nachgerechnet mit CryptoKit |
| AK-12 | Fehlen von `SURequireSignedFeed` in `Info.plist` | Lücke → FB-08 |
| AK-13 | `project.yml:70-74`, `MikaPlusPlayer.entitlements:7-8` | |
| AK-14 | `project.yml:71` (ad hoc), `make-dmg.sh` (keine DMG-Signatur), fehlender Notarisierungsschritt | ⚠, FB-05 |
| AK-15 | Xcode-Standard `ENABLE_HARDENED_RUNTIME = NO`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`; `build-macos.sh` baut mit `build` statt `archive`/Export | ⚠, FB-03 |
| AK-16 | `MikaPlusPlayer.entitlements:11-12` | ⚠, FB-04 |
| AK-17 | `scripts/release.sh`, `build-macos.sh`, `make-dmg.sh` | nicht ausgeführt |
| AK-18 | `make-dmg.sh:28-36` | |
| AK-19 | `release.sh:22-23`, `make-dmg.sh:10` | |
| AK-20 | `release.sh:26-29`, lokales `dist/appcast.xml`, `generate_appcast`-Standard `--maximum-versions 3` | ⚠, FB-10 |
| AK-21 | `project.yml:34-35`, `release.sh:19` (liest nur `CFBundleShortVersionString`), README „ggf." | ⚠, FB-02 |
| AK-22 | `project.yml:21-23`, `.gitignore:2` | FB-12 |
| AK-23 | Sparkle `SPUUserAgent+Private.m`, `SUHost.name`; `SUSendProfileInfo` nicht gesetzt | |
| AK-24 | Sparkle `SPUUpdaterSettings`, `SUHost` (UserDefaults der Bundle-ID) | |
| AK-25 | Sparkle-Downloader; GitHub; `web/app/privacy/page.tsx:57-59` | Offenlegung unvollständig → FB-15 |
| AK-26 | GitHub-Repository-Einstellungen (`main` ungeschützt), `raw.githubusercontent.com`-Cache | FB-09 |
| AK-27 | v1.1-`Info.plist` `SUFeedURL`; GitHub-Namensraum `Mukaarts` | ⚠, FB-01 — keine Komponente schützt davor |
| AK-28 | `Info.plist` `SUPublicEDKey` (familienweit), `SUInstaller.installSourcePathInUpdateFolder` | ⚠, FB-07 |
| AK-29 | `.gitignore` (`dist/`, `*.dmg`), Keychain-Nutzung in `generate_appcast`, `release.sh` ohne Geheimnisse | |
| AK-30 | ad-hoc Designated Requirement (CDHash), `SUUpdateValidator.m:373-376` | ⚠, FB-06 — keine Komponente ermöglicht Rotation |

Jedes AK hat eine Zuordnung. Umgekehrt ohne AK: keine Zeile Code in `SparkleUpdater.swift` oder den Skripten.
Nicht durch ein AK gedeckt ist allein der Hinweistext am Ende von `release.sh` („vorher mit Developer ID
signieren + notarisieren"), der auf den README-Weg aus FB-13 verweist.
