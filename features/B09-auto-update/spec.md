# B09 · Auto-Update — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-15 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Beschreibt, was Code, Konfiguration und veröffentlichte Artefakte heute tun** — Stand `main` @ `c01f1cf`,
> installierte `v1.1` (Build 2) und das GitHub-Release `v1.1`. Nur macOS.
> Belegt am 2026-09-15 durch: `codesign`/`spctl` am installierten Bundle und am veröffentlichten DMG,
> effektive Release-Build-Settings (`xcodebuild -showBuildSettings`), Abruf beider Feed-URLs, Nachrechnen
> der EdDSA-Signatur des veröffentlichten DMG allein mit dem öffentlichen Schlüssel (CryptoKit, ohne
> Keychain), Start des `main`-Debug-Builds mit Auslösen von „Nach Updates suchen …" samt Unified Log,
> Lesen des Sparkle-Quelltexts in der tatsächlich verwendeten Version **2.9.3**.
> Was nur aus dem Sparkle-Quelltext folgt und nicht beobachtet werden konnte (es gibt kein neueres
> Release), ist am Kriterium als *(laut Sparkle 2.9.3, nicht beobachtet)* gekennzeichnet.
> `scripts/release.sh` wurde **nicht** ausgeführt.

## Zweck

Die Mac-App hält sich selbst aktuell: Sie fragt einen Update-Feed auf GitHub ab, bietet neuere Versionen
an und installiert sie nur, wenn deren EdDSA-Signatur zum eingebauten öffentlichen Schlüssel passt.
Für den Entwickler erzeugt ein Skript aus dem Quellstand ein DMG und einen signierten Feed-Eintrag.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| — | — | keine Feature-Abhängigkeit. Berührt das Datenmodell: Ein Update ohne Schema-Migration kann die App beim Start abstürzen lassen (`docs/datenmodell.md`, DM-04) |
| *(wird gebraucht von)* B10 Website | bestand | Download-Link, Changelog und FAQ beschreiben diesen Update-Weg |

## User Stories

- **US-01** · Als Mac-Nutzer möchte ich neue Versionen angeboten bekommen, ohne die Website erneut zu besuchen, damit ich Fehlerbehebungen erhalte.
- **US-02** · Als Mac-Nutzer möchte ich jederzeit selbst nach Updates suchen, damit ich nicht auf die automatische Prüfung warten muss.
- **US-03** · Als Mac-Nutzer möchte ich sicher sein, dass nur Updates des Herausgebers installiert werden, damit mir niemand fremden Code unterschiebt.
- **US-04** · Als Entwickler möchte ich mit einem Befehl ein DMG und einen signierten Feed-Eintrag erzeugen, damit ein Release reproduzierbar gleich abläuft.

## Nicht im Scope

- **iOS-Updates** — iOS hat keinen Vertriebsweg; Sparkle ist nur am macOS-Target (PRD, Rahmenbedingungen).
- **Veröffentlichen selbst:** GitHub-Release anlegen, DMG hochladen, `appcast.xml` committen und pushen, Git-Tag — `release.sh` gibt diese Schritte nur als Text aus; sie erfolgen von Hand.
- **Delta-Updates, Beta-Kanäle, gestaffelte Auslieferung, Versionshinweise im Feed** — nichts davon ist konfiguriert.
- **Download-Seite und Changelog** — gehören zu B10.
- **Datenbank-Migration beim Update** — gehört zum Datenmodell (DM-04); hier nur als Risiko unter *Fehlbestand*.

Developer-ID-Signatur und Notarisierung sind **nicht** „nicht im Scope", sondern fehlen — siehe *Fehlbestand*.

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. „Die App" meint die macOS-App.

### Prüfen und Anbieten

- **AK-01** · Angenommen, die App läuft, wenn das App-Menü „Mika+Player" geöffnet wird, dann steht direkt unter „Über Mika+Player" der Eintrag **„Nach Updates suchen …"** und ist aktiv. Die übrigen Einträge des App-Menüs sind System-Standard und erscheinen auf Deutsch.
  *(Beobachtet 2026-09-15 am `main`-Debug-Build, 5 s nach dem Start: Eintrag an Position 2, `enabled = true`.)*
  *(Neu gefasst 2026-10-01 nach `OF-01`. Vorher stand hier „… direkt unter „About Mika+Player" … Die übrigen Einträge des App-Menüs sind System-Standard und erscheinen auf Englisch.“ Der Betreiber hat entschieden, dass sich die App als deutschsprachig deklariert; heute erfüllt der Code das noch nicht.)*

- **AK-02** · Angenommen, die Build-Nummer der App ist gleich oder höher als die höchste `sparkle:version` im Feed, wenn „Nach Updates suchen …" gewählt wird, dann erscheinen zuerst ein Statusfenster der Update-Prüfung mit einer Abbrechen-Schaltfläche und danach die Meldung, dass die installierte Version die neueste ist, mit einer Schaltfläche für den Versionsverlauf – in Sparkles **deutscher** Übersetzung, wie der Menüeintrag. Der Zeitpunkt der letzten Prüfung (`SULastCheckTime`) wird aktualisiert.
  *(Beobachtet 2026-09-15: Log zeigt `SUStatus.nib`, die genannten Texte aus `Base.lproj`, TLS-Verbindung; `SULastCheckTime` sprang von 21:00:35Z auf 21:10:19Z.)*
  *(Neu gefasst 2026-10-01 nach `OF-01`. Vorher stand hier „… dann erscheint zuerst ein Statusfenster „Checking for updates…" mit „Cancel", danach die Meldung **„You're up to date!"** mit „Mika+Player 1.1 is currently the newest version available." und einer Schaltfläche „Version History". Die Sparkle-Oberfläche erscheint **auf Englisch**, obwohl der Menüeintrag deutsch ist. …“ Der genaue deutsche Wortlaut stammt aus Sparkles `de.lproj` und wird beim Bau beobachtet, nicht hier festgelegt.)*

- **AK-03** · Angenommen, die App startet zum ersten Mal (kein `SULastCheckTime` in ihren Einstellungen), wenn sie gestartet ist, dann fragt sie **ohne Einwilligungsdialog** sofort im Hintergrund den Feed ab. Gibt es kein Update, ist davon nichts zu sehen.
  *(Laut Sparkle 2.9.3: `SUEnableAutomaticChecks = true` in `Info.plist` unterdrückt die Rückfrage; fehlende letzte Prüfung gilt als überfällig.)*

- **AK-04** · Angenommen, die letzte Prüfung liegt weniger als 24 Stunden zurück, wenn die App startet, dann wird nicht sofort geprüft, sondern 24 Stunden nach der letzten Prüfung — während die App läuft, oder beim nächsten Start, falls der Zeitpunkt dann überschritten ist. Eine Einstellung dafür gibt es in der App nicht.
  *(Laut Sparkle 2.9.3: Standardintervall 86 400 s, `SUScheduledCheckInterval` nicht gesetzt.)*

- **AK-05** · Angenommen, die App ist aus dem aktuellen `main` gebaut, wenn sie prüft, dann ruft sie `https://raw.githubusercontent.com/daumedia/MikaPlusPlayer/main/appcast.xml` ab. Angenommen, es ist die installierte **v1.1**, dann ruft sie `https://raw.githubusercontent.com/Mukaarts/MikaPlusPlayer/main/appcast.xml` ab. Beide Adressen liefern heute HTTP 200 **ohne** für den Client sichtbare Weiterleitung und byte-identischen Inhalt (SHA-256 `fb2cc3fd…`, gleich der `appcast.xml` im Repository).
  *(Beobachtet 2026-09-15 mit `curl -sI`/`curl -sL`.)*

- **AK-06** · Angenommen, der Feed enthält einen Eintrag mit höherer `sparkle:version` als die Build-Nummer der App und einer `sparkle:minimumSystemVersion`, die das System erfüllt, wenn geprüft wird, dann erscheint der Dialog „A new version of Mika+Player is available!" mit „Install Update", „Skip This Version", „Remind Me Later" und dem Kontrollkästchen „Automatically download and install updates in the future" — ohne Versionshinweise, weil der Feed keine enthält.
  *(Laut Sparkle 2.9.3, nicht beobachtet — es gibt kein neueres Release.)*

- **AK-07** · Angenommen, ein Feed-Eintrag hat `sparkle:shortVersionString` 1.2, aber `sparkle:version` 2, und die App ist 1.1 mit Build 2, wenn geprüft wird, dann wird **kein** Update angeboten. Maßgeblich ist allein die Build-Nummer (`CFBundleVersion`), nicht die angezeigte Version.
  *(Laut Sparkle 2.9.3, nicht beobachtet.)*

- **AK-08** · Angenommen, der Feed ist nicht erreichbar, wenn die Prüfung **manuell** ausgelöst wurde, dann erscheint „Update Error!" mit „An error occurred in retrieving update information. Please try again later."; bei der **automatischen** Prüfung erscheint nichts, und es wird zum nächsten Intervall erneut geprüft.
  *(Laut Sparkle 2.9.3, nicht beobachtet.)*

- **AK-31** · Angenommen, die App läuft, wenn im App-Menü „Automatisch nach Updates suchen“ bzw. „Updates automatisch installieren“ abgehakt wird, dann prüft bzw. installiert sie nicht mehr von selbst, auch nach einem Neustart; „Nach Updates suchen …“ funktioniert weiter. Anhaken stellt den vorigen Zustand wieder her.
  *(Neu 2026-10-01 nach `OF-02` (Betreiber). Heute erfüllt der Code das noch nicht; Umsetzung über Sparkles eigene Einstellungen in `/sdd-build B09`.)*

### Installieren und Signaturprüfung

- **AK-09** · Angenommen, das angebotene DMG trägt eine EdDSA-Signatur, die zum `SUPublicEDKey` der **laufenden** App passt, wenn „Install Update" gewählt wird, dann lädt Sparkle das DMG, entpackt es, prüft die Signatur, ersetzt `MikaPlusPlayer.app` an ihrem Ort, **entfernt das Quarantäne-Attribut** und startet die App neu — ohne Gatekeeper-Dialog.
  *(Laut Sparkle 2.9.3, nicht beobachtet. Quarantäne-Entfernung: `SUPlainInstaller.m:50`.)*

- **AK-10** · Angenommen, die EdDSA-Signatur passt nicht (DMG verändert, falscher Schlüssel oder keine Signatur im Feed), wenn installiert werden soll, dann bricht Sparkle **nach dem Entpacken** ab und zeigt „The update is improperly signed and could not be validated. Please try again later or contact the app developer."; die installierte App bleibt unverändert. Weil die App nur ad hoc signiert ist (Designated Requirement = CDHash), gibt es keinen zweiten Prüfweg über Apple-Code-Signing — die EdDSA-Signatur ist die **einzige** Integritätsprüfung.
  *(Laut Sparkle 2.9.3 `SUUpdateValidator.m:336-376`, `SPUInstallerDriver.m:108-113`, nicht beobachtet.)*

- **AK-11** · Angenommen, das Release `v1.1` ist veröffentlicht, wenn das Asset `MikaPlusPlayer-v1.1.dmg` von GitHub geladen und die `sparkle:edSignature` aus `appcast.xml` mit dem `SUPublicEDKey` aus `Info.plist` geprüft wird, dann ist die Signatur **gültig**, Länge (36 455 860 Byte) und SHA-256 (`8da0620e…`) stimmen mit `appcast.xml`, der GitHub-Asset-Prüfsumme und dem lokalen `dist/`-DMG überein; eine um ein Byte veränderte Kopie ist **ungültig**. Die Download-URL im Feed (`github.com/daumedia/…`) leitet mit 302 auf `release-assets.githubusercontent.com` weiter, die alte URL (`github.com/Mukaarts/…`) mit 301 auf die neue.
  *(Beobachtet 2026-09-15.)*

- **AK-12** · Angenommen, die App ab Version 1.2 ist installiert, wenn sie einen Feed ohne oder mit ungültiger Signatur abruft, dann verwirft sie ihn und bietet kein Update an; einen gültig signierten Feed verarbeitet sie wie bisher. Schlagen die Prüfungen 20 Tage lang durchgehend fehl, nutzt sie den Feed nur noch eingeschränkt: Updates erst nach Bestätigung, ohne Versionshinweise und Links, ohne automatischen Download.
  *(Neu gefasst 2026-10-02 nach `OF-15`. Vorher (Fassung vom 2026-10-01) endete das Kriterium nach „… verarbeitet sie wie bisher.“ Der Betreiber behält Sparkles Notweg für den Verlust des Update-Schlüssels; die 20 Tage sind Sparkles Vorgabe.)*
  *(Neu gefasst 2026-10-01 nach `OF-07`. Vorher stand hier „Angenommen, der Feed-Inhalt wurde verändert (andere Einträge, Links, Texte), wenn die App prüft, dann übernimmt sie ihn **ohne** eigene Signaturprüfung des Feeds; geschützt ist er nur durch TLS und den Zugang zum GitHub-Konto.“ mit dem Vermerk „`SURequireSignedFeed` nicht gesetzt, `Info.plist:27-32`. Die fehlende Absicherung ist als Lücke erfasst → FB-08.“ Der Betreiber hat die Feed-Pflicht ab 1.2 entschieden (BF-08). Heute erfüllt der Code das neue Kriterium noch nicht.)*

### Signatur und Berechtigungen des ausgelieferten Bundles

- **AK-13** · Angenommen, die installierte v1.1 bzw. das DMG aus dem Release, wenn `codesign -dv` ausgeführt wird, dann ist die App mit `Signature=adhoc`, `TeamIdentifier=not set` signiert; `codesign --verify --deep --strict` meldet „valid on disk". Die App-Sandbox ist aus (`com.apple.security.app-sandbox = false`).
  *(Beobachtet 2026-09-15. Sandbox aus ist in README und CLAUDE.md als gewollt beschrieben.)*

- **AK-14** ⚠ · Angenommen, die installierte v1.1 bzw. das DMG aus dem Release, wenn `spctl -a -vv` auf App und DMG ausgeführt wird, dann lautet das Ergebnis „rejected" (DMG: „no usable signature"). Die App ist nicht notarisiert, das DMG nicht signiert. Die Website weist Nutzer an, den Start per Rechtsklick → Öffnen zu erzwingen.
  *(So verhält sich der Bestand heute. Als Kriterium aufgenommen, damit die QA es reproduziert; als Fehler eingestuft → FB-05.)*

- **AK-15** ⚠ · Angenommen, die App wird mit `scripts/build-macos.sh` (Konfiguration Release) gebaut, wenn ihre Entitlements gelesen werden, dann enthalten sie **`com.apple.security.get-task-allow = true`**, und die Hardened Runtime ist **aus** (CodeDirectory `flags=0x2(adhoc)` ohne `runtime`).
  *(Beobachtet an installierter v1.1, am Release-DMG und an der Release-`.xcent` vom 2026-06-23; effektive Settings heute unverändert: `ENABLE_HARDENED_RUNTIME = NO`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`. Debug-Berechtigung im Release → als Fehler eingestuft, FB-03.)*

- **AK-16** ⚠ · Angenommen, dasselbe Bundle, wenn seine Entitlements gelesen werden, dann ist **`com.apple.security.cs.disable-library-validation = true`** gesetzt, obwohl die Hardened Runtime aus ist, auf die sich die Begründung in Entitlements-Kommentar und README bezieht.
  *(Als Fehler eingestuft → FB-04.)*

### Release erzeugen

- **AK-17** · Angenommen, vollständiges Xcode, `xcodegen` und `create-dmg` sind installiert und der EdDSA-Privatschlüssel liegt in der Keychain, wenn `bash scripts/release.sh` läuft, dann (1) wird `xcodegen generate` ausgeführt, (2) die App im Schema `MikaPlusPlayer-macOS`, Konfiguration Release, nach `build/dd` gebaut und nach `build/MikaPlusPlayer.app` kopiert, (3) werden **alle** DMGs in `dist/` gelöscht und `dist/MikaPlusPlayer-v<CFBundleShortVersionString>.dmg` mit Volume „Mika+Player" und `Applications`-Verknüpfung erzeugt, (4) `generate_appcast` aus `build/dd/SourcePackages/artifacts` auf `dist/` mit Download-Präfix `https://github.com/daumedia/MikaPlusPlayer/releases/download/v<Version>/` aufgerufen, (5) `dist/appcast.xml` nach `appcast.xml` im Repository kopiert und (6) werden drei manuelle Folgeschritte ausgegeben. Es wird nichts hochgeladen, getaggt, committet, notarisiert oder gegengeprüft.
  *(Aus `scripts/*.sh` gelesen, nicht ausgeführt.)*

- **AK-18** · Angenommen, `create-dmg` ist nicht installiert, wenn `make-dmg.sh` läuft, dann entsteht das DMG über `hdiutil` (UDZO, zlib-Stufe 9) mit gleichem Volume-Namen und `Applications`-Verknüpfung, aber ohne Fensterlayout.

- **AK-19** · Angenommen, `generate_appcast` liegt nicht unter `build/dd/SourcePackages/artifacts`, wenn `release.sh` läuft, dann bricht es nach Build und DMG mit „FEHLER: generate_appcast nicht gefunden." und Exit-Code 1 ab. Angenommen, `build/MikaPlusPlayer.app` fehlt, wenn `make-dmg.sh` allein läuft, dann bricht es mit „FEHLER: … fehlt. Erst scripts/build-macos.sh ausführen." ab.

- **AK-20** ⚠ · Angenommen, in `dist/` liegt noch die `appcast.xml` vom 2026-06-23 (Titel „MikaPlusPlayer", Einträge 1.1 **und** 1.0, beide mit `Mukaarts`-URLs), wenn `release.sh` läuft, dann übernimmt `generate_appcast` diese Einträge (bis zu 3 Versionen) in den neuen Feed, und das Skript **überschreibt** die handkorrigierte `appcast.xml` im Repository damit — der 2026-06-23 entfernte, nie veröffentlichte 1.0-Eintrag, die `Mukaarts`-Download-URL und der alte Titel kämen zurück.
  *(Aus `release.sh:26-29`, dem Inhalt von `dist/appcast.xml` und der Werkzeughilfe von `generate_appcast` 2.9.3 abgeleitet, nicht ausgeführt. Als Fehler eingestuft → FB-10.)*

- **AK-21** ⚠ · Angenommen, vor einem Release wird nur `MARKETING_VERSION` erhöht (README: „und ggf. `CURRENT_PROJECT_VERSION`"), wenn `release.sh` läuft, dann entstehen ein DMG und ein Feed-Eintrag mit neuer Anzeigeversion, aber `sparkle:version` 2 — und keine bestehende Installation bekommt das Update angeboten (AK-07). `release.sh` prüft das nicht. Heute stehen in `project.yml` genau die Werte von v1.1 (1.1 / 2).
  *(Als Fehler eingestuft → FB-02.)*

- **AK-22** · Angenommen, ein frischer Klon ohne `MikaPlusPlayer.xcodeproj`, wenn `xcodegen generate` und der Build laufen, dann löst SwiftPM Sparkle neu auf — auf die neueste 2.x-Version ab 2.6.0. Die bisherigen Builds (v1.1, `main`) verwenden **Sparkle 2.9.3** (`Package.resolved` vom 2026-06-19, Framework-Version im Bundle 2.9.3 / 2058); diese Datei ist nicht versioniert, weil die `.xcodeproj` in `.gitignore` steht.

### Datenschutz und Missbrauchsschutz

Katalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog).

**1 · Personenbezogene Daten**

- **AK-23** · Angenommen, die App prüft auf Updates (automatisch oder manuell), wenn die Anfrage an GitHub geht, dann erhält GitHub die **IP-Adresse** und den User-Agent `<App-Name>/<Version> Sparkle/2.9.3` (v1.1: `MikaPlusPlayer/1.1`, `main`: `Mika+Player/1.1`). Es wird **kein** Systemprofil gesendet (`SUSendProfileInfo` nicht gesetzt, Standard aus), keine Zugangsdaten, keine Playlist- oder Senderdaten.
  *(Laut Sparkle 2.9.3 `SPUUserAgent+Private.m:22`, `SUHost.m:121-136`.)*

- **AK-24** · Angenommen, die App hat mindestens einmal gestartet, wenn `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist` gelesen wird, dann enthält sie von Sparkle geschriebene Schlüssel (`SUHasLaunchedBefore`, `SULastCheckTime`, `SUUpdateGroupIdentifier`; nach Nutzerwahl zusätzlich `SUSkippedVersion`, `SUAutomaticallyUpdate`). Sie enthalten keine personenbezogenen Daten außer dem Zeitpunkt der letzten Prüfung und bleiben beim Löschen der App liegen. Debug-Builds und installierte App teilen sich diese Datei (gleiche Bundle-ID).
  *(Beobachtet 2026-09-15, nur `SU*`-Schlüssel gelesen. Sparkle protokolliert Fehler über `os_log` mit Pfaden und URLs, ohne Nutzerdaten.)*

- **Besondere Kategorien:** trifft nicht zu, weil der Update-Weg keine Inhalte des Nutzers berührt.

**2 · Weitergabe an externe Dienste**

- **AK-25** · Angenommen, eine Prüfung oder ein Download läuft, wenn der Netzverkehr betrachtet wird, dann gehen Anfragen ausschließlich an `raw.githubusercontent.com` (Feed), `github.com` und `release-assets.githubusercontent.com` (DMG), alle über HTTPS. Die Datenschutzseite der Website nennt GitHub und die IP-Adresse, **nicht** den User-Agent mit App- und Sparkle-Version.
  *(Pseudonymisierung: trifft nicht zu, es werden keine Nutzerdaten übertragen. AV-Vertrag: GitHub liefert öffentliche Dateien aus, eine Auftragsverarbeitung liegt nicht vor; `docs/datenschutz.md` fehlt projektweit. Training: trifft nicht zu.)*

**3 · Zugriff** — wer die Update-Kette verändern kann

- **AK-26** · Angenommen, jemand kann auf `main` von `daumedia/MikaPlusPlayer` pushen, wenn er `appcast.xml` ändert, dann erreicht die Änderung alle Installationen aus `main`-Builds ohne Review — `main` hat keinen Branch-Schutz und keine Rulesets; `raw.githubusercontent.com` liefert mit `max-age=300` aus.
  *(Beobachtet 2026-09-15 über `gh api`. → FB-09)*

- **AK-27** ⚠ · Angenommen, jemand registriert den GitHub-Benutzernamen `Mukaarts` und legt ein Repository `MikaPlusPlayer` mit `main/appcast.xml` an, wenn eine v1.1-Installation prüft, dann lädt sie **dessen** Feed. Heute ist der Name **nicht vergeben** (`GET /users/Mukaarts` → 404); die alte Feed-URL funktioniert nur, solange GitHubs Weiterleitung nach der Umbenennung besteht.
  *(So verhält sich der Bestand heute. Nicht ausgeführt — der Name wurde selbstverständlich nicht registriert. Als Fehler eingestuft → FB-01.)*

- **AK-28** ⚠ · Angenommen, ein DMG trägt eine gültige Signatur mit dem familienweiten Schlüssel, wenn es in einem Feed dieser App angeboten wird, dann akzeptiert Sparkle die Signatur unabhängig davon, für welche App oder Version sie erzeugt wurde; ob installiert wird, entscheidet danach allein, ob im Archiv eine App mit dem Namen `MikaPlusPlayer.app` bzw. dem Anzeigenamen der App liegt. Derselbe `SUPublicEDKey` steht in sechs installierten Mika+-Apps (FileScope, Flow, Grid, ScreenSnap, MediaFetch, Player).
  *(Beobachtet 2026-09-15 an `/Applications/*/Contents/Info.plist`; Auswahl der App im Archiv laut `SUInstaller.m:81-88`. Als Fehler eingestuft → FB-07.)*

- **Rollen:** trifft nicht zu — die App hat keine Konten. Wer signiert, ist, wer Zugriff auf den Keychain-Eintrag des Entwicklerrechners hat.

**4 · Missbrauch und Kosten**

- **Rate Limit:** trifft nicht zu, weil kein eigener Endpunkt existiert; Feed und DMG liefert GitHub aus, die App fragt höchstens einmal je 24 Stunden automatisch (AK-04), manuell beliebig oft.
- **Kosten:** trifft nicht zu — GitHub-Auslieferung ist für öffentliche Repositories kostenlos.
- **Uploads / Größenbegrenzung:** Der Download hat keine eigene Größengrenze; die `length` aus dem Feed dient Sparkle nur für Fehlermeldungen. Das DMG wird vor der Signaturprüfung eingehängt (AK-10) → FB-08.

**5 · Löschen und Auskunft**

- Trifft weitgehend nicht zu: Der Update-Weg speichert keine Nutzerdaten. Zurück bleiben nach dem Löschen der App die Sparkle-Schlüssel aus AK-24 (wo Sparkle heruntergeladene Updates zwischenlagert und ob es sie aufräumt, wurde nicht geprüft). Eine Auskunft über Serverprotokolle von GitHub ist Sache von GitHub.

**6 · Geheimnisse**

- **AK-29** · Angenommen, das Repository mit gesamter Historie, wenn nach privaten Schlüsseln gesucht wird (`git log -p --all`), dann findet sich kein EdDSA-Privatschlüssel, keine Schlüsseldatei und kein Token; im Repository steht nur der öffentliche Schlüssel in `Info.plist`. `release.sh` liest den Privatschlüssel über `generate_appcast` aus der Keychain (Standard-Konto `ed25519`) und enthält selbst keine Geheimnisse; `dist/` und `*.dmg` sind in `.gitignore`.
  *(Beobachtet 2026-09-15. Die Keychain wurde nicht gelesen.)*

- **AK-30** ⚠ · Angenommen, der private Schlüssel geht verloren oder gilt als kompromittiert, wenn ein neues Schlüsselpaar in eine neue Version eingebaut wird, dann kann **keine** bestehende Installation diese Version per Sparkle annehmen: Sparkle erlaubt einen Schlüsselwechsel nur, wenn alte und neue App mit derselben Apple-Code-Signing-Identität signiert sind, und das Designated Requirement einer ad-hoc-signierten App ist ihr CDHash (`cdhash H"a474f9b6…"`).
  *(Laut `SUUpdateValidator.m:373-376` und `codesign -d -r-` am installierten Bundle. Als Fehler eingestuft → FB-06.)*

## Edge Cases

- **EC-01** · `xcodebuild test` → die Test-Host-App startet Sparkle mit und führt eine **echte** Feed-Abfrage durch; beobachtet: `SULastCheckTime` = 23:00:35 Uhr, exakt das Ende des Testlaufs vom 2026-09-15. Weil Debug-Builds dieselbe Bundle-ID nutzen, verschiebt das den Prüfzeitpunkt der installierten App.
- **EC-02** · Neuer Release mit einer Build-Nummer, die im Feed schon vorkommt → Verhalten von `generate_appcast` (ersetzen, doppeln oder abbrechen) nicht geprüft; siehe OF-03. Für bestehende Installationen gilt in jedem Fall AK-07: kein Update.
- **EC-03** · `xcodegen` nicht installiert → `build-macos.sh` baut ohne Hinweis mit der vorhandenen, möglicherweise veralteten `.xcodeproj`.
- **EC-04** · `xcodebuild` scheitert → dank `set -o pipefail` bricht `build-macos.sh` ab, zeigt aber nur die letzten 3 Zeilen der Build-Ausgabe.
- **EC-05** · Frischer Klon ohne `dist/appcast.xml` → der erzeugte Feed enthält nur den neuen Eintrag; die Einträge aus der versionierten `appcast.xml` werden trotzdem überschrieben, weil `release.sh` nicht von ihr ausgeht.
- **EC-06** · `appcast.xml` wird gepusht, bevor das DMG als Release-Asset hochgeladen ist → Installationen sehen das Update, der Download liefert 404, Sparkle meldet einen Update-Fehler. Die README nennt die richtige Reihenfolge, das Skript erzwingt sie nicht.
- **EC-07** · Update mit geänderter SwiftData-Schemadefinition, die sich nicht leichtgewichtig migrieren lässt → die aktualisierte App stürzt beim Start mit `fatalError` ab; Sparkle behält keine alte Version, einen Rückweg gibt es nicht (DM-04).
- **EC-08** · Update während Wiedergabe oder Multiview → „Install Update" beendet und startet die App neu; Wiedergabe und Multiview-Belegung (flüchtig) gehen verloren.
- **EC-09** · `sparkle:minimumSystemVersion` höher als die macOS-Version → der Eintrag wird nicht angeboten. `generate_appcast` übernimmt den Wert aus `LSMinimumSystemVersion` (heute 14.0).
- **EC-10** · „Skip This Version" → Sparkle merkt sich die Version (`SUSkippedVersion`), die automatische Prüfung bietet sie nicht mehr an; eine manuelle Prüfung zeigt sie wieder *(laut Sparkle-Doku)*.
- **EC-11** · Menüeintrag während einer laufenden Prüfung → `canCheckForUpdates` wird von SwiftUI nicht beobachtet (Sparkle-Eigenschaft hinter `@ObservationIgnored`, kein KVO-Publisher); der aktivierte/deaktivierte Zustand kann veralten. Ein Klick während einer laufenden Prüfung holt laut Sparkle das bestehende Fenster nach vorn. Von der QA zu prüfen.
- **EC-12** · Nutzer schaltet die automatische Prüfung ab → über den Menüeintrag (AK-31); `defaults write lu.daumedia.MikaPlusPlayer SUEnableAutomaticChecks -bool NO` bleibt als Weg erhalten. *(Neu gefasst 2026-10-01 nach `OF-02`. Vorher: „… nur über `defaults write …`; die Nutzereinstellung hat laut Sparkle Vorrang vor `Info.plist`. Eine Oberfläche dafür gibt es nicht (OF-02).“)*
- **EC-13** · App aus dem DMG heraus gestartet statt nach `/Applications` kopiert → Verhalten des Updaters nicht geprüft.

## Offene Fragen

- **OF-01** · Sparkle-Dialoge erscheinen auf Englisch, der Menüeintrag auf Deutsch (die App hat keine Lokalisierung, `CFBundleDevelopmentRegion` ist `en`). Gewollt, oder soll die App eine deutsche Lokalisierung deklarieren? — Nutzer, bei der Freigabe dieser Spec.
  ✔ **Beantwortet 2026-10-01 (Betreiber): Die App deklariert sich als deutschsprachig (Entwicklungssprache bzw. Lokalisierung `de`), damit Sparkle-Dialoge und System-Menüeinträge deutsch erscheinen.** Folge: AK-01 und AK-02 neu gefasst; Umsetzung und Beobachtung am Sparkle-Dialog in `/sdd-build B09`. Gilt projektweit: Die gleichlautenden Sprachfragen (B01 OF-06, B02 OF-08, B04 OF-03, B05 OF-06, B06 OF-01, B07 OF-03) werden in ihren Features mit Verweis hierauf beantwortet.
- **OF-02** · Soll die automatische Prüfung und das automatische Installieren in der App abschaltbar sein (Einstellung oder Menü), oder genügt der Hinweis auf der Datenschutzseite? — Nutzer, bei der Freigabe dieser Spec.
  ✔ **Beantwortet 2026-10-01 (Betreiber): Ja – zwei Menüeinträge zum An- und Abhaken: „Automatisch nach Updates suchen“ und „Updates automatisch installieren“.** Folge: neues Kriterium AK-31, EC-12 neu gefasst; der Website-Satz „has no switch“ (`web/app/privacy/page.tsx:158`) muss angepasst werden (B10); Bau in `/sdd-build B09`.
- **OF-03** · Was tut `generate_appcast` 2.9.3, wenn die Build-Nummer eines neuen DMG schon im Feed steht? Prüfbar ohne echten Schlüssel mit einer Kopie in einem temporären Verzeichnis und einer Test-Schlüsseldatei (`--ed-key-file`). — `sdd-qa`.
  ✔ **Beantwortet durch Ausführung (QA 1, `qa-report.md` EC-02/OF-03), vermerkt 2026-10-01 (`sdd-klaeren`): Bei zwei Archiven derselben Build-Nummer bricht `generate_appcast` mit `SUSparkleErrorDomain` 1002 ab und schreibt nichts; bei einem Archiv aktualisiert es den bestehenden Eintrag an Ort und Stelle.** `release.sh` legt genau ein DMG ab, und seit der Reparatur von BUG-04 bricht die Gegenprüfung schon vorher ab, wenn die Build-Nummer nicht größer ist (`scripts/b09_release_check.sh:85-86`). EC-02 ist damit belegt; keine Betreiberentscheidung nötig.
- **OF-04** · Ist das GitHub-Konto `daumedia`, das Feed und Releases allein trägt, mit Zwei-Faktor-Anmeldung geschützt? Von außen nicht prüfbar. — Nutzer.
  ✔ **Beantwortet 2026-10-01 (Betreiber): Ja, das Konto `daumedia` ist mit Zwei-Faktor-Anmeldung geschützt.** Folge: keine Handlung; BF-07 bleibt nur wegen des fehlenden Branch-Schutzes offen (zur Behebung freigegeben).
- **OF-05** · Welche Mika+-Apps und Rechner halten den familienweiten Privatschlüssel, und gibt es eine Sicherung? Ohne Sicherung ist FB-06 schon bei einem Rechnerverlust erreicht. — Nutzer.
  ✔ **Beantwortet 2026-10-01 (Betreiber): Eine Sicherung gibt es bisher nicht; der Betreiber exportiert den privaten Schlüssel jetzt verschlüsselt und offline (`generate_keys -x`).** Folge: externe Handlung des Betreibers, gilt für alle sechs Mika+-Apps; Ort der Sicherung wird bewusst nicht im öffentlichen Repository genannt. Erst danach ist das Risiko „Rechnerverlust beendet alle Updates“ (BF-05/BF-06) gemindert.
- **OF-06** · Welche Anzeigeversion trägt das nächste Release? `CURRENT_PROJECT_VERSION` steht seit der Reparatur vom 2026-09-16 auf 3, `MARKETING_VERSION` weiter auf 1.1; die Gegenprüfung in `release.sh` bricht ab, solange 1.1 schon im Feed steht (Tag- und DMG-Namenskollision). Produktentscheidung. — Nutzer, vor dem nächsten Release. *(aus sdd-build 2026-09-16)*
  ✔ **Beantwortet 2026-10-01 (Betreiber): Das nächste Release heißt 1.2.** Folge: `MARKETING_VERSION` 1.2 in `project.yml`, Tag `v1.2`, DMG-Name und der Versionshinweis der Website (`web/app/privacy/page.tsx`) folgen; es ist das Übergangs-Release für BF-01 (Teil von `/sdd-build B09` bzw. `/sdd-deploy`).
- **OF-07** · Ab welcher Version soll die App einen signierten Feed verlangen (`SURequireSignedFeed`)? `release.sh` signiert den Feed ab dem nächsten Release; wer den Schlüssel danach setzt, kann `appcast.xml` nie mehr von Hand korrigieren, ohne neu zu signieren. — Nutzer, nach dem ersten signiert veröffentlichten Feed. *(aus sdd-build 2026-09-16)*
  ✔ **Beantwortet 2026-10-01 (Betreiber): Die App verlangt schon ab Version 1.2 einen signierten Feed (`SURequireSignedFeed`).** Folge: AK-12 neu gefasst; Voraussetzung ist, dass BF-48 vorher behoben ist und die Release-Prüfung die Feed-Signatur vor dem Push kontrolliert (`/sdd-build B09`). Ein unsigniert gepushter Feed sperrt 1.2-Installationen aus, bis neu signiert wird – in Kauf genommen.
- **OF-08** · Beiseitegelegte Datenbanken (`Application Support/<Bundle-ID>/Beiseitegelegt/<Zeitstempel>/`) bleiben unbegrenzt liegen und lassen sich in der App nicht zurückholen; der Hinweis nennt nur den Ordner. Soll es einen Weg zum Wiederherstellen oder Aufräumen geben, und soll der Hinweis auf iOS (Ordner im App-Container, für Nutzer unerreichbar) anders lauten? — Nutzer. *(aus sdd-build 2026-09-16)*
  ✔ **Beantwortet 2026-10-01 (Betreiber): Beiseitegelegte Datenbanken bleiben bis „Alle Daten entfernen“ liegen; kein Wiederherstellen, kein automatisches Aufräumen. Der Hinweis wird gebessert.** Folge: Der Hinweis sagt künftig, dass auch die Zugangsdaten der alten Playlists im Schlüsselbund erhalten bleiben, nennt „Alle Daten entfernen“ als Löschweg und zeigt unter iOS keinen Ordnerpfad (`AppPersistence.swift` `StoreNotice`) → `/sdd-build B09`. B01 BF-46 (BUG-20) wird in der B01-Runde zum Akzeptieren vorgelegt.
- **OF-09** · Wiedergabe unter Hardened Runtime: Das Release startet mit Sparkle und VLCKit; ob VLCKit unter Hardened Runtime alle Formate dekodiert, ist nur stichprobenhaft (stumme H.264-MPEG-TS-Datei) belegt, nicht für echte Anbieter-Streams (HEVC, AC-3, verschlüsselte HLS). — `sdd-qa` B06/B09 vor dem nächsten Release. *(aus sdd-build 2026-09-16)*
  ✔ **Beantwortet 2026-10-01 (Betreiber): Vor dem Release ein Kurztest des Release-Builds mit dem echten Anbieter des Betreibers (HLS und MPEG-TS, mit Ton).** Folge: Pflichtschritt vor `/sdd-deploy`, Ergebnis im Build-Bericht; vorbereiten kann ihn `sdd-build`, ausführen nur der Betreiber (Zugang). Nach einem VLCKit-Wechsel (B06 OF-06) wird er wiederholt.
- **OF-10** · Der Test-Host startet Sparkle weiterhin mit echter Feed-Abfrage und schreibt `SULastCheckTime` in die Einstellungen der installierten App (EC-01). Soll `SparkleUpdater` im Test-Host nicht starten? Nicht im Fehlerauftrag. — Nutzer. *(aus sdd-build 2026-09-16)*
  ✔ **Beantwortet 2026-10-01 (Betreiber): Ja – Sparkle startet im Test-Host nicht, und Debug-Build sowie Test-Host bekommen eine eigene Bundle-ID.** Folge: umgesetzt über die freigegebenen Befunde BF-49 und BF-119 in `/sdd-build B09`; `CLAUDE.md` wird dort ergänzt.

Ergänzt beim Entwurf (`sdd-architektur`, 2026-10-02). Nicht im Entwurf entschieden, weil sie ein Kriterium betreffen oder vom
Betreiber abhängen (Herleitung in `design.md`, *Offene Punkte aus dem Entwurf*):

- **OF-11** · Soll „Nach Updates suchen …“ während einer vom Nutzer gestarteten Prüfung inaktiv sein (Erwartung aus BF-18)? Sparkle
  2.9.3 meldet „Prüfung möglich“ in diesem Fall absichtlich; ein Klick holt ein angezeigtes Update-Fenster nach vorn oder bleibt
  wirkungslos. Der Entwurf folgt Sparkle; inaktiv in jeder Prüfung ginge nur über einen nicht als beobachtbar dokumentierten
  Sparkle-Zustand. — Betreiber.
  ⏳ **Zurückgestellt 2026-10-02 (Betreiber) bis nach dem Bau** — der Betreiber hat den Bauweg „sdd-build mit Entwurf“ gewählt statt vorher zu klären; der Bau folgt dem Vorschlag in `design.md`. Auslöser: `/sdd-build B09` abgeschlossen; dann `/sdd-klaeren B09` vor der QA.
- **OF-12** · AK-31 im Detail: Soll der zweite Schalter wie in Sparkles Update-Fenster „Updates automatisch laden und installieren“
  heißen? Und soll er bei abgeschalteter automatischer Prüfung ausgegraut ohne Häkchen erscheinen und beim Wiedereinschalten den
  alten Wert zurückbringen (so wirkt Sparkle; automatisches Installieren ohne automatische Prüfung hat keine Wirkung)? Sparkle blendet
  dann im Update-Fenster auch „Später erinnern“ und das Kontrollkästchen aus. — Betreiber.
  ⏳ **Zurückgestellt 2026-10-02 (Betreiber) bis nach dem Bau** — der Betreiber hat den Bauweg „sdd-build mit Entwurf“ gewählt statt vorher zu klären; der Bau folgt dem Vorschlag in `design.md`. Auslöser: `/sdd-build B09` abgeschlossen; dann `/sdd-klaeren B09` vor der QA.
- **OF-13** · Sechs Sparkle-Meldungen sind in 2.9.3 nicht ins Deutsche übersetzt (u. a. „The update feed is improperly signed …“ zur
  neuen Feed-Pflicht und „The updater failed to start …“), und das Installationsfenster läuft in einem eigenen Prozess, der
  vermutlich der Systemsprache folgt. Hinnehmen, oder Sparkle anheben, sobald eine Version sie übersetzt? — Betreiber.
  ⏳ **Zurückgestellt 2026-10-02 (Betreiber) bis nach dem Bau** — der Betreiber hat den Bauweg „sdd-build mit Entwurf“ gewählt statt vorher zu klären; der Bau folgt dem Vorschlag in `design.md`. Auslöser: `/sdd-build B09` abgeschlossen; dann `/sdd-klaeren B09` vor der QA.
- **OF-14** · AK-01, AK-03, AK-06, AK-08, AK-09, AK-10, AK-13 bis AK-17, AK-20 bis AK-22, AK-24, AK-26 und AK-30 beschreiben das
  Verhalten vom 2026-09-15 oder widersprechen den Freigaben vom 2026-10-01 (englische Texte, ad-hoc-Signatur, Prüfung nach dem
  Entpacken, ungeschützter Branch, fehlender Schlüsselwechsel, gemeinsame Einstellungen von Debug und Release, „übrige Menüeinträge
  System-Standard“, Prüfung beim ersten Start auch in Debug). Neufassung nach dem Zielentwurf — jetzt im Interview oder nach dem
  Bau anhand der Beobachtung? — Betreiber (`sdd-klaeren`).
  ⏳ **Zurückgestellt 2026-10-02 (Betreiber) bis nach dem Bau: Neufassung der genannten Kriterien anhand der Beobachtung am gebauten Release** — Auslöser: `/sdd-build B09` abgeschlossen; dann `/sdd-klaeren B09` vor der QA.
- **OF-15** · Wie lange darf ein dauerhaft falsch signierter Feed verworfen werden, bevor Sparkle ihn eingeschränkt doch nutzt
  (`SUSignedFeedFailureExpirationInterval`)? Frist 0: AK-12 gilt dauerhaft, ein Verlust des Update-Schlüssels beendet Updates für
  1.2+ endgültig. Vorgabe 20 Tage: AK-12 gilt nur bis zur Frist, danach bietet Sparkle Updates ohne Hinweise und Links und nur mit
  Bestätigung an — der einzige Weg aus einem Schlüsselverlust. — Betreiber, vor `/sdd-build B09`.
  ✔ **Beantwortet 2026-10-02 (Betreiber, bei der Vorlage des Entwurfs): Sparkles Vorgabe von 20 Tagen bleibt; der Notweg für einen Schlüsselverlust bleibt erhalten.** Folge: AK-12 neu gefasst (Einschränkung nach 20 Tagen); `SUSignedFeedFailureExpirationInterval` wird nicht gesetzt; `design.md` Entscheidung 4 entsprechend.

## Decision Log

Alle Einstufungen ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer.

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Sandbox aus (AK-13) — Kriterium oder Befund? | reguläres Kriterium | in README, CLAUDE.md und Entitlements-Kommentar als gewollt beschrieben (DMG-Vertrieb + Sparkle); kein Punkt aus `sicherheit.md` direkt verletzt. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 2 | Keine Notarisierung, ad-hoc-Signatur (AK-14) | ⚠-Kriterium + FB-05, als Fehler eingestuft | Website und FAQ beschreiben es als bewusst, aber das Stack-Profil verlangt Developer ID + Notarisierung für eine Veröffentlichung, und Nutzer werden zur Gatekeeper-Umgehung angeleitet. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 3 | `get-task-allow` und fehlende Hardened Runtime im Release (AK-15) | ⚠-Kriterium + FB-03, als Fehler eingestuft | Debug-Berechtigung im Release ist im Zielmodus ausdrücklich als Schwäche genannt; nirgends als gewollt beschrieben. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 4 | `disable-library-validation` (AK-16) | ⚠-Kriterium + FB-04, als Fehler eingestuft | die dokumentierte Begründung („unter Hardened Runtime") trifft auf den Build nicht zu; das Entitlement schwächt die Abwehr gegen Bibliotheks-Injektion, sobald die Runtime aktiviert wird. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 5 | Unsignierter Feed (AK-12) | reguläres Kriterium, Lücke als FB-08 | Sparkle-Standard und nicht als gewollt oder ungewollt beschrieben; die fehlende Absicherung ist eine Lücke (Regel 2), kein Verhalten, das zu korrigieren wäre. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 6 | Alte Feed-URL `Mukaarts` in v1.1 (AK-05, AK-27) | AK-05 regulär (beobachtetes Ist), AK-27 ⚠ + FB-01, als Fehler eingestuft | Commit `a67d956` nennt die Folge selbst, nimmt sie aber hin; dass der Name frei ist, war dort nicht bekannt. Integrität der Update-Kette → Sicherheitsschwäche. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 7 | Familienweit geteilter Schlüssel (AK-28) | ⚠-Kriterium + FB-07, als Fehler eingestuft | README und `Info.plist` beschreiben es als gewollt, aber es verletzt *Geheimnisse*: ein Schlüssel für mehrere Produkte vergrößert die Wirkung jeder Kompromittierung. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 8 | Kein Schlüsselwechsel möglich (AK-30) | ⚠-Kriterium + FB-06, als Fehler eingestuft | Folge aus ad-hoc-Signatur und Sparkle-Regel; nirgends bedacht, sicherheitsrelevant (Rotation nach Kompromittierung unmöglich). Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 9 | `release.sh` überschreibt Feed mit Altstand aus `dist/` (AK-20) | ⚠-Kriterium + FB-10, als Fehler eingestuft | Absicht ist ableitbar: Commits `907c9f8` und `a67d956` haben genau diese Einträge von Hand entfernt bzw. korrigiert; die Rückkehr der `Mukaarts`-URLs berührt FB-01. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 10 | Kein Versionssprung / Build-Nummer „ggf." (AK-21) | ⚠-Kriterium + FB-02, als Fehler eingestuft | ein Release in diesem Zustand erreicht keine Installation — auch nicht die v1.1-Installationen, die für den Feed-Wechsel ein Update brauchen. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 11 | Automatische Prüfung ohne Einwilligung und ohne Abschaltmöglichkeit (AK-03, AK-04) | reguläres Kriterium, Abschaltbarkeit als OF-02 | README beschreibt die automatische Prüfung als gewollt; die Datenschutzseite legt den Kontakt zu GitHub offen; der Katalog verlangt kein Opt-out. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 12 | Englische Sparkle-Oberfläche (AK-02) | reguläres Kriterium, OF-01 | keine Sicherheitsrelevanz, Absicht nicht ableitbar. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 13 | Website-Aussagen zum Update-Weg | FB-14 | Website verspricht etwas, das der Code nicht tut. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 14 | Fehlender Branch-Schutz, fehlende Release-Gegenprüfungen, ungepinntes Sparkle, falsche README-Reihenfolge, unvollständige Datenschutzseite, fehlende Migration, fehlende Tests | Fehlbestand FB-09, FB-11, FB-12, FB-13, FB-15, FB-16, FB-17 — kein Kriterium | Lücken sind Befunde, keine Kriterien (Regel 2); FB-15 berührt Katalog Abschnitt 2, FB-12/FB-17 die Reproduzierbarkeit der Kette. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 15 | Beobachtung am laufenden Build statt nur Lesen | `main`-Debug-Build gestartet, Menüpunkt per Bedienungshilfe ausgelöst, echter Feed abgerufen; installierte v1.1 **nicht** gestartet, keine Datenbankinhalte gelesen, nur `SU*`-Schlüssel der Einstellungen gelesen | Regel „ausführen, nicht nur lesen" ohne Zugriff auf Zugangsdaten; der Start öffnet die lokale Datenbank, liest aber nichts aus. Ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer |
| 16 | Anzeigeversion des nächsten Release (OF-06) | 1.2 | ehrlich zum Umfang seit v1.1, geringster Aufwand; entsperrt das Übergangs-Release für BF-01 |
| 17 | Wiedergabe unter Hardened Runtime mit echten Streams (OF-09) | Kurztest mit echtem Anbieter vor dem Release | ein Ausfall träfe jede aktualisierte Installation ohne Rückweg über Sparkle |
| 18 | Ab wann signierter Feed Pflicht (OF-07) | ab 1.2; AK-12 neu gefasst | Schutz für alle, die auf 1.2 aktualisieren; BF-48 und die Signaturprüfung der Release-Gegenprüfung machen das Aussperr-Risiko klein |
| 19 | Zwei-Faktor-Anmeldung des GitHub-Kontos (OF-04) | an | Auskunft des Betreibers |
| 20 | Sicherung des privaten Update-Schlüssels (OF-05) | bisher keine; Betreiber sichert jetzt offline | ohne Sicherung beendet ein Rechnerverlust die Updates aller sechs Apps |
| 21 | Sparkle in Testläufen (OF-10) | nicht starten, eigene Bundle-ID für Debug und Test-Host | Vorfall vom 2026-09-29: Test-Host übernahm die echte Datenbank (BF-119) |
| 22 | Sprache von Sparkle und Systemmenüs (OF-01) | App als deutsch deklarieren; AK-01, AK-02 neu gefasst | passt zu „App nur Deutsch“ im PRD; Sparkle bringt `de.lproj` mit; eine Konfigurationszeile |
| 23 | Abschaltbarkeit der automatischen Prüfung und Installation (OF-02) | zwei Menüschalter; neu AK-31, EC-12 neu gefasst | wer automatisches Installieren anhakt, braucht einen Rückweg in der App; Datenschutz: Nutzer kann die tägliche Abfrage abstellen |
| 24 | Beiseitegelegte Datenbanken: Wiederherstellen, Aufräumen, Hinweis (OF-08) | so lassen, Hinweis bessern (Schlüsselbund, Löschweg, iOS ohne Pfad) | seltener Fall, ein Löschweg existiert seit B03; Wiederherstellen lohnt den Aufwand nicht |
| 25 | Frist für dauerhaft falsch signierte Feeds (OF-15) | Sparkle-Vorgabe 20 Tage; AK-12 neu gefasst | einziger Weg aus einem Schlüsselverlust; Schlüssel ist offline gesichert (OF-05), Verlust unwahrscheinlich |
| 26 | Neufassung überholter Kriterien (OF-14) | nach dem Bau, anhand der Beobachtung | Bauweg „sdd-build mit Entwurf“ gewählt; Kriterien werden am gebauten Ergebnis neu gefasst |
| 27 | Klärung von OF-11 vor oder nach dem Bau | nach dem Bau; Bau folgt dem Entwurf | Betreiber wählte sdd-build mit Entwurf als Auftrag |
| 28 | Klärung von OF-12 vor oder nach dem Bau | nach dem Bau; Bau folgt dem Entwurf | Betreiber wählte sdd-build mit Entwurf als Auftrag |
| 29 | Klärung von OF-13 vor oder nach dem Bau | nach dem Bau; Bau folgt dem Entwurf | Betreiber wählte sdd-build mit Entwurf als Auftrag |

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus Code, Konfiguration und Artefakten belegt. Kein Kriterium —
`sdd-qa` prüft nichts davon als bestanden, sondern nimmt es als Suchliste. Die Reihenfolge folgt der
Bedeutung für die Integrität der Update-Kette.

- **FB-01 · v1.1-Installationen hängen an einem freien GitHub-Namensraum.** `git show v1.1:Sources/Resources/Info.plist` (Zeile 28) und installiertes Bundle: `SUFeedURL = https://raw.githubusercontent.com/Mukaarts/MikaPlusPlayer/main/appcast.xml`. `GET https://api.github.com/users/Mukaarts` → 404 (2026-09-15); Konto `daumedia` ist ein umbenannter Benutzer (`owner_type: User`). Nach GitHubs Regeln für Umbenennungen ist der alte Name frei, und ein neues gleichnamiges Repository hebt die Weiterleitung auf. Folge: Wer den Namen registriert, steuert den Feed aller v1.1-Installationen — kann Updates dauerhaft unterdrücken, gefälschte Update-Hinweise mit beliebigen Links anzeigen (Informations-Updates öffnen die Adresse im Browser; Nutzer sind durch die FAQ bereits auf „Rechtsklick → Öffnen" trainiert) und signierte Archive unter falscher Versionsnummer erneut einspielen. Ein manipuliertes Binary lässt sich ohne Privatschlüssel nicht installieren. Ein Wechsel auf den neuen Feed geschieht erst nach einem Update — das es nicht gibt (FB-02). Außerhalb dieses Projekts beobachtet: Mika+FileScope fragt ebenfalls `raw.githubusercontent.com/Mukaarts/…` ab.
- **FB-02 · Kein Versionssprung seit v1.1, und die Build-Nummer gilt als optional.** `project.yml:34-35` (`MARKETING_VERSION` 1.1, `CURRENT_PROJECT_VERSION` 2) ist identisch mit dem Tag `v1.1`; `README.md` (Abschnitt *Veröffentlichen*): „und ggf. `CURRENT_PROJECT_VERSION`"; `release.sh` prüft keine Erhöhung. Folge: Ein Release von `main` erreicht keine bestehende Installation (Sparkle vergleicht `CFBundleVersion`) — damit bleiben auch alle v1.1-Installationen auf der gefährdeten Feed-URL aus FB-01.
- **FB-03 · Debug-Berechtigung und keine Hardened Runtime im Release.** Effektive Release-Settings: `ENABLE_HARDENED_RUNTIME = NO`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`; Release-`.xcent` vom 2026-06-23 und installierte v1.1: `get-task-allow = true`, CodeDirectory ohne `runtime`. Folge: Jeder Prozess des Benutzers kann sich an die laufende App hängen und ihren Speicher lesen — einschließlich der Xtream-Zugangsdaten (DM-01); `DYLD_INSERT_LIBRARIES` wird nicht blockiert; eine Notarisierung ist so nicht möglich.
- **FB-04 · `disable-library-validation` ohne tragfähige Begründung.** `MikaPlusPlayer.entitlements:9-12`, README-Abschnitt *macOS App Sandbox & Entitlements*: begründet mit „Hardened Runtime", die aus ist. Folge: Das Entitlement hat heute keinen Nutzen und würde nach Aktivieren der Hardened Runtime das Nachladen fremd signierter Bibliotheken erlauben.
- **FB-05 · Keine Developer-ID-Signatur, keine Notarisierung, DMG unsigniert.** `project.yml:70-71` (`CODE_SIGN_IDENTITY: "-"`), `spctl` → „rejected" für App und DMG. Das Stack-Profil `swiftui-macos` verlangt beides für eine Veröffentlichung. Folge: Die **Erstinstallation** ist nur durch TLS zu GitHub geschützt — die EdDSA-Signatur prüft niemand beim ersten Download; Nutzer werden angeleitet, Gatekeeper zu übergehen, und können ein untergeschobenes DMG nicht vom echten unterscheiden.
- **FB-06 · Kein Schlüsselwechsel möglich.** Ad-hoc-Signatur → Designated Requirement `cdhash H"a474f9b6…"`; Sparkle 2.9.3 akzeptiert ein Update nur bei gültiger EdDSA-Signatur **oder** passender Code-Signing-Identität (`SUUpdateValidator.m:373-376`). Folge: Bei Verlust oder Kompromittierung des Privatschlüssels lassen sich bestehende Installationen nie wieder per Sparkle aktualisieren — auch nicht, um sie gegen einen Angreifer mit dem alten Schlüssel abzusichern.
- **FB-07 · Ein EdDSA-Schlüssel für die ganze App-Familie.** `Info.plist:23-30` („familienweiter EdDSA-Public-Key"), README; identischer `SUPublicEDKey` in sechs installierten Apps. Folge: Eine Kompromittierung in einem beliebigen Mika+-Projekt oder auf einem beliebigen Rechner mit dem Schlüssel betrifft alle Apps; eine Signatur ist nicht an App oder Version gebunden.
- **FB-08 · Feed unsigniert, Signaturprüfung erst nach dem Entpacken.** `Info.plist:27-32`: weder `SURequireSignedFeed` noch `SUVerifyUpdateBeforeExtraction` gesetzt, obwohl Sparkle 2.9 signierte Feeds unterstützt. Folge: Feed-Inhalte (Einträge, Links, Hinweise) sind nur durch TLS und den GitHub-Zugang geschützt; ein unautorisiertes DMG wird vom Installer eingehängt, bevor seine Signatur geprüft ist.
- **FB-09 · Feed wird ungeschützt direkt aus `main` ausgeliefert.** `gh api repos/daumedia/MikaPlusPlayer/branches/main` → `protected: false`, Rulesets: 0. Folge: Jeder Push auf `main` — auch ein versehentlicher aus FB-10 — geht ohne Review binnen etwa fünf Minuten an alle Installationen.
- **FB-10 · `release.sh` überschreibt die versionierte `appcast.xml` mit dem lokalen Stand aus `dist/`.** `scripts/release.sh:26-29`; `dist/appcast.xml` enthält den nie veröffentlichten 1.0-Eintrag und `Mukaarts`-URLs. Folge: Beim nächsten Release kehren stillschweigend alte Einträge, alte Download-URLs (FB-01) und der alte Titel zurück; Handkorrekturen am Feed gehen verloren.
- **FB-11 · Keine Gegenprüfungen im Release-Ablauf.** `scripts/release.sh`, `build-macos.sh`, `make-dmg.sh`: kein `codesign --verify`, kein `spctl`, keine EdDSA-Gegenprobe des erzeugten Eintrags, keine Prüfung auf sauberen Git-Stand, Tag oder erhöhte Build-Nummer. Folge: Fehler aus FB-02, FB-03 oder FB-10 fallen erst bei Nutzern auf — oder nie.
- **FB-12 · Sparkle nicht gepinnt, aufgelöste Version nicht versioniert.** `project.yml:21-23` (`from: "2.6.0"`), `.gitignore:2` (`MikaPlusPlayer.xcodeproj/`). Folge: Builds aus einem frischen Klon können eine andere Sparkle-Version enthalten als v1.1; auch `generate_appcast` stammt dann aus einer anderen Version.
- **FB-13 · Dokumentierter Weg zu Developer ID und Notarisierung in falscher Reihenfolge.** README-Abschnitt *Öffentliche Distribution*: signiert `build/MikaPlusPlayer.app` **nach** `release.sh` und reicht dann das bereits erzeugte DMG ein; verwendet `codesign --deep`. Folge: Das DMG enthält weiter die ad-hoc-signierte App, die Notarisierung schlägt fehl oder — bei neu erzeugtem DMG — passt die EdDSA-Signatur im Feed nicht mehr. Nicht ausgeführt.
- **FB-14 · Website beschreibt den Update-Weg ungenau.** `web/app/changelog/page.tsx:21`: „The Mac app also checks this list for itself through Sparkle" — die App liest `appcast.xml` aus `main`, nicht die Releases; `web/content/features.ts:42-43`: „Updates that install themselves" — automatisch installiert wird erst nach Opt-in im Update-Dialog. Folge: Release-Liste und Feed können auseinanderlaufen, ohne dass die Website es zeigt; Nutzer erwarten eine Selbstinstallation, die nicht voreingestellt ist.
- **FB-15 · Datenschutzseite unvollständig für den Update-Weg.** `web/app/privacy/page.tsx:57-59` nennt IP-Adresse an GitHub, nicht den User-Agent mit App- und Sparkle-Version (AK-23) und nicht, dass die Prüfung ohne Einwilligung startet. Folge: unvollständige Information nach Art. 13 DSGVO.
- **FB-16 · Update-Risiko durch fehlende Schema-Migration.** `docs/datenmodell.md` DM-04 (`MikaPlusPlayerApp.swift:10-14`). Folge für B09: Ein Update mit nicht automatisch migrierbarer Modelländerung macht die App für jeden Nutzer unbrauchbar, ohne Rückweg — Sparkle hält keine Vorversion vor.
- **FB-17 · Keine Tests für die Update-Kette.** Kein Test prüft `SUFeedURL`, `SUPublicEDKey`, Entitlements oder Versionsfortschritt; `Tests/` enthält nur Parser-, URL- und Engine-Tests. Folge: FB-02, FB-03 und FB-10 können unbemerkt in ein Release gelangen.
