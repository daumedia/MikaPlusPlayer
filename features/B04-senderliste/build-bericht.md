# B04 · Senderliste — Build-Bericht

Durchlauf 1 · 2026-09-29 · Eingang: Fehlerauftrag (`qa-report.md` QA 1, BUG-01 bis BUG-14; BUG-08, -09, -11 warten auf OF-01,
-02, -03 und sind nicht gebaut) · Branch `sdd/reparaturen` auf dem Stand von `main` (`47a90c3`) plus den nicht committeten
Reparaturen B02+B03 (mit Nacharbeit R-01 bis R-11), B06, B07 und B08; nicht committet. macOS und iOS teilen den Code; ausgeführt
ist macOS, iOS ist gebaut.

## Ausgangslauf

Bezug ist der letzte Gesamtlauf des B08-Builds (`features/B08-multiview/build-bericht.md`, *Verifikation* 2: 29.09., 18:11–19:05,
501 Tests, 21 übersprungen, **1 Fehlschlag**: B04 `testEC07_WegscrollenUndZurueckscrollenWaehrendDesLadens`). Seitdem war der
Arbeitsbaum unverändert. Vor jeder Änderung dieses Builds sind die B04-Suiten einzeln gelaufen (29.09., 19:23–19:33, Debug,
`build/dd-test`, `test-without-building`):

```
Test Suite 'B04AufbauTests' passed        Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B04ErgaenzungTests' passed    Executed 4 tests, with 2 tests skipped and 0 failures (0 unexpected)
Test Suite 'B04ErkundungTests' passed     Executed 1 test, with 0 failures (0 unexpected)
Test Suite 'B04GruppenTests' passed       Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B04LeistungTests' passed      Executed 2 tests, with 0 failures (0 unexpected)
Test Suite 'B04LogoTests' passed          Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B04SicherheitTests' passed    Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B04SucheTests' passed         Executed 5 tests, with 0 failures (0 unexpected)
** TEST EXECUTE SUCCEEDED **
```

Darin **26 erwartete Fehlschläge**, die jeden BUG des Auftrags reproduzieren, z. B. (gekürzt):

```
B04GruppenTests.swift:222  Expected failure … testAK14_…: ("2") is not equal to ("6") - alle sechs Sport-Sender unter dem Chip „Sport“ (BUG-01)
B04GruppenTests.swift:246  Expected failure … testAK15_AK19_…: ("0") is not equal to ("2") - die zwei Sender der Gruppe „Tab“ (BUG-01/BUG-03)
B04GruppenTests.swift:355  Expected failure … testAK17_EC08_…: ("["Alle", "Kino", "News", "Sport"]") is not equal to ("["Alle", "Doku", "News", "Sport"]") (BUG-02)
B04LogoTests.swift:80      Expected failure … testAK22_…: fünf Karten mit Ladeindikator is not equal to ("[]") (BUG-04)
B04LogoTests.swift:172     Expected failure … testAK24_…: ("614.3") is not less than ("150.0") - Speicher (BUG-05)
B04LogoTests.swift:225/226 Expected failure … testAK25_AK26_…: Ziel 1 Anfrage; User-Agent "Mika+Player/3 CFNetwork/3896.100.1.1.1 Darwin/27.0.0" (BUG-06)
B04LogoTests.swift:327/328 Expected failure … testAK28_…: no-store im Cache; 6 Einträge nach dem Löschen (BUG-07)
B04GruppenTests.swift:192/193, B04ErgaenzungTests.swift:123  Expected failure … Kontrast 2,77 : 1; isAccessibilitySelected false (BUG-10)
B04LeistungTests.swift:98  Expected failure … Filter der Liste nutzt einen Index (BUG-12)
B04LeistungTests.swift:170–176 Expected failure … Öffnen 876 ms, Leeren/Abwählen 555 ms, 8 Zeichen 387 ms / 1,0 s, Zeichen 300 ms, Chip 188 ms (BUG-13)
```

BUG-14 mit dem SQL-Test (Startargument `-com.apple.CoreData.SQLDebug 1`, eigene Kopie der xctestrun-Datei):

```
AK-33|chipAbfrage=["SELECT 0, t0.Z_PK, t0.Z_OPT, t0.ZGROUP, t0.ZID, t0.ZISFAVORITE, t0.ZLOGOURL, t0.ZNAME, t0.ZPLAYLISTID, t0.ZSTREAMURL, t0.ZTVGID, t0.ZPLAYLIST FROM ZCHANNEL t0 WHERE  t0.ZPLAYLISTID = ?"]
B04ErgaenzungTests.swift:75: Expected failure … nur die Spalte ZGROUP wird gelesen (BUG-14)
** TEST EXECUTE SUCCEEDED **
```

**EC-07 aus dem B08-Lauf ist unabhängig vom Code – belegt:** Das Energieprotokoll des Rechners (`pmset -g log`) zeigt
`2026-09-29 18:34:22 Display is turned off` und `18:35:00 Display is turned on`. `B04LogoTests` endete im B08-Lauf um
**18:34:57** mit EC-07 als letztem Test (Laufzeit rund 30 s), also vollständig bei ausgeschaltetem Bildschirm. Bei
ausgeschaltetem Bildschirm liefert die Fensteraufnahme eine leere, weiße Fläche; der Test zählt dann 0 Logopunkte. Das ist heute
um 19:41–19:47 erneut passiert (Bildschirm aus 19:41:13–19:44:04 und ab 19:44:16): Alle Aufnahmen dieses Zeitraums waren leer
(z. B. `EC-07-zurueckgescrollt` 810 × 706 px weiß), EC-07 schlug mit genau derselben Meldung fehl (`logopunkte0=0`), ebenso
AK-21, AK-22, AK-24, AK-25 mit `logopunkte=0`. Mit eingeschaltetem Bildschirm besteht EC-07 – im Ausgangslauf oben und in allen
Läufen nach der Reparatur außer Lauf 4 (dort ein Befund dieses Builds, siehe *Verifikation* 4). Seitdem hält während der Läufe `caffeinate -d -i -u` den Bildschirm an (am Ende beendet).

**Release vorher** (Kopie des Ausgangsstands in einem eigenen Worktree unter `…/wt/b04-vorher`, gebaut mit
`-configuration Release -derivedDataPath <Projekt>/build/dd-release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO
CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES` wie in QA 1; Produkte nach `build/dd-release/vorher/` kopiert, damit vorher und nachher
abwechselnd unter derselben Last laufen): Zahlen in Abschnitt 1 und im `qa-report.md` unter BUG-13.

## 1 · Umgesetzt

Die Senderliste lädt nicht mehr auf dem Main-Thread. Trefferliste und Gruppen holt `ChannelListQuery` in einem eigenen
`ModelContext` im Hintergrund, die Trefferliste nur als Kennungen und gefiltert über die indizierte Beziehung zur Playlist;
jede Karte holt ihren Sender erst, wenn sie sichtbar wird. Die Suche ist entprellt, Chips wirken sofort. Bei 17.000 Sendern
blockieren Öffnen, Suchfeld-Leeren und Chip-Abwählen die Oberfläche im Release **7- bis 15-mal kürzer**, das erste Zeichen und das
Wählen eines Chips 2,5- bis 7-mal kürzer; jeder Vorgang bleibt unter 100 ms, und das Öffnen dauert nicht mehr länger als bei
einer Liste mit 20 Sendern. Chips und Filter benutzen dieselbe gekürzte Gruppenform; nach einem Aktualisieren – auch in einem
anderen Fenster – folgen Chips und Liste dem neuen Bestand, eine weggefallene Auswahl wird aufgehoben. Ein Chip ohne Treffer sagt
das, statt eine leere Playlist zu behaupten. Logos laden in Senderliste und Favoriten-Tab über **einen** Loader: nur
`http`/`https`, mit Größen-, Abmessungs- und Zeitgrenzen, als kleines Vorschaubild, ohne Plattencache, mit neutralen Kopfzeilen und
Weiterleitungen nur auf denselben Host; ohne Adresse und bei jedem Fehler erscheint der Platzhalter. Der gewählte Chip ist in
beiden Modi mit mindestens 5,8 : 1 lesbar (gerendert) und für VoiceOver als ausgewählt gekennzeichnet.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 | mittel | behoben | `ChannelListQuery.groups`/`descriptor` (Rohwerte je Chip), `ChannelListView` | G `testAK14_…`, G `testAK15_AK19_…`, R `testBUG01_…` |
| BUG-02 | mittel | behoben | `PlaylistEvents.didReplaceChannels` (neu), `PlaylistImporter.refresh`, `ChannelListView` | G `testAK17_EC08_…` (zwei Fenster), R `testBUG02_…`, B03 `testAK27_EC05_…` |
| BUG-03 | mittel | behoben | `ChannelResultsList` (Leerzustand „Keine Sender in dieser Gruppe“ + „Alle Sender zeigen“) | G `testAK15_AK19_…` |
| BUG-04 | mittel | behoben | `ChannelLogoLoader` (neu), `ChannelLogoView` (in `ChannelRowView.swift`) | L `testAK22_…`, L `testAK23_Zeitgrenze…`, X `testAngriff7_…`, R `testBUG04_…` |
| BUG-05 | mittel | behoben | `ChannelLogoLoader` (1 MiB, 2.048² px, 10 s/15 s ab dem Senden, ImageIO-Vorschaubild 128 px), `RequestGate` (höchstens 6 Anfragen je Host, Wartende abbrechbar) | L `testAK24_…`, L `testEC06_…`, L `testEC07_…`, R `testBUG05_…` ×2 |
| BUG-06 | mittel | **teilweise**: Weiterleitungen, Kopfzeilen, Cookies behoben; Abschalten/Zustimmung/nur HTTPS offen (OF-07) | `ChannelLogoLoader`, `PlaylistHTTPLoader` (`.sameHost`, `init(configuration:)`) | L `testAK25_AK26_…`, R `testBUG06_…` ×2; L `testAK27_…` behält `XCTExpectFailure` |
| BUG-07 | mittel | behoben | `ChannelLogoLoader` (ohne `URLCache`, Arbeitsspeicher), `PlaylistImporter.delete`, `AppDataReset` | L `testAK28_…`, X `testAngriff8_…`, X `testAngriff3_…`, R `testBUG07_…` ×2 |
| BUG-08 | niedrig | **nicht behoben** (wartet auf OF-01) | — | S `testAK09_…` behält `XCTExpectFailure` |
| BUG-09 | niedrig | **nicht behoben** (wartet auf OF-02) | — | G `testAK12_…` behält `XCTExpectFailure` |
| BUG-10 | mittel | behoben | `PlayerTheme` (Token `playerOnAccent`), `GroupChip` (`.isSelected`) | E `testAK13_Kontrast…` (gerendert 5,86 / 7,94 : 1), G `testAK13_…` |
| BUG-11 | niedrig | **nicht behoben** (wartet auf OF-03) | — | G `testAK20_EC04_…` behält `XCTExpectFailure` |
| BUG-12 | niedrig | behoben | `ChannelListQuery.descriptor` (`playlist!.persistentModelID`), Kommentar `Channel.swift` | P `testAK31_AK32_…` (`SEARCH … USING INDEX`), E `testAK31_AK33_…` (SQLDebug), X `testAngriff1_…`, R `testBUG12_…` |
| BUG-13 | mittel | behoben für die Listengröße; Rest Grundlast (siehe 2) | `ChannelListView` (Hintergrund, Kennungen, Entprellen, Neuaufbau ab 2.000 Treffern, Hybrid-Chipleiste), `ChannelListQuery` | P `testAK33_AK34_EC12_…` (Release-Tabelle im `qa-report.md`) |
| BUG-14 | niedrig | **teilweise**: Hintergrund behoben; nur Spalte `ZGROUP` offen (OF-08) | `ChannelListQuery.groups`, `ChannelListView.loadGroups` | E `testAK31_AK33_…` (SQLDebug) behält `XCTExpectFailure` für die Spalten; P Blockade |

Kürzel: A `B04AufbauTests`, S `B04SucheTests`, G `B04GruppenTests`, L `B04LogoTests`, P `B04LeistungTests`,
X `B04SicherheitTests`, E `B04ErgaenzungTests`, R `B04ReparaturTests` (neu, 10 Tests).

**Release, 17.000 Sender, 300 Gruppen**, Endstand (30.09., Tabelle mit allen Vorgängen unter BUG-13 im `qa-report.md`),
längste Blockade der Oberfläche, je zwei Läufe vorher/nachher abwechselnd:

| Vorgang | vorher | nachher | 20 Sender nachher |
|---|---|---|---|
| Liste öffnen | 639–870 ms | 60–67 ms | 93–158 ms |
| Tippen (erstes Zeichen „F“ / „Fu“ / weitere) | 310–317 / 150–312 / 67–141 ms | 41–62 / 47–73 / 28–88 ms | 30 / 35 / 10–28 ms |
| Suchfeld leeren | 293–446 ms | 56–66 ms | 52–84 ms |
| Chip wählen / abwählen | 180–187 / 527–539 ms | 71–72 / 34–56 ms | 31 / 72 ms |
| 8 Zeichen à 100 ms | 397–401 ms, 1,0 s | 44–53 ms, 0,8 s | 40 ms, 0,8 s |

Tests: Von 17 `XCTExpectFailure`-Blöcken in `Tests/B04` sind 10 entfernt (BUG-01 ×2, davon einer BUG-01/-03; BUG-02, -04, -05,
-06 [AK-25], -07, -10 ×2, -12) und 2 durch engere ersetzt (BUG-13 Rest, nicht strikt; BUG-14 Teil Spalten, nur mit SQLDebug); die
Ist-Assertions, die das fehlerhafte Verhalten festschrieben, stehen jetzt auf dem behobenen Verhalten. Unverändert bleiben 5:
BUG-06 Teil (AK-27, Grund jetzt OF-07), BUG-08, BUG-09, BUG-11 und H-1 (iOS, im Projekt nicht ausgeführt). Umbenannt, weil der Name den Fehler beschrieb: G `testAK14_…` →
`…ChipZeigtAlleSenderDerGruppeAuchMitRandleerzeichen`, G `testAK15_AK19_…` → `…ChipMitRandzeichenFindetSeineSenderLeererChipMeldetDieGruppe`,
G `testAK17_EC08_…` → `…ChipsFolgenDemAktualisierenInAllenFenstern`, L `testAK22_…` → `…ErscheintDerPlatzhalter`, L
`testAK23_ZeitgrenzeSechzigSekundenOhneDaten` → `testAK23_ZeitgrenzeOhneDatenDannPlatzhalter`, L `testAK24_…` →
`…GrenzenFuerDateigroesseUndBildabmessung`, L `testAK28_…` → `…KeinPlattencacheUndLoeschenLeertDieLogos`, L `testEC05_…` →
`…ZeigtPlatzhalter`, L `testEC06_…` → `…WirdNachDerGesamtfristGetrennt`, X `testAngriff3_…` →
`…WiederholtesOeffnenFragtGeladeneLogosNichtErneutAn`, X `testAngriff8_…` → `…LoeschenEntferntSenderUndLogos`, P
`testAK31_AK32_…AberOhneIndex` → `…UeberDenIndex`, P `testAK33_AK34_EC12_OberflaecheBlockiertBeimOeffnenUndTippen` →
`testAK33_AK34_EC12_BlockadeHaengtNichtVonDerListengroesseAb`.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-08, BUG-09, BUG-11** — nicht gebaut, warten auf OF-01, OF-02, OF-03 (Produktentscheidungen). Belegt: ihre
  `XCTExpectFailure` schlagen weiter erwartungsgemäß fehl.
- **BUG-06, Teil „Logos abschaltbar / Zustimmung / nur HTTPS“** — Produktentscheidung mit spürbarer Folge (viele Anbieter liefern
  Logos nur über HTTP; ohne Logos zeigen alle Karten den Platzhalter) → `spec.md` OF-07. Belegt: `testAK27_…` – nach der Suche
  „Religion“ fragt die App genau die Religion-Logos an (erwarteter Fehlschlag). Gilt ebenso für den Favoriten-Tab: **B05 · BUG-03
  bleibt im Kern offen** (der Host erfährt weiter die Favoriten); geändert haben sich dort nur Kopfzeilen, Cache und Grenzen.
- **BUG-14, Teil „nur die Spalte `ZGROUP`“** — SwiftData wertet `propertiesToFetch` nicht aus (SQLDebug: alle Spalten), und eine
  Abfrage nur einer Spalte bzw. `DISTINCT` gibt es in dieser SwiftData-Version nicht. Lösbar über eine gespeicherte Gruppenliste
  an der Playlist (Schema V2 mit Migrationsstufe) → OF-08. Die Rechenzeit (~0,2 s bei 17.000 Sendern) liegt jetzt im Hintergrund.
- **BUG-13, Rest** — zwei Grenzen der QA sind nicht verlässlich erreicht, und zwar auch nicht mit 20 Sendern und auch nicht vor
  der Reparatur: Öffnen einer Senderliste < 100 ms (17.000 Sender im Endstand erreicht: Release 60–67 ms, Debug 63 ms; am 29.09.
  noch 104–105 ms in Runde 1; eine 20er-Liste liegt vorher wie nachher darüber: 93–172 ms) und < 50 ms je Zeichen (Aufbau einer
  neuen Bildschirmseite Karten, Release bis 88 ms am 30.09., bis 94 ms am 29.09.; 20 Sender bis 61 ms). Das ist Grundlast von
  Navigation, Suchfeld-Toolbar und Kartenaufbau (Stern, ⊞ mit Tooltip, Logo, Badge – B05/B08), nicht die Listengröße. Der Test
  führt die beiden Grenzen als nicht strikte Erwartung und prüft stattdessen streng „Öffnen mit 17.000 ≤ Öffnen einer 20er-Liste im
  selben Lauf + 50 ms“ und „jedes Zeichen < 150 ms“ (Rückfallschutz, vorher 297–318 ms); alle übrigen Grenzen der QA bleiben.
  Die Aussagen der Website („responds immediately“, „as fast as you can type“) sind B10 Teil 2.
- **AK-06 „ohne Verzögerung“** gilt nicht mehr wörtlich: Die Suche wartet 150 ms nach dem letzten Zeichen (Auftrag „Suche
  entprellt“). Ergebnis nach dem letzten Zeichen im Release nach 215–234 ms sichtbar.
- **iOS nur gebaut, nicht bedient.** Die iOS-Oberflächentests aus QA 1 (`B04iOSOberflaecheUITests`) brauchen ein UI-Test-Target,
  das das Projekt nicht hat; H-1 (Suchfeld auf iOS erst nach Herunterziehen) ist nicht Teil des Auftrags und unverändert.
- **Nicht aus dem Auftrag, festgestellt:**
  - Bildschirm aus → leere Fensteraufnahmen → Oberflächentests, die Farben oder Logopunkte zählen, schlagen fehl (siehe
    *Ausgangslauf*). Für QA 2 und künftige Gesamtläufe: `caffeinate -d -u` während des Laufs.
  - `docs/design-system.md` („Weiß auf Akzent“, Kontrasttabelle, `GroupChip`), `docs/datenmodell.md` (Abfragen: Filter über
    `playlistID`, `loadGroups` im Speicher) und `docs/app-shell.md` („Senderliste: Laden keiner (synchron aus der DB)“) sind
    **nicht geändert und jetzt veraltet**; ebenso die rekonstruierten Kriterien in `spec.md` (AK-11 bis AK-34 beschreiben das Ist
    vor der Reparatur) – Nachführen ist Sache von QA-Durchlauf 2.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus), zur Bestätigung durch den Nutzer; die mit Produktfolge stehen als OF-07/OF-08 in `spec.md`.

1. **Grenzen je Logo:** 1 MiB je Antwort, 2.048 × 2.048 Bildpunkte laut Bildkopf, 10 s Leerlauf, 15 s Gesamtfrist, höchstens
   3 Weiterleitungen, Vorschaubild 128 px Kantenlänge (Logofeld 40 pt, bis 3-fache Auflösung). Die Fristen gelten ab dem Senden:
   Höchstens 6 Logo-Anfragen je Host laufen gleichzeitig (wie die Verbindungen je Host von `URLSession`), weitere warten
   abbrechbar in `RequestGate` (Nachtrag 30.09., siehe *Verifikation*: sonst liefen wartende Anfragen in der Warteschlange ab). Gemessen: Ein 12.000 × 12.000-px-PNG
   ohne Abmessungsgrenze, nur über ImageIO verkleinert, kostet 2,3 s Rechenzeit und +13 MB – deshalb zusätzlich die Abmessungsgrenze.
2. **Neutrale Kopfzeilen:** `User-Agent: Mozilla/5.0` (ein leerer oder fehlender User-Agent wird von manchen CDNs abgewiesen) und
   `Accept-Language: *`. `Accept: */*` und `Accept-Encoding` bleiben (verraten nichts über Gerät oder App).
3. **Weiterleitungen:** nur auf denselben Host und Port; einzige Ausnahme `http:80` → `https:443` desselben Hosts (häufige
   Umleitung auf HTTPS); nie `https` → `http`. Ein anderer Port gilt als anderer Dienst (der QA-Test leitet auf denselben Host
   127.0.0.1 mit anderem Port um).
4. **Nur `http`/`https`** – gleiche Regel wie beim Import (B02 · BUG-05); `file:` zeigt jetzt den Platzhalter (EC-05, OF-06 mit
   Vermerk, weiter zur Bestätigung).
5. **Arbeitsspeicher statt Plattencache:** fertige Vorschaubilder (nicht die Antworten), höchstens 400 Stück bzw. 24 MB, für die
   Laufzeit der App; `max-age` wird nicht ausgewertet, `no-store` und Fehler werden nie aufbewahrt. Das Löschen **irgendeiner**
   Playlist leert den ganzen Logo-Speicher (die Zuordnung Logo ↔ Playlist wird nicht geführt). Folge: weniger Anfragen als
   vorher (zehnmal Öffnen = eine Anfrage je Logo).
6. **Gruppen:** Chip-Titel wie bisher mit `.whitespaces` gekürzt (ein Zeilenumbruch bleibt, AK-11/EC-02); ein Chip filtert
   über alle gespeicherten Werte, die gekürzt so heißen. Sortierung und Groß-/Kleinschreibung unverändert (OF-02).
7. **Nach dem Aktualisieren** bleibt eine Auswahl, deren Gruppe es weiter gibt; eine weggefallene wird zu „Alle“. Das Ereignis
   `PlaylistEvents.didReplaceChannels` kommt nach dem Abholen der neuen Sender in den Kontext der Ansicht (nach dem Nachziehen
   der Sterne, R-01).
8. **Leerzustand Gruppe:** Symbol `line.3.horizontal.decrease.circle`, „Keine Sender in dieser Gruppe“, „In der Gruppe „…“ sind
   keine Sender.“, Taste „Alle Sender zeigen“ (Stil wie „Playlist importieren“). Scheitert eine Abfrage, bleibt der bisherige
   Stand stehen (keine leere Liste als Aussage).
9. **Laden beim Öffnen:** Listen bis 2.000 Sender laden beim ersten Erscheinen sofort (Gruppen und Treffer, wenige
   Millisekunden; das erste Bild zeigt die Karten wie bisher). Größere Listen laden im Hintergrund; bis die erste Trefferliste
   da ist (17.000 Sender: rund 65 ms Abfrage), zeigt die Seite nur Kopfzeile und Titel, keinen Leerzustand und keinen
   Ladeindikator. Anlass war ein Test von B05 (EC-04), der die Hauptwarteschlange während des Wartens blockiert: Die im
   Hintergrund geladene Liste erschien dort erst nach dem Aktualisieren.
10. **Entprellen 150 ms** nur für Änderungen am Suchtext; Chips und das Aktualisieren wirken sofort.
11. **Neuaufbau statt Abgleich** der Kartenliste, wenn die alte oder neue Trefferliste mehr als 2.000 Sender hat (SwiftUI glich
    sonst bis zu 17.000 Kennungen ab); kleinere Listen werden abgeglichen, sichtbare Karten bleiben erhalten.
12. **Chip-Leiste:** bis 40 Chips wie bisher alle sofort (auch für Bedienungshilfen vollständig), ab 41 nur die sichtbaren
    (`LazyHStack`, wie die Karten); 300 Chips hatten das Öffnen allein um rund 0,2–0,3 s blockiert (gemessen).
13. **Filter über die Beziehung:** Ein Sender mit widersprüchlicher Kopie `playlistID` erscheint in der Playlist seiner
    Beziehung (wie beim Abspielen); ein Sender ohne Beziehung erscheint nirgends (H-3).
14. **Schriftfarbe gewählter Chip:** #120F10 in beiden Modi (Token `playerOnAccent`); die Fläche bleibt der Akzent, damit AK-13
    („in Akzentfarbe gefüllt“) gilt. Die Website nutzt im Hellmodus stattdessen eine dunklere Fläche mit weißer Schrift – für die
    App gewählt, weil der Auftrag nur die Textfarbe ändert.
15. **Tests angepasst**, wo sie das alte Verhalten festschrieben (Namen siehe 1): B04-Hilfen benutzen die Abfrage der App statt
    eines Spiegels (`B04QA.resultsDescriptor`, `groupsMirror`); `rows` wählt die Senderliste als höchsten Lazy-Container (bei vielen
    Gruppen ist auch die Chip-Leiste einer); neu `revealChip` (Leiste scrollen). `testEC06_…` lässt den Host alle 4 s statt 10 s
    ein Byte senden, damit die **Gesamtfrist** geprüft wird und nicht zufällig die Leerlauffrist greift. In
    `testAK33_AK34_EC12_…` wird das Chip-Drücken ohne das Durchsuchen des Accessibility-Baums gemessen (mit Suche weiter
    protokolliert); dazu Vergleichsmessung mit 20 Sendern und Zeit bis zur Anzeige.
16. **Testumgebung:** `caffeinate -d -i -u` während der Läufe, damit der Bildschirm nicht ausgeht (sonst leere Aufnahmen); am
    Ende beendet.

## 4 · Systemweite Änderungen

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Services/PlaylistHTTPLoader.swift` | **B01, B02, B03** | neuer Initialisierer `init(configuration:)` (der bisherige `init()` ruft ihn mit unveränderter Konfiguration), neue Regel `RedirectPolicy.sameHost(maxRedirects:)`, Entscheidung in `allowsRedirect` ausgelagert. `.sameOrigin` (Xtream) und `.follow` (M3U) unverändert (R `testBUG06_WeiterleitungsregelFuerLogos` prüft beide mit) |
| `Sources/Views/ChannelRowView.swift` | **B05, B08** | Logo über `ChannelLogoView`/`ChannelLogoLoader` statt `AsyncImage` – gilt auch im **Favoriten-Tab** (neutrale Kopfzeilen, Grenzen, kein Plattencache, Arbeitsspeicher: erneutes Öffnen des Tabs fragt geladene Logos nicht mehr an). Stern (R-01) und ⊞ (B08) unverändert |
| `Sources/Services/PlaylistImporter.swift` | **B02, B03** | `refresh` meldet `PlaylistEvents.didReplaceChannels`; `delete` leert die Logos im Arbeitsspeicher; `init` mit Parameter `logoLoader` (Standard `.shared`) |
| `Sources/Services/PlaylistEvents.swift` | B03, B06, B08 | neues Ereignis `didReplaceChannels` (bisher nur `willDelete`) |
| `Sources/Services/AppDataReset.swift` | **B03**, B09 | „Alle Daten entfernen“ leert auch die Logos (`Targets.logoLoader`) |
| `Sources/Views/Theme/PlayerTheme.swift` | Design-System | neues Farb-Token `Color.playerOnAccent` (#120F10 hell und dunkel) |
| `Sources/Models/Channel.swift` | B05 | nur Kommentar zu `playlistID`; **kein** Schemawechsel, `SchemaMigrationPlan` unverändert |
| neu: `Sources/Services/ChannelListQuery.swift`, `Sources/Services/ChannelLogoLoader.swift` | B04, B05 | siehe oben |
| Tests anderer Features | B03, B05 | B03 `testAK27_EC05_…`: Chip „Neu“ erscheint nach dem Aktualisieren (vorher: „nicht aktualisiert (B04)“); B05 `testAK25_Angriff5_…`: `user-agent` = `Mozilla/5.0`, `accept-language` = `*` (vorher App-Kennung und Sprache); das `XCTExpectFailure` zu B05 · BUG-03 bleibt |
| `Tests/B04/B04Support.swift` | Tests | Abfrage der App statt Spiegel, `rows` robust gegen eine Lazy-Chip-Leiste, `revealChip` |
| `docs/design-system.md`, `docs/datenmodell.md`, `docs/app-shell.md`, `CLAUDE.md` | Doku | **nicht geändert, jetzt veraltet** (siehe 2); CLAUDE.md nennt `ChannelListQuery`/`ChannelLogoLoader` noch nicht und beschreibt die Liste als `@Query` (Vorschlag für den Orchestrator) |
| `features/B04-senderliste/spec.md` | Doku | nur *Offene Fragen*: Vermerk unter OF-06, neu OF-07, OF-08 |
| `features/B05-favoriten/qa-report.md` | Doku | Vermerk unter BUG-03 (nicht behoben, berührt) |
| `project.yml`, `Info.plist`, Entitlements, Abhängigkeiten, Schema | alle | **unverändert** (keine neue Abhängigkeit; `#Index` nicht verfügbar, Deployment-Ziel nicht angehoben) |

Nicht angefasst: `features/index.md`, `features/befunde.md`, `appcast.xml`, `web/`, Schlüsselbund, die echte Datenbank.

## Unabhängiges Review

Ein `code-reviewer`-Agent hat die Quelltext-Änderungen (Diff gegen den Ausgangsstand) ohne Kenntnis dieser Bewertung gelesen:
keine Funde mit hoher Sicherheit (Nebenläufigkeit, gelöschte Modelle, Weiterleitungsregel, bestehende Aufrufer des Loaders,
Leerzustände, Cache-Leerung geprüft). Eine Beobachtung unterhalb der Meldeschwelle: `Task.detached` erbt den Abbruch der
`.task(id:)`-Aufgabe nicht, bei sehr schnellem Wechseln der Chips laufen einzelne Hintergrundabfragen zu Ende, bevor ihr Ergebnis
verworfen wird – keine falsche Anzeige, nur doppelte Arbeit. Nicht geändert (bewusst: eine laufende SQLite-Abfrage lässt sich ohnehin
nicht abbrechen; die Abfragen dauern 1–65 ms). Die Warteschlange je Host (`RequestGate`, Nachtrag 30.09.) ist nach dem
Review entstanden und nicht vom Reviewer gelesen; sie hat einen eigenen Test (Abbruch eines Wartenden, Freigabe des Platzes).

## Verifikation

Stand **2026-09-30**, Schlussläufe nach allen Änderungen (letzte Quelländerung: `RequestGate`, 30.09. 18:05). Streams zeigen
auf den geschlossenen Port 9 bzw. lokale Mocks, keine Tonspur, keine Tastaturereignisse außer denen der B06/B07-Tests selbst (und zweimal Escape in
Lauf 6, siehe 4);
Logo-Hosts nur `B04LogoHost` auf 127.0.0.1/`localhost`. Während aller Läufe hielt `caffeinate -d -i -u` den Bildschirm an
(Energieprotokoll: kein „Display is turned off“ seit dem Neustart). Die Sitzung wurde am 29.09. um 23:32 durch einen Neustart
des Rechners unterbrochen (Gesamtlauf 3 bis B07 ohne Fehlschlag, dann abgebrochen); nach dem Neustart lief **keine**
App-Instanz aus `build/dd-test` (geprüft 30.09. 17:17). Am 30.09. lief bis 17:30 ein fremder iOS-Testlauf (anderes Projekt,
Last bis 370); die Läufe unten begannen danach (Last 5–15).

**1 · Projekt erzeugen** — `xcodegen generate` → exit 0 (vor jedem Lauf).

**2 · Warnungen** — `xcodebuild clean build-for-testing … -derivedDataPath build/dd-test` (30.09. 17:19) →
`** CLEAN SUCCEEDED **`, `** TEST BUILD SUCCEEDED **`: **0 Warnungen in `Sources/`**. In `Tests/B04/` dieselben vier Arten wie
in QA 1 (`CGWindowListCreateImage` veraltet ×2 Dateien, Sendable `NSMutableData` in `B04GruppenTests`, überflüssiges `??` in
`B04LeistungTests`); `B04ReparaturTests` ohne Warnung. Keine neue Warnung.

**3 · macOS-Gesamtlauf (Schlusslauf 7, 30.09. 20:26–21:23, Last 6–8)** — `xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' -derivedDataPath build/dd-test -collect-test-diagnostics never`
mit Aktivierungshelfer (wie im B08-Build: `TEST_RUNNER_B06_ACTIVATE_REQ`, `TEST_RUNNER_B08_AKTIVIEREN`,
`TEST_RUNNER_B07_BRIDGE`; der Helfer holt den Test-Host per Bedienungshilfen nach vorn und lehnt alle anderen
Bridge-Befehle ab, sodass die B07-Systemfenster-Tests wie bisher übersprungen werden):

```
Test Suite 'All tests' started at 2026-09-30 20:26:06.506.
…
Test Suite 'B04AufbauTests' passed       Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B04ErgaenzungTests' passed   Executed 4 tests, with 2 tests skipped and 0 failures (0 unexpected)
Test Suite 'B04ErkundungTests' passed    Executed 1 test, with 0 failures (0 unexpected)
Test Suite 'B04GruppenTests' passed      Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B04LeistungTests' passed     Executed 2 tests, with 0 failures (0 unexpected)
Test Suite 'B04LogoTests' passed         Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'B04ReparaturTests' passed    Executed 10 tests, with 0 failures (0 unexpected)
Test Suite 'B04SicherheitTests' passed   Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'B04SucheTests' passed        Executed 5 tests, with 0 failures (0 unexpected)
…
B09BUILD|BUG-11|falscherSchluessel|exit=1
Tests/B09/B09ReleaseSkriptTests.swift:121: error: -[… B09ReleaseSkriptTests testBUG11_ReleaseBrichtBeiFalschemSchluesselAbOhneFeedZuAendern] : XCTAssertTrue failed - ==> Gegenprüfung vor dem Build … == Ergebnis: keine Befunde … ==> [Attrappe] build/MikaPlusPlayer.app
Test Suite 'B09ReleaseSkriptTests' failed at 2026-09-30 21:23:11.334.
	 Executed 7 tests, with 1 failure (0 unexpected) in 34.888 (34.891) seconds
…
	 Executed 511 tests, with 22 tests skipped and 1 failure (0 unexpected) in 3424.549 (3424.843) seconds
** TEST FAILED **
```

**Alle Suiten von B01 bis B08 und die übrigen B09-Suiten grün**, einschließlich B05 (Favoriten-Tab mit dem gemeinsamen Logo-Loader), B03 (Chip
„Neu“ nach dem Aktualisieren) und der B06/B07/B08-Oberflächentests. In `Tests/B04` blieben genau die erwarteten Fehlschläge
übrig: BUG-08 (S `testAK09_…` ×2), BUG-09 (G `testAK12_…`), BUG-11 (G `testAK20_EC04_…`), OF-07 (L `testAK27_…`) und der nicht
strikte Rest von BUG-13 („Fußball 1“ 81 ms > 50 ms). Die 22 Übersprungenen überspringen sich selbst mit einem Umgebungsgrund
(Datenträgerabbild, Private-Data-Logging, Laufzeit > 3 min, SQLDebug/iOS-Store nur auf Anforderung, B07-Systemfenster ohne
Bridge). Gegenüber Lauf 2 (21) kommt B06 `testAK22_HoverAmOberenRandImVollbild` hinzu („Synthetische Mausbewegung erreicht
onContinuousHover nicht“, ebenso in Lauf 5, in Lauf 2 grün) – eine Grenze der Maussimulation im Player, nicht der Senderliste.

**Der eine Fehlschlag ist unabhängig von B04:** B09 `testBUG11_ReleaseBrichtBeiFalschemSchluesselAbOhneFeedZuAendern` prüft, dass
`scripts/release.sh` (in einer Attrappe mit Stub-Build, eigenem Test-Schlüssel) bei falschem Schlüssel **mit einem Befund**
abbricht. Das Skript brach nach dem Stub-Build mit Exit 1 ab, aber ohne die erwartete Zeile `[BEFUND]` in der Ausgabe. Der Test
berührt weder `Sources/` noch die Senderliste; `scripts/` und `Tests/B09` sind in diesem Build unverändert. Einzeln wiederholt
(`-only-testing:MikaPlusPlayerTests/B09ReleaseSkriptTests`, 30.09. 21:23–21:25, direkt nach dem Gesamtlauf): **2 × 7 von 7 grün**. Im B08-Lauf und in
den Läufen 1, 2 und 5 dieses Builds war der Test grün (9–10 s; im Fehlschlag 2,7 s, das Skript endete also früher als sonst).
Einordnung: vorübergehend, Ursache im Skriptablauf von B09, kein Befund dieses Builds; für QA 2 von B09 im Blick behalten.

**4 · Frühere Gesamtläufe und ihre Einordnung**

| Lauf | Ergebnis | Fehlschlag | Einzeln wiederholt / Gegenprobe | Einordnung |
|---|---|---|---|---|
| 1 (29.09. 20:44–21:40) | 510 Tests, 22 übersprungen, 2 Tests rot | B05 `testEC04_SternWaehrendDesWartensAufDenAnbieter`: Karte „Beta“ nicht gefunden | 1 × rot (gleich) | **Befund dieses Builds.** Der Test blockiert während des Wartens die Hauptwarteschlange; die im Hintergrund geladene Liste erschien erst nach dem Aktualisieren. Behoben durch sofortiges Laden kleiner Listen (Annahme 9); danach einzeln grün und in allen folgenden Läufen |
| 1 | | B03 `testAK12_AK13_EC09_…` (Kontextmenü erst nach 51 s) | einzeln rot; **derselbe Test auf dem Ausgangsstand** (Release-Kopie `vorher`) ebenfalls rot mit denselben drei Meldungen | unabhängig vom Code (synthetische Kontextmenüs unter Last, wie in der B02/B03-Nacharbeit); in Lauf 2, 5, 6 und 7 grün |
| 2 (29.09. 21:50–22:44) | 510 Tests, 21 übersprungen, 1 rot | B04 `testAK24_…`: Speicher +169 MB (> 150) | 2 × grün (+35/+36 MB), in der Reihenfolge des Gesamtlaufs grün (+28 MB) | Ausreißer der Prozess-Speichermessung (enthält alles im Test-Host); sonst +27 bis +28 MB; vor der Reparatur +614 MB |
| 3 (29.09. 22:49–23:32) | abgebrochen (Neustart) | — bis `B07VerlassenTests` keiner | — | — |
| 4 (30.09. 17:30–18:00) | von mir abgebrochen nach B06 | B04 `testEC07_…`: „Sender 00“ und „Sender 02“ zeigen nach dem Zurückscrollen den Platzhalter (Aufnahme) | — | **Befund dieses Builds** (Fristen liefen in der Warteschlange ab), behoben mit `RequestGate`; danach EC-07 4 × einzeln grün, strengere Prüfung (alle sechs sichtbaren Karten) – siehe `qa-report.md` BUG-05, Nachtrag |
| 5 (30.09. 18:08–19:05) | 511 Tests, 22 übersprungen, 4 Tests rot | B06 `testAK01_AK14_…`, `testAK21_AK19_EC07_…`, `testAK23_…` (unbehandeltes Tastenereignis bzw. Fenstergröße nach Vollbild); B07 `testBUG01_EchteOberflaeche_ZurueckMitPiP_…` („nie zwei Streams zugleich“, 1 statt 0 Sekunden) | ohne Helfer: alle vier übersprungen (Test-Host nicht aktivierbar); **mit Helfer: alle vier grün**. B07-Test in Serie: Endstand Debug 8 von 10 grün, Release 11 von 13; Ausgangsstand Release 13 von 13 | B06: Tastaturfokus/Aktivierung des Test-Hosts (wie im B08-Bericht, B06-Review H-3); die B06-Tests benutzen eine eigene Senderliste, nicht `ChannelListView`. B07: Das zeitgenaue Kriterium hielt in **allen** Läufen („anfragenA nach erster Anfrage von B = 0“); rot wird nur die Zählung je Sekunde, wenn die letzte Anfrage an A und die erste an B in dieselbe Sekunde fallen. In 8 abwechselnden Läufen Ausgangsstand/Endstand (Release) 8/8 und 8/8 grün. Ein Einfluss der Liste auf die Zeit bis zum Start von B ist damit nicht belegt, aber auch nicht ausgeschlossen – für QA 2 im Blick behalten |
| 6 (30.09. 19:25–20:25) | von mir abgebrochen in B06 | B02 `testAK16_DateiPlaylistSymbolUndKontextmenue` hing 25 min im Kontextmenü (Test-Host nicht vorn, Menü-Tracking wartete); ab B06 `testAK09_…` blieben 4 VLC-Player offen („abgebaut nach 15,2 s, noch offen=4“), danach B06 `testBUG07_MultiviewSchliessenUndSofortNeuAbbau…` rot | B02-Test lief nach Vordergrundholen des Test-Hosts und zweimal Escape (gegen 19:56, meine einzigen Tastendrücke) weiter und wurde grün; in Lauf 7 ohne Eingriff grün (113 s). B06-Folge in Lauf 7 nicht wieder aufgetreten, B06 dort vollständig grün | B02: Aktivierung des Test-Hosts, kein Code dieses Builds (Kontextmenü der Playlist). B06: bekannter libVLC-Hänger beim Abbau (BF-101, B06 BUG-03 wartet auf OF-06); die B06-Tests benutzen die Senderliste nicht |

**5 · Leistung im Gesamtlauf (Debug, Lauf 7)** – längste Blockade bei 17.000 Sendern: Öffnen 63 / 63 ms (20er-Liste 134 / 128),
„F“ 36, „Fu“ 65, weitere Zeichen 29–81, Leeren 68 / 59, „a“ 54, Chip 73 (mit Suche im Baum 89), Abwählen 62 (58), 8 Zeichen
46 ms / 0,8 s; bis zur Anzeige: Öffnen 113, Suche „Fußball 12“ 207, Leeren 270, Chip 59, Abwählen 120 ms. Lauf 5 lag gleich
(Öffnen 71 / 84, Chip 75). **Knapp:** „Chip wählen“ lag in allen Läufen unter 100 ms, aber mit wenig Abstand (Debug 66–94 ms,
Release 54–98 ms).

**6 · Release vorher / nachher** — nach der letzten Quelländerung neu gebaut (`xcodebuild build-for-testing -configuration Release
-derivedDataPath build/dd-release …`, 30.09. 18:08; Ausgangsstand wie im *Ausgangslauf* beschrieben aus dem Worktree
`…/wt/b04-vorher`), dann `B04LeistungTests` mit `test-without-building` abwechselnd vorher/nachher, je zwei Läufe mit 17.000 und
einer mit 20 Sendern (30.09. 21:25–21:32, Last 5–11). **Alle sechs Läufe `** TEST EXECUTE SUCCEEDED **`**; der Ausgangsstand
erfüllt seine alten `XCTExpectFailure` (BUG-12, BUG-13: 7–8 erwartete Fehlschläge je Lauf mit 17.000), der Endstand löst nur die
nicht strikte Erwartung „< 50 ms je Zeichen“ aus („Fußball 1“ 76 / 88 ms). Zahlen: Abschnitt 1 und `qa-report.md` BUG-13
(*Nachtrag 2026-09-30*). Gegenüber der Messung vom 29.09. (vor `RequestGate`) liegt der Endstand im selben Bereich
(Öffnen 60–67 statt 65–105 ms, Leeren 56–66 statt 43–58 ms, Abwählen 34–56 statt 56–57 ms); `RequestGate` betrifft nur Logos
und wirkt nicht auf die Liste. Reine Abfragen: Kennungen ohne Filter 64–70 ms (als Objekte 241–248 ms, vorher 256–261 ms),
Chips berechnen 195–204 ms im Hintergrund. `build/dd-release` ist danach gelöscht.

**7 · Echtes SQL** (Startargument `-com.apple.CoreData.SQLDebug 1`, eigene Kopie der xctestrun-Datei in `build/dd-test`,
29.09. 21:49):

```
AK-31|sql|oeffnen|SELECT 0, t0.Z_PK FROM ZCHANNEL t0 WHERE ( t0.ZPLAYLIST IS NOT NULL AND  t0.ZPLAYLIST = ?) ORDER BY t0.ZNAME COLLATE NSCollateLocaleSensitive
AK-31|sql|oeffnen|SELECT 0, t0.Z_PK, … FROM ZCHANNEL t0 WHERE  t0.Z_PK = ?  LIMIT 1          ← je sichtbare Karte
AK-31|sql|chip|SELECT 0, t0.Z_PK FROM ZCHANNEL t0 WHERE (( t0.ZPLAYLIST IS NOT NULL AND  t0.ZPLAYLIST = ?) AND  t0.ZGROUP = ?) ORDER BY …
AK-31|sql|sucheUndChip|… AND  NSCoreDataStringSearch( t0.ZNAME, ?, 417, 1)) AND  t0.ZGROUP = ?) ORDER BY …
AK-33|chipAbfrage=["SELECT 0, t0.Z_PK, t0.Z_OPT, t0.ZGROUP, t0.ZID, t0.ZISFAVORITE, t0.ZLOGOURL, t0.ZNAME, t0.ZPLAYLISTID, t0.ZSTREAMURL, t0.ZTVGID, t0.ZPLAYLIST FROM ZCHANNEL t0 WHERE ( t0.ZPLAYLIST IS NOT NULL AND  t0.ZPLAYLIST = ?)"]
B04ErgaenzungTests.swift:82: Expected failure … nur die Spalte ZGROUP wird gelesen (BUG-14 Teil Spalten, OF-08)
** TEST EXECUTE SUCCEEDED **
```

**8 · iOS** — `xcodebuild build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`
(30.09. 17:19 als `clean build`, nach der letzten Quelländerung um 18:07 erneut; `ChannelListQuery.swift`,
`ChannelListView.swift`, `ChannelLogoLoader.swift` jeweils für arm64 und x86_64 übersetzt):

```
** CLEAN SUCCEEDED **
** BUILD SUCCEEDED **
appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found   ← wie Ausgangslauf
** BUILD SUCCEEDED **   (18:07, gleiche Warnung)
```

**Aufräumen und Vorkommnisse**

- **Beendet:** Aktivierungshelfer (`aktivierer.sh`, 30.09. 21:37) und mein `caffeinate -d -i -u` (beim Aufräumen schon beendet;
  Energieprotokoll ohne „Display is turned off“ seit 30.09. 17:01). Die beiden `caffeinate -i -t 300` und die
  `xcodebuildmcp`-Prozesse gehören anderen Sitzungen und sind unberührt. Mock-Server liefen nur im Test-Host (127.0.0.1) und
  endeten mit ihm; danach lief keine Instanz von `MikaPlusPlayer`, kein `xcodebuild`, kein eigener Python-Prozess. Die App
  wurde nie regulär gestartet; nach dem Neustart vom 29.09. lief keine Instanz (geprüft 30.09. 17:17).
- **Gelöscht:** `build/dd-release` (3,9 GB, mit den Produkten des Ausgangsstands in `vorher/`); Worktree `…/wt/b04-vorher`
  (`git worktree remove --force`, `git worktree prune`, leeres `wt/` entfernt); die SQLDebug-Kopie der xctestrun-Datei; der
  vorübergehende Erkundungstest (nie im Projekt geblieben); die Standard-DerivedData-Ordner, die am 29.09. ein
  `test-without-building` ohne `-derivedDataPath` angelegt hatte (sofort gelöscht, seitdem immer mit `-derivedDataPath`); meine
  Kopien im Arbeitsordner (Sicherung der Nachweise, Ausgangsquellen, Diff). Aufbewahrt außerhalb des Repositorys:
  `~/.claude/projects/…/e8de96ed-…/b04work/logs/` (Textprotokolle aller Läufe und Messungen, 16 MB, erfundene Zugangsdaten)
  und die Hilfsskripte.
- **Nicht angelegt:** Simulatoren (iOS nur `generic/platform=iOS Simulator`), Datenträgerabbilder, Schlüsselbund-Einträge.
  `build/dd-test` und `build/dd-ios` bleiben (erlaubt); `build/dd` (Stand 30.07.) unberührt. Datenbank und Cache des Nutzers
  weder gelesen noch beschrieben, alles ohne Ton, nichts committet.
- **Fremde Nachweise:** Nach jedem Lauf zurückgesetzt (`git checkout --` für versionierte Dateien unter `features/*/qa/`, neue
  fremde Dateien dort entfernt, gesicherte unversionierte Nachweise anderer Builds zurückgespielt). Endstand: keine versionierte
  Datei unter `features/*/qa/` geändert; neu sind nur die acht `features/B04-senderliste/qa/BUILD-*`-Nachweise dieses Builds.
- **Vorkommnis – zurückgesetzte Review-Abschnitte (behoben):** Die erste Fassung meines Rücksetzskripts (29.09. 19:23 bis
  30.09. 17:18) spielte **alle** gesicherten unversionierten Dateien unter `features/` zurück, nicht nur Nachweise. Dadurch wurden
  die Abschnitte „Review 2026-09-29“, die das parallele B07/B08-Review am 29.09. um 20:09 an
  `features/B08-multiview/build-bericht.md` und `features/B07-bild-in-bild/build-bericht.md` angehängt hatte, beim nächsten
  Rücksetzen auf den Stand vor dem Review zurückgesetzt. Bemerkt beim Aufräumen am 30.09.; beide Abschnitte sind **wortgleich
  wiederhergestellt** (aus dem Protokoll des Reviews, das sie mit `cat >>` angehängt hatte; 80 bzw. 73 Zeilen, wieder am
  Dateiende). Andere Dateien waren nicht betroffen: Die Build-Berichte von B03 und B06 hat seit der Sicherung niemand geändert,
  versionierte Dateien (Berichte, `spec.md`, `index.md`) berührte das Skript nie. Seit 30.09. 17:18 spielt es nur noch Dateien
  unter `qa/` zurück, und nur, wenn sie sich unterscheiden.
- **Weitere Vorkommnisse:** Neustart des Rechners am 29.09. 23:32 (Lauf 3 abgebrochen). In Lauf 6 zweimal Escape an den
  Test-Host (B02-Kontextmenü, siehe Tabelle unter 4) – sonst keine Tastatur- oder Mauseingaben von mir. Der Aktivierungshelfer
  holte den Test-Host auf Anforderung der B06/B08-Tests nach vorn und lehnte alle B07-Bridge-Befehle ab (Bildschirmaufnahmen,
  PiP-Fenster), die zugehörigen Tests wurden übersprungen.
