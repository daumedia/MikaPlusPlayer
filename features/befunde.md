# Befunde — projektweit

Stand: 2026-09-16 · Quelle: die `qa-report.md` aller geprüften Features

Diese Liste wird aus den QA-Berichten fortgeschrieben, nicht von Hand. Sie ist die Grundlage
des Auditberichts, den `/sdd-erfassen abschluss` daraus baut.

## Offen

| ID | Feature | Befund | Grad | Fundstelle | Seit |
|---|---|---|---|---|---|
| BF-01 | B09 | v1.1-Feed im freien GitHub-Namensraum `Mukaarts` — wer den Namen registriert, steuert den Feed (Updates unterdrücken, Informations-Update mit Link, Replay signierter Archive) (Namen nur zu reservieren verstößt gegen GitHubs Richtlinie — Ausweg ist ein Übergangs-Release über den neuen Feed) · BUG-01 — 2026-09-26: Nutzer bestätigt Umbenennung des Kontos auf `daumedia`; `Mukaarts` weiterhin frei (404), Weiterleitung aktiv; Abhilfe weiter offen (Übergangs-Release) | kritisch | `Info.plist`@v1.1 `SUFeedURL`; `users/Mukaarts` → 404 | 2026-09-15 |
| BF-03 | B09 | Keine Developer-ID-Signatur, keine Notarisierung, DMG unsigniert · BUG-03 | hoch | `project.yml:70-71`, `scripts/make-dmg.sh` | 2026-09-15 |
| BF-05 | B09 | Schlüsselwechsel unmöglich (ad-hoc Designated Requirement = CDHash) · BUG-05 | hoch | Ad-hoc-Signatur | 2026-09-15 |
| BF-06 | B09 | Ein EdDSA-Schlüssel für sechs Mika+-Apps; Signatur nicht an App/Version gebunden · BUG-06 | hoch | `Info.plist` `SUPublicEDKey` | 2026-09-15 |
| BF-07 | B09 | Feed-Branch `main` ohne Branch-Schutz oder Ruleset · BUG-07 | hoch | GitHub-Repo-Einstellungen | 2026-09-15 |
| BF-08 | B09 | Feed unsigniert (DMG-Prüfung vor dem Einhängen behoben 2026-09-16; Feed-Pflicht offen, braucht signierten Appcast beim nächsten Release) · BUG-08 | hoch | `Info.plist:27-32` | 2026-09-15 |
| BF-09 | B09 | `disable-library-validation` ohne tragfähige Begründung · BUG-09 | mittel | `MikaPlusPlayer.entitlements:9-12` | 2026-09-15 |
| BF-12 | B09 | Datenschutzseite nennt User-Agent und automatische Prüfung nicht · BUG-12 | mittel | `web/app/privacy/page.tsx:57-59` | 2026-09-15 |
| BF-16 | B09 | Website beschreibt den Update-Weg ungenau · BUG-16 | niedrig | `web/app/changelog/page.tsx:21`, `web/content/features.ts:42-43` | 2026-09-15 |
| BF-18 | B09 | Menüpunkt „Nach Updates suchen …" aktualisiert seinen Aktiv-Zustand nicht (nicht observierbar) (Reparatur greift an der echten Menüleiste nicht, QA 2) · BUG-18 | mittel | `SparkleUpdater.swift:10,22`, `MikaPlusPlayerApp.swift:39` | 2026-09-15 |
| BF-19 | B10 | Website öffentlich nicht erreichbar (`DEPLOYMENT_NOT_FOUND`, Vercel-Login mit Cookie, Domain NXDOMAIN) — einzige Datenschutzerklärung nicht abrufbar · BUG-01 | hoch | Vercel-Projekt, Repository-Homepage | 2026-09-15 |
| BF-20 | B10 | Datenschutzerklärung widerspricht dem App-Verhalten (Speicherort, Kopien, Löschen der App, Empfänger, „Nowhere") · BUG-02 | hoch | `web/app/privacy/page.tsx:19-20,37-39,47-49`, `web/app/page.tsx:64-72`, `web/content/faq.ts:40` | 2026-09-15 |
| BF-21 | B10 | Pflichtangaben fehlen: Verantwortlicher, Rechtsgrundlagen, Speicherdauer, Betroffenenrechte, nicht öffentlicher Kontaktweg; kein `docs/datenschutz.md` · BUG-03 | hoch | `web/app/privacy/page.tsx`, `web/components/site-footer.tsx` | 2026-09-15 |
| BF-22 | B10 | `/download` ohne Cache im Fehlerfall und ohne Limit (64 Aufrufe → 64 GitHub-Anfragen) · BUG-04 | mittel | `web/app/download/route.ts:5-9`, `web/lib/releases.ts:73-90` | 2026-09-15 |
| BF-23 | B10 | `next` 16.2.12 mit kritischer Advisory GHSA-2xp9-vwfh-vxw4; Angriffsfläche heute nur lokale Quellen · BUG-05 | mittel | `web/package.json:15` | 2026-09-15 |
| BF-24 | B10 | Gatekeeper-Anleitung beschreibt ab macOS 15 entfallenen Weg; keine Prüfsumme für den Erstdownload · BUG-06 | mittel | `web/app/support/page.tsx:35-44`, `web/components/gatekeeper-note.tsx:9-13`, `web/content/faq.ts:10` | 2026-09-15 |
| BF-25 | B10 | Werbeaussagen, die Release v1.1 nicht erfüllt (Bild-in-Bild, Doppelklick-Import, Changelog in Sparkle, App-Name, „open-source" ohne Lizenz, Sprache) · BUG-07 | mittel | `web/content/features.ts:13-48`, `web/app/support/page.tsx`, `web/components/site-footer.tsx:14` | 2026-09-15 |
| BF-26 | B10 | Ersatz-Release fest auf v1.1 verdrahtet, vom Release-Skript nicht gepflegt · BUG-08 | mittel | `web/lib/releases.ts:46-60,126`, `scripts/release.sh` | 2026-09-15 |
| BF-27 | B10 | Keine Content-Security-Policy, keine Permissions-Policy · BUG-09 | niedrig | `web/next.config.ts:5-19` | 2026-09-15 |
| BF-28 | B10 | `node="[object Object]"` in gerenderten Release-Notizen · BUG-10 | niedrig | `web/components/release-notes.tsx:14-18` | 2026-09-15 |
| BF-29 | B10 | Open-Graph-Angaben der Unterseiten zeigen auf die Startseite · BUG-11 | niedrig | `web/app/layout.tsx:52-59` | 2026-09-15 |
| BF-40 | B01 | Zweiter Import desselben Zugangs legt eine zweite Playlist an (Doppelklick-Teil behoben 2026-09-16; Dublette wartet auf Nutzerentscheidung OF-01) · BUG-09 | niedrig | `PlaylistImporter.swift:61-85`, `ImportPlaylistView.swift:81-86` | 2026-09-16 |
| BF-43 | B01 | Zugangsdaten stehen bei aktivem Private-Data-Logging im Unified Log (CFNetwork-Fehlerzeilen) · Hinweis H-2 | niedrig | Folge von `XtreamClient.swift:61-72` (Zugangsdaten in der URL) | 2026-09-16 |
| BF-44 | B01 | Nach Übernahme einer v1.1-Datenbank ohne verbliebene Xtream-Playlist bleiben alte Passwörter aus freien Datenbankseiten erhalten (878 Vorkommen), weil nur bei ≥ 1 umgestellter Playlist verdichtet wird · QA 2 BUG-13 | mittel | `AppPersistence.swift` (Migration/VACUUM) | 2026-09-16 |
| BF-45 | B01 | Nach einem Update entfernt das Löschen einer Xtream-Playlist den Schlüsselbund-Eintrag nicht (`-25244`), der Fehler wird mit `try?` verschluckt · QA 2 BUG-14 | mittel | `PlaylistsView.swift`, `XtreamCredentialStore.swift` | 2026-09-16 |
| BF-46 | B01 | Wird eine unlesbare Datenbank beiseitegelegt, bleiben die Schlüsselbund-Einträge ihrer Playlists ohne Löschweg zurück · QA 2 H-8, ebenso B09 QA 2 BUG-20 | niedrig | `AppPersistence.swift`, `StoreRecoveryAlert.swift` | 2026-09-16 |
| BF-47 | B09 | Feed-Gegenprüfung blockiert ab Build 5 jedes Release, weil `generate_appcast` auf 3 Einträge kürzt · QA 2 BUG-19 | mittel | `scripts/b09_release_check.sh`, `scripts/release.sh` | 2026-09-16 |
| BF-48 | B09 | Fremde Download-Adresse in einem bestehenden Feed-Eintrag wird nicht erkannt und beim nächsten Release mitsigniert · QA 2 BUG-23 | mittel | `scripts/b09_release_check.sh` | 2026-09-16 |
| BF-49 | B09 | Test-Host startet Sparkle in der Einstellungsdomäne der installierten App · QA 2 BUG-21 | niedrig | `SparkleUpdater.swift`, Test-Host | 2026-09-16 |
| BF-50 | B09 | Leere Anzeigeversion kommt durch die Release-Gegenprüfung · QA 2 BUG-22 | niedrig | `scripts/b09_release_check.sh` | 2026-09-16 |
| BF-51 | B09 | `release.sh` bricht ohne `generate_appcast` ohne Meldung ab · QA 2 BUG-24 | niedrig | `scripts/release.sh` | 2026-09-16 |
| BF-52 | B03 | Aktualisieren und Löschen großer Playlists blockieren den Hauptthread minutenlang, quadratisch (17.000 Sender: Aktualisieren 280 s im Release, Löschen 41–133 s) · BUG-01 | hoch | `PlaylistImporter.swift:220-265,270-278,284-305` | 2026-09-16 |
| BF-53 | B03 | Ein Favorit wird beim Aktualisieren zu mehreren (nicht eindeutiger `favoriteKey`; 4 → 7, Xtream 1 → 3) (bestätigt in B05 QA 1 BUG-01: M3U 3 → 8, Xtream 2 → 6, entfernte Sterne kehren zurück) · BUG-02 | mittel | `Channel.swift:49-52`, `PlaylistImporter.swift:253,299` | 2026-09-16 |
| BF-54 | B03 | Ladeindikator nur für die zuletzt gestartete Aktualisierung, verschwindet beim ersten Ende · BUG-03 | mittel | `PlaylistsView.swift:11,110-111` | 2026-09-16 |
| BF-55 | B03 | Keine Sperre gegen mehrfaches Aktualisieren; jede Wahl sendet Zugangsdaten erneut (10× → 30 Anfragen) · BUG-04 | mittel | `PlaylistsView.swift:39-46`, `PlaylistImporter.swift:220` | 2026-09-16 |
| BF-56 | B03 | Player, Multiview und Senderliste halten gelöschte/ersetzte Sender: Verbindungen mit Zugangsdaten laufen weiter, „Erneut versuchen" ohne Zugangsdaten bzw. mit alter Adresse · BUG-05 (bestätigt in B08 BUG-05 und B07: PiP-Fenster spielt nach Löschen weiter) | mittel | `MultiviewSession.swift:37-41`, `PlayerView.swift:45-51,239-257`, `StreamURLResolver.swift:25`, `ChannelListView.swift:9-35` | 2026-09-16 |
| BF-57 | B03 | M3U-Adresse samt Token und Senderliste bleiben nach dem Löschen im HTTP-Plattencache · BUG-06 | mittel | `PlaylistImporter.swift:307-321,270-278` | 2026-09-16 |
| BF-58 | B03 | Kein Weg, alle Daten zu entfernen; Datenbank, beiseitegelegte Datenbank, Cache, Einstellungen und Schlüsselbund überdauern das Löschen der App (Website verspricht das Gegenteil) · BUG-09 | mittel | keine Funktion; `AppPersistence.swift:140-172,201-205`, `web/app/privacy/page.tsx:39` | 2026-09-16 |
| BF-59 | B03 | Namen und Stream-Adressen gelöschter Sender bleiben als Bytes in der Datenbankdatei (bestätigt in B05 QA 1 BUG-10: 3 von 11 Läufen) · BUG-07 | niedrig | `PlaylistImporter.swift:270-278` | 2026-09-16 |
| BF-60 | B03 | Verwaister Schlüsselbund-Eintrag nach Löschen während des Aktualisierens (Altbestand); Löschfehler mit `try?` verworfen · BUG-08 | niedrig | `PlaylistImporter.swift:242-245`, `PlaylistsView.swift:106` | 2026-09-16 |
| BF-61 | B03 | Löschen ohne Rückfrage und ohne Rückgängig — wartet auf Nutzerentscheidung OF-01 · BUG-10 | niedrig | `PlaylistsView.swift:47-51,104-107` | 2026-09-16 |
| BF-62 | B03 | Kürzere Liste ersetzt ohne Rückfrage, Favoriten kommen nicht zurück — wartet auf OF-02 · BUG-11 | niedrig | `PlaylistImporter.swift:250-262` | 2026-09-16 |
| BF-63 | B03 | Meldung „Zugangsdaten fehlen" führt nur über Löschen, das die Favoriten kostet — wartet auf OF-06 · BUG-12 | niedrig | `PlaylistImporter.swift:233-237` | 2026-09-16 |
| BF-64 | B02 | Zugangsdaten aus M3U-Links (`get.php?…password=`, `user:pass@`) im Klartext in `Playlist.sourceURL` und jeder `Channel.streamURL`; Schlüsselbund, Umstellung und Resolver greifen nur für Xtream · BUG-01 | hoch | `PlaylistImporter.swift:51-53,63,289-298`, `StreamURLResolver.swift:25`, `AppPersistence.swift:19-20,271` | 2026-09-16 |
| BF-65 | B02 | M3U-Import friert die Oberfläche ein, quadratisch: 17.000 Sender 282 s in Debug **und** Release; Datei-Lesen ebenfalls auf dem Hauptthread · BUG-04 | hoch | `PlaylistImporter.swift:22,58-66,197-212,289-304` | 2026-09-16 |
| BF-66 | B02 | HTTP-Plattencache enthält M3U-Adresse mit Zugangsdaten und Antwortkörper, übersteht das Löschen; das einmalige Leeren aus B01 wirkt nur einmal · BUG-02 | mittel | `PlaylistImporter.swift:307-311`, `AppPersistence.swift:361-366` | 2026-09-16 |
| BF-67 | B02 | Keine Größen-, Längen-, Mengen- und Gesamtzeitgrenze für Listen per URL und Datei (52 MB angenommen, 100 s Tröpfeln) · BUG-03 | mittel | `PlaylistImporter.swift:199,311`, `M3UParser.swift` | 2026-09-16 |
| BF-68 | B02 | Stream- und Logo-Adressen jedes Schemas (`file:`, `smb:`, `javascript:`, `vlc:`) ungeprüft gespeichert · BUG-05 | mittel | `M3UParser.swift:48,53` | 2026-09-16 |
| BF-69 | B02 | „Öffnen mit"/Doppelklick importiert nicht, jedes Öffnen erzeugt ein leeres Fenster; Website verspricht den Doppelklick-Import · BUG-06 | mittel | `Info.plist:76-90`, `MikaPlusPlayerApp.swift:29-35`, `web/content/features.ts:48` | 2026-09-16 |
| BF-70 | B02 | „Abbrechen" bricht URL- und Datei-Import nicht ab; ein späterer Fehler erscheint in einem losgelösten Sheet-Fenster · BUG-08 | mittel | `ImportPlaylistView.swift:106,133-136,154,192-224` | 2026-09-16 |
| BF-71 | B02 | App meldet sich als Öffner (Rang Default) für alle Text-Typen (`public.text`) · BUG-07 | niedrig | `Info.plist:83,87` | 2026-09-16 |
| BF-72 | B02 | Zwei Klicks vor dem Neuzeichnen starten zwei URL-Importe (zwei gleiche Playlists) · BUG-09 | niedrig | `ImportPlaylistView.swift:105-110,193` | 2026-09-16 |
| BF-73 | B04 | Gruppen-Chips gekürzt gebildet, Filter vergleicht ungekürzt — Sender mit Randleerzeichen fehlen unter ihrem Chip · BUG-01 | mittel | `ChannelListView.swift:77,95` | 2026-09-26 |
| BF-74 | B04 | Chip-Leiste wird nach Aktualisieren der Playlist nicht neu berechnet · BUG-02 | mittel | `ChannelListView.swift:43` | 2026-09-26 |
| BF-75 | B04 | Leerer Gruppenfilter behauptet „Diese Playlist enthält keine Sender." · BUG-03 | mittel | `ChannelListView.swift:101-104` | 2026-09-26 |
| BF-76 | B04 | Ohne Logo-Adresse und bei Verbindungsfehlern dreht der Ladeindikator dauerhaft (macOS und iOS) · BUG-04 | mittel | `ChannelRowView.swift:36-46` | 2026-09-26 |
| BF-77 | B04 | Keine Grenze für Logo-Größe, -Abmessung oder -Dauer; 12.000 × 12.000 px kosten über 600 MB, teils nach dem Verlassen nicht freigegeben · BUG-05 | mittel | `ChannelRowView.swift:36` | 2026-09-26 |
| BF-78 | B04 | Logos gehen ungefragt an beliebige Hosts (auch HTTP, auch über Weiterleitungen) und verraten IP, App-Build, OS-Version, Sprache und die gefilterten Sender · BUG-06 | mittel | `ChannelRowView.swift:36`, `Info.plist:45-48` | 2026-09-26 |
| BF-79 | B04 | Logo-Antworten landen im Plattencache (auch `no-store`, 404, HTML) und bleiben nach dem Löschen der Playlist · BUG-07 | mittel | `ChannelRowView.swift:36` (`URLCache.shared`) | 2026-09-26 |
| BF-80 | B04 | Gewählter Chip mit zu wenig Kontrast (gerendert 3,16 : 1 hell, 2,33 : 1 dunkel), keine Auswahl-Kennzeichnung für VoiceOver · BUG-10 | mittel | `ChannelListView.swift:137-157`, `PlayerTheme.swift:26` | 2026-09-26 |
| BF-81 | B04 | Liste blockiert bei 17.000 Sendern beim Öffnen (0,68–0,90 s), Leeren der Suche, Chip-Abwählen — auch im Release; Website „responds immediately" widerlegt · BUG-13 | mittel | `ChannelListView.swift:23-27,42,88-97`; `web/content/features.ts:12-13` | 2026-09-26 |
| BF-82 | B04 | Zahlen in Sendernamen als Text sortiert — wartet auf OF-01 · BUG-08 | niedrig | `ChannelListView.swift:97` | 2026-09-26 |
| BF-83 | B04 | Gruppen-Chips nach Zeichencode sortiert, Groß-/Klein-Varianten getrennt — wartet auf OF-02 · BUG-09 | niedrig | `ChannelListView.swift:79` | 2026-09-26 |
| BF-84 | B04 | Leerzustand der Suche englisch — wartet auf OF-03 · BUG-11 | niedrig | `ChannelListView.swift:105-106` | 2026-09-26 |
| BF-85 | B04 | Senderabfrage ohne Index (Filter über unindizierte Kopie `playlistID`) · BUG-12 | niedrig | `Channel.swift:20-23`, `ChannelListView.swift:73,93` | 2026-09-26 |
| BF-86 | B04 | Chip-Berechnung lädt alle Sender mit allen Spalten auf dem Hauptthread (~200 ms je Öffnen) · BUG-14 | niedrig | `ChannelListView.swift:70-80` | 2026-09-26 |
| BF-87 | B05 | Speicherfehler beim Umschalten des Sterns verschluckt: Stern und Tab zeigen den neuen Zustand, gespeichert ist nichts, keine Meldung · BUG-02 | mittel | `ChannelRowView.swift:60-62` (`try?`) | 2026-09-26 |
| BF-88 | B05 | Favoriten-Tab fragt bei jedem Öffnen genau die Logos der Favoriten an und verrät Logo-Hosts damit die Favoritenliste samt IP, App-Build und Sprache · BUG-03 | mittel | `FavoritesView.swift:8-12,22-28`, `ChannelRowView.swift:36` | 2026-09-26 |
| BF-89 | B05 | Favoriten-Zustand für VoiceOver nicht wahrnehmbar; Stern nur als englische Aktion „Favourite" · BUG-04 | mittel | `ChannelRowView.swift:59-69`, `FavoritesView.swift:24-27` | 2026-09-26 |
| BF-90 | B05 | Scheitert das Speichern beim Aktualisieren, zeigt die App den ungespeicherten Stand, meldet einen englischen SQLite-Fehler, und ein späteres Speichern schreibt ihn unbemerkt mit (kein `rollback`) · BUG-11 | mittel | `PlaylistImporter.swift:256-264`, `PlaylistsView.swift:113-116` | 2026-09-26 |
| BF-91 | B05 | Favorit geht beim Aktualisieren ohne Hinweis verloren (tvg-id-Schreibweise, Umbenennung, Wegfall) und kommt bei Rückkehr nicht zurück — wartet auf OF-03 · BUG-05 | niedrig | `PlaylistImporter.swift:253-262`, `Channel.swift:49-52` | 2026-09-26 |
| BF-92 | B05 | Gleichnamige Favoriten verschiedener Playlists nicht unterscheidbar, Reihenfolge wechselt — wartet auf OF-02 · BUG-06 | niedrig | `FavoritesView.swift:8-12,22-28` | 2026-09-26 |
| BF-93 | B05 | Favoriten-Tab sortiert nach Zeichencode statt sprachgerecht — wartet auf OF-01 · BUG-07 | niedrig | `FavoritesView.swift:10` | 2026-09-26 |
| BF-94 | B05 | Löschen einer Playlist nimmt ihre Favoriten ohne Hinweis mit; Neuimport hat keine — wartet auf OF-04 · BUG-08 | niedrig | `PlaylistsView.swift:104-107` | 2026-09-26 |
| BF-95 | B05 | NUL-Zeichen in Name oder tvg-id wird beim Speichern abgeschnitten, Favorit geht bei jedem Aktualisieren verloren · BUG-09 | niedrig | `M3UParser.swift:83,113`, `Channel.swift:49-52` | 2026-09-26 |
| BF-96 | B06 | VLC-Fehler (401/403/404, Host weg, Hänger, HTML, Abbruch) erreichen die Oberfläche nie: endloser Ladekreis, Schwarz oder Standbild — betrifft jeden Xtream-Sender im Standardformat MPEG-TS · BUG-01 (gegengeprüft ✅; auch in B08-Kacheln, B08 BUG-07) | hoch | `VLCPlaybackEngine.swift:80-99`, `PlayerView.swift:100-103` | 2026-09-26 |
| BF-97 | B06 | „Zurück" pausiert nur: Engines und Verbindungen überleben den Player (Release: bis App-Ende, bis zu 3 Verbindungen zum Anbieter; iPhone: 10 min Nachladen) · BUG-02 (gegengeprüft ✅; Mac-PiP-Ausprägung BF-105) | hoch | `PlayerView.swift:17,83-92`, `PlaybackEngine.swift:35-81`, `VLCPlaybackEngine.swift:49` | 2026-09-26 |
| BF-98 | B06 | libVLC `3.0.21-49` mit veröffentlichten Lücken (Bulletin 3.0.22, CVE-2025-51602) verarbeitet Streams beliebiger Hosts und `file://` ohne Sandbox; `vlckit-spm` ohne neuere Version, VLCKit 3.7.x mit libVLC 3.0.23 bei VideoLAN verfügbar · BUG-03 (gegengeprüft ✅) | hoch | `project.yml:17-19`, `VLCPlaybackEngine.swift:40-46`, `MikaPlusPlayer.entitlements:7-12` | 2026-09-26 |
| BF-99 | B06 | Fehleransicht zeigt Endnutzern den README-Hinweis „VLCKit fehlt" bei fehlenden Zugangsdaten, nie bei echten VLC-Fehlern · BUG-04 | mittel | `PlayerView.swift:220-223,234-236` | 2026-09-26 |
| BF-100 | B06 | Vollbildzustand nicht an das Player-Fenster gebunden (falsches Fenster, grüner Knopf, Tabwechsel) · BUG-06 | mittel | `PlayerView.swift:20,306-313,399-411` | 2026-09-26 |
| BF-101 | B06 | libVLC-Hänger des Hauptthreads beim Erzeugen eines Players, während andere abgebaut werden (zweimal im Test-Host; relevant für Multiview) · BUG-07 | mittel | `VLCPlaybackEngine.swift:30-38` | 2026-09-26 |
| BF-102 | B06 | Am iPad erreicht die Hardware-Tastatur den Player nicht · BUG-08 | mittel | `PlayerView.swift:58-61,81` | 2026-09-26 |
| BF-103 | B06 | Website verspricht Rückmeldung für jede Taste; F, Esc und P (VLC) haben keine · BUG-05 | niedrig | `web/content/features.ts:38`, `web/app/support/page.tsx:65-72` | 2026-09-26 |
| BF-104 | B06 | Ladekreis dunkelgrau statt weiß; Sendername unter iOS im hellen Erscheinungsbild unsichtbar · BUG-09 | niedrig | `PlayerView.swift:53,66-68,101-103` | 2026-09-26 |
| BF-105 | B07 | Mac: Nach „Zurück" spielt Bild-in-Bild verwaist weiter, die App kann es nicht beenden, der nächste Sender läuft parallel (42–60 s), „Zurück zur App" lässt den Stream unsichtbar weiterlaufen — gleiche Ursache wie BF-97 · BUG-01 (gegengeprüft ✅) | hoch | `PlayerView.swift:17,83-92`, `AVKitPlaybackEngine.swift:76-78,153-172` | 2026-09-26 |
| BF-106 | B07 | Wiedergabezustand folgt dem Player nicht, wenn das System ihn anhält (Pause/Schließen im Systemfenster, zweites Bild-in-Bild) · BUG-03 | mittel | `AVKitPlaybackEngine.swift:13,45-47`, `PlayerView.swift:146,348-353` | 2026-09-26 |
| BF-107 | B07 | Kein Bild-in-Bild im Xtream-Standardformat MPEG-TS (VLC), ohne Hinweis in Import-Sheet, Player und Website · BUG-04 | mittel | `ImportPlaylistView.swift:33`, `PlaybackEngine.swift:85-94`, `web/content/features.ts:31-33,38` | 2026-09-26 |
| BF-108 | B07 | iPad: Das Bild-in-Bild-Fenster verdeckt den eigenen Knopf „Bild-in-Bild schließen" · BUG-05 | mittel | `PlayerView.swift:113-133` | 2026-09-26 |
| BF-109 | B07 | iOS/iPadOS: „Zurück" beendet Bild-in-Bild sofort und ohne Hinweis, gegensätzlich zum Mac — wartet auf OF-04 · BUG-02 | mittel | `PlayerView.swift:17,83-92`, `AVKitPlaybackEngine.swift:154` | 2026-09-26 |
| BF-110 | B07 | Englische Systemtexte („Minimise/Maximise Video", Platzhalter) — wartet auf OF-03 · BUG-06 | niedrig | `PlayerView.swift:119-124` | 2026-09-26 |
| BF-111 | B08 | Absturz („Index out of range") im Raster beim Schließen des Multiview-Fensters und beim Entfernen per X (3 → 2, 1 → 0), Debug und Release; mit einem Stream ist „Fokus" gesperrt; **seit v1.1 ausgeliefert** · BUG-01 (gegengeprüft ✅) | kritisch | `MultiviewScreen.swift:69-93,79,26,116`, `MultiviewTile.swift:62` | 2026-09-26 |
| BF-112 | B08 | VLC-Stream (Xtream-Standardformat) nach Fokuswechsel im großen Bild schwarz, Ton läuft; im Raster nach Entfernen der ersten Kachel ebenso — Website verspricht das Gegenteil · BUG-02 (gegengeprüft ✅) | hoch | `MultiviewScreen.swift:40-46,74-85`, `VLCPlaybackEngine.swift:121-129` | 2026-09-26 |
| BF-113 | B08 | X des großen Streams liegt unter der ersten kleinen Kachel: Klick verlegt den Fokus, entfernt nichts · BUG-04 (gegengeprüft ✅) | hoch | `MultiviewScreen.swift:41-64`, `MultiviewTile.swift:53-75` | 2026-09-26 |
| BF-114 | B08 | Klick auf den abgeblendeten ⊞ öffnet den Player mit Ton und fünfter Verbindung · BUG-03 | mittel | `ChannelRowView.swift:73-85`, `ChannelListView.swift:111`, `FavoritesView.swift:24` | 2026-09-26 |
| BF-115 | B08 | N Kacheln = N Verbindungen ohne Rücksicht auf das Anbieterlimit; über dem Limit endlose Ladeanzeige ohne Meldung · BUG-06 | mittel | `MultiviewSession.swift:34,54-67`, `XtreamClient.swift:167-170` | 2026-09-26 |
| BF-116 | B08 | Derselbe Sender ohne Hinweis zweimal im Multiview — wartet auf OF-01 · BUG-08 | niedrig | `MultiviewSession.swift:54-67` | 2026-09-26 |
| BF-117 | B08 | ⊞ ohne Zugangsdaten öffnet leeres Multiview ohne Meldung — wartet auf OF-02 · BUG-09 | niedrig | `MultiviewSession.swift:57`, `ChannelRowView.swift:75-76` | 2026-09-26 |
| BF-118 | B08 | Multiview bis 105 × 106 pt verkleinerbar, kleine Kacheln laufen über, Umschalter verschwindet · BUG-10 | niedrig | `MikaPlusPlayerApp.swift:58`, `MultiviewScreen.swift:13-27` | 2026-09-26 |

## Behoben

| ID | Feature | Befund | Grad | Behoben am | Ausgeliefert |
|---|---|---|---|---|---|
| BF-30 | B01 | Xtream-Passwort im Klartext in `Playlist.sourceURL` und in jeder `Channel.streamURL`, keine Keychain · BUG-01 | hoch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-31 | B01 | Eingegebenes `https://` wird ohne Hinweis auf `http://` herabgestuft; Zugangsdaten gehen im Klartext durchs Netz · BUG-02 | hoch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-32 | B01 | Import blockiert den Hauptthread, Aufwand wächst quadratisch (17.000 Sender = 285 s) · BUG-12 | hoch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-33 | B01 | Anfragen mit Zugangsdaten und Antwortkörper im HTTP-Plattencache, überstehen das Löschen der Playlist · BUG-03 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-34 | B01 | Datenbank als generische `default.store` im gemeinsamen Application-Support-Ordner, nicht vom Backup ausgeschlossen · BUG-04 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-35 | B01 | Benutzername/Passwort nicht prozentkodiert: `+` scheitert an PHP-Panels, `/ # ?` zerlegen die Stream-Adresse · BUG-05 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-36 | B01 | Dekodierung strenger als zugesagt: `category_id` als Zahl oder ein Eintrag ohne Namen verhindert den ganzen Import · BUG-06 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-37 | B01 | Keine Drosselung wiederholter Fehlanmeldungen (10 Versuche in 0,01 s beim Panel) · BUG-07 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-38 | B01 | Keine Größen- und Gesamtzeitgrenze für Panel-Antworten (24 MB angenommen, Import 70 s offen gehalten) · BUG-08 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-39 | B01 | Nach „Abbrechen" erscheint das geschlossene Import-Sheet losgelöst wieder, mit Fehler-Alert · BUG-11 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-41 | B01 | Zugangsdaten folgen HTTP-Weiterleitungen zu fremdem Host/Port · BUG-10 | niedrig | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-42 | B01 | Rekonstruktion aus `sourceURL` verliert die Benutzerinfo (`u:pw@…`) — wirkt beim Aktualisieren (B03) · Hinweis H-1 | niedrig | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-02 | B09 | `get-task-allow` im Release ohne Hardened Runtime — Debugger-Attach ohne Root, Speicher samt Zugangsdaten lesbar · BUG-02 | kritisch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-04 | B09 | Kein Versionssprung seit v1.1 — ein Release erreicht keine Installation · BUG-04 | hoch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-10 | B09 | `release.sh` überschreibt `appcast.xml` mit Altstand aus `dist/` (1.0-Eintrag, `Mukaarts`-URLs) · BUG-10 | hoch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-11 | B09 | Keine Gegenprüfungen im Release-Ablauf · BUG-11 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-13 | B09 | Update kann die App durch fehlende Schema-Migration unbenutzbar machen (DM-04) · BUG-13 | hoch | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-14 | B09 | Sparkle nicht gepinnt, aufgelöste Version nicht versioniert · BUG-14 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-15 | B09 | Notarisierungsweg im README in falscher Reihenfolge · BUG-15 | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |
| BF-17 | B09 | Keine Tests für die Update-Kette · BUG-17 (Tests aus QA-Durchlauf 1 liegen bereit) | mittel | 2026-09-16 (QA 2 bestätigt) | nein — Branch `sdd/rueckerfassung`, nicht committet |

## Akzeptiert

Bewusst nicht behoben. Ohne Begründung und Datum ist ein Befund nicht akzeptiert,
sondern vergessen.

| ID | Feature | Befund | Grad | Begründung | Beschlossen am |
|---|---|---|---|---|---|

## Muster

Was in mehr als einem Feature auftritt — der Grund, warum diese Liste existiert.

- **Außendarstellung läuft dem Code voraus bzw. widerspricht ihm** (BF-12, BF-16, BF-20, BF-25, BF-26).
  Website und README werden ohne Abgleich mit Code und Release gepflegt; es gibt keinen Schritt im
  Release-Ablauf, der Website-Aussagen gegen die ausgelieferte Version prüft.
- **Große Listen auf dem Hauptthread** (BF-32 behoben, BF-52 offen; laut Rückerfassung auch M3U-Import B02 und
  Löschen). Der Xtream-Import wurde auf einen Hintergrundkontext umgebaut, die übrigen Schreibwege nicht.
  Dieselbe Ursache — Sender einzeln mit Beziehung auf dem Main-Actor anlegen oder löschen — steckt in jedem Pfad,
  der viele `Channel`-Objekte anfasst.
- **Reparaturen je Importweg statt im gemeinsamen Pfad** (BF-64 ↔ BF-30, BF-66 ↔ BF-33, BF-65 ↔ BF-32, BF-70 ↔ BF-39,
  BF-72 ↔ BF-40). Fünf B02-Befunde wiederholen wörtlich, was die B01-Reparatur für den Xtream-Zweig behoben hat:
  Schlüsselbund, Cache, Hintergrundkontext, Abbrechen, Doppelklick. Dasselbe Import-Sheet verhält sich je Reiter
  unterschiedlich. Die Ursache ist nicht der Einzelfehler, sondern dass Abruf und Anlegen zwei getrennte Wege haben.
- **Logos als stiller Datenabfluss** (BF-78, BF-79, BF-88, dazu BF-20). Jede Ansicht mit Logos schickt IP, App-Build,
  Systemsprache und — über die Auswahl der angefragten Logos — Such- und Favoritenverhalten an beliebige Hosts,
  und legt die Antworten dauerhaft im Cache ab. Die Datenschutzseite nennt Logo-Hosts, verschweigt aber, was sie
  daraus erfahren.
- **Fehler werden mit `try?` verschluckt** (BF-45, BF-60, BF-87, BF-90). Speichern, Schlüsselbund-Löschen und Aufräumen
  scheitern still; die Oberfläche zeigt dann einen Zustand, den es auf der Platte nicht gibt.
- **Englische Texte in einer deutschen Oberfläche** (BF-84, BF-89, B01 OF-06, B07 OF-03, B10 FB-14). Überall dort,
  wo System-Komponenten eigene Texte mitbringen. Solange die App-Sprache nicht entschieden ist (PRD, Offene Punkte),
  wiederholt sich das in jedem Feature.
- **Reste nach dem Löschen** (BF-33 behoben, BF-46, BF-56, BF-57, BF-58, BF-59, BF-60 offen). Löschen entfernt
  die Zeile in der Datenbank, aber nicht die Kopien daneben: HTTP-Cache, freie Datenbankseiten, Schlüsselbund,
  laufende Verbindungen, beiseitegelegte Datenbank. Es fehlt ein zentraler Löschweg.
- **Zugangsdaten stecken in URLs** (BF-30, BF-33, BF-41, BF-42, BF-43, außerdem BF-02 als Speicherzugriff). Weil
  Benutzername und Passwort Teil jeder Adresse sind, landen sie überall, wo Adressen landen: Datenbank,
  HTTP-Cache, Weiterleitungen, Systemprotokoll. Eine Einzelreparatur je Fundstelle greift zu kurz.
- **Auslieferungskette ohne Vertrauensanker** (BF-01 bis BF-08, BF-24): ad-hoc-Signatur, keine
  Notarisierung, unsignierter Feed auf ungeschütztem Branch, geteilter Schlüssel. Die Lücke liegt in
  der fehlenden Developer-ID-Infrastruktur, nicht in einer einzelnen Zeile.
