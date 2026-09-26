# B02 · M3U-Import — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-16 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Stand: `c01f1cf` + Reparatur B01 (2026-09-16).** Gelesen und ausgeführt wurde eine eingefrorene
> Kopie des Arbeitsbaums nach der B01-Reparatur. Die Pfade von B02 sind gegenüber `c01f1cf`
> **unverändert** (per `diff` geprüft): `M3UParser.swift`, in `PlaylistImporter.swift` die Methoden
> `importFromURL`, `importFromFile`, `attach`, `fetchText` und `decodeText`, die Reiter „URL" und
> „Datei" in `ImportPlaylistView.swift`, `CFBundleDocumentTypes` in `Info.plist` und
> `M3UParserTests`. Mittelbar wirkt die B01-Reparatur so: Die Datenbank liegt jetzt app-eigen
> (`AppPersistence`), der HTTP-Cache wird beim ersten Start einmal geleert, das gemeinsame Sheet hat
> einen abbrechbaren Xtream-Import, und der Test-Host arbeitet mit einer In-Memory-Datenbank.
>
> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code **tut**, nicht, was er tun sollte.
> Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen bewusst als Kriterium hier,
> damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind, steht ein Verweis auf
> *Fehlbestand*, sonst auf eine offene Frage.
>
> **Wie belegt.** Am 2026-09-16 **ausgeführt** in einer Kopie im Scratchpad. Die Kopie lief unter
> der eigenen Bundle-ID `lu.daumedia.MikaPlusPlayer.b02probe`, mit der Datenbank auf einer
> Temp-Datei und ohne Sparkle. Datenbank, Schlüsselbund und Cache des Nutzers blieben unberührt.
> Eine temporäre XCTest-Sonde im Test-Host der Mac-App hat Folgendes geprüft:
> (1) den Parser direkt und über den Dateipfad (Kodierung);
> (2) den URL-Import gegen lokale Mocks auf `127.0.0.1`: Status, Weiterleitungen, Kopfzeilen,
> Cookies, Plattencache, Zeitgrenzen und 17.000 Sender mit Main-Thread-Wächter;
> (3) den Datei-Import über `PlaylistImporter.importFromFile`: Endungen, Rechte, Symlinks, 50 MB;
> (4) die Reiter „URL" und „Datei" in einem echten Fenster, bedient über Accessibility.
> Außerdem wurde die gebaute Probe-App mit `open -a` und `.m3u`/`.m3u8`/`.txt` gestartet; die
> Fenster sind über `CGWindowList` gezählt.
> Nur macOS; iOS ist *(gelesen)*. Der Dateidialog selbst wurde nicht geöffnet. Welche Dateien
> wählbar sind, ist über die Typkonformität ausgeführt. Kriterien nur aus dem Code tragen den
> Vermerk *(gelesen)*. Erfundene Zugangsdaten (`qa-user`, `qa-pass-…`), kein echter Anbieter,
> keine öffentliche Liste abgerufen. Alles ohne Ton, keine Wiedergabe. Die Kopie ist gelöscht.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (alle Ausgaben), `qa-erfassung/sonde.patch`
> (Sonden-Code und Änderungen der Kopie), `qa-erfassung/mac-01-playlist-nach-url-import.png`.
>
> **Messumgebung für alle Zeitangaben:** Apple M3 Max, macOS 27.0, **Debug-Build** (Test-Host).
> Die Zahlen sind Ist-Werte zur Orientierung, keine Zielwerte.

## Zweck

Nutzer mit einem M3U-Link ihres Anbieters, einer öffentlichen Liste oder einer Playlist-Datei legen
daraus eine Playlist an. Die App liest je Sender den Namen, die Gruppe, das Logo und die tvg-ID. Eine
per URL importierte Playlist lässt sich später aktualisieren (B03).

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| — | — | B02 hat keine Vorstufe. Das Import-Sheet teilt es sich mit B01; die Playlist-Übersicht, aus der das Sheet geöffnet wird, gehört zu B03 |

Auf B02 bauen auf: B03 (Aktualisieren lädt `sourceURL` über denselben Abruf und Parser neu), B04
(zeigt die Sender, lädt die Logos), B05 (tvg-ID bzw. Name als Favoriten-Schlüssel), B06 (spielt die
Stream-Adresse unverändert).

## User Stories

- **US-01** · Als Nutzer mit einem M3U-Link möchte ich die Adresse einfügen, damit die Sender als
  aktualisierbare Playlist in der App landen.
- **US-02** · Als Nutzer mit einer Playlist-Datei möchte ich sie von der Festplatte auswählen, damit
  ich auch ohne Link Sender importieren kann.
- **US-03** · Als Nutzer möchte ich, dass Namen mit Kommas, Gruppen und Logos korrekt übernommen
  werden, damit die Senderliste aussieht wie beim Anbieter.
- **US-04** · Als Nutzer möchte ich bei einem gescheiterten Import erfahren, woran es lag.

## Nicht im Scope

- Aktualisieren und Löschen einer M3U-Playlist → **B03**. B03 nutzt dafür `fetchText` und den Parser
  aus B02; was hier über Abruf, Cache und Cookies steht, gilt beim Aktualisieren genauso.
- Anzeige der Senderliste und Laden der Logos → **B04**; Favoriten → **B05**; Wiedergabe → **B06**
- Reiter „Xtream" desselben Sheets → **B01**
- EPG (`url-tvg`, `x-tvg-url`), `tvg-name`, `tvg-chno`, Catch-up, `#EXTVLCOPT` und `#KODIPROP`
  (User-Agent, Referrer, DRM): werden nicht gelesen → OF-09
- Andere Formate (PLS, XSPF), mehrere Dateien auf einmal

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Für die Netzwerkkriterien genügt ein lokaler HTTP-Mock,
der Status, Kopfzeilen und Körper frei wählt und die Anfragen mitschreibt.

### Oberfläche

- **AK-01** · Angenommen, das Sheet „Playlist importieren" ist offen (Einstieg wie B01 AK-01), wenn der
  Reiter „URL" gewählt wird, dann sind zu sehen: der Abschnitt „Name (optional)" mit dem Feld
  „z. B. Mein IPTV-Anbieter", der Abschnitt „Playlist-URL" mit dem Feld „https://… .m3u8" und der
  Button „Von URL importieren". Beim Reiter „Datei" stehen dort „Name (optional)", der Abschnitt
  „Lokale Datei" und der Button „Datei auswählen (.m3u/.m3u8)". Eine eingegebene URL bleibt beim
  Wechsel zwischen den Reitern stehen. *(ausgeführt, macOS)*
- **AK-02** · Angenommen, der Reiter „URL" ist offen, wenn in das URL-Feld getippt wird, dann greift
  keine Autokorrektur. Auf iOS wird zusätzlich nichts automatisch großgeschrieben, und das Feld zeigt
  die URL-Tastatur. *(gelesen)*
- **AK-03** · Angenommen, der Reiter „URL" ist offen: Solange das URL-Feld leer ist, bleibt „Von URL
  importieren" deaktiviert. Schon ein einzelnes Leerzeichen aktiviert den Button. „Datei auswählen"
  ist immer aktiv, außer während eines Imports. *(ausgeführt)*
- **AK-04** · Angenommen, ein Import per URL läuft, dann zeigt das Formular die Zeile „Importiere…"
  mit Fortschrittsanzeige. Die Import-Buttons sind deaktiviert, „Abbrechen" bleibt bedienbar.
  *(ausgeführt für URL; für Datei gelesen)*
- **AK-05** · Angenommen, „Datei auswählen" wird angetippt, dann öffnet sich der Systemdialog zum
  Öffnen **einer** Datei. Wählbar sind M3U-Playlists (`.m3u`, `.m3u8`) und alle Typen, die als
  Klartext gelten, u. a. `.txt`, `.csv`, `.swift`, `.log`, `.md`. Nicht wählbar sind z. B. `.json`,
  `.html`, `.pls`, `.xspf` und Dateien ohne Endung. *(Typregel ausgeführt; Dialog gelesen)*

### Import per URL

- **AK-06** · Angenommen, die URL liefert HTTP 2xx und eine M3U mit N ≥ 1 gültigen Einträgen, wenn „Von
  URL importieren" angetippt wird, dann schließt sich das Sheet. In der Übersicht steht die neue
  Playlist an erster Stelle, mit Globus-Symbol und dem Badge „N Sender". *(ausgeführt, Aufnahme
  `mac-01-playlist-nach-url-import.png`)*
- **AK-07** · Angenommen, „Name (optional)" ist leer, dann heißt die Playlist wie der Host der URL,
  ohne Schema und Port (`127.0.0.1`, `localhost`). Hat die Adresse keinen Host (`file:`, `data:`),
  heißt sie „Playlist". Ein eingegebener Name wird exakt übernommen, auch „   " oder „  Mein Name  ".
  *(ausgeführt)*
- **AK-08** · Angenommen, eine URL wird importiert, dann gilt:
  (a) Leerzeichen, Tabs und Zeilenumbrüche vor und nach der URL werden entfernt.
  (b) Die Adresse wird genau einmal per GET abgerufen.
  (c) Leerzeichen und Umlaute im Pfad werden prozentkodiert (`/mit%20leerzeichen.m3u`,
  `/%C3%BCmlaut.m3u`).
  (d) Ein Fragment wird nicht gesendet.
  (e) Gespeichert wird die gekürzte Eingabe als Quelladresse, mit Großschreibung des Schemas,
  Query, Benutzerinfo und Fragment (`HTTP://…/gross.m3u`, `…/liste.m3u#fragment`).
  *(ausgeführt)*
- **AK-09** · Angenommen, die Antwort enthält eine gültige M3U, dann wird sie unabhängig vom
  `Content-Type` importiert: `audio/x-mpegurl`, `application/vnd.apple.mpegurl`, `text/html`,
  `application/octet-stream`, `image/png`. Ein `charset` in der Kopfzeile wird nicht beachtet.
  *(ausgeführt)*
- **AK-10** · Angenommen, der Server antwortet mit 200 oder 203, dann wird importiert. Bei 204 oder
  leerem Körper lautet die Meldung „Die Playlist enthält keine gültigen Sender.". Jeder Status
  außerhalb von 200–299 ergibt „Netzwerkfehler: HTTP <Status>", geprüft mit 300, 304, 400, 401, 403,
  404, 407, 429, 500 und 503. *(ausgeführt)*
- **AK-11** · Angenommen, der Server antwortet mit einer Weiterleitung (301, 302, 307), dann folgt die
  App ohne Rückfrage, auch auf einen anderen Host oder Port. Das Ziel bekommt genau die Adresse aus
  `Location`, samt Query. Gespeichert wird die ursprünglich eingegebene Adresse. Bei einer Schleife
  lautet die Meldung nach 21 Anfragen „Netzwerkfehler: too many HTTP redirects". Eine Weiterleitung
  auf `file:` ergibt „Netzwerkfehler: You do not have permission to access the requested resource.".
  *(ausgeführt)*
- **AK-12** · Angenommen, die Eingabe hat kein erkennbares Schema (`127.0.0.1:8080/liste.m3u`,
  `example.invalid/liste.m3u`, nur Leerzeichen), dann lautet die Meldung „Die angegebene URL ist
  ungültig.", und es wird nichts gesendet. Hat sie ein Schema, aber kein abrufbares Ziel, gilt:
  `localhost:8080/…` (Schema „localhost") und `javascript:…` → „Netzwerkfehler: unsupported URL";
  `http://` bzw. `http:///liste.m3u` ohne Host → „Netzwerkfehler: Could not connect to the
  server."; `ftp://…` → „Netzwerkfehler: The request timed out." nach der Leerlaufzeit. *(ausgeführt;
  Wartezeit aus der Laufzeit des Testlaufs abgeleitet, ≈ 60 s)*
- **AK-13** ⚠ · Angenommen, im URL-Feld steht eine `file:`-Adresse einer lokalen M3U oder eine
  `data:…;base64,…`-Adresse mit eingebetteter Liste, dann wird sie importiert. Die Playlist heißt
  „Playlist", hat das Globus-Symbol und gilt als aktualisierbar. Bei `data:` steht der gesamte Inhalt
  als Quelladresse in der Datenbank. *(ausgeführt; Absicht unklar → OF-02)*
- **AK-14** · Angenommen, die URL enthält eine Benutzerinfo (`http://user:pass@host/liste.m3u`), dann
  geht die erste Anfrage ohne `Authorization`-Kopfzeile. Verlangt der Server Basic-Auth (401 mit
  `WWW-Authenticate`), wiederholt die App die Anfrage mit Benutzer und Passwort aus der Adresse.
  Leitet der Server danach auf einen anderen Host weiter, erhält dieser keine
  `Authorization`-Kopfzeile. *(ausgeführt)*
- **AK-15** ⚠ · Angenommen, eine Playlist mit derselben URL existiert schon, wenn noch einmal importiert
  wird, dann entsteht eine zweite, unabhängige Playlist mit eigenen Sendern. Es gibt weder Warnung
  noch Dublettenprüfung. *(ausgeführt; Absicht unklar → OF-01)*

### Import aus einer Datei

- **AK-16** · Angenommen, eine lesbare Datei mit N ≥ 1 gültigen Einträgen wird gewählt, dann schließt
  sich das Sheet. Die neue Playlist steht oben, mit Dokument-Symbol und „N Sender". Ohne eingegebenen
  Namen heißt sie wie die Datei ohne die letzte Endung: `liste.v2.m3u` → „liste.v2",
  `Sender & Ümlaut (Kopie).M3U8` → „Sender & Ümlaut (Kopie)", `.m3u` → „.m3u". Ein eingegebener Name
  wird exakt übernommen. Die Playlist hat keine Quelladresse und keinen Aktualisierungszeitpunkt, ihr
  Kontextmenü bietet kein „Aktualisieren". *(Anlage und Name ausgeführt; Symbol und Menü gelesen)*
- **AK-17** · Angenommen, eine Datei enthält eine gültige M3U, dann entscheidet der Inhalt, nicht die
  Endung: Mit `.txt`, `.csv`, `.swift`, `.png` oder ohne Endung wird sie genauso importiert. Eine
  `.txt`-Datei ohne `#EXTINF`-Einträge ergibt „Die Playlist enthält keine gültigen Sender.". Über den
  Dialog erreichen die App nur die Typen aus AK-05. *(ausgeführt über den Importpfad)*
- **AK-18** · Angenommen, die gewählte Datei ist nicht lesbar, dann lautet die Meldung „Auf die
  ausgewählte Datei kann nicht zugegriffen werden.". Das gilt für: Rechte `000`, Datei in einem
  Ordner mit Rechten `000`, Datei gelöscht, Ordner statt Datei, Symlink ins Leere, Named Pipe. Ein
  Symlink, auch eine Kette von Symlinks, auf eine lesbare Datei wird gelesen; der Name kommt vom
  Symlink, nicht vom Ziel. *(ausgeführt)*
- **AK-19** · Angenommen, auf iOS wird im Dateien-Dialog eine Datei außerhalb des App-Containers
  gewählt, dann liest die App sie mit vorübergehendem Zugriffsrecht (security-scoped) und gibt das
  Recht danach wieder ab. *(gelesen; unter macOS ohne Sandbox ohne Wirkung, dort ausgeführt)*

### Parser (gemeinsam für URL und Datei)

- **AK-20** · Angenommen, eine Liste wird gelesen, dann entsteht ein Sender aus einer Zeile, die mit
  `#EXTINF:` beginnt (genau so, großgeschrieben, mit Doppelpunkt), und der nächsten Zeile, die weder
  leer ist noch mit `#` beginnt. Diese Zeile muss eine Adresse mit Schema sein. `#EXTM3U` ist nicht
  nötig. Leerzeilen, Kommentare, `#EXTVLCOPT` und `#KODIPROP` dazwischen stören nicht. Leerzeichen
  und Tabs am Zeilenrand werden ignoriert. *(ausgeführt)*
- **AK-21** · Angenommen, eine `#EXTINF`-Zeile wird gelesen, dann ist der Anzeigename der Text nach dem
  ersten Komma, das nicht in doppelten Anführungszeichen steht, ohne Leerzeichen am Rand. Kommas und
  Anführungszeichen im Namen bleiben erhalten (`Das Erste, HD`, `Sender "Eins", HD`). Ein Komma in
  einem Attributwert trennt nicht (`group-title="News, Politik"`, Logo-Adresse mit `,`). Ist der Name
  leer oder fehlt das Komma, heißt der Sender wie der letzte Pfadabschnitt seiner Adresse
  (`stream-name.ts`). *(ausgeführt; Tests `testQuoteSafeNameWithCommas`, `testMinimalEntry`)*
- **AK-22** · Angenommen, vor dem Namenskomma stehen Attribute, dann gilt:
  (a) Gelesen werden nur `tvg-id`, `tvg-logo` und `group-title`; die Groß- und Kleinschreibung des
  Schlüssels ist egal.
  (b) Der Wert muss in doppelten Anführungszeichen stehen. Leerzeichen um `=` und Tabs als Trenner
  sind erlaubt.
  (c) Kommt ein Attribut mehrfach vor, gilt der letzte Wert. Ein leerer Wert fehlt am Sender.
  (d) Leerzeichen am Rand eines Werts bleiben (`" News "`).
  (e) Werte ohne Anführungszeichen oder in einfachen Hochkommas werden nicht gelesen.
  (f) Attribute nach dem Namenskomma gehören zum Namen.
  *(ausgeführt)*
- **AK-23** · Angenommen, zwischen `#EXTINF` und Adresse steht `#EXTGRP:<Gruppe>`, dann erhält der
  Sender diese Gruppe, falls `group-title` fehlt. Bei mehreren gilt die erste, eine leere wird
  ignoriert. Vor dem `#EXTINF`, kleingeschrieben oder für Folgesender wirkt sie nicht.
  *(ausgeführt; Test `testExtGrpFallback`)*
- **AK-24** · Angenommen, die Liste hat Zeilenenden LF, CRLF, CR oder gemischt, dann werden die Sender
  gleich erkannt. *(ausgeführt)*
- **AK-25** · Angenommen, der Text ist gültiges UTF-8, mit oder ohne BOM, dann wird er so gelesen. Ist
  er kein gültiges UTF-8, wird er als ISO-Latin-1 gelesen, sodass „Österreich" aus einer Latin-1-Datei
  richtig ankommt. *(ausgeführt, Datei und URL)*
- **AK-26** · Angenommen, die Liste enthält keinen einzigen gültigen Eintrag (leer, HTML-Seite, JSON,
  nur Adressen ohne `#EXTINF`), dann lautet die Meldung „Die Playlist enthält keine gültigen Sender.",
  und nichts wird angelegt. Ungültige Einträge in einer sonst gültigen Liste fallen still weg.
  *(ausgeführt)*

### Fehler und Verhalten des Sheets

- **AK-27** · Angenommen, ein Import per URL scheitert, dann erscheint im offenen Sheet der Alert „Fehler"
  mit der Meldung und „OK". Nach „OK" stehen Name und URL noch im Formular, „Von URL importieren" ist
  sofort bedienbar, und es ist keine Playlist angelegt. *(ausgeführt mit „Netzwerkfehler: HTTP 404"
  und „Die angegebene URL ist ungültig."; für Datei gelesen)*
- **AK-28** · Angenommen, der Server ist nicht erreichbar, dann lautet die Meldung „Netzwerkfehler:" plus
  englischer Systemtext: geschlossener Port „Could not connect to the server.", unbekannter Host
  „A server with the specified hostname could not be found.", 60 s ohne Daten „The request timed
  out.". *(ausgeführt)*
- **AK-29** ⚠ · Angenommen, ein Import per URL läuft, wenn „Abbrechen" angetippt wird, dann schließt sich
  nur das Sheet, und der Import läuft weiter. Gelingt er, erscheint die Playlist einige Sekunden
  später in der Übersicht. Scheitert er, taucht das geschlossene Sheet losgelöst vom Hauptfenster
  wieder auf dem Bildschirm auf, samt eingegebener URL und dem Alert „Fehler". Auf iOS wird das
  Wegwischen gleich behandelt. *(macOS ausgeführt, `CGWindowList`: on screen; iOS und Datei-Import
  gelesen; als Fehler eingestuft → FB-08)*
- **AK-30** ⚠ · Angenommen, „Von URL importieren" wird zweimal kurz hintereinander geklickt, dann starten
  zwei Importe, wenn beide Klicks vor dem Neuzeichnen ankommen: zwei Anfragen, zwei gleiche
  Playlists. Mit 150 ms Abstand bleibt es bei einem Import. *(ausgeführt; als Fehler eingestuft →
  FB-09)*

### Öffnen aus dem System

- **AK-31** ⚠ · Angenommen, eine `.m3u`-, `.m3u8`- oder `.txt`-Datei wird mit Mika+Player geöffnet
  („Öffnen mit", `open -a`), dann gilt:
  (a) Läuft die App nicht, startet sie mit einem leeren Fenster „Playlists".
  (b) Läuft sie, öffnet sie bei jedem Öffnen ein **zusätzliches** leeres Fenster „Playlists".
  (c) Es wird nichts importiert, und es erscheint keine Meldung.
  (d) Ein Doppelklick im Finder öffnet auf dem Prüfrechner gar nicht Mika+Player, sondern die
  Standard-App des Typs: Music für `.m3u`/`.m3u8`, TextEdit für `.txt`.
  *(ausgeführt: 1 → 2 → 3 → 4 Fenster, 0 Playlists; Standard-App über `NSWorkspace` ermittelt;
  als Fehler eingestuft → FB-06)*
- **AK-32** ⚠ · Angenommen, die App ist installiert, dann bietet sie sich dem System als Öffner (Rang
  „Default") für M3U-Playlists **und für alle Text-Typen** an. Dazu zählen auch `.json`, `.html`,
  `.csv`, `.swift`, `.md`, `.log` und `.pls`. *(ausgeführt über Typkonformität und die
  Kandidatenliste von LaunchServices; als Fehler eingestuft → FB-07)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Jede Frage hat ein
Kriterium, ein „trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-33** · Angenommen, ein Import per URL scheitert, dann enthält die Meldung weder Benutzername noch
  Passwort noch die Adresse, auch wenn sie in Query oder Benutzerinfo stehen. *(ausgeführt für
  HTTP-Status, Weiterleitungsschleife, leere Liste, geschlossenen Port, unbekannten Host, `ftp:` mit
  Benutzerinfo, fehlendes Schema)*
- **AK-34** ⚠ · Angenommen, eine M3U-URL mit Zugangsdaten wird importiert
  (`…/get.php?username=…&password=…` oder `http://user:pass@…`), dann gilt:
  (a) Das Passwort steht im Klartext in `Playlist.sourceURL`.
  (b) Enthält die Liste Stream-Adressen mit Zugangsdaten, wie bei `get.php` üblich, steht es
  zusätzlich in **jeder** `Channel.streamURL`.
  (c) Die B01-Reparatur greift hier nicht: Es entsteht kein Schlüsselbund-Eintrag, die Umstellung
  beim Start meldet 0 Playlists und lässt die Adressen unverändert, und der `StreamURLResolver` reicht
  die Adresse mit Passwort zum Abspielen durch.
  (d) Die Datenbank ist nicht vom Backup ausgeschlossen. Die B01-Reparatur begründet das damit, dass
  sie keine Zugangsdaten mehr enthalte; für M3U-Playlists stimmt das nicht.
  *(ausgeführt: 1 Quelladresse und 3 von 3 Stream-Adressen mit Passwort; Backup gelesen; als Fehler
  eingestuft → FB-01)*
- **AK-35** ⚠ · Angenommen, eine URL wurde importiert, wenn der HTTP-Cache der App untersucht wird
  (macOS `~/Library/Caches/<Bundle-ID>/Cache.db`, iOS `Library/Caches`), dann stehen dort die
  Anfrage-Adresse samt Query mit Zugangsdaten und der Antwortkörper mit den Stream-Adressen. Das
  Löschen der Playlist entfernt den Eintrag nicht. Nur ein `Cache-Control: no-store` des Servers
  verhindert den Eintrag. *(ausgeführt; das einmalige Leeren aus B01 läuft nur beim ersten Start nach
  der Reparatur; als Fehler eingestuft → FB-02)*
- **AK-36** · Angenommen, eine URL wird abgerufen, dann schickt die App die Kopfzeilen `User-Agent`
  (`Mika+Player/<Build> CFNetwork/<Version> Darwin/<Version>`), `Accept: */*`, `Accept-Language`
  (Sprache des Systems, z. B. `de-DE,de;q=0.9`), `Accept-Encoding`, `Connection` und `Host`. Einen
  `Referer` schickt sie nicht. Setzt der Server ein Cookie, speichert die App es und schickt es beim
  nächsten Abruf desselben Hosts mit, auch beim Aktualisieren (B03). *(ausgeführt; ob das Cookie über
  einen Neustart erhalten bleibt, nicht geprüft)*
- **AK-37** ⚠ · Angenommen, eine Antwort oder Datei ist sehr groß, dann wird sie ohne Grenze vollständig
  in den Speicher gelesen und importiert. Geprüft: 52 MB mit 1.000 Einträgen und 52.000 Zeichen
  langen Namen, per URL und per Datei. Namen, Gruppen, Logo- und Stream-Adressen werden ungekürzt
  gespeichert (1 MB Name, 5 MB Logo-Adresse, 2 MB Stream-Adresse im Parser). Eine Mengengrenze gibt
  es nicht. *(ausgeführt: 52 MB, Speicher des Prozesses bei Datei +120 MB, bei URL +223 MB; als Fehler
  eingestuft → FB-03)*
- **AK-38** ⚠ · Angenommen, der Server sendet langsam, dann bricht der Abruf nur nach 60 s ohne Daten ab.
  Eine Gesamtfrist gibt es nicht: Eine Antwort in 10 Stücken alle 10 s (100 s) wird importiert.
  *(ausgeführt; als Fehler eingestuft → FB-03)*
- **AK-39** ⚠ · Angenommen, eine Liste enthält Adressen mit beliebigem Schema, dann werden sie ohne
  Prüfung als Stream- bzw. Logo-Adresse übernommen: `file:///etc/hosts`,
  `file:///Users/…/privat.mp4`, `javascript:`, `data:`, `smb://`, `udp://@239.0.0.1:1234`, `rtp:`,
  `rtsp:`, `rtmp:`, `ftp:`, `mailto:`, `vlc://quit`, `x-apple.systempreferences:…`. Verworfen werden
  nur Adressen ohne Schema. *(ausgeführt; als Fehler eingestuft → FB-05)*
- **AK-40** ⚠ · Angenommen, eine große Liste wird importiert, dann steht die Oberfläche still, bis
  Dekodieren, Parsen, Anlegen und Speichern fertig sind. Nur das Warten auf die Netzantwort blockiert
  nicht. Die Dauer wächst quadratisch mit der Senderzahl.

  | Sender (per URL) | gesamt | längster Stillstand des Main-Threads |
  |---|---|---|
  | 1.500 | 2,4 s | 2,3 s |
  | 3.000 | 9,4 s | 9,3 s |
  | 6.000 | 36,3 s (Store-Datei: 35,8 s) | 36,3 s |
  | **17.000** | **286,6 s** | **286,6 s** |
  | 1.000 mit je 52 KB Namen (52 MB) | 3,5 s (Datei: 3,7 s) | 3,5 s (Datei: 3,7 s) |

  Der Parser allein braucht für 17.000 Einträge 0,31 s. *(ausgeführt; als Fehler eingestuft →
  FB-04)*
- **AK-41** · Angenommen, ein Import per URL scheitert, wenn das Systemprotokoll mitgelesen wird, dann
  gilt: Die App selbst protokolliert nichts. CFNetwork schreibt die fehlgeschlagene Adresse ins
  Protokoll. In einem normal gestarteten Prozess erscheint sie dort als `<private>`. In einem von Xcode
  gestarteten Debug-Prozess steht sie im Klartext, samt Zugangsdaten. *(ausgeführt: gleicher Aufruf in
  einem eigenständigen Prozess 0 Klartext-Vorkommen, 2 × `<private>`; im Test-Host unter `xcodebuild`
  5 Klartext-Vorkommen. Ein normal gestarteter Build der App selbst ist nicht geprüft)*
- **AK-42** · Angenommen, eine M3U-Playlist mit Zugangsdaten in den Adressen wird über die App gelöscht
  (B03), dann steht das Passwort, solange die Datenbank offen ist, noch in der `-wal`-Datei. Nach dem
  Schließen steht es in keiner der Dateien `*.store`, `-wal`, `-shm` mehr. Nicht erfasst werden
  Cache (AK-35), Cookies (AK-36) und Backups (AK-34). *(ausgeführt mit Temp-Store)*
- **AK-43** · Angenommen, die gesamte Git-Historie wird nach `username=`, `password=` und `.m3u`-Dateien
  durchsucht, dann finden sich nur Beispielwerte (`demo`/`secret`, `u`/`p`, Platzhalter), keine
  echten M3U-Links und keine eingecheckte Playlist-Datei. *(ausgeführt am 2026-09-16 über alle
  19 Commits)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B02 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Zugangsdaten, sofern der Anbieter sie in die M3U-URL oder die Stream-Adressen schreibt (AK-34). Der Host verrät das Abo. Beim Anbieter kommen IP-Adresse, App-Name, Build- und Systemversion sowie die Systemsprache an (AK-36). Cookies des Servers (AK-36). Der lokale Pfad einer Datei wird nicht gespeichert, nur ihr Name als Playlist-Name |
| 1.2 | Besondere Kategorien? | Trifft nicht zu, weil B02 nur die Senderliste des Anbieters speichert. Rückschlüsse aus bevorzugten Sendern entstehen erst durch Favoriten → B05 |
| 1.3 | Wo gespeichert, wie lange? | Datenbank: unbefristet bis zum Löschen der Playlist (AK-34, AK-42). HTTP-Cache: bis das System ihn räumt (AK-35). Cookies: laut Ablaufdatum des Servers (AK-36). Backups: FB-01. Eine Löschfrist gibt es nicht |
| 1.4 | Landen sie in Logs? | Die App schreibt kein Protokoll. CFNetwork protokolliert Fehler-Adressen, im normalen Betrieb als `<private>` (AK-41). In Fehlermeldungen nicht (AK-33). Im HTTP-Cache ja (AK-35 / FB-02) |
| 2.1 | Welche externen Dienste? | Der Server der eingegebenen URL, bei Weiterleitung auch das Ziel (AK-11). Logo- und Stream-Hosts aus der Liste werden hier nur gespeichert und erst in B04/B06 kontaktiert. Keine KI, keine Analyse, kein Fehler-Tracking |
| 2.2 | Was wird übertragen, was vorher entfernt? | Die vollständige Adresse samt Query, bei 401 auch Basic-Auth aus der Benutzerinfo (AK-14), außerdem Kopfzeilen und Cookies (AK-36). Entfernt wird nichts, nur ein Fragment wird nicht gesendet. HTTP ist erlaubt. Ein Hinweis auf unverschlüsselte Zugangsdaten wie seit B01 im Xtream-Reiter fehlt hier → OF-05 |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil der Nutzer die Quelle selbst wählt und die App direkt dort abruft. daumedia empfängt nichts |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Der lokale Nutzer: alles, Löschen über B03. Unter macOS können alle Prozesse desselben Benutzers Datenbank, Cache und Cookies lesen, weil die Sandbox aus ist. Die App selbst liest jede Datei, die der Benutzer lesen darf (AK-18), und jede `file:`-Adresse (AK-13, AK-39) |
| 3.2 | Erzwungen in DB oder Anwendung? | Nirgends in der App. Auf iOS schützt die App-Sandbox des Systems, auf macOS nichts |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keinen Server der App und keine per ID abrufbaren Ressourcen gibt |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit auf die Anmeldung | Trifft nicht zu, weil B02 keine Anmeldung hat. Basic-Auth beantwortet CFNetwork einmal mit den Daten aus der Adresse (AK-14) |
| 4.2 | Rate Limit für Kostenpflichtiges | Trifft nicht zu, weil B02 keinen kostenpflichtigen Dienst des Betreibers aufruft |
| 4.3 | Kosten je Aufruf | Trifft nicht zu, siehe 4.2 |
| 4.4 | Uploads: Größe, Typ, Inhalt, Speicherort | Datei-Import und Netzantwort sind unvertraute Eingaben. Größe: keine Grenze → **FB-03**. Typ: Der Dialog lässt nur M3U und Klartext zu (AK-05); geprüft wird dann der Inhalt, nicht die Endung (AK-17). Inhalt: Schemata der Adressen ungeprüft → **FB-05**. Speicherort: Die Datei wird nicht kopiert, nur die geparsten Einträge landen in der Datenbank |
| 4.5 | Wo greift das Limit? | Nirgends, siehe FB-03. Einzige Grenzen: 60 s ohne Daten (AK-28) und 20 Weiterleitungen (AK-11), beides Voreinstellungen von `URLSession` |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil die App kein eigenes Konto hat. Die Playlist löscht der Nutzer über B03 |
| 5.2 | Was wird dabei gelöscht? | Playlist und alle Sender, nach dem Schließen auch aus den Datenbankdateien (AK-42). **Nicht** gelöscht werden Cache-Eintrag, Cookies und Backups → FB-01, FB-02 |
| 5.3 | Was bleibt, und warum? | Cache, Cookies und Backup-Kopien bleiben, ohne Begründung → FB-01, FB-02 |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil daumedia keine Daten erhält. Alles liegt auf dem Gerät des Nutzers |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine App-Schlüssel. Geheimnisse sind nur die Zugangsdaten in einer M3U-URL; sie liegen nicht im Schlüsselbund → FB-01 |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Nein: AK-43 |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B02 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Einfache M3U nur aus Adresszeilen, ohne `#EXTINF` → 0 Sender, „Die Playlist enthält keine
  gültigen Sender.". *(ausgeführt → OF-03)*
- **EC-02** · `#extinf:` kleingeschrieben oder `#EXTINF -1,…` ohne Doppelpunkt → Eintrag wird als
  Kommentar übersprungen. *(ausgeführt)*
- **EC-03** · Ungültige Adresszeile nach `#EXTINF` (z. B. `kein url`) → Der Eintrag ist verbraucht;
  eine direkt folgende gültige Adresse ohne eigenes `#EXTINF` fällt ebenfalls weg. Zwei `#EXTINF`
  hintereinander → der zweite gilt. Zwei Adressen nach einem `#EXTINF` → nur die erste.
  `#EXTINF` am Dateiende ohne Adresse → verworfen. *(ausgeführt)*
- **EC-04** · Ungerade Zahl doppelter Anführungszeichen vor dem Namen → Es gibt kein Namenskomma;
  der Name wird zum letzten Pfadabschnitt der Adresse. `group-title="News,Das Erste` ergibt die
  Gruppe „News,Das Erste". Fehlt ein schließendes Anführungszeichen, frisst der Wert das nächste
  Attribut (`tvg-id="abc group-title=`). *(ausgeführt)*
- **EC-05** · Einfache Hochkommas mit Komma im Wert (`group-title='Grp, X',Name`) → Name „X',Name",
  keine Gruppe. *(ausgeführt)*
- **EC-06** · Unicode-Zeilentrenner im Namen (U+2028, U+0085, vertikaler Tab) → Die Zeile wird dort
  geteilt, der Sender geht ohne Meldung verloren. NUL, ESC-Sequenzen (`\u{1B}[31m`) und
  Bidi-Override (U+202E) bleiben im Namen stehen und erreichen die Anzeige in B04. *(ausgeführt)*
- **EC-07** · Überwiegend UTF-8 mit einem einzigen ungültigen Byte → Die **ganze** Datei wird als
  Latin-1 gelesen: „Ärger TV" wird zu „Ã\u{84}rger TV", „Österreich" zu „Ã\u{96}sterreich".
  *(ausgeführt → OF-06)*
- **EC-08** · Windows-1252 mit `…` (0x85) → Latin-1 macht daraus U+0085, einen Zeilentrenner; der
  Sender geht verloren (EC-06). `€` (0x80) wird zum Steuerzeichen U+0080. *(ausgeführt → OF-06)*
- **EC-09** · UTF-16 mit BOM, auch mit `charset=utf-16` in der Antwort → 0 Sender, „Die Playlist enthält
  keine gültigen Sender.". *(ausgeführt → OF-06)*
- **EC-10** · Relative Adressen (`stream.m3u8`, `/live/1.ts`, `../live/1.ts`, `//cdn.example/1.ts`)
  → verworfen, auch in einer lokalen Datei, neben der die Datei liegt. Sie werden nicht gegen
  Playlist-Adresse oder Dateiort aufgelöst. `C:\Videos\a.ts` wird dagegen als `C:%5CVideos%5Ca.ts`
  (Schema „C") übernommen, `localhost:8080/live/1.ts` mit Schema „localhost". *(ausgeführt → OF-04)*
- **EC-11** · Logo-Adresse mit Leerzeichen → prozentkodiert als relative Adresse gespeichert
  (`kein%20url%20mit%20leer%20zeichen`). Relative Logo-Pfade (`logos/a.png`) bleiben relativ.
  *(ausgeführt)*
- **EC-12** · Derselbe Sender zweimal in der Liste → zwei Sender. *(ausgeführt)*
- **EC-13** · Sehr lange Zeilen: 1 MB Name, 5 MB Logo-Adresse, 2 MB Stream-Adresse, 1 MB Gruppe,
  1 MB Anführungszeichen, 500.000 × `a=` → alles ungekürzt übernommen, Parser je 0,1–0,7 s.
  *(ausgeführt → FB-03)*
- **EC-14** · 300.000 Einträge in 46,5 MB → Parser allein 5,5 s, Prozessspeicher +370 MB. Der
  vollständige Import in dieser Größe ist nicht ausgeführt. Nach der gemessenen quadratischen Kurve
  (AK-40) läge er bei vielen Stunden eingefrorener Oberfläche. *(Parser ausgeführt, Import
  hochgerechnet)*
- **EC-15** · Captive Portal oder Login-Seite des Anbieters mit Status 200 → „Die Playlist enthält keine
  gültigen Sender.". *(ausgeführt mit HTML-Antwort)*
- **EC-16** · Status 203 → Import; Status 304 → „Netzwerkfehler: HTTP 304". *(ausgeführt)*
- **EC-17** · `ftp://`-Adresse → Wartezeit bis zur Leerlaufgrenze (≈ 60 s, aus der Testlaufzeit), dann „Netzwerkfehler: The request timed out."; mit
  Benutzerinfo auf geschlossenem Port sofort „Netzwerkfehler: unknown error". *(ausgeführt)*
- **EC-18** · Datei im iCloud-Drive-Ordner, die noch nicht lokal geladen ist → nicht geprüft. Es
  wurde keine Datei dort erzeugt und keine vorhandene gelesen, weil sie Zugangsdaten enthalten
  könnte. Gelesen wird ohne `NSFileCoordinator`. *(gelesen → OF-07)*
- **EC-19** · Datei auf einem langsamen Volume → Das Lesen läuft synchron auf dem Main-Thread; die
  Oberfläche steht bis zum Ende still (AK-40, 52-MB-Datei 3,7 s). Eine Named Pipe als Ersatz für ein
  langsames Volume ergab sofort den Zugriffsfehler (AK-18). *(ausgeführt)*
- **EC-20** · Reiterwechsel während eines URL-Imports → Der Import läuft weiter, „Importiere…" steht auf
  jedem Reiter. *(für den Xtream-Import in B01 EC-21 ausgeführt; für URL gelesen)*
- **EC-21** · Erfolgreicher Import nach „Abbrechen" → Das Sheet lässt sich danach normal wieder öffnen.
  Ein ausstehender Alert hängt nicht am neuen Sheet, sondern steht im losgelösten alten Fenster
  (AK-29). *(ausgeführt)*
- **EC-22** · Öffnen einer Datei mit der App, danach Neustart → macOS stellt alle zusätzlich geöffneten
  leeren Fenster wieder her. Im Test waren es 3 bzw. 4 Fenster, mit einem weiteren für die beim Start
  übergebene Datei. *(ausgeführt)*
- **EC-23** · iOS: „Öffnen in Mika+Player" aus einer anderen App → Das System kopiert die Datei in den
  App-Container (Inbox) und übergibt die Adresse. Mangels Handler passiert nichts, die Kopie bleibt
  liegen. Beim iOS-Build erscheint die Warnung, dass `LSSupportsOpeningDocumentsInPlace` fehlt
  (B01-Build-Bericht). *(gelesen → FB-06)*
- **EC-24** · Öffentliche Demo-Liste, die Website und README empfehlen
  (`https://iptv-org.github.io/iptv/index.m3u`) → nicht abgerufen, weil kein Netzzugriff auf fremde
  Listen erlaubt war. Ihre `#EXTVLCOPT`-Zeilen (Referrer, User-Agent) würden ignoriert (AK-20). Ihre
  Größe bestimmt die Stillstandszeit nach AK-40. *(gelesen → OF-09)*

## Offene Fragen

Alle vom 2026-09-16. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde nach
der QA von B02.

- **OF-01** · Soll ein erneuter Import derselben URL eine zweite Playlist anlegen (AK-15), oder soll die
  App auf die vorhandene hinweisen bzw. sie aktualisieren? Gleiche Frage wie B01 OF-01, sinnvoll
  gemeinsam zu entscheiden.
- **OF-02** · Sollen `file:`- und `data:`-Adressen im URL-Feld erlaubt sein (AK-13)? Heute gilt eine so
  importierte lokale Datei als aktualisierbare Remote-Playlist, und bei `data:` steht die ganze Liste
  als Adresse in der Datenbank.
- **OF-03** · Sollen einfache M3U-Listen ohne `#EXTINF` importiert werden (EC-01), z. B. mit dem Dateinamen
  der Adresse als Sendername?
- **OF-04** · Sollen relative Adressen gegen die Playlist-Adresse bzw. den Ort der Datei aufgelöst werden
  (EC-10)?
- **OF-05** · Soll der URL-Reiter wie seit B01 der Xtream-Reiter darauf hinweisen, dass eine `http://`-
  Adresse mit Zugangsdaten unverschlüsselt übertragen wird (Katalog 2.2)?
- **OF-06** · Soll die Kodierung robuster erkannt werden (EC-07 bis EC-09)? Heute kippt ein einziges
  ungültiges Byte die ganze Datei nach Latin-1, 0x85 zerreißt Zeilen, und UTF-16 wird nicht erkannt.
  Der Code-Kommentar beschreibt nur „UTF-8 mit Latin-1-Fallback".
- **OF-07** · Wie soll sich der Import bei iCloud-Dateien verhalten, die noch nicht lokal liegen (EC-18)?
  Das braucht einen Test auf Gerät bzw. mit echtem iCloud-Konto.
- **OF-08** · Sollen Fehlermeldungen englische Systemtexte und rohe HTTP-Codes zeigen (AK-12, AK-28)?
  Gleiche Frage wie B01 OF-06.
- **OF-09** · Sollen `#EXTVLCOPT` (User-Agent, Referrer), `tvg-name` und `url-tvg` gelesen werden (EC-24)?
  Ohne sie spielen manche Sender öffentlicher Listen nicht (B06). Das wäre eine Erweiterung mit
  eigener Feature-Nummer.

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft
nichts davon als bestanden, sondern nimmt es als Suchliste. Fundstellen beziehen sich auf `Sources/`
im Stand `c01f1cf` + Reparatur B01.

- **FB-01 · Zugangsdaten aus M3U-Links liegen im Klartext in der Datenbank; der Schutz aus B01 greift
  nicht.**
  Fundstelle: `PlaylistImporter.swift:63` speichert die eingegebene URL als `sourceURL`;
  `PlaylistImporter.swift:289-298` speichert jede Stream-Adresse unverändert. Die B01-Maßnahmen
  wirken nur für `isXtream`: `StreamURLResolver.swift:25`, `AppPersistence.swift:131`. Die Begründung
  für den fehlenden Backup-Ausschluss steht in `AppPersistence.swift:16-17`.
  Folge: `get.php?username=…&password=…` ist der übliche Weg, auf dem Anbieter M3U-Links ausgeben.
  Wer so importiert, hat dieselbe Lücke wie B01 vor der Reparatur (B01 FB-01): 1 Kopie in der
  Playlist-Adresse, bei 17.000 Sendern bis zu 17.000 weitere. Die Kopien sind für jeden Prozess des
  Benutzers lesbar und landen im Backup, weil die Datenbank ausdrücklich mit der Begründung „enthält
  keine Zugangsdaten mehr" nicht ausgeschlossen ist. (AK-34)
- **FB-02 · Anfrage-Adresse samt Zugangsdaten und Antwort landen im HTTP-Plattencache und überstehen das
  Löschen.**
  Fundstelle: `PlaylistImporter.swift:307-311` nutzt `URLSession.shared`. Die `cachePolicy
  .reloadIgnoringLocalCacheData` verhindert nur das Lesen, nicht das Schreiben.
  `AppPersistence.purgeLegacyHTTPCacheOnce` (`AppPersistence.swift:221-226`) läuft nur einmal.
  Nachweis: `Cache.db` enthielt nach dem Import 1 Schlüssel mit Passwort und 1 Antwortkörper mit
  Passwort, beide auch nach dem Löschen der Playlist noch vorhanden.
  Folge: eine weitere Klartextkopie außerhalb der Datenbank, auch beim Aktualisieren (B03). Das
  widerspricht der Datenschutzseite („no copy anywhere else", `web/app/privacy/page.tsx:38`). (AK-35)
- **FB-03 · Keine Größen-, Mengen-, Längen- oder Gesamtzeitgrenze für unvertraute Listen.**
  Fundstelle: `PlaylistImporter.swift:311` lädt die Antwort vollständig, `PlaylistImporter.swift:199`
  liest die Datei vollständig (`Data(contentsOf:)`). `M3UParser.swift` kürzt nichts. Es gilt die
  Standardkonfiguration von `URLSession`: 60 s Leerlauf, keine praktische Gesamtfrist.
  Folge: Ein fehlerhafter oder bösartiger Server bzw. eine präparierte Datei kann den Speicher
  erschöpfen (Parser für 46,5 MB: +370 MB). Sie kann Megabyte-lange Namen in die Datenbank schreiben
  und den Import durch langsames Senden beliebig offen halten. Für Xtream hat B01 Grenzen eingeführt
  (64 MB, 100.000 Sender, 180 s, 512 Zeichen), für M3U nicht. (AK-37, AK-38, EC-13, EC-14)
- **FB-04 · Der Import friert die Oberfläche ein, bei großen Listen minutenlang; Website und README
  versprechen „einige Sekunden".**
  Fundstelle: `PlaylistImporter` ist `@MainActor` (`PlaylistImporter.swift:22`). Parsen, `attach` und
  `save` laufen dort (`:58-66`, `:199-212`). `attach` legt jeden Sender mit `Channel(playlist:)` an und
  hängt ihn einzeln mit `playlist.channels.append` an (`:289-301`). Das wächst quadratisch; B01 hat
  genau diesen Pfad für Xtream ersetzt.
  Nachweis: 17.000 Sender brauchen 286,6 s, die ganze Zeit ohne Reaktion des Main-Threads.
  Folge: Die Anbieterlisten, für die die App laut PRD gedacht ist, sind per M3U praktisch nicht
  importierbar; macOS zeigt nach kurzer Zeit den Wartecursor. Die FAQ sagt „Importing a list that
  size takes a few seconds" (`web/content/faq.ts:35`), die README „der Import selbst kann einige
  Sekunden dauern" (`README.md:307`). Die Website empfiehlt zum Ausprobieren eine große öffentliche
  Liste (`web/app/support/page.tsx:121`). (AK-40)
- **FB-05 · Adressen aus der Liste werden ohne Schema-Prüfung übernommen.**
  Fundstelle: `M3UParser.swift:48` prüft nur `url.scheme != nil`, `M3UParser.swift:53` prüft die
  Logo-Adresse gar nicht.
  Folge: Eine fremde Liste (Link eines Dritten, öffentliche Sammlung) kann Sender anlegen, die beim
  Antippen lokale Dateien (`file:///Users/…`), Netzfreigaben (`smb://`) oder App-Schemata an die
  Wiedergabe übergeben. Ebenso kann sie Logo-Adressen auf lokale Dateien setzen. Was dann tatsächlich
  passiert, entscheiden B06 (Engine-Wahl nach Endung, VLCKit versteht viele Schemata) und B04
  (`AsyncImage`). Sender mit `javascript:`, `mailto:` usw. erscheinen in der Liste und spielen nicht.
  (AK-39)
- **FB-06 · Doppelklick-Import fehlt, obwohl die Website ihn verspricht; jedes Öffnen erzeugt ein leeres
  Fenster.**
  Fundstelle: `Info.plist:68-82` registriert den Dokumenttyp. In `Sources/` gibt es kein `onOpenURL`,
  kein `handlesExternalEvents` und keinen `NSApplicationDelegate`, der Dateien annimmt. Die Website
  sagt: „Mika+Player also registers as a handler for .m3u files, so double-clicking one opens it
  here." (`web/content/features.ts:48`)
  Folge: Das Versprechen stimmt nicht. Die Website nennt keinen Weg, die App zum Standard zu machen;
  auf dem Prüfrechner öffnet der Doppelklick Music. Wer „Öffnen mit" wählt, bekommt ohne Rückmeldung
  ein weiteres leeres Fenster, das macOS beim nächsten Start wiederherstellt (EC-22). Auf iOS bleiben
  übergebene Dateien als Kopie im Container liegen (EC-23). Entspricht AS-01. (AK-31)
- **FB-07 · Die App meldet sich als Öffner für alle Text-Typen.**
  Fundstelle: `Info.plist:79` (`public.text`, Rang `Default`).
  Folge: Mika+Player erscheint in „Öffnen mit" für JSON, HTML, CSV, Markdown, Quelltext und Logs. Das
  Öffnen bewirkt dort nur ein leeres Fenster (FB-06). Denkbar, aber nicht nachgestellt: Sie wird zum Standard für Textdateien, für die kein anderes
  Programm Anspruch erhebt. (AK-32)
- **FB-08 · „Abbrechen" bricht einen URL- oder Datei-Import nicht ab; ein späterer Fehler erscheint in
  einem losgelösten Fenster.**
  Fundstelle: `ImportPlaylistView.swift:106` und `:208` starten ungebundene Aufgaben. „Abbrechen"
  (`:133-136`) und `onDisappear` (`:154`) brechen nur `xtreamImportTask` ab. `importFromURL`/
  `importFromFile` (`:192-202`, `:214-224`) setzen `errorMessage` ohne Prüfung auf Abbruch.
  Folge: Nach „Abbrechen" taucht die Playlist doch auf, oder ein Fenster mit dem alten Sheet und
  „Fehler" erscheint scheinbar grundlos. Seit der B01-Reparatur (BUG-11) verhält sich dasselbe Sheet je
  Reiter unterschiedlich. Absicht eindeutig, weil die Beschriftung „Abbrechen" lautet und B01 so
  entschieden hat. (AK-29)
- **FB-09 · Zwei schnelle Klicks auf „Von URL importieren" starten zwei Importe.**
  Fundstelle: `ImportPlaylistView.swift:106` startet die Aufgabe, `isImporting` wird erst darin gesetzt
  (`:193`). Für Xtream ist das seit B01 behoben (`startXtreamImport`, `:168-176`).
  Folge: zwei gleiche Playlists (AK-15) und bei großen Listen doppelte Stillstandszeit (FB-04). (AK-30)
- **FB-10 · Die Datenschutzseite beschreibt den M3U-Weg nicht zutreffend.**
  Fundstelle: `web/app/privacy/page.tsx:36-38` nennt als gespeicherte Zugangsdaten nur „the credentials
  you enter for an Xtream login" und sagt „no copy anywhere else". `web/app/privacy/page.tsx:47-49` sagt
  „Every stream, channel list and logo request goes to the host you entered".
  Folge: Zugangsdaten in M3U-Links (FB-01), Cache-Kopie (FB-02) und Cookies (AK-36) fehlen. Bei M3U
  gehen Stream- und Logo-Anfragen an beliebige Hosts aus der Liste, bei Weiterleitung auch Listenabrufe
  (AK-11). Die Seite gehört zu B10 und ist dort zu korrigieren. (AK-11, AK-34, AK-35, AK-36)

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den
Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Zugangsdaten aus M3U-Links im Klartext, B01-Schutz greift nicht | ⚠ AK-34 + FB-01, als Fehler eingestuft | Klartext-Zugangsdaten sind nach `sicherheit.md` und Zielmodus eine Schwäche; B01 hat sie für denselben Datenbestand bereits als Fehler behoben |
| 2 | Einträge im HTTP-Plattencache | ⚠ AK-35 + FB-02 | beim Ausführen gefunden; weitere Klartextkopie, die das Löschen übersteht; widerspricht der Datenschutzseite |
| 3 | Keine Größen- und Zeitgrenzen | ⚠ AK-37, AK-38 + FB-03 | `sicherheit.md` 4.4: Größe unvertrauter Eingaben |
| 4 | 286 s eingefrorene Oberfläche bei 17.000 Sendern | ⚠ AK-40 + FB-04 | FAQ und README versprechen „einige Sekunden"; Regel „verspricht, tut es nicht" |
| 5 | Beliebige Schemata in Stream- und Logo-Adressen | ⚠ AK-39 + FB-05 | unvertraute Eingabe wird ungeprüft an Wiedergabe und Bildlader weitergereicht (`sicherheit.md` 4.4, Inhalt prüfen) |
| 6 | Doppelklick öffnet leeres Fenster statt zu importieren | ⚠ AK-31 + FB-06 | Website verspricht den Doppelklick-Import |
| 7 | Registrierung für `public.text` | ⚠ AK-32 + FB-07 | kein Sicherheitspunkt, aber die Registrierung hat keine Funktion (FB-06), und die Absicht „M3U öffnen" ist aus Typname und Kommentar eindeutig; eine Frage wäre hier Zurechtrücken durch Unterlassen |
| 8 | „Abbrechen" bricht URL-/Datei-Import nicht ab | ⚠ AK-29 + FB-08, **nicht** OF | Beschriftung eindeutig; für dasselbe Sheet in B01 bereits so entschieden (B01 OF-02, BUG-11); das losgelöste Fenster ist sichtbar fehlerhaft |
| 9 | Doppelklick auf „Von URL importieren" | ⚠ AK-30 + FB-09 | in B01 für den Xtream-Reiter als Fehler behoben (BUG-09); Absicht eindeutig |
| 10 | Datenschutzseite passt nicht zum M3U-Weg | FB-10 | Website verspricht etwas, das der Code nicht tut; Korrektur gehört zu B10 |
| 11 | Doppelter Import derselben URL | ⚠ AK-15 + OF-01 | nicht sicherheitsrelevant, Absicht nicht ableitbar; gleiche Frage wie B01 OF-01 |
| 12 | `file:`/`data:` im URL-Feld | ⚠ AK-13 + OF-02 | Nutzer handelt selbst, kein Sicherheitsgewinn für Dritte; Absicht nicht ableitbar |
| 13 | Weiterleitungen auf fremde Hosts | reguläres Kriterium AK-11, **kein** ⚠ | bei M3U-Links (CDN, Pages-Hosting) üblich; Basic-Auth geht nicht an fremde Hosts (ausgeführt); Query-Zugangsdaten erreicht das Ziel nur, wenn der eingegebene Server sie selbst in die Weiterleitung schreibt. Anders als B01 AK-26, wo die App die Zugangsdaten selbst an jede Anfrage hängt |
| 14 | Content-Type und `charset` ignoriert | reguläres Kriterium AK-09 | Inhalt wird geparst, Fehlformate enden in „keine gültigen Sender"; keine Sicherheitsfolge |
| 15 | Einfache M3U ohne `#EXTINF` | EC-01 + OF-03 | Code-Kommentar nennt „Extended-M3U-Format", README/Website sagen nur „M3U"; Absicht nicht eindeutig |
| 16 | Relative Adressen verworfen | EC-10 + OF-04 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 17 | Kein HTTP-Hinweis im URL-Reiter | OF-05, kein FB | die App stuft nichts herab (AK-08), der Anbieter-Link bestimmt das Schema; Gleichbehandlung mit B01 ist eine Produktfrage |
| 18 | Kodierung (ein Byte kippt alles, 0x85, UTF-16) | EC-07 bis EC-09 + OF-06 | Kommentar beschreibt „UTF-8 mit Latin-1-Fallback" als gewollt; die Nebenwirkungen sind nicht beschrieben |
| 19 | Name aus Leerzeichen wird übernommen | reguläres Kriterium AK-07 | wie B01 AK-07; keine Sicherheitsfolge, kein Versprechen |
| 20 | Leerzeichen-URL aktiviert den Button | reguläres Kriterium AK-03 | die Meldung „Die angegebene URL ist ungültig." fängt es ab; keine Folge |
| 21 | Quote-sicherer Name, Attribute, `#EXTGRP` | reguläre Kriterien AK-21 bis AK-23 | in CLAUDE.md, README, Code-Kommentar und Tests als gewollt beschrieben |
| 22 | Datei ohne Quelladresse, nicht aktualisierbar | reguläres Kriterium AK-16 | Code-Kommentar `PlaylistImporter.swift:208` |
| 23 | Klartext-URL im Systemprotokoll unter Xcode | reguläres Kriterium AK-41, kein FB | im normal gestarteten Prozess `<private>` (ausgeführt); Klartext nur bei Debug-Start aus Xcode, dort nicht in der Hand der App (vgl. B01 H-2) |
| 24 | Cookies des Servers werden gespeichert und zurückgeschickt | reguläres Kriterium AK-36, im Katalog 1.1/1.3 geführt | Standardverhalten von `URLSession`, wie ein Browser; keine Zugangsdaten der App |
| 25 | Öffnen per iCloud-Datei | EC-18 + OF-07, nicht ausgeführt | Test hätte eine Datei in iCloud Drive erzeugen oder eine fremde lesen müssen; beides ausgeschlossen |
