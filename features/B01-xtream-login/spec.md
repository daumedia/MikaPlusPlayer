# B01 · Xtream-Codes-Login — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-15 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code auf `main` @ `c01f1cf` **tut**,
> nicht, was er tun sollte. Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen
> bewusst als Kriterium hier, damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind,
> steht ein Verweis auf *Fehlbestand*.
>
> **Wie belegt.** Adressbildung, Netzwerkablauf, Fehlermeldungen, Speicherung und Cache wurden am
> 2026-09-15 **ausgeführt**: ein temporärer XCTest (im Test-Host der Mac-App) lief gegen einen
> lokalen Python-Mock von `player_api.php` auf `127.0.0.1:18765`/`18766`, mit erfundenen
> Zugangsdaten (`qa-user` / `qa-pass-123`). Dazu kam ein zweiter Lauf unter eigener Bundle-ID
> für den Plattencache. Das Verhalten der Oberfläche (Sheet, Buttons, Alert) ist **aus dem Code
> gelesen und nicht bedient**. Solche Kriterien tragen den Vermerk *(gelesen)*.
> Die Sonde ist wieder entfernt; Mock-Skript und Protokolle liegen nur im Scratchpad der Session.

## Zweck

Nutzer mit einem Xtream-Codes-Abo melden sich mit Host, Benutzername und Passwort an. Die App
legt daraus eine aktualisierbare Playlist mit allen Live-Sendern des Anbieters an. Die
Senderliste kommt über `player_api.php`, damit auch Panels funktionieren, die den klassischen
`get.php`-M3U-Link sperren.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| — | — | B01 hat keine Vorstufe. Das Import-Sheet teilt es sich mit B02; die Playlist-Übersicht, aus der das Sheet geöffnet wird, gehört zu B03 |

Auf B01 bauen auf: B03 (Aktualisieren rekonstruiert die Zugangsdaten aus der gespeicherten
Adresse), B04 (zeigt die angelegten Sender), B06 (spielt die gebauten Stream-Adressen).

## User Stories

- **US-01** · Als Nutzer mit Xtream-Abo möchte ich mich mit Host, Benutzername und Passwort
  anmelden, damit die Live-Sender meines Anbieters als Playlist in der App landen.
- **US-02** · Als Nutzer möchte ich zwischen HLS und MPEG-TS wählen, damit ich das Format nehme,
  das mein Anbieter tatsächlich ausliefert.
- **US-03** · Als Nutzer möchte ich bei einer gescheiterten Anmeldung erfahren, ob Zugangsdaten,
  Host oder Netzwerk das Problem sind, damit ich es beheben kann.

## Nicht im Scope

- Aktualisieren und Löschen einer Xtream-Playlist, einschließlich der Rekonstruktion der
  Zugangsdaten aus `sourceURL` → **B03**. B01 liefert dafür nur `XtreamCredentials(playerAPIURL:)`
  und den `XtreamClient`.
- Anzeige der Senderliste, Laden der Logos → **B04**; Favoriten → **B05**
- Wiedergabe, Engine-Wahl nach Endung, Fehleranzeige im Player → **B06**; Multiview → **B08**
- M3U-Import per URL oder Datei (Reiter „URL" und „Datei" desselben Sheets) → **B02**
- Video on Demand, Serien, Catch-up, EPG: `XtreamClient` fragt nur Live-Kategorien und Live-Streams ab
- Der `get.php`-Playlist-Link: Der Code dafür existiert (`XtreamCodes.swift:100-112`), die App
  ruft ihn nicht auf

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Für die Netzwerkkriterien genügt ein lokaler
Mock-Server, der `player_api.php` beantwortet und die empfangenen Anfragen protokolliert.

### Oberfläche

- **AK-01** · Angenommen, die Playlist-Übersicht ist offen, wenn „+" oder „Playlist importieren"
  angetippt wird, dann öffnet sich das Sheet „Playlist importieren". Der Reiter „Xtream" ist
  vorausgewählt. Zu sehen sind die Felder „Name (optional)", „Host (z. B.
  http://dein-anbieter.tld)" und „Benutzername", ein Feld „Passwort" mit verdeckter Eingabe,
  der Umschalter „Stream-Format" und der Button „Anmelden & importieren". Auf macOS ist das
  Sheet mindestens 420 × 360 pt groß. *(gelesen)*
- **AK-02** · Angenommen, das Sheet ist frisch geöffnet, wenn der Reiter „Xtream" sichtbar ist,
  dann steht das Format auf „MPEG-TS (.ts)" und darunter „Originalformat des Anbieters – benötigt
  VLCKit.". Wird auf „HLS (.m3u8)" umgeschaltet, lautet der Hinweis „Spielt direkt mit AVKit –
  kein VLCKit nötig.". *(gelesen)*
- **AK-03** · Angenommen, das Sheet ist offen: Solange Host, Benutzername oder Passwort leer ist
  oder nur aus Leerzeichen bzw. Tabulatoren besteht, bleibt „Anmelden & importieren"
  deaktiviert. Sobald alle drei Felder ein anderes Zeichen enthalten, ist der Button aktiv.
  *(Regel ausgeführt, Button gelesen)*
- **AK-04** · Angenommen, das Sheet ist offen, wenn in Host oder Benutzername getippt wird, dann
  greift keine Autokorrektur. Auf iOS wird zusätzlich nichts automatisch großgeschrieben, und
  das Host-Feld zeigt die URL-Tastatur. *(gelesen)*
- **AK-05** · Angenommen, ein Import läuft, dann zeigt das Formular die Zeile „Importiere…" mit
  Fortschrittsanzeige. „Anmelden & importieren" (und die Import-Buttons der Reiter „URL" und
  „Datei") sind deaktiviert. „Abbrechen" bleibt bedienbar. *(gelesen)*

### Anmeldung und Import

- **AK-06** · Angenommen, das Panel akzeptiert die Zugangsdaten und liefert N ≥ 1 Live-Streams,
  wenn „Anmelden & importieren" angetippt wird, dann schließt sich das Sheet von selbst. In der
  Playlist-Übersicht steht die neue Playlist an erster Stelle, mit Globus-Symbol und dem Badge
  „N Sender". *(Anlage und Anzahl ausgeführt, Anzeige gelesen)*
- **AK-07** · Angenommen, „Name (optional)" ist leer, wenn importiert wird, dann heißt die
  Playlist wie der Host, ohne Schema und Port (Eingabe `127.0.0.1:18765` → `127.0.0.1`). Ist
  ein Name eingegeben, heißt die Playlist exakt so, ungekürzt, auch wenn er nur aus
  Leerzeichen besteht. *(ausgeführt)*
- **AK-08** · Angenommen, der Import war erfolgreich, dann gibt es genau einen Sender je Eintrag
  aus `get_live_streams`, und keinen für VOD oder Serien. Jeder Sender übernimmt den Namen aus
  dem Panel. Seine Gruppe ist der Kategoriename zu seiner `category_id`. Gibt es zu einer ID
  mehrere Kategorien, gilt die erste. Ohne `category_id` oder bei unbekannter ID bleibt der
  Sender ohne Gruppe. Das Logo kommt aus `stream_icon`, die tvg-ID aus `epg_channel_id`; ist
  einer dieser Werte leer oder `null`, fehlt er am Sender. *(ausgeführt)*
- **AK-09** ⚠ · Angenommen, eine Playlist mit denselben Zugangsdaten existiert schon, wenn noch
  einmal importiert wird, dann entsteht eine zweite, unabhängige Playlist mit eigenen Sendern.
  Es gibt keine Warnung und keine Dublettenprüfung. *(ausgeführt; Absicht unklar → OF-01)*
- **AK-10** · Angenommen, ein Import wird ausgelöst, dann schickt die App genau drei
  GET-Anfragen an `/player_api.php` des eingegebenen Hosts, nacheinander in dieser Reihenfolge:
  ohne `action` (Anmeldung), mit `action=get_live_categories`, mit `action=get_live_streams`.
  Jede Anfrage trägt `username` und `password` als Query-Parameter. `get.php` wird nicht
  aufgerufen. Scheitert eine Anfrage, folgt keine weitere. *(ausgeführt)*

### Adressbildung

- **AK-11** · Angenommen, der Host wird mit Leerzeichen oder Zeilenumbruch davor oder dahinter,
  ohne Schema, mit Port, mit abschließenden Schrägstrichen oder mit Pfad und Query eingegeben
  (z. B. ` example.com:8080/panel/?x=1 `), dann gehen die Anfragen an
  `http://example.com:8080/player_api.php`. Leerzeichen, Pfad und Query sind verworfen, der
  Port bleibt, `http://` wird ergänzt. *(ausgeführt)*
- **AK-12** ⚠ · Angenommen, der Host wird mit `https://` eingegeben (in beliebiger Groß- und
  Kleinschreibung, z. B. `HTTPS://example.com:8443`), dann gehen alle Anfragen und alle
  gespeicherten Stream-Adressen über **`http://`**. Ein eingegebener Port bleibt dabei stehen.
  Benutzername und Passwort laufen damit unverschlüsselt durchs Netz. Die App zeigt keinen
  Hinweis. *(ausgeführt; als Fehler eingestuft → FB-02)*
- **AK-13** · Angenommen, Benutzername oder Passwort beginnen oder enden mit Leerzeichen, dann
  werden diese vor dem Senden entfernt, in den Anfragen wie in den Stream-Adressen.
  Zeilenumbrüche werden **nicht** entfernt. *(ausgeführt)*
- **AK-14** ⚠ · Angenommen, Benutzername oder Passwort enthalten Sonderzeichen, wenn importiert
  wird, dann gilt:
  (a) Leerzeichen, Umlaute, `%`, `&` und `=` kommen beim Panel unverändert an, sowohl in den
  Anfragen als auch im Pfad der Stream-Adressen.
  (b) Ein `+` wird unkodiert gesendet. Ein Panel, das Formulardaten üblich dekodiert (PHP),
  liest es als **Leerzeichen**; die Anmeldung scheitert dann.
  (c) Bei `#` oder `?` endet der Pfad der Stream-Adressen an dieser Stelle. Der Rest wird zum
  Fragment bzw. zur Query (Passwort `a#b` → Pfad `/live/qa-user/a`).
  (d) Ein `/` erzeugt einen zusätzlichen Pfadabschnitt (`/live/qa-user/a/b/101.ts`).
  In den Fällen (c) und (d) klappt der Import, aber die Adressen sind falsch.
  *(ausgeführt; als Fehler eingestuft → FB-06)*
- **AK-15** · Angenommen, der Import war erfolgreich, dann hat jeder Sender die Stream-Adresse
  `http://<host>[:<port>]/live/<benutzername>/<passwort>/<stream_id>.ts` bei MPEG-TS bzw.
  `….m3u8` bei HLS. Der Host ist immer der eingegebene, auch wenn das Panel in `server_info`
  einen anderen meldet. Eine `stream_id` als Zahl (`101`) und als Text (`"102"`) ergibt dieselbe
  Form. *(ausgeführt)*

### Fehlerfälle

Gemeinsam für AK-16 bis AK-22: Die Meldung erscheint als Alert „Fehler" mit einem Button „OK"
im offenen Sheet. Nach „OK" verschwindet der Alert, alle Eingaben stehen noch im Formular, und
„Anmelden & importieren" ist sofort wieder bedienbar. *(gelesen)*

- **AK-16** · Angenommen, das Panel antwortet auf die Anmeldung mit `user_info.auth` ungleich
  `1` oder ganz ohne `user_info`, wenn importiert wird, dann lautet die Meldung „Anmeldung
  fehlgeschlagen. Benutzername/Passwort prüfen.". *(ausgeführt)*
- **AK-17** · Angenommen, eine der drei Anfragen liefert einen HTTP-Status außerhalb von 200–299,
  dann lautet die Meldung „Netzwerkfehler: HTTP <Status>", z. B. „Netzwerkfehler: HTTP 407".
  *(ausgeführt mit 401 und 407)*
- **AK-18** · Angenommen, eine Antwort ist nicht das erwartete JSON (HTML-Seite, leerer Inhalt,
  `auth` als Text `"1"`, Kategorien `null`, Streams als Objekt statt Liste), dann lautet die
  Meldung „Netzwerkfehler: Unerwartete Serverantwort (…)". In der Klammer steht ein englischer
  Systemtext, z. B. „The data couldn’t be read because it isn’t in the correct format." oder
  „… because it is missing.". *(ausgeführt)*
- **AK-19** · Angenommen, die Anmeldung gelingt, aber `get_live_streams` liefert eine leere
  Liste, dann lautet die Meldung „Die Playlist enthält keine gültigen Sender.". *(ausgeführt)*
- **AK-20** · Angenommen, der Host ist nicht erreichbar, dann lautet die Meldung „Netzwerkfehler:"
  plus englischer Systemtext:
  - Port geschlossen: „Could not connect to the server."
  - Name nicht auflösbar: „A server with the specified hostname could not be found."
  - Verbindung steht, aber 60 Sekunden lang kommen keine Daten: „The request timed out."
  *(ausgeführt)*
- **AK-21** · Angenommen, der Host enthält ein Leerzeichen mitten im Namen (`exa mple.com`) oder
  besteht nur aus `http://`, dann lautet die Meldung „Host ungültig. Bitte prüfe die Eingabe.",
  und es wird keine Anfrage gesendet. *(ausgeführt)*
- **AK-22** · Angenommen, ein Import scheitert aus einem der Gründe AK-16 bis AK-21, dann ist
  keine Playlist und kein Sender angelegt, und die Playlist-Übersicht ist unverändert.
  *(ausgeführt)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Jede Frage hat ein
Kriterium, ein „trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-23** · Angenommen, ein Import scheitert mit einer der Meldungen aus AK-16 bis AK-21,
  dann enthält der angezeigte Text weder Benutzername noch Passwort noch die Anfrage-Adresse.
  *(ausgeführt für Anmeldung, HTTP-Status, Dekodierfehler, leere Liste, geschlossenen Port,
  unbekannten Host, Timeout, ungültigen Host)*
- **AK-24** ⚠ · Angenommen, ein Xtream-Import war erfolgreich, wenn die Datenbank der App gelesen
  wird, dann steht das Passwort **im Klartext** in `Playlist.sourceURL`
  (`http://<host>[:<port>]/player_api.php?username=<benutzer>&password=<passwort>`) und
  zusätzlich im Pfad **jeder** `Channel.streamURL`. Die Keychain wird nicht benutzt.
  *(ausgeführt: 10 von 10 Stream-Adressen enthielten das Passwort; als Fehler eingestuft → FB-01)*
- **AK-25** ⚠ · Angenommen, ein Xtream-Import ist gelaufen, wenn der HTTP-Cache der App
  untersucht wird (macOS: `~/Library/Caches/lu.daumedia.MikaPlusPlayer/Cache.db`; iOS:
  `Library/Caches` im App-Container), dann sind dort die Anfrage-Adressen **mit Benutzername und
  Passwort** gespeichert, samt Antwortdaten. Das Löschen der Playlist entfernt diese Einträge
  nicht. *(ausgeführt unter eigener Bundle-ID: Anmeldung, Kategorien und Streams als Einträge in
  `cfurl_cache_response`; das Nicht-Entfernen ist gelesen, kein Code der App leert den Cache;
  als Fehler eingestuft → FB-03)*
- **AK-26** ⚠ · Angenommen, das Panel beantwortet die Anfragen mit einer HTTP-Weiterleitung auf
  einen anderen Host oder Port, dann folgt die App ohne Rückfrage. Der Zielhost erhält die
  Anfragen samt Zugangsdaten, wenn das Weiterleitungsziel sie enthält. Die gespeicherten
  Stream-Adressen zeigen weiter auf den eingegebenen Host. *(ausgeführt; Absicht unklar → OF-04)*
- **AK-27** · Angenommen, ein Import läuft, wenn das Systemprotokoll des App-Prozesses
  mitgeschnitten wird (`log stream --process MikaPlusPlayer`), dann erscheint das Passwort dort
  nicht im Klartext. *(gelesen: kein `print`, `Logger`, `os_log` oder `NSLog` im Code; **nicht
  ausgeführt**, die QA weist es am laufenden Build nach)*
- **AK-28** ⚠ · Angenommen, die Mac-App speichert eine Xtream-Playlist, dann liegt die Datenbank
  unter `~/Library/Application Support/default.store`. Der Dateiname ist generisch und nicht
  nach App getrennt, weil die Sandbox aus ist. Auf iOS liegt sie im App-Container. Die Datei ist
  nicht vom Backup ausgeschlossen. *(macOS-Pfad ausgeführt über die Standardkonfiguration;
  Backup gelesen; als Fehler eingestuft → FB-08, FB-09)*
- **AK-29** · Angenommen, eine Xtream-Playlist existiert, dann gibt es in der App genau einen Weg,
  ihre gespeicherten Zugangsdaten aus der Datenbank zu entfernen: die Playlist löschen (B03).
  Ändern der Zugangsdaten, Abmelden oder Anzeigen des gespeicherten Passworts gibt es nicht.
  *(gelesen; Änderungswunsch → OF-05)*
- **AK-30** · Angenommen, die gesamte Git-Historie wird nach `username=`, `password=` und
  `/live/<…>/<…>/` durchsucht, dann finden sich nur Beispielwerte (`demo`/`secret`, `u`/`p`,
  Platzhalter in Kommentaren), keine echten Zugangsdaten und keine Anbieter-Hosts.
  *(ausgeführt am 2026-09-15 über alle 19 Commits)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B01 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Xtream-Benutzername (oft E-Mail-Adresse oder Kundennummer), Passwort, Host des Anbieters (verrät das Abo), die IP-Adresse gegenüber dem Anbieter. Gespeichert: AK-24, AK-25, AK-28 |
| 1.2 | Besondere Kategorien? | Trifft nicht zu, weil B01 nur Zugangsdaten und die vom Anbieter gelieferte Senderliste speichert. Rückschlüsse aus bevorzugten Sendern entstehen erst durch Favoriten → B05 |
| 1.3 | Wo gespeichert, wie lange? | Datenbank: AK-24, AK-28, unbefristet bis zum Löschen der Playlist (AK-29). HTTP-Cache: AK-25, bis das System den Cache räumt. Backups: FB-08. Eine Löschfrist gibt es nicht |
| 1.4 | Landen sie in Logs? | App-seitig nein: AK-27 (nachzuweisen). In Fehlermeldungen nein: AK-23. Im HTTP-Cache ja: AK-25 / FB-03 |
| 2.1 | Welche externen Dienste? | Nur das Panel am eingegebenen Host (AK-10), bei Weiterleitung auch das Ziel (AK-26). Keine KI, keine Analyse, kein Fehler-Tracking. Logo-Hosts aus `stream_icon` werden hier nur gespeichert und erst in B04 geladen |
| 2.2 | Was wird übertragen, was vorher entfernt? | Benutzername und Passwort als Query-Parameter über HTTP (AK-10, AK-12); entfernt wird nichts. Das verlangt das Xtream-Protokoll, das erzwungene HTTP nicht → FB-02 |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil der Nutzer den Anbieter selbst wählt und seine Zugangsdaten direkt an dessen Server schickt. daumedia empfängt und verarbeitet dabei nichts |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Der lokale Nutzer: alles, Löschen nur über B03 (AK-29). Unter macOS können außerdem alle Prozesse desselben Benutzers Datenbank und Cache lesen, weil die Sandbox aus ist → FB-09 |
| 3.2 | Erzwungen in DB oder Anwendung? | Nirgends in der App. Auf iOS schützt die App-Sandbox des Systems, auf macOS nichts → FB-09 |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keinen Server der App und keine per ID abrufbaren Ressourcen gibt. Alle Daten liegen lokal beim Nutzer |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit auf die Anmeldung | Trifft für einen eigenen Endpunkt nicht zu, weil die Anmeldung beim Anbieter läuft. App-seitig gibt es keinerlei Drosselung → **FB-04** |
| 4.2 | Rate Limit für Kostenpflichtiges | Trifft nicht zu, weil B01 keinen kostenpflichtigen Dienst des Betreibers aufruft |
| 4.3 | Kosten je Aufruf | Trifft nicht zu, siehe 4.2. Verbindungslimits des Anbieters betreffen B06/B08 |
| 4.4 | Uploads: Größe, Typ, Inhalt | Keine Datei-Uploads. Die unvertrauten Antworten des Panels haben aber kein Größen-, Mengen- oder Gesamtzeitlimit → **FB-05**. Zu strenge Typprüfung → FB-07 |
| 4.5 | Wo greift das Limit? | Nirgends, siehe FB-04 und FB-05. Einzige Grenze: 60 s ohne Daten je Anfrage (AK-20) |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil die App kein eigenes Konto hat. Die gespeicherten Zugangsdaten entfernt der Nutzer über das Löschen der Playlist (AK-29) |
| 5.2 | Was wird dabei gelöscht? | Playlist und alle Sender samt Stream-Adressen (B03). **Nicht** gelöscht werden HTTP-Cache und Backups → FB-03, FB-08 |
| 5.3 | Was bleibt, und warum? | Cache-Einträge und Backup-Kopien bleiben, ohne Begründung → FB-03, FB-08 |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil daumedia keine Daten erhält, die es herausgeben könnte. Alles liegt auf dem Gerät des Nutzers |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine App-Schlüssel. Das einzige Geheimnis ist das Xtream-Passwort des Nutzers; es liegt nicht in der Keychain → FB-01 |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Nein: AK-30 |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B01 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Host mit Fragment (`https://example.com:8443/panel/?x=1#f`) → Das Fragment bleibt an
  der Basisadresse hängen. Die Anfragen funktionieren, aber jede Stream-Adresse hat den ganzen
  `/live/…`-Teil im Fragment; kein Sender ist abspielbar. *(Adresse ausgeführt)*
- **EC-02** · Host mit fremdem Schema (`ftp://example.com`, `httpx://example.com`) → nicht
  abgelehnt. Der Schema-Name wird zum Host (`http://ftp`, `http://httpx`), die Anfrage scheitert
  mit einem Netzwerkfehler. *(Adresse ausgeführt, Meldung gelesen)*
- **EC-03** · Host mit Benutzerinfo (`http://u:pw@example.com`) → bleibt in Anfragen und
  Stream-Adressen erhalten. *(ausgeführt)*
- **EC-04** · Internationalisierter Host (`müller.de`) → wird zu `xn--mller-kva.de`. So heißt auch
  die Playlist, wenn kein Name eingegeben ist. *(ausgeführt)*
- **EC-05** · IPv6-Host (`[::1]:8080`) → Anfragen und Stream-Adressen korrekt, Standardname `::1`.
  Die Rekonstruktion für B03 ergibt wieder `http://[::1]:8080`. *(ausgeführt)*
- **EC-06** · Panel unter einem Unterpfad (`host/panel/`) → Der Pfad wird verworfen, die Anfragen
  gehen an `/player_api.php` im Wurzelverzeichnis. Solche Panels sind nicht nutzbar. *(ausgeführt)*
- **EC-07** · `https://host:8443` bei einem Panel, das nur TLS spricht → wird zu
  `http://host:8443`, das Panel versteht die Anfrage nicht, Netzwerkfehler. *(Adresse ausgeführt,
  Verhalten gegen einen TLS-Port nicht)*
- **EC-08** · Host `//example.com` → Basisadresse `http://` mit leerem Host, Anfrage an
  `http:///player_api.php`. *(Adresse ausgeführt, Meldung nicht)*
- **EC-09** · Benutzername nur aus Zeilenumbruch, oder Passwort mit Zeilenumbruch am Ende → gilt
  als ausgefüllt, der Zeilenumbruch wird als `%0A` mitgesendet. *(Zugangsdaten ausgeführt; ob die
  Textfelder beim Einfügen Zeilenumbrüche annehmen, nicht geprüft)*
- **EC-10** · Passwort mit Leerzeichen am Anfang oder Ende → wird still gekürzt (AK-13). Konten mit
  solchen Passwörtern sind nicht nutzbar. *(ausgeführt)*
- **EC-11** · `category_id` als Zahl statt Text, in den Kategorien oder in den Streams → Der
  **gesamte** Import scheitert mit „Netzwerkfehler: Unerwartete Serverantwort (The data couldn’t
  be read because it isn’t in the correct format.)". *(ausgeführt → FB-07)*
- **EC-12** · Ein einziger Stream mit `name: null`, oder Kategorien als `null` → Der gesamte
  Import scheitert mit „… (The data couldn’t be read because it is missing.)". *(ausgeführt → FB-07)*
- **EC-13** · `stream_id` als Kommazahl `5.0` → wird als `5` übernommen. *(ausgeführt)*
- **EC-14** · `stream_id` mit Schrägstrich (`"abc/def"`) → Stream-Adresse `…/live/<u>/<p>/abc/def.ts`,
  unkodiert. *(ausgeführt)*
- **EC-15** · Stream mit leerem Namen `""` → Sender ohne Namen. Anders als beim M3U-Import (B02)
  gibt es keinen Ersatznamen. *(gelesen)*
- **EC-16** · Konto mit `auth: 1` und `status: "Expired"` → Import gelingt ohne Hinweis.
  *(ausgeführt → OF-03)*
- **EC-17** · Das Panel hält die Verbindung offen, schickt aber nichts → Nach 60 s bricht die
  Anfrage ab (AK-20); bis dahin läuft der Import bis zu drei Mal je 60 s. Ein Panel, das
  Daten langsam tröpfelt, hält den Import unbegrenzt offen, weil die 60 s nur Leerlaufzeit
  sind. *(Stillstand ausgeführt, Tröpfeln gelesen → FB-05)*
- **EC-18** · „Abbrechen", unter iOS auch das Wegwischen, während eines laufenden Imports → Das
  Sheet schließt, der Import läuft im Hintergrund weiter. Bei Erfolg taucht die Playlist später
  in der Übersicht auf; ein Fehler wird nirgends angezeigt. *(gelesen, nicht bedient → OF-02)*
- **EC-19** · Doppelklick auf „Anmelden & importieren" → Der Button wird erst deaktiviert, wenn
  die gestartete Aufgabe den Import-Zustand gesetzt hat und die Ansicht neu gezeichnet ist.
  Kommt der zweite Klick vorher an, startet ein zweiter Import. Mangels Dublettenprüfung
  (AK-09) entstünden zwei Playlists. *(gelesen, nicht bedient; die QA prüft das per UI)*
- **EC-20** · Sehr große Senderliste (≈ 17.000) → Alle Sender werden auf dem Main-Actor angelegt
  und gespeichert; die Oberfläche kann dabei stocken. *(gelesen, nicht gemessen)*
- **EC-21** · Reiter während des Imports gewechselt → Der Import läuft weiter. Die Zeile
  „Importiere…" ist auf jedem Reiter zu sehen, die Import-Buttons aller Reiter sind
  deaktiviert. *(gelesen)*
- **EC-22** · HLS gewählt, das Panel sperrt aber HLS → Der Import gelingt, weil das Format nicht
  geprüft wird. Die Sender spielen erst in B06 nicht. *(gelesen → OF-07)*

## Offene Fragen

Alle vom 2026-09-15. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde
nach der QA von B01.

- **OF-01** · Soll ein erneuter Import desselben Zugangs eine zweite Playlist anlegen (AK-09), oder
  soll die App auf die vorhandene hinweisen bzw. sie aktualisieren?
  *Stand Build 2026-09-16:* weiterhin offen. BUG-09 ist nur im eindeutigen Teil behoben (zwei Klicks
  starten keinen zweiten Import mehr); die Dublettenprüfung ist eine Produktentscheidung und nicht gebaut.
- **OF-02** · Soll „Abbrechen" einen laufenden Import tatsächlich abbrechen (EC-18)? Heute
  schließt es nur das Sheet, und ein späterer Fehler bleibt unsichtbar.
  *Stand Build 2026-09-16:* Zur Behebung von BUG-11 bricht „Abbrechen" (und unter iOS das Wegwischen)
  den Import jetzt ab; es entsteht nichts, es erscheint kein Alert. Ohne Rückfrage entschieden
  (Zielmodus) — zur Bestätigung durch den Nutzer.
- **OF-03** · Sollen Konten mit `status` „Expired", „Banned" oder „Disabled" trotz `auth = 1`
  importiert werden (EC-16), oder mit Hinweis bzw. gar nicht?
- **OF-04** · Sollen HTTP-Weiterleitungen des Panels befolgt werden (AK-26)? Das PRD sagt:
  „Zugangsdaten gehen ausschließlich an den Host, den der Nutzer eingegeben hat". Bei einer
  Weiterleitung stimmt das nicht mehr.
  *Stand Build 2026-09-16:* Zur Behebung von BUG-10 folgt die App nur noch Weiterleitungen innerhalb
  desselben Panels (Schema, Host, Port) und bricht sonst mit Meldung ab. Zur Bestätigung durch den Nutzer.
- **OF-05** · Soll man die Zugangsdaten einer bestehenden Playlist ändern können (AK-29)? Heute
  heißt ein Passwortwechsel beim Anbieter: löschen und neu importieren, und dabei gehen die
  Favoriten verloren. Wäre ein neues Feature mit eigener Nummer, keine Änderung an B01.
- **OF-06** · Sollen Fehlermeldungen englische Systemtexte und rohe HTTP-Codes zeigen
  (AK-17, AK-18, AK-20)? Die Oberfläche ist sonst nur Deutsch.
- **OF-07** · Soll der Import prüfen, ob das gewählte Format beim Panel funktioniert (EC-22)?

Aus der Reparatur (sdd-build 2026-09-16), nicht gebaut:

- **OF-08** · Die Mac-App ist ad-hoc signiert. Einträge im Anmelde-Schlüsselbund vertrauen deshalb nur
  genau dem Build, der sie angelegt hat. Nach jedem Update ist zu erwarten (nicht nachgestellt), dass macOS beim
  ersten Abspielen oder Aktualisieren einer Xtream-Playlist einmal nach dem Anmeldepasswort fragt. Soll die App
  mit Developer ID signiert werden (dann entfällt die Abfrage)? Betrifft B09; braucht Apple-Team und
  Signaturschlüssel.
- **OF-09** · Zugangsdaten liegen `…ThisDeviceOnly` im Schlüsselbund. Nach einer Wiederherstellung auf
  einem neuen Gerät sind die Playlists da, die Zugangsdaten nicht; Abspielen und Aktualisieren melden
  „Die Zugangsdaten dieser Xtream-Playlist fehlen …". Soll es einen Weg geben, sie neu einzugeben,
  ohne die Playlist (und ihre Favoriten) zu löschen? Hängt mit OF-05 zusammen.
- **OF-10** · Scheitert eine `https://`-Anmeldung, weil das Panel kein TLS spricht, zeigt die App nur
  den Netzwerkfehler. Soll sie anbieten, es nach ausdrücklicher Bestätigung über `http://` zu versuchen
  (Vorschlag aus BUG-02)?
- **OF-11** · Fehlen im Multiview (B08) die Zugangsdaten eines Senders, fügt „⊞" ihn stillschweigend
  nicht hinzu. Soll dort eine Meldung erscheinen?
- **OF-12** · Die Grenzen aus BUG-08 (64 MB je Antwort, 100.000 Sender, 180 s je Import, Namen
  gekürzt auf 512 Zeichen) sind ohne Vorgabe gewählt. Passen sie zu den Anbietern der Zielgruppe?

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft
nichts davon als bestanden, sondern nimmt es als Suchliste.

- **FB-01 · Zugangsdaten im Klartext in der Datenbank, keine Keychain.**
  Fundstelle: `PlaylistImporter.swift:76` speichert `playerAPIURL()` (`XtreamCodes.swift:85-95`)
  als `sourceURL`. `XtreamClient.swift:46` interpoliert Benutzername und Passwort in jede
  Stream-Adresse, `PlaylistImporter.swift:162` speichert sie je Sender.
  Folge: Wer die Datei `default.store` lesen kann, hat Benutzername und Passwort. Das kann
  jeder Prozess des Benutzers sein (macOS ohne Sandbox), ein Backup oder ein Diebstahl des
  Datenträgers ohne FileVault. Bei 17.000 Sendern gibt es 17.001 Kopien. Entspricht DM-01.
  (AK-24)
- **FB-02 · Ausdrücklich eingegebenes `https://` wird auf `http://` herabgestuft.**
  Fundstelle: `XtreamCodes.swift:70-71`, ohne TLS-Versuch und ohne Rückfall-Logik. HTTP ist
  app-weit erlaubt durch `NSAllowsArbitraryLoads` (`Info.plist:39-40`). Die App zeigt keinen
  Hinweis. Offengelegt ist das nur auf der Website (`web/app/privacy/page.tsx:65-74`), nicht in
  der App, nicht in README oder CLAUDE.md.
  Folge: Zugangsdaten gehen auch bei Panels, die TLS können, im Klartext übers Netz und sind in
  jedem offenen WLAN mitlesbar. Panels, die nur TLS sprechen, sind nicht nutzbar (EC-07).
  Der Code-Kommentar begründet es mit „viele IPTV-Panels bedienen nur HTTP". Das rechtfertigt
  das Herabstufen einer ausdrücklichen `https`-Eingabe nicht. (AK-12)
- **FB-03 · Anfragen samt Zugangsdaten und Antworten landen im HTTP-Plattencache.**
  Fundstelle: `XtreamClient.swift:75-78` benutzt `URLSession.shared`. Die
  `cachePolicy = .reloadIgnoringLocalCacheData` verhindert nur das **Lesen** aus dem Cache, nicht
  das Schreiben. Kein Code der App leert den Cache.
  Nachweis: Nach einem Import standen drei Einträge
  `…/player_api.php?username=…&password=…[&action=…]` mit Antwortdaten in
  `~/Library/Caches/<Bundle-ID>/Cache.db`.
  Folge: eine zweite Klartextkopie außerhalb der Datenbank, die das Löschen der Playlist
  übersteht. Echte Xtream-Panels schicken in `user_info` zudem Benutzername und Passwort zurück;
  die gespeicherte Antwort enthält sie dann ein weiteres Mal. (AK-25)
- **FB-04 · Kein Schutz vor wiederholten Anmeldeversuchen.**
  Fundstelle: `ImportPlaylistView.swift:86`. Der Button ist nach jedem Fehler sofort wieder
  aktiv; es gibt keine Zählung, keine Wartezeit, keinen Hinweis.
  Folge: Viele Panels sperren IP oder Konto nach mehreren Fehlversuchen. Der Nutzer kann sich
  so selbst aussperren, ohne dass die App warnt.
- **FB-05 · Keine Grenzen für die unvertrauten Antworten des Panels.**
  Fundstelle: `XtreamClient.swift:78-82` lädt jede Antwort vollständig in den Speicher und
  dekodiert sie ganz. `PlaylistImporter.swift:159-172` legt jeden Stream als Datensatz auf dem
  Main-Actor an. `timeoutInterval = 60` (`XtreamClient.swift:77`) begrenzt nur die Leerlaufzeit,
  nicht die Gesamtdauer.
  Folge: Ein fehlerhaftes oder bösartiges Panel kann mit einer übergroßen Antwort den Speicher
  erschöpfen, die Oberfläche blockieren oder den Import durch langsames Senden unbegrenzt
  offen halten (EC-17, EC-20).
- **FB-06 · Benutzername und Passwort werden nicht passend kodiert.**
  Fundstelle: `XtreamClient.swift:46`, reine String-Interpolation in den Pfad. Außerdem
  `XtreamCodes.swift:91-92` und `XtreamClient.swift:67-68`: `URLQueryItem` lässt `+` unkodiert.
  Folge: Passwörter mit `+` scheitern an PHP-Panels, weil dort ein Leerzeichen ankommt. Mit
  `#`, `?` oder `/` klappt der Import, aber kein Sender spielt (AK-14). Das ist eine
  Funktionsstörung, keine Sicherheitslücke; als Fehler eingestuft, weil die Absicht klar ist.
- **FB-07 · Dekodierung strenger als der eigene Code-Kommentar zusagt; ein Eintrag kippt den
  ganzen Import.**
  Fundstelle: Der Kommentar `XtreamClient.swift:126` sagt „`stream_id`/`category_id` kommen je
  nach Panel als Int ODER String". `FlexibleID` wird aber nur für `stream_id` benutzt;
  `category_id` ist fest `String` (`:103`, `:116`), `name` fest nicht-optional (`:112`).
  Folge: Panels, die `category_id` als Zahl liefern, sind gar nicht importierbar. Ein einziger
  Stream ohne Namen verhindert den Import aller übrigen (EC-11, EC-12).
- **FB-08 · Datenbank nicht vom Backup ausgeschlossen, und Löschen erreicht Kopien außerhalb der
  Datenbank nicht.**
  Fundstelle: `MikaPlusPlayerApp.swift:7-15`, kein `isExcludedFromBackup`. Kein Code räumt den
  URL-Cache (FB-03).
  Folge: Zugangsdaten landen in Time Machine bzw. im iCloud- oder Geräte-Backup und überdauern
  das Löschen der Playlist. Entspricht DM-02. (AK-28)
- **FB-09 · Speicherort unter macOS nicht app-eigen, entgegen der Website.**
  Fundstelle: `MikaPlusPlayerApp.swift:9`, `ModelConfiguration` ohne Name und URL, dazu
  Sandbox aus (`MikaPlusPlayer.entitlements:7-8`). Ergebnis:
  `~/Library/Application Support/default.store`. Die Website sagt dagegen „They stay in the
  app’s own storage" (`web/app/privacy/page.tsx:37`).
  Folge: Die Datei mit den Zugangsdaten hat einen generischen Namen im gemeinsamen
  Application-Support-Ordner und ist für jeden Prozess des Benutzers lesbar. Möglicher Konflikt
  mit anderen Apps, die denselben Standard nutzen (DM-03, dort als Verdacht). (AK-28)

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den
Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | `https://` → `http://`: gewollt oder Fehler? | ⚠-Kriterium AK-12 **und** FB-02, als Fehler eingestuft | `sicherheit.md`-Schwäche (erzwungenes HTTP bei ausdrücklicher `https`-Eingabe); Kommentar und Website erklären es, begründen es aber nicht |
| 2 | Klartext in `sourceURL` und jeder `streamURL` | ⚠ AK-24 + FB-01, als Fehler eingestuft | Klartext-Zugangsdaten sind im Zielmodus ausdrücklich als Schwäche benannt |
| 3 | Einträge im HTTP-Plattencache | ⚠ AK-25 + FB-03, als Fehler eingestuft | beim Ausführen gefunden; zweite Klartextkopie, die das Löschen übersteht |
| 4 | Sonderzeichen in Benutzername/Passwort | ⚠ AK-14 + FB-06, als Fehler eingestuft | nicht sicherheitsrelevant, aber die Absicht (Anmeldung soll klappen) ist eindeutig; eine offene Frage wäre hier Zurechtrücken durch Unterlassen |
| 5 | `category_id` als Zahl bricht ab | EC-11 + FB-07 | der Code-Kommentar sagt Int-oder-String zu, der Code hält das nicht ein; nach Zielmodus-Regel „verspricht, tut es nicht" |
| 6 | Speicherort `default.store` | ⚠ AK-28 + FB-09 | die Website verspricht „app’s own storage", und die Datei ist unter macOS für alle Prozesse des Benutzers lesbar |
| 7 | Kein Backup-Ausschluss | ⚠ AK-28 + FB-08 | Zugangsdaten verlassen das Gerät über Backups; das Löschen erreicht sie nicht |
| 8 | Keine Drosselung wiederholter Anmeldungen | FB-04, **nicht** „trifft nicht zu" | Regel 2: Eine Lücke ist ein Befund. Der Endpunkt gehört zwar dem Anbieter, die Folge (Selbstaussperrung) trifft aber den Nutzer der App |
| 9 | Keine Größen- oder Gesamtzeitgrenzen | FB-05 | `sicherheit.md`: fehlende Größenlimits bei unvertrauten Eingaben |
| 10 | Doppelter Import legt zweite Playlist an | ⚠ AK-09 + OF-01 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 11 | „Abbrechen" bricht nicht ab | EC-18 + OF-02 | nicht sicherheitsrelevant, Absicht nicht ableitbar; nur gelesen |
| 12 | `status: Expired` wird ignoriert | EC-16 + OF-03 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 13 | Weiterleitungen werden befolgt | ⚠ AK-26 + OF-04 | nur das Panel selbst (oder wer HTTP ohnehin mitliest) kann umleiten; geringe eigene Sicherheitsrelevanz, aber Widerspruch zum PRD, daher dem Nutzer vorgelegt |
| 14 | Standardformat MPEG-TS | reguläres Kriterium AK-02 | in Code-Kommentar (`ImportPlaylistView.swift:29-31`), README und Website als gewollt beschrieben, kein Sicherheitspunkt |
| 15 | `player_api.php` statt `get.php` | reguläres Kriterium AK-10 | in CLAUDE.md, README und Code-Kommentar als gewollt beschrieben |
| 16 | Keine Protokollierung | reguläres Kriterium AK-27, als nicht ausgeführt markiert | im PRD als Ist-Stand beschrieben, kein Logging-Aufruf im Code; der Nachweis am Build fehlt noch |
| 17 | `playlistURL(output:)` nur in Tests benutzt | kein Kriterium, Hinweis in `design.md` (Code ohne AK) | kein beobachtbares Verhalten der App |
