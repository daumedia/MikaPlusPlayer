# B09 · Auto-Update — Systemdesign

Status: Zielentwurf vom 2026-10-02 nach den Entscheidungen vom 2026-10-01 (`sdd-klaeren`), gegengeprüft am 2026-10-02 ·
Feature-Status bleibt `review` (Bestandsfeature) · vom Betreiber am 2026-10-02 als Bauauftrag freigegeben: `/sdd-build B09` baut
die freigegebenen Befunde **und** diesen Entwurf · Stack-Profil: `swiftui-macos` (Vertrieb) + `swiftui-ios` (Projektstruktur,
XcodeGen) · ersetzt den rekonstruierten Ist-Entwurf vom 2026-09-15 (in der Git-Historie)

**Kein Code in diesem Dokument.** Es wird gelesen und freigegeben, nicht ausgeführt. Namen von Typen, Schlüsseln und
Werkzeugen stehen hier nur als Bezeichnung.

## Überblick

Die macOS-App bettet Sparkle 2.9.3 ein und sucht damit einmal täglich nach Updates. Neu ist dreierlei. Erstens wird jedes
Release mit dem Developer-ID-Zertifikat des Teams signiert, notarisiert und als signiertes, „geheftetes“ DMG ausgeliefert;
Gatekeeper nimmt die App dann ohne Umweg an, und ein späterer Wechsel des Update-Schlüssels wird möglich. Zweitens nimmt die
App ab Version 1.2 nur noch einen signierten Update-Feed an. Drittens bekommt das App-Menü zwei Schalter für die automatische
Prüfung und Installation, die App deklariert sich als deutschsprachig (Sparkles Fenster und das Systemmenü sollen damit
deutsch erscheinen, mit bekannten Ausnahmen), und Debug-Builds samt Test-Host berühren die installierte App nicht mehr, weil
sie eine eigene Bundle-ID tragen. Version 1.2 ist zugleich das Übergangs-Release, das jede v1.1-Installation, die das Update
annimmt, vom freien GitHub-Namen `Mukaarts` auf den `daumedia`-Feed holt (BF-01).

## Was sich gegenüber dem Bestand ändert

| Bereich | Heute (`main`, 2026-10-02) | Entwurf | Grundlage |
|---|---|---|---|
| Signatur Release | ad hoc, Hardened Runtime an, kein `get-task-allow` (seit 2026-09-16) | Developer ID Application, Team `CWJM4J4HFN`, über Archivieren und Exportieren | BF-03, BF-05 |
| Notarisierung | keine | DMG wird notarisiert und geheftet | BF-03 |
| DMG | unsigniert | signiert mit Developer ID, eigener Bezeichner | BF-03, BF-05 |
| `disable-library-validation` | gesetzt (bei ad hoc nötig) | entfällt | BF-09 |
| Feed | `release.sh` signiert ihn, die App verlangt es nicht | App verlangt ab 1.2 einen signierten Feed | BF-08, OF-07, AK-12 |
| Gegenprüfung `b09_release_check.sh` | Developer ID, Notarisierung, DMG-Signatur nur „offen“; fremde Download-Adressen, leere Version, Eintragszahl ungeprüft | alles davon blockierend; neue Stufen | BF-03, BF-47, BF-48, BF-50 |
| `release.sh` | bricht ohne `generate_appcast` stumm ab | meldet es | BF-51 |
| Sprache | Entwicklungssprache Englisch, keine Lokalisierung | Entwicklungssprache Deutsch, einzige Lokalisierung `de` — iOS und macOS | OF-01, AK-01, AK-02 |
| App-Menü | ein Eintrag „Nach Updates suchen …“, Zustand direkt im Menü-Block gelesen | drei Einträge in einer eigenen Menü-Ansicht, Zustand beobachtet | BF-18, OF-02, AK-31 |
| Bundle-ID | Debug, Test-Host und Release gleich (`lu.daumedia.MikaPlusPlayer`) | Debug und Test-Host `lu.daumedia.MikaPlusPlayer.debug` | BF-119, OF-10 |
| Sparkle | startet überall, auch im Test-Host | startet nicht im Test-Host; in Debug ohne automatische Prüfung | BF-49, OF-10 |
| Fensterwiederherstellung | Test-Host kann von macOS als normale App wieder gestartet werden | Test-Host startet mit „Fensterzustand ignorieren“ | BF-119 |
| Hinweis „Datenbank neu angelegt / nicht verfügbar“ | nennt nur den Ordner, auch unter iOS | nennt Zugangsdaten im Schlüsselbund und „Alle Daten entfernen“, unter iOS ohne Pfad | OF-08 |
| Version | `MARKETING_VERSION` 1.1, Build 3 | 1.2, Build mindestens 3 | OF-06 |
| Branch `main` | ungeschützt | Ruleset ohne Umgehungsliste: kein Force-Push, kein Löschen, Änderungen nur per PR (ohne fremdes Review) | BF-07 |

Unverändert bleiben: Sparkle 2.9.3 (exakt gepinnt), Feed-Adresse `daumedia`, öffentlicher Schlüssel (familienweit, BF-06
zurückgestellt), Prüfintervall, Sandbox aus, `SUVerifyUpdateBeforeExtraction`, der Weg des Feeds über `raw.githubusercontent.com`.

## Seiten und Routen

Keine eigenen Ansichten außer den Menüeinträgen. Orte, an denen der Nutzer dem Feature begegnet:

| Ort | Zweck | Zugang |
|---|---|---|
| App-Menü „Mika+Player“ → „Nach Updates suchen …“ (direkt nach „Über Mika+Player“) | manuelle Prüfung | jeder Nutzer, nur macOS |
| App-Menü → „Automatisch nach Updates suchen“ (Häkchen) | tägliche Prüfung an/aus | jeder Nutzer, nur macOS |
| App-Menü → „Updates automatisch installieren“ (Häkchen) | gefundene Updates im Hintergrund laden und beim Beenden installieren | jeder Nutzer, nur macOS; ausgegraut, solange die automatische Prüfung aus ist |
| Sparkle-Fenster (Prüfung läuft, Update verfügbar, aktuell, Fehler) | Status, Angebot, Installation | von Sparkle erzeugt, Texte aus Sparkles deutscher Übersetzung, mit den Ausnahmen aus OF-13 |
| Sparkles Installationsfenster (Updater-Hilfsprogramm) | Fortschritt und Neustart | eigener Prozess; folgt vermutlich der Systemsprache (abgeleitet, OF-13) |
| Website `/download`, `/changelog` | Erstinstallation | gehört zu B10 |

Nach dem Erfolg: Nach „Installieren“ im Update-Fenster beendet Sparkle die App, ersetzt sie und startet sie neu (AK-09); bei
automatischer Installation wird beim nächsten Beenden ersetzt, ohne Fenster und ohne Neustart. Nach dem Abhaken eines Schalters
bleibt das Menü, wie es ist, mit neuem Häkchen.

## Komponentenstruktur

### In der App (Laufzeit, nur macOS)

```
MikaPlusPlayerApp
├── Update-Dienst (SparkleUpdater, beobachtbar)   wird beim Start angelegt; startet Sparkle in Release- und
│   │                                             Debug-Builds, nicht im Test-Host (Entscheidung 8)
│   ├── gespiegelte Werte               Prüfung möglich · automatisch prüfen · automatisch installieren ·
│   │                                   automatisch installieren erlaubt — je per Beobachtung von Sparkles Updater
│   ├── Aktion „jetzt prüfen“           startet die sichtbare Prüfung
│   └── Schreibwege „automatisch prüfen“ / „automatisch installieren“
│                                       setzen Sparkles eigene Einstellung, nur auf Nutzeraktion, nie beim Start
├── App-Menü, nach „Über Mika+Player“
│   └── Update-Menü (eigene Ansicht)    liest die gespiegelten Werte in ihrem eigenen Rumpf (Entscheidung 6)
│       ├── Schaltfläche „Nach Updates suchen …“        aktiv, wenn „Prüfung möglich“
│       ├── Schalter „Automatisch nach Updates suchen“  zeigt „automatisch prüfen“
│       └── Schalter „Updates automatisch installieren“ zeigt „automatisch installieren“,
│                                                       gesperrt, wenn „automatisch installieren erlaubt“ falsch ist
└── App-Menü, Position Einstellungen: „Alle Daten entfernen …“   unverändert (B03); löscht auch Sparkles
                                                                Einstellungen der laufenden Bundle-ID
Hinweise „Datenbank neu angelegt“ / „Datenbank nicht verfügbar“  Texte aus dem Persistenz-Dienst (OF-08, unten)
Sparkle.framework 2.9.3 (eingebettet, beim Export mit Developer ID neu signiert)
├── Updater                Zeitplan, Feed-Abruf, Feed-Signaturprüfung, Versionsvergleich, Einstellungen
├── Standard-Oberfläche    alle Sparkle-Dialoge
├── Autoupdate             prüft das DMG vor dem Entpacken (EdDSA, ersatzweise Developer-ID-Signatur), ersetzt die App
└── Updater-Hilfsprogramm  Installationsfortschritt (eigener Prozess)
```

Wiederverwendet wird: der vorhandene Update-Dienst mit seinem Beobachtungsmuster (heute nur für „Prüfung möglich“), der
vorhandene Wächter für Testläufe (`AppEnvironment`), der vorhandene Hinweis-Mechanismus für die Datenbank.

### Zustände des Update-Menüs

| Zustand | „Nach Updates suchen …“ | „Automatisch nach Updates suchen“ | „Updates automatisch installieren“ |
|---|---|---|---|
| leer — Sparkle nicht gestartet (nur Test-Host) | inaktiv | inaktiv, zeigt den gespeicherten Sparkle-Wert der Test-Bundle-ID | inaktiv |
| ladend — geplante Hintergrundprüfung läuft | inaktiv (Sparkle meldet „Prüfung nicht möglich“) | bedienbar | bedienbar, wenn automatische Prüfung an |
| ladend — vom Nutzer gestartete Prüfung läuft | **aktiv** (Sparkle-Verhalten: ein Klick holt ein angezeigtes Update-Fenster nach vorn, sonst wirkungslos; OF-11) | bedienbar | wie oben |
| Fehler — Feed nicht erreichbar oder falsch signiert | aktiv | bedienbar | wie oben |
| Fehler — Updater startet nicht (Konfigurationsfehler, z. B. Feed-Pflicht ohne Prüfung vor dem Entpacken) | inaktiv | inaktiv | inaktiv; Sparkle zeigt seinen eigenen Fehlerdialog (englisch, OF-13); die Gegenprüfung „nach dem Export“ verhindert, dass ein solches Release entsteht |
| gefüllt — Ruhezustand | aktiv | Häkchen nach Einstellung | Häkchen nach Einstellung; ausgegraut ohne Häkchen, solange automatische Prüfung aus (OF-12) |

### Ablauf einer Prüfung

```
Start (Release- oder Debug-Build, nicht Test-Host) ──▶ Sparkle startet
        │  „automatisch prüfen“: Nutzerwert, sonst Vorgabe der Konfiguration (Release an, Debug aus)
        ├─ aus  → keine geplante Prüfung
        ▼ an
  letzte Prüfung fehlt oder ≥ 24 h her? ── ja → sofort Hintergrundprüfung
        │ nein → Hintergrundprüfung 24 h nach der letzten (während die App läuft, sonst beim nächsten Start)
Menü „Nach Updates suchen …“ ───────────────────────────────────────▶ sichtbare Prüfung
        ▼
  Feed laden (HTTPS, raw.githubusercontent.com/daumedia/…/main/appcast.xml)
        ▼
  Feed-Signatur prüfen (ab 1.2 Pflicht, öffentlicher Schlüssel der laufenden App)
        ├─ fehlt / ungültig → Feed verworfen: sichtbare Prüfung zeigt Fehler, Hintergrundprüfung schweigt
        │                     (nach 20 Tagen durchgehender Fehlschläge: eingeschränkter Modus, OF-15)
        ▼ gültig
  höhere Build-Nummer und Systemversion erfüllt? ── nein → „aktuell“ (nur bei sichtbarer Prüfung)
        ▼ ja
  ├─ sichtbar bzw. „automatisch installieren“ aus → Update-Fenster → „Installieren“ → DMG laden → prüfen → Ersetzen, Neustart
  └─ Hintergrund und „automatisch installieren“ an → ohne Fenster laden → prüfen → beim nächsten Beenden der App ersetzen
Prüfen des DMG vor dem Entpacken: EdDSA mit dem Schlüssel der laufenden App
        ├─ gültig → entpacken, App ersetzen, Quarantäne entfernen
        └─ ungültig → nur wenn die laufende App Developer-ID-signiert ist: DMG mit Developer ID desselben Teams?
                      ├─ ja → Schlüsselwechsel-Weg: neue App muss das DMG mit ihrem neuen Schlüssel bestätigen
                      └─ nein → abgelehnt, App unverändert
```

### Release-Ablauf (Entwicklerseite)

Reihenfolge ist Teil des Entwurfs: Jeder Schritt verändert Bytes, die ein späterer Schritt signiert. Nach der EdDSA-Signatur
werden weder DMG noch Feed mehr angefasst.

```
scripts/release.sh                                            GH_REPO = daumedia/MikaPlusPlayer
├── 0  Projekt erzeugen                 xcodegen (die Projektdatei ist nicht versioniert; trägt die Sprache und die Signatur)
├── 1  Gegenprüfung „vor-build“          Version neu und nicht leer, Build-Nummer größer, Mukaarts-Sperre, Notar-Profil benannt
├── 2  Archivieren                      Schema MikaPlusPlayer-macOS, Konfiguration Release (ersetzt den heutigen Build-Schritt)
├── 3  Exportieren „Developer ID“        Exportoptionen aus scripts/ (Methode Developer ID, Team, manuelle Signatur)
│                                       → App samt Sparkle-Hilfsprogrammen und VLCKit mit Developer ID und Zeitstempel
├── 4  Gegenprüfung „nach-build“         strenge Signaturprüfung jedes Teils, Team-ID, Zeitstempel, Runtime, Entitlements,
│                                       Info.plist-Werte und Sprache — noch keine Gatekeeper-Bewertung (nicht notarisiert)
├── 5  DMG bauen                        wie bisher (create-dmg, sonst hdiutil), Format UDZO
├── 6  DMG signieren                    Developer ID Application, Zeitstempel, eigener Bezeichner
├── 7  Notarisieren                     nur das DMG; Ergebnis über das maschinenlesbare Ergebnis „Accepted“ prüfen,
│                                       Notar-Protokoll immer abholen und ablegen
├── 8  Heften                           Ticket an das DMG, danach Validierung
├── 9  Gegenprüfung „nach-heften“        Gatekeeper nimmt DMG und App an, Ticket gültig
├── 10 Feed-Eintrag erzeugen            generate_appcast über das fertige DMG (EdDSA, familienweiter Schlüssel), Obergrenze
│                                       der behaltenen Einträge ausdrücklich gesetzt
├── 11 Feed signieren                   sign_update über appcast.xml
├── 12 Gegenprüfung „feed“               Feed-Signatur, Download-Adressen, Eintragszahl, Enclosure-Signatur
└── 13 Ausgabe der Folgeschritte         (a) Pflichtproben vor dem Veröffentlichen, (b) Release anlegen, DMG hochladen,
                                        appcast.xml per PR auf main, (c) Gegenprüfung „nach-merge“
```

**Pflichtproben vor dem Veröffentlichen** (Schritt 13 a; ohne sie wird nicht veröffentlicht):

| Probe | Wer | Was | Grundlage |
|---|---|---|---|
| Kurztest Wiedergabe | Betreiber (Zugang zum Anbieter) | notarisierter Release-Build, echte Sender als HLS und MPEG-TS, mit Ton | OF-09 |
| Übergangsprobe 1.1 → 1.2 | Entwickler | eine installierte v1.1 (ad hoc) nimmt einen notarisierten Test-Build mit hoher Build-Nummer aus einem eigenen Test-Feed an; danach liest sie den `daumedia`-Feed und verlangt die Feed-Signatur | Entscheidung 14 |
| Offline-Erststart | Entwickler | App aus dem gehefteten DMG nach /Applications kopieren, Netz trennen, erster Start | Entscheidung 2 |

**Gegenprüfung „nach-merge“** (Schritt 13 c): Die ausgelieferte Datei wird zuerst mit der gemergten Datei verglichen (gleiche
Prüfsumme; bis zu fünf Minuten wiederholen, weil GitHub mit `max-age=300` zwischenspeichert), dann ihre Signatur geprüft — an
der `daumedia`-Adresse **und** an der alten `Mukaarts`-Adresse, die v1.1 abfragt (beide müssen denselben Inhalt mit dem
1.2-Eintrag liefern, BF-01).

Ausweichweg, falls Archivieren/Exportieren für das XcodeGen-Projekt scheitert (Entscheidung 1): Bauen wie heute, danach jede
eingebettete Komponente einzeln mit Developer ID, Zeitstempel und Runtime neu signieren, von innen nach außen, App zuletzt —
nie mit der „tiefen“ Signier-Option; Sparkles Downloader-Dienst behält dabei seine Entitlements.

### Gegenprüfungen (`scripts/b09_release_check.sh`)

Das Skript kennt heute die Stufen „vor-build“, „nach-build“ und „feed“ und drei Ergebnisse (Befund, offen, in Ordnung). Die
Stufennamen bleiben; „nach-build“ prüft künftig das exportierte Bundle. Neu sind „nach-heften“ und „nach-merge“. Punkte, die
bisher nur „offen“ waren, werden Befunde. Alle bestehenden Prüfungen bleiben, ausdrücklich: `SUFeedURL` im Bundle ist die
`daumedia`-Adresse, `SUPublicEDKey` im Bundle gleich Info.plist und unverändert gegenüber v1.1 (Sparkle erlaubt keinen
gleichzeitigen Wechsel von Code-Signatur und Schlüssel), Sperre gegen `Mukaarts`.

| Stufe | Prüfung | bei Abweichung |
|---|---|---|
| vor-build | `MARKETING_VERSION` nicht leer und noch nicht im Feed; Build-Nummer größer als jede im Feed | Befund, Abbruch (BF-50) |
| vor-build | Notar-Profil per Umgebungsvariable benannt und im Schlüsselbund vorhanden (entfällt im Probemodus) | Befund, Abbruch |
| nach-build | jede Komponente (App, Sparkle.framework und seine Hilfsprogramme, VLCKit.framework): Developer ID Application, Team `CWJM4J4HFN`, sicherer Zeitstempel, Runtime bei Programmen; strenge Signaturprüfung | Befund |
| nach-build | Entitlements der App ohne `get-task-allow` und ohne `disable-library-validation` | Befund |
| nach-build | Bundle-ID `lu.daumedia.MikaPlusPlayer`; Info.plist verlangt signierten Feed **und** Prüfung vor dem Entpacken (sonst startet der Updater nicht); Entwicklungssprache `de`, Lokalisierung `[de]` | Befund |
| nach-heften | DMG mit Developer ID signiert, Ticket geheftet und gültig, Gatekeeper nimmt DMG und App an | Befund |
| feed | Feed-Signatur gültig (gegen den öffentlichen Schlüssel aus Info.plist) | Befund |
| feed | in **allen** Einträgen nur Download-Adressen unter `github.com/daumedia/MikaPlusPlayer/releases/download/` | Befund (BF-48) |
| feed | die Prüfung verlangt genau die Einträge, die `generate_appcast` nach der in `release.sh` gesetzten Obergrenze behält | Befund (BF-47) |
| feed | Enclosure-Signatur des neuen Eintrags passt zum fertigen DMG | Befund |
| nach-merge | ausgelieferte Datei an beiden Adressen gleich der gemergten, Signatur gültig | Befund (Meldung an den Entwickler) |

**Prüfnähte für Tests:** Jeder neue Schritt (Archivieren, Exportieren, DMG-Signatur, Notarisieren, Heften) ist wie die heutigen
Werkzeug-Übersteuerungen von außen ersetzbar, und es gibt einen ausdrücklichen Probemodus ohne Developer ID und Notarisierung,
in dem die Developer-ID-Prüfungen „offen“ statt „Befund“ melden. Der strenge Modus der Gegenprüfung bleibt. So laufen die
Release-Skript-Tests weiter offline in Attrappen.

## Datenmodell

Keine eigenen Entitäten. An die Stelle des Datenmodells tritt Konfiguration. Änderungen sind markiert.

### `Sources/Resources/Info.plist`

| Schlüssel | Wert | Änderung | Bedeutung |
|---|---|---|---|
| `CFBundleDevelopmentRegion` | `$(DEVELOPMENT_LANGUAGE)`; soll nach der Projektoption zu `de` auflösen (abgeleitet, am Bundle zu prüfen) | **geändert** (über `project.yml`) | Standardsprache des Bundles |
| `CFBundleLocalizations` | `[de]` | **neu** | einzige Lokalisierung; Apples Weg für Apps ohne Sprachordner |
| `CFBundleAllowMixedLocalizations` | nicht gesetzt | bewusst nicht gesetzt | Apple beschreibt den Schlüssel für Werkzeuge; welche Sprache Frameworks damit wählen, ist nicht belegt |
| `SUFeedURL` | `https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml` | unverändert | Feed |
| `SUPublicEDKey` | familienweiter Schlüssel | unverändert (BF-06 zurückgestellt) | EdDSA-Prüfung |
| `SUEnableAutomaticChecks` | Release an, Debug aus | **je Konfiguration** | Vorgabe; der Nutzerwert aus dem Menü hat Vorrang |
| `SUVerifyUpdateBeforeExtraction` | an | unverändert | Prüfung vor dem Entpacken; Voraussetzung für die Feed-Pflicht |
| `SURequireSignedFeed` | an | **neu ab 1.2** | Feed ohne gültige Signatur wird verworfen |
| `SUSignedFeedFailureExpirationInterval` | nicht gesetzt (Vorgabe 20 Tage) | bewusst nicht gesetzt (OF-15) | Frist, nach der Sparkle einen dauerhaft falsch signierten Feed eingeschränkt doch nutzt; Notweg bei Schlüsselverlust |
| `SUAllowsAutomaticUpdates` | nicht gesetzt | bewusst nicht gesetzt | dann gilt: automatisches Installieren nur bei automatischer Prüfung |
| `CFBundleShortVersionString` / `CFBundleVersion` | 1.2 / mindestens 3 | **geändert** (`project.yml`) | Anzeigeversion / Vergleichsgrundlage |

Die Info.plist ist für iOS und macOS dieselbe; die `SU*`-Schlüssel wirken nur dort, wo Sparkle läuft. Die Sprachschlüssel
wirken auf beiden Plattformen (Entscheidung 5).

### `Sources/Resources/MikaPlusPlayer.entitlements`

| Entitlement | Wert | Änderung |
|---|---|---|
| `com.apple.security.app-sandbox` | aus | unverändert (Direktvertrieb mit Sparkle) |
| `com.apple.security.cs.disable-library-validation` | — | **entfällt** (BF-09): Sparkle und VLCKit tragen nach dem Export dieselbe Team-ID wie die App |

### `project.yml` (danach `xcodegen generate`)

| Einstellung | Wo | Wert | Änderung |
|---|---|---|---|
| Entwicklungssprache | Projektoptionen | `de` | **neu**; wirkt auf iOS, macOS und Test-Bundle |
| `PRODUCT_BUNDLE_IDENTIFIER` | Target `MikaPlusPlayer-macOS`, nur Konfiguration Debug | `lu.daumedia.MikaPlusPlayer.debug` | **neu**; nicht im gemeinsamen Template, damit iOS unverändert bleibt; Release unverändert |
| Vorgabe automatische Prüfung | Target `MikaPlusPlayer-macOS`, je Konfiguration | Release an, Debug aus | **neu**; Weg (Build-Einstellung in Info.plist oder Startargument der Run-Aktion) legt `sdd-build` fest |
| `CODE_SIGN_IDENTITY` | Target `MikaPlusPlayer-macOS`, nur Release | Developer ID Application | **geändert**; Debug und Test-Bundle bleiben ad hoc |
| `CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM` | macOS-Target | manuell, `CWJM4J4HFN` | unverändert |
| `ENABLE_HARDENED_RUNTIME`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | macOS-Target, nur Release | an / aus | unverändert (seit 2026-09-16) |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | Template | `1.2` / mindestens `3` | **geändert** |
| Testaktion des Schemas `MikaPlusPlayer-macOS` | Schema | Startargument „Fensterzustand ignorieren“ und eine eigene Umgebungsmarke für den Test-Host | **neu**; die Testaktion übernimmt danach keine Argumente und Umgebung der Run-Aktion mehr (die `TEST_RUNNER_…`-Variablen der Tests sind davon nicht betroffen, sie kommen von `xcodebuild`) |
| Paket Sparkle | Pakete | exakt 2.9.3 | unverändert |

### Einstellungen (Benutzervorgaben) je Bundle-ID

Sparkle schreibt seine Einstellungen in die Vorgaben der laufenden Bundle-ID. Release (`lu.daumedia.MikaPlusPlayer`) und
Debug/Test-Host (`….debug`) haben damit getrennte Werte.

| Schlüssel | Typ | Wer schreibt | Bedeutung |
|---|---|---|---|
| `SUEnableAutomaticChecks` | Wahrheitswert | **neu über das Menü**, sonst Sparkle bzw. `defaults` | automatische Prüfung; Vorrang vor der Vorgabe |
| `SUAutomaticallyUpdate` | Wahrheitswert | **neu über das Menü**, weiterhin über das Kontrollkästchen im Update-Fenster | automatisch installieren; bleibt gespeichert, wenn die Prüfung aus- und wieder eingeschaltet wird |
| `SULastCheckTime`, `SUHasLaunchedBefore`, `SUUpdateGroupIdentifier`, `SUSkippedVersion` | wie bisher | Sparkle | Zeitplan und Nutzerwahl |
| `SUInitialFailedFeedSigningValidationDate` | Datum | Sparkle | **neu** relevant: Beginn einer Serie fehlgeschlagener Feed-Prüfungen (Frist 20 Tage, OF-15) |

Keine eigenen Schlüssel der App für diese Schalter: Die App liest und schreibt ausschließlich Sparkles Einstellungen
(Entscheidung 7). Löschregel: „Alle Daten entfernen …“ (B03) löscht die Vorgaben der laufenden Bundle-ID und damit auch diese
Werte; danach gelten wieder die Vorgaben der Konfiguration. Sparkles Zwischenspeicher für heruntergeladene Updates
(`Caches/<Bundle-ID>/…`) räumt Sparkle selbst; „Alle Daten entfernen“ fasst ihn nicht an (unverändert gegenüber heute).

### Weitere Daten, die an der Bundle-ID hängen

Durch die eigene Debug-ID getrennt, ohne weitere Änderung: Datenbank (`Application Support/<Bundle-ID>/`), Sparkle-Zwischenspeicher,
Sparkles Installer-Dienstnamen. **Nicht** von selbst getrennt und deshalb Teil dieses Entwurfs:

| Stelle | Heute | Entwurf |
|---|---|---|
| Dienstname der Zugangsdaten im Schlüsselbund (normaler Start) | fest `lu.daumedia.MikaPlusPlayer.xtream` | aus der Bundle-ID abgeleitet: `<Bundle-ID>.xtream` — für das Release identisch zu heute (keine Migration), für Debug `….debug.xtream` |
| Dienstname im Test-Host | je Lauf `lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>` | **unverändert** (die Wächter der Tests prüfen genau dieses Präfix) |
| Übernahme der alten `Application Support/default.store` | durch jede Bundle-ID | nur, wenn die **übergebene** Bundle-ID die Release-ID ist (die Regel hängt am Parameter, nicht am laufenden Bundle; so bleiben die Übernahme-Tests mit übergebener Release-ID gültig) |

### `appcast.xml` (Repository-Wurzel, ausgeliefert von `main`)

| Element | Wert | Änderung |
|---|---|---|
| Einträge | 1.1 (Build 2), neu 1.2 (Build ≥ 3) | **neuer Eintrag** |
| Download-Adressen | nur `github.com/daumedia/MikaPlusPlayer/releases/download/v<Version>/MikaPlusPlayer-v<Version>.dmg` | durch die Gegenprüfung erzwungen |
| Enclosure-Signatur | EdDSA über das fertige, geheftete DMG | Reihenfolge erzwungen |
| Feed-Signatur | Signaturblock am Dateiende, über alle Bytes davor | **neu**; Pflicht für 1.2+; v1.1 ignoriert ihn |
| Zeilenenden | unverändert ausgeliefert | **neu**: Git behandelt die Datei als unveränderlich (keine Zeilenende-Umwandlung), damit die Signatur hält |
| Versionshinweise | keine | unverändert (B10 BF-123: Website verspricht keine) |

### Neue Dateien

| Datei | Inhalt | Geheimnisse |
|---|---|---|
| Exportoptionen unter `scripts/` | Methode Developer ID, Team, manuelle Signatur, Zertifikat „Developer ID Application“ | keine |
| Git-Attribute für `appcast.xml` | keine Zeilenende-Umwandlung | keine |

Notar-Zugangsdaten (App-spezifisches Passwort oder API-Schlüssel) liegen **nur** als benanntes Profil im Anmelde-Schlüsselbund
des Release-Rechners; das Skript kennt nur den Profilnamen aus einer Umgebungsvariable.

### Hinweise bei nicht lesbarer Datenbank (OF-08)

Kein neues Feld; geändert werden die Inhalte der beiden vorhandenen Hinweise. Sie enthalten: (1) **nur wenn die Datenbank
tatsächlich beiseitegelegt wurde**: dass sie nicht gelöscht, sondern beiseitegelegt ist, unter macOS mit Ordnerpfad und „Im Finder
zeigen“, unter iOS ohne Pfad; ist das Beiseitelegen selbst gescheitert, sagt der Hinweis, dass die Datenbank unverändert am
bisherigen Ort liegt; (2) dass die Zugangsdaten der Xtream-Playlists im Schlüsselbund erhalten bleiben; (3) „Alle Daten
entfernen …“ als Löschweg (macOS: App-Menü; iOS: Menü der Playlist-Übersicht).

## Zugriffsregeln

Wer kann die Update-Kette an welcher Stelle beeinflussen — und was hält ihn auf.

| Wer | Darf lesen | Darf schreiben / auslösen | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | Feed, DMG (öffentlich) | manuelle Prüfung; automatische Prüfung und Installation an/aus; Update annehmen/überspringen | Sparkle-Einstellungen der eigenen Bundle-ID |
| Schreibberechtigte auf `daumedia/MikaPlusPlayer` | — | `appcast.xml` auf `main` nur per PR (ohne fremdes Review); kein Force-Push, kein Löschen | GitHub-Ruleset auf `main` **ohne Umgehungsliste** (BF-07), 2FA des Kontos (OF-04); ab 1.2 zusätzlich Feed-Signatur |
| Inhaber des Namens `Mukaarts` (frei) | — | Feed aller v1.1-Installationen, die 1.2 noch nicht angenommen haben | nichts — nur das Übergangs-Release beendet die Abhängigkeit, je aktualisierter Installation (BF-01) |
| Release-Berechtigte | — | DMG-Assets | GitHub-Konto mit 2FA. Gatekeeper und Notarisierung schützen nur gegen unsignierte oder nicht notarisierte Dateien; ein fremd notarisiertes DMG nähmen sie an |
| Inhaber des EdDSA-Privatschlüssels | — | gültige Update-Archive und Feed-Signaturen für **alle** Mika+-Apps mit diesem Schlüssel | Schlüsselbund jedes Rechners mit dem Schlüssel; offline gesicherte Kopie (OF-05). **Die Developer-ID-Signatur ist für normale Updates keine zweite Hürde**: Sparkle nimmt ein Archiv an, dessen EdDSA-Signatur gültig ist, und vergleicht dann keine Team-ID *(Sparkle 2.9.3, `SUUpdateValidator`, gelesen 2026-10-02)* |
| Inhaber des Developer-ID-Zertifikats | — | Code-Signatur; zusammen mit dem Feed der Ausweichweg für einen Schlüsselwechsel | Schlüsselbund des Release-Rechners |
| Debug-Build, Test-Host | eigene Daten unter `….debug` | nichts an Daten, Einstellungen, Schlüsselbund-Einträgen oder Sparkle-Zustand der installierten App | eigene Bundle-ID, abgeleiteter Schlüsselbund-Dienstname, keine Altbestands-Übernahme. Gilt **nicht** für Release-Konfiguration: Läufe in Release (Messungen, QA) laufen weiter unter der echten ID — siehe *Folgen* |
| Beliebiger Prozess des Benutzers | — | kein Anhängen an die Release-App, keine fremden Bibliotheken | Hardened Runtime, kein `get-task-allow`, Library Validation ohne Ausnahme |
| Netzwerk dazwischen | — | — | TLS; EdDSA für DMG und (ab 1.2) Feed |

## Missbrauchsschutz

| Endpunkt | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| Feed-Abruf automatisch | höchstens einmal je 24 h, abschaltbar | — | Sparkle-Vorgabe; Nutzerschalter im Menü |
| Feed-Abruf manuell | keins | — | — |
| Feed-Signatur fehlerhaft | 20 Tage verworfen, danach eingeschränkter Modus (Updates nur nach Bestätigung, ohne Hinweise und Links, ohne automatischen Download) | Notweg bei Schlüsselverlust | Sparkle-Vorgabe, bewusst nicht überschrieben (OF-15) |
| Notarisierung (Entwickler) | 75 Einreichungen je Tag | Release wartet | Apple |
| Auslieferung Feed und DMG | Limits und Kosten trägt GitHub | — | GitHub |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| GitHub raw (`raw.githubusercontent.com`) | Feed | IP-Adresse, User-Agent `Mika+Player/<Version> Sparkle/2.9.3` | nichts nötig — keine Nutzerdaten, kein Systemprofil |
| GitHub Releases | DMG-Download | IP-Adresse, User-Agent | wie oben |
| Apple Notardienst (nur Entwicklerseite) | Notarisierung | das signierte DMG mit der App | enthält keine Nutzerdaten; Zugangsdaten nur im Schlüsselbund-Profil |
| Apple Zeitstempeldienst (nur Entwicklerseite) | sicherer Zeitstempel der Signaturen | Prüfsummen der signierten Teile | — |
| Apple, durch macOS selbst (nicht durch die App) | Gatekeeper prüft beim ersten Start ggf. Notarisierung und Widerruf | Angaben des Systems, nicht der App | außerhalb der App; gehört zur Datenschutzseite (B10) nur als Hinweis |

## Technische Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Release über **Archivieren und Exportieren** mit Methode Developer ID | Bauen wie heute und jede Komponente per Skript neu signieren | Apple und Sparkle empfehlen den Export; er signiert auch Sparkles Hilfsprogramme mit Zeitstempel (ein normaler Bau signiert nur das Framework neu). Der Skriptweg bleibt Ausweichweg *(developer.apple.com „Creating distribution-signed code for the Mac“; sparkle-project.org/documentation/#4-distributing-your-app und /sandboxing/#code-signing; gelesen 2026-10-02)* |
| 2 | Nur das **DMG** notarisieren und heften; Offline-Erststart als Pflichtprobe | zusätzlich die App einzeln (ZIP) notarisieren | Apple: den äußersten Behälter notarisieren. Ob eine aus dem DMG kopierte App beim ersten Start offline ohne eigenes Ticket angenommen wird, ist nicht belegt — die Probe klärt es; scheitert sie, wird die App zusätzlich notarisiert *(developer.apple.com „Packaging Mac software for distribution“, gelesen 2026-10-02)* |
| 3 | Notar-Ergebnis über das **maschinenlesbare Ergebnis** („Accepted“) auswerten, Protokoll immer ablegen | Exit-Code des Werkzeugs | Apple dokumentiert den Exit-Code bei „Invalid“/„Rejected“ nicht *(notarytool(1), Xcode 27.0, gelesen 2026-10-02)* |
| 4 | Feed-Pflicht ab 1.2 mit **Sparkles Vorgabe-Frist von 20 Tagen** für dauerhaft falsch signierte Feeds | Frist 0 (nie) | vom Betreiber entschieden (OF-15, 2026-10-02): Mit 0 beendete ein Schlüsselverlust Updates für 1.2+ endgültig; mit 20 Tagen bekommen Nutzer danach wenigstens bestätigungspflichtige Updates ohne Hinweise und Links. AK-12 ist entsprechend neu gefasst *(sparkle-project.org/documentation/customization; Sparkle 2.9.3 `SUAppcastDriver`; gelesen 2026-10-02)* |
| 5 | Sprache über **Entwicklungssprache `de` plus `CFBundleLocalizations [de]`**, ohne Sprachordner und ohne String-Kataloge | ein `de.lproj` mit Inhalt; String-Katalog | passt zu „Literale im Code“ (PRD); Apples Weg für Apps ohne Sprachordner ist `CFBundleLocalizations` *(Apple QA1828, gelesen 2026-10-02)*. Wirkt auch auf iOS (Systemtexte dort für alle Nutzer deutsch) und auf alle Fehlertexte, die die App vom System übernimmt — so projektweit entschieden (OF-01), Folgen siehe unten. Dass Frameworks und Systemmenüs unter macOS der App-Sprache folgen, ist abgeleitet und am gebauten Bundle zu belegen |
| 6 | Update-Menü als **eigene Ansicht** im Menü, die die gespiegelten Werte in ihrem Rumpf liest | Zustand direkt im Menü-Block der App lesen (heute) | Apple dokumentiert die Abhängigkeitsbildung nur für den Rumpf einer Ansicht; Sparkles SwiftUI-Anleitung nutzt dieselbe Zwischenansicht *(developer.apple.com „Managing model data in your app“; sparkle-project.org/documentation/programmatic-setup; gelesen 2026-10-02)*. Die QA-2-Reproduktion (manuelle Prüfung) wird auch danach „aktiv“ zeigen, weil Sparkle das so meldet (OF-11); nachweisbar ist die Beobachtung an einer geplanten Hintergrundprüfung |
| 7 | Schalter direkt an **Sparkles eigene Einstellungen** gebunden, Anzeige nur aus dem beobachteten Spiegel | eigene Vorgaben der App; Startwert einmalig übernehmen (Muster der Sparkle-Einstellungsanleitung) | Sparkle verlangt, keine eigenen zusätzlichen Vorgaben zu führen und die Werte nur auf Nutzeraktion zu setzen. Ein einmal übernommener Startwert zeigt Änderungen aus Sparkles Update-Fenster nicht *(Sparkle 2.9.3 `SPUUpdater.h`; sparkle-project.org/documentation/preferences-ui; gelesen 2026-10-02)* |
| 8 | Sparkle **startet nicht im Test-Host**; in Debug-Builds startet er mit Vorgabe „automatische Prüfung aus“ | Sparkle nur in Release-Builds; nur Startargument „automatische Prüfung aus“ im Test | Im Test-Host verlangt OF-10 keinen Start. Debug soll die Menüschalter und die manuelle Prüfung unter der eigenen Debug-ID zeigen können (AK-01, AK-02, AK-31), ohne planmäßig gegen den echten Feed zu prüfen und sich das Release-Update anbieten zu lassen. Das Startargument allein verhindert nur geplante Prüfungen, nicht den Start *(Sparkle 2.9.3 `SPUUpdater.h`, gelesen 2026-10-02)* |
| 9 | **Eigene Bundle-ID nur für Debug des macOS-Targets** (`….debug`) | im gemeinsamen Template (ändert iOS-Debug mit); eigener App-Typ als Test-Einstieg ohne Fenster | iOS bleibt unberührt; Release-ID unverändert. Ein eigener Test-Einstieg ist von Apple nicht dokumentiert *(XcodeGen 2.46 ProjectSpec, gelesen 2026-10-02)* |
| 10 | Test-Host: Startargument **„Fensterzustand ignorieren“** plus eigene Umgebungsmarke | SwiftUI-Wiederherstellung abschalten (erst ab macOS 15); undokumentierte Systemvorgaben | Das Argument ist für automatisierte Tests dokumentiert und lenkt neuen wiederherstellbaren Zustand in ein temporäres Verzeichnis *(AppKit-Versionshinweise 10.7, gelesen 2026-10-02)*. Ob SwiftUI-Szenen es beachten und ob es den Neustart beim Anmelden aus BF-119 verhindert, ist **nicht belegt**; trifft ein solcher Neustart doch einen Debug-Test-Host, betrifft er nur Debug-Daten |
| 11 | Schlüsselbund-Dienstname **aus der Bundle-ID abgeleitet** (Test-Host unverändert); Altbestands-Übernahme nur für die übergebene Release-ID | so lassen | Ohne beides träfe ein Debug-Lauf weiterhin die Zugangsdaten bzw. eine noch nicht umgezogene Datenbank der installierten App — genau das, was BF-119 verhindern soll. Für das Release bleibt der Dienstname gleich, keine Migration |
| 12 | `disable-library-validation` **ganz** streichen; Hardened Runtime bleibt nur im Release | Ausnahme nur im Release behalten | Mit Developer ID tragen Sparkle und VLCKit dieselbe Team-ID; Debug ohne Hardened Runtime lädt weiter ad hoc *(developer.apple.com Entitlement `disable-library-validation`, gelesen 2026-10-02)*. Folge: Ein ad-hoc-signierter Release-Build startet nicht mehr (siehe *Folgen*) |
| 13 | Feed-Datei für Git **unveränderlich** (keine Zeilenende-Umwandlung) und nach dem Merge an der ausgelieferten Datei erneut geprüft | nur vor dem Push prüfen | Ein signierter Feed muss byte-genau ankommen; eine Umwandlung ließe 1.2 den Feed im Hintergrund still verwerfen *(sparkle-project.org/documentation/#signing-feeds-optional, gelesen 2026-10-02)* |
| 14 | Übergangsprobe 1.1 → 1.2 vor der Veröffentlichung über einen **eigenen Test-Feed** | erst am echten Feed beobachten | Sparkle rät, Updates zwischen nicht notarisierten und notarisierten Builds mit einem notarisierten Test-Build in eigenem Feed zu prüfen; ein Fehler beträfe jede v1.1-Installation ohne Rückweg *(sparkle-project.org/documentation, Abschnitt „Test Sparkle out“, gelesen 2026-10-02)* |

### Schlüsselwechsel (vorbereitet, nicht Teil von 1.2)

1.2 erscheint mit **unverändertem** EdDSA-Schlüssel: Sparkle erlaubt nicht, Code-Signatur (ad hoc → Developer ID) und Schlüssel
im selben Release zu wechseln. Ab dem Release nach 1.2 ist ein **geplanter** Wechsel möglich (BF-05), unter diesen Bedingungen:
die installierte App ist Developer-ID-signiert; das Update ist ein vollständiges DMG, mit Developer ID desselben Teams signiert;
die neue App trägt den neuen öffentlichen Schlüssel und das DMG ist mit dem **neuen** Schlüssel signiert. Weil ab 1.2 auch der
Feed signiert ist und jede App ihn mit **ihrem** Schlüssel prüft, braucht das Wechsel-Release eine eigene Feed-Adresse für
Versionen mit neuem Schlüssel, während der bisherige Feed (alter Schlüssel) das Wechsel-Release noch anbietet. Dieser Weg ist aus
Sparkles Prüflogik abgeleitet, nicht dokumentiert, und vor dem ersten Wechsel zu erproben.

Grenzen: Ist der alte Schlüssel **verloren**, kann der bisherige Feed nicht mehr signiert werden; dann hilft nur die Frist aus
OF-15 (20 Tage). Nicht aktualisierte **v1.1**-Installationen (ad hoc, ohne Team-ID) können einem Wechsel nie folgen und bleiben am
`Mukaarts`-Pfad. Ob ein Wechsel kommt, hat der Betreiber am 2026-10-02 entschieden (BF-06): eigener Schlüssel für
MikaPlusPlayer ab dem Release nach 1.2; gebaut wird das nach dem Release 1.2, nicht im Bau für 1.2.

## Folgen für andere Features und bestehende Tests

`sdd-build` muss diese Folgen mitbauen bzw. anpassen; sie sind keine neuen Anforderungen, sondern Wirkungen der freigegebenen
Entscheidungen.

**Deutsche Lokalisierung (OF-01, projektweit).**
- Fehlertexte, die die App vom System übernimmt (Netz, Zeitüberschreitung, Datei lesen, Wiedergabe), erscheinen auf macOS und iOS
  deutsch. Rund 20 Prüfungen erwarten englischen Wortlaut, u. a. in `B01ImportTests`, `B01LangsamTests`, `B02LangsamTests`,
  `B02URLImportTests`, `B03AktualisierenTests`, `B06EngineZustandTests`, `B06PlayerViewTests`, `B08OberflaecheTests`.
- Bedienungshilfe-Namen von Symbolen und Systemansichten können deutsch werden: „Rectangle Split Two By Two“ (`B05TabTests`,
  `B05SternTests`), „Add“ (`B01OberflaecheTests`, `B01QA2OberflaecheTests`, `B02OberflaecheTests`, `B03OberflaecheTests`,
  `B08HauptfensterTests`), Lautsprecher-Namen (`B08OberflaecheTests`), Suchleerzustand (`B04GruppenTests`, `B04SucheTests`),
  Menütitel „About“/„Window“ (`B09QA2Tests`, `B05TabTests`). Muster der Anpassung wie in `B04NacharbeitTests`: englischen
  **oder** deutschen Namen annehmen. Eigene deutsche Beschriftungen für ⊞ und „+“ wären eine neue Anforderung (Sache von B05/B08/B03).
- Kriterien anderer Features zitieren englische Systemtexte (u. a. B01, B02, B04 AK-20, B05 AK-05, B06 AK-06, B08); ihre
  Sprachfragen (B01 OF-06, B02 OF-08, B04 OF-03, B05 OF-06, B06 OF-01, B07 OF-03) sind dort noch offen und werden mit Verweis auf
  B09 OF-01 beantwortet (`/sdd-klaeren`).

**Eigene Debug-Bundle-ID.**
- Tests, die die Bundle-ID oder daraus gebildete Pfade fest erwarten, z. B. `B01SicherheitTests` (Pfad mit
  `lu.daumedia.MikaPlusPlayer`), `B09QA2Tests` (fest erwartete Bundle-ID; Erwartung für BUG-21 wird erfüllt). Übernahme-Tests
  mit übergebener Release-ID bleiben gültig (Regel am Parameter).
- Rückstandsprüfung im Schlüsselbund (`B01QA2Tests`) muss den Debug-Dienst `….debug.xtream` als App-Dienst kennen.
- Debug-Builds deklarieren dieselben Dokumenttypen (`.m3u`) unter einer zweiten Bundle-ID; welche App der Finder beim Doppelklick
  öffnet, ist nicht belegt. Debug und Release tragen denselben Anzeigenamen. Beides bleibt so (keine neue Anforderung); `sdd-build`
  prüft und meldet.

**Sparkle im Test-Host aus.** `B09QA2Tests` (AK-01 am Test-Host: „aktiv“) und der EC-01-Test werden auf „im Test-Host inaktiv,
Sparkle nicht gestartet“ umgestellt; AK-01 selbst wird am Debug- oder Release-Build beobachtet.

**B09-eigene Tests drehen sich.** Erwartete Fehlschläge für behobene Befunde (Developer ID, Feed-Pflicht, Library Validation,
BUG-19 bis BUG-23) werden zu festen Prüfungen; die Prüfung „keine Ad-hoc-Signatur“ beschränkt sich auf den Release-Block des
macOS-Targets (Debug und Test-Bundle bleiben ad hoc); die Prüfung des Datenbank-Hinweises erwartet den neuen Text (Schlüsselbund).
Release-Skript-Tests laufen über die Prüfnähte und den Probemodus.

**Läufe in Release-Konfiguration.** Ohne `disable-library-validation` startet ein ad-hoc-signierter Release-Build mit Hardened
Runtime nicht mehr. Release-Messungen und QA-Läufe in Release (bisher z. B. B02, B03, B04, B06, B08) brauchen künftig entweder
Developer-ID-Signatur oder eine Kopie mit eigener Bundle-ID und abgeschalteter Hardened Runtime — und sollen ohnehin in einer
Kopie mit eigener Bundle-ID laufen, weil die Release-Konfiguration die echte ID trägt.

**Dokumentation.** `CLAUDE.md` (Signing-Konventionen: Release mit Developer ID; Debug-Bundle-ID; Sprache) und der README-Abschnitt
zur Veröffentlichung werden nachgeführt (OF-10 verlangt die `CLAUDE.md`-Ergänzung).

## Offene Punkte aus dem Entwurf

Beim Entwerfen aufgefallen und als offene Fragen in `spec.md` eingetragen (OF-11 bis OF-15). Bei der Vorlage am 2026-10-02
entschieden: OF-15 (20 Tage, AK-12 neu gefasst). Zurückgestellt bis nach dem Bau, der Bau folgt bis dahin diesem Entwurf: OF-11
bis OF-14.

- **OF-11 · Menüpunkt während einer vom Nutzer gestarteten Prüfung.** Sparkle meldet „Prüfung möglich“ absichtlich, sobald eine
  sichtbare Prüfung läuft; ein Klick holt ein angezeigtes Update-Fenster nach vorn oder bleibt wirkungslos. BF-18 erwartet
  „inaktiv während der Prüfung“. Der Entwurf folgt Sparkle; inaktiv in **jeder** Prüfung ginge nur über einen nicht als beobachtbar
  dokumentierten Sparkle-Zustand.
- **OF-12 · Zweiter Schalter: Wortlaut und Abhängigkeit.** AK-31 nennt „Updates automatisch installieren“; Sparkle sagt im
  Update-Fenster „Updates in Zukunft automatisch laden und installieren“. Ist die automatische Prüfung aus, wirkt automatisches
  Installieren nicht; der Entwurf zeigt den Schalter dann ausgegraut ohne Häkchen und stellt beim Wiedereinschalten den alten Wert
  her. Außerdem blendet Sparkle dann im Update-Fenster „Später erinnern“ und das Kontrollkästchen aus. AK-31 sagt dazu nichts.
- **OF-13 · Englische Reste trotz deutscher App.** Sechs Sparkle-Meldungen sind in 2.9.3 nicht übersetzt (u. a. „The update feed is
  improperly signed …“ — gerade die Meldung zur neuen Feed-Pflicht — und „The updater failed to start …“); das Installationsfenster
  läuft in einem eigenen Prozess und folgt vermutlich der Systemsprache. Hinnehmen, oder Sparkle anheben, wenn eine Version sie
  übersetzt?
- **OF-14 · Kriterien, die einen überholten Stand beschreiben.** AK-01, AK-03, AK-06, AK-08, AK-09, AK-10, AK-13 bis AK-17,
  AK-20 bis AK-22, AK-24, AK-26 und AK-30 beschreiben das Verhalten vom 2026-09-15 oder widersprechen den Freigaben vom 2026-10-01
  (englische Texte, ad-hoc-Signatur, Prüfung nach dem Entpacken, ungeschützter Branch, fehlender Schlüsselwechsel, gemeinsame
  Einstellungen von Debug und Release, „übrige Menüeinträge System-Standard“, Prüfung beim ersten Start auch in Debug). Die
  Abdeckung unten nennt je Kriterium die Zielstelle; die Neufassung steht aus.
- **OF-15 · Frist für dauerhaft falsch signierte Feeds** (Entscheidung 4) — entschieden: Notweg nach 20 Tagen, AK-12 neu gefasst.

Weitere Risiken, die `sdd-build` am gebauten Ergebnis belegen muss: ob der Export für das XcodeGen-Projekt ein App-Archiv ergibt
und ohne Profil durchläuft; ob der Export Sparkles Hilfsprogramme tatsächlich mit Developer ID und Zeitstempel signiert; ob VLCKit
unter Hardened Runtime ohne Ausnahme rohes MPEG-TS dekodiert (OF-09-Kurztest); ob `DEVELOPMENT_LANGUAGE` aus der Projektoption folgt
und macOS-Menüs, Sparkle und das Updater-Hilfsprogramm der App-Sprache folgen (Probe mit englischer Systemsprache); ob die
Vorgabe „automatische Prüfung aus“ je Konfiguration greift; ob „Fensterzustand ignorieren“ für SwiftUI-Fenster wirkt; ob nach dem
Wechsel auf Developer ID einmalig eine Schlüsselbund-Rückfrage für vorhandene Zugangsdaten erscheint (betrifft nur Builds seit B01,
nicht v1.1); Offline-Erststart (Pflichtprobe).

## Abdeckung der Akzeptanzkriterien

Ausgeführt gegen `spec.md` vom 2026-10-01, Kriterien in der Reihenfolge der Datei (AK-31 steht dort nach AK-08).

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | Update-Menü (eigene Ansicht) nach „Über“; Entwicklungssprache `de` + `CFBundleLocalizations`; Sparkle startet in Debug und Release | „übrige Einträge System-Standard“ stimmt nicht mehr (zwei Schalter, „Alle Daten entfernen“); im Test-Host inaktiv → OF-14 |
| AK-02 | Aktion „jetzt prüfen“ → Sparkle-Standardoberfläche; Sparkles `de`-Übersetzung; `SULastCheckTime` | beobachtbar am Debug-Build unter `….debug` |
| AK-03 | Vorgabe „automatische Prüfung an“ im Release; Sparkle-Start | in Debug Vorgabe aus → gilt nur für Release → OF-14 |
| AK-04 | Sparkle-Standardintervall; Ablaufbild (Zweig „nein → 24 h nach der letzten“) | unverändert |
| AK-05 | `SUFeedURL` (`daumedia`); v1.1 liest bis zum Update auf 1.2 die alte Adresse | Kern gilt; Beobachtungsdaten (Prüfsumme, „heute“) vom 2026-09-15 |
| AK-06 | Sparkle-Update-Fenster; Kontrollkästchen „automatisch installieren“ an `SUAutomaticallyUpdate` | zitiert englische Texte; bei abgeschalteter Prüfung fehlen Kontrollkästchen und „Später erinnern“ → OF-14, OF-12 |
| AK-07 | Sparkle-Versionsvergleich über die Build-Nummer; Gegenprüfung „Build-Nummer größer als jede im Feed“ | |
| AK-08 | Sparkle-Fehlerbehandlung (sichtbar vs. Hintergrund) | englische Texte → OF-14 |
| AK-31 | Update-Menü: zwei Schalter an Sparkles Einstellungen, Anzeige aus dem beobachteten Spiegel; Werte je Bundle-ID gespeichert | Abhängigkeit, Wortlaut → OF-12; beobachtbar am Debug-Build |
| AK-09 | Autoupdate: Prüfung vor dem Entpacken, Ersetzen, Entfernen der Quarantäne | englischer Schaltflächentext, Reihenfolge „entpacken, dann prüfen“ überholt → OF-14 |
| AK-10 | Prüfung vor dem Entpacken (`SUVerifyUpdateBeforeExtraction`); mit Developer ID zusätzlich der Ausweichweg über die Code-Signatur | beschreibt „nach dem Entpacken“ und „einzige Integritätsprüfung“ → OF-14 |
| AK-11 | historische Beobachtung v1.1; für 1.2 Gegenprüfung „Enclosure-Signatur passt zum fertigen DMG“ | |
| AK-12 | `SURequireSignedFeed` + `SUVerifyUpdateBeforeExtraction` ab 1.2; Sparkles Vorgabe-Frist (20 Tage, nicht überschrieben); Feed-Signatur in `release.sh`; Gegenprüfungen „feed“ und „nach-merge“; Git-Attribut für `appcast.xml` | Fassung vom 2026-10-02 (OF-15); Fehlermeldung bleibt englisch → OF-13 |
| AK-13 | Developer-ID-Export; Sandbox aus unverändert | Kriterium nennt `Signature=adhoc` → OF-14 |
| AK-14 | Signiertes, notarisiertes, geheftetes DMG; Gegenprüfung „nach-heften“ | ⚠-Kriterium beschreibt „rejected“ (BF-03) → OF-14 |
| AK-15 | Hardened Runtime an, kein `get-task-allow` im Release (seit 2026-09-16); Gegenprüfung „nach-build“ | ⚠-Kriterium beschreibt den Stand davor → OF-14 |
| AK-16 | Entitlements ohne `disable-library-validation`; Gegenprüfung „nach-build“ | BF-09 → OF-14 |
| AK-17 | Release-Ablauf in den Schritten 0 bis 13 | ersetzt den beschriebenen Ablauf → OF-14 |
| AK-18 | DMG-Bau mit hdiutil-Rückfall (unverändert), danach DMG-Signatur | |
| AK-19 | `release.sh` meldet fehlendes `generate_appcast` (BF-51); die Meldung bei fehlender App bleibt (Pfad dann der Export-Ordner) | |
| AK-20 | Feed wird aus der versionierten `appcast.xml` fortgeschrieben (seit 2026-09-16); Gegenprüfung „feed“ | ⚠-Kriterium beschreibt den Stand davor → OF-14 |
| AK-21 | Gegenprüfung „vor-build“ (Version neu, Build-Nummer größer) | ⚠ → OF-14 |
| AK-22 | Sparkle exakt 2.9.3 gepinnt | beschreibt „ab 2.6.0“ → OF-14 |
| AK-23 | Sparkle-User-Agent, kein Systemprofil | unverändert; Version dann 1.2 |
| AK-24 | Sparkle-Vorgaben je Bundle-ID; Debug/Test-Host getrennt; neu die beiden Schalterwerte | „Debug-Builds und installierte App teilen sich diese Datei“ gilt nicht mehr → OF-14 |
| AK-25 | Externe Dienste (GitHub raw, Releases); Apple-Dienste nur auf Entwicklerseite bzw. durch macOS selbst | Datenschutzseite: B10 |
| AK-26 | GitHub-Ruleset auf `main` ohne Umgehungsliste; ab 1.2 Feed-Signatur | Änderungen weiter ohne **fremdes** Review (so entschieden), aber nur per PR → Neufassung → OF-14 |
| AK-27 | Übergangs-Release 1.2 holt jede aktualisierte v1.1-Installation auf den `daumedia`-Feed; Gegenprüfung „nach-merge“ an der alten Adresse | für nicht aktualisierte v1.1 bleibt das Kriterium wahr; keine Komponente kann das ändern |
| AK-28 | `SUPublicEDKey` unverändert (BF-06 zurückgestellt) | Developer ID ist für normale Updates keine zweite Hürde (Zugriffsregeln) |
| AK-29 | keine Geheimnisse im Repository; Notar-Profil nur im Schlüsselbund; Exportoptionen ohne Geheimnisse | |
| AK-30 | geplanter Wechsel: Abschnitt *Schlüsselwechsel* (ab dem Release nach 1.2); Verlust: nur die 20-Tage-Frist (OF-15) | ⚠ → OF-14; v1.1-Restbestand kann nie folgen |

Alle 31 Kriterien haben eine Zuordnung. Wie formuliert erfüllt der Entwurf 13 (AK-02, -04, -05, -07, -11, -12, -18, -19, -23,
-25, -27, -28, -29) und AK-31 bis auf die zurückgestellte Abhängigkeit (OF-12); die übrigen 17 widersprechen in ihrer
heutigen Fassung dem Entwurf, weil sie einen überholten Stand beschreiben, und sind zur Neufassung vorgemerkt (OF-14). Ohne
Kriterium, aber durch Freigaben bzw. Antworten begründet: Hinweistexte zur beiseitegelegten Datenbank (OF-08),
Fensterwiederherstellung im Test-Host, Schlüsselbund-Dienstname und Altbestands-Übernahme (BF-119), Ruleset (BF-07),
Pflichtproben vor dem Veröffentlichen (OF-09, Entscheidungen 2 und 14).
