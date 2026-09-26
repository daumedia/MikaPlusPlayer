# Mika+Player — Design-System

Stand: 2026-09-15 · rekonstruiert aus `Sources/Views/Theme/PlayerTheme.swift` und allen Views

> Aus dem Code gelesen, nicht entworfen. Wildwuchs ist **dokumentiert, nicht bereinigt** —
> eine Aufräumaktion wäre ein eigenes Feature mit eigener Spec.

## Herkunft

Die App folgt der **Mika+-Designsprache** (geteilte Konventionen der Mika+-Apps von daumedia).
Zentrale Quelle ist `PlayerTheme.swift`: Layout-Konstanten, adaptive Farben, drei wiederverwendbare
Komponenten. Farben sind **programmatisch** über `UIColor`/`NSColor`-Dynamic-Provider definiert,
nicht im Asset-Catalog. Die Website (`web/app/globals.css`) übernimmt Palette und Radien laut
Kommentar „1:1 aus der App".

## Farben

### Tokens aus `PlayerTheme`

| Token | Rolle | Hell | Dunkel |
|---|---|---|---|
| `Color.playerAccent` | Akzent: Tint, Header-Subline, Favoriten-Stern, gewählter Chip, Fokus-Rahmen | `#EF4444` (239, 68, 68) | `#F87171` (248, 113, 113) |
| `Color.playerBackground` | App-Hintergrund der Listen | `#F6F4F3` (246, 244, 243) | `#120F10` (18, 15, 16) |
| `Color.playerCardBackground` | Karten | `#FFFFFF` | `#201C1D` (32, 28, 29) |
| `Color.playerCardBorder` | 1-pt-Kartenrand | `#E6E2E0` (230, 226, 224) | `#383234` (56, 50, 52) |

Rot ist in der Mika+-Familie die Akzentfarbe des Moduls „Watch". **Das App-Icon ist seit
2026-09 violett/mint (daumedia-Farben), der Akzent in der App blieb rot.**

### Außerhalb der Tokens verwendet

| Wert | Wo | Rolle |
|---|---|---|
| `.primary`, `.secondary`, `.tertiary` | alle Listen | Text, gedämpfter Text, Chevron |
| `Color.secondary.opacity(0.1)` | Logo-Hintergrund (`ChannelRowView`) | Platzhalterfläche |
| `Color.secondary.opacity(0.14)` | `PlayerBadge` ungetönt | Pillenfläche |
| `Color.secondary.opacity(0.16)` | `GroupChip` nicht gewählt | Pillenfläche |
| `Color.secondary.opacity(0.3)` | Multiview-Button deaktiviert | deaktiviert |
| `Color.playerAccent.opacity(0.18)` | `PlayerBadge` getönt | Pillenfläche |
| `Color.black` | Player, Multiview-Fenster und -Kacheln, VLC-/AVKit-Layer | Videofläche, in beiden Modi |
| `.white` | alle Player-Bedienelemente, Spinner, HUD | Vordergrund über Video |
| `.black.opacity(0.5)` | runde Player-Buttons, Multiview-Schließen | Hinterlegung über Video |
| `.black.opacity(0.55)` | HUD (Play/Pause, Stumm, Lautstärke) | Hinterlegung über Video |
| `.ultraThinMaterial` | Fehleransicht im Player und in Kacheln | Hinterlegung |
| `.bar` | Leiste der Gruppen-Chips | System-Leistenmaterial |
| `Color.white` auf Akzent | gewählter `GroupChip` | Text |

Eine **Gefahr- bzw. Fehlerfarbe** gibt es nicht; Fehler erscheinen als System-Alert oder
`ContentUnavailableView` mit Warndreieck. Destruktive Aktionen nutzen `role: .destructive`.

### Kontraste (WCAG, nachgerechnet)

| Kombination | Hell | Dunkel | Verwendung |
|---|---|---|---|
| Akzent auf `playerBackground` | **3,43 : 1** | 6,89 : 1 | Header-Subline, `caption2` semibold — kleiner Text |
| Akzent auf `playerCardBackground` | **3,76 : 1** | 6,10 : 1 | Favoriten-Stern (Symbol) |
| Weiß auf Akzent | **3,76 : 1** | **2,77 : 1** | gewählter Gruppen-Chip, `subheadline` medium |
| Weiß auf Schwarz 50 % über hellem Videobild | **3,95 : 1** | — | Player-Symbole im ungünstigsten Fall |

Unter 4,5 : 1 für kleinen Text liegen: die Header-Subline im hellen Modus und der gewählte
Gruppen-Chip in **beiden** Modi. Die Website hat dasselbe Problem erkannt und verwendet für
Text abgedunkelte Varianten (`--accent-ink #C2352F`, im Dunkelmodus `--on-accent #120F10`) —
die App nicht.

## Typografie

Ausschließlich **System-Schriften** (SF), keine eigenen Fonts. Stile nach Häufigkeit:

| Stil | Anzahl | Wo |
|---|---|---|
| `.headline` | 5 | Playlist- und Sendername in Karten, Titel leerer Zustände |
| `.title3` | 5 | Symbole in Karten (Playlist-Symbol, Stern, Multiview-Button, Logo-Platzhalter, Schließen) |
| `.subheadline` | 3 | Beschreibung leerer Zustände |
| `.system(size: 44)` | 3 | Symbol leerer Zustände — **feste Größe** |
| `.system(size: 44, weight: .bold)` | 2 | HUD Play/Pause und Stumm — feste Größe |
| `.caption2.weight(.semibold)` | 2 | Header-Subline (mit `.tracking(1.4)`), Badge-Symbol |
| `.caption.weight(.semibold)` | 2 | Badge-Text (`.monospacedDigit()`), Lautstärke in Prozent |
| `.largeTitle.bold()` | 1 | Seitentitel in `PlayerHeader` |
| `.title3.weight(.semibold)` | 1 | runde Player-Buttons |
| `.system(size: 32, weight: .bold)` | 1 | Lautstärkesymbol im HUD — feste Größe |
| `.subheadline.weight(.medium)` | 1 | Gruppen-Chip |
| `.footnote.weight(.semibold)` | 1 | Chevron |
| `.footnote` | 1 | TS/VLCKit-Hinweis in der Fehleransicht |

Sechs Stellen verwenden feste Punktgrößen und skalieren nicht mit Dynamic Type.

## Abstände

### Tokens

| Token | Wert | Verwendet für |
|---|---|---|
| `cardVPadding` / `cardHPadding` | 14 / 14 | Innenabstand `.playerCard()` |
| `rowSpacing` | 10 | Abstand zwischen Karten in Listen |
| `sectionSpacing` | 22 | Abstand Header ↔ Liste |
| `contentHPadding` | 20 | seitlicher Rand aller Listen, Header, Chip-Leiste |
| `cardBorderWidth` | 1 | Kartenrand |

### Hart codiert

| Wert | Wo |
|---|---|
| 4 | Header Titel-Stack, Badge-Innenabstand vertikal, Logo-Padding, Grid-Abstand Multiview, leere Zustände oben am Button |
| 6 | Schließen-Button Multiview |
| 7 / 14 | Gruppen-Chip vertikal / horizontal |
| 8 | Chip-Abstand, Badge horizontal, leere Zustände Stack, Kachel-Chrome, Listen oben, `Spacer(minLength:)` |
| 10 | Chip-Leiste vertikal, HUD-Lautstärke-Stack |
| 12 | Header-HStack, Karten-HStack, Player-Buttons (Innen und im Fenster) |
| 16 | Kachelstapel im Fokus-Layout |
| 20 | untere Player-Leiste |
| 24 | Player-Buttons im Vollbild |
| 28 | HUD-Innenabstand |
| 32 | Listen unten |
| 40 / 60 | leerer Suchzustand / übrige leere Zustände oben |

Kein Abstandsraster: Neben den Token-Werten 10, 14, 20, 22 treten 4, 6, 7, 8, 12, 16, 24, 28, 32,
40 und 60 frei auf. Der Token `rowSpacing = 10` gilt nur zwischen Karten, innerhalb der Karten steht 12.

## Radien und Formen

| Wert | Wo |
|---|---|
| `cardRadius` = 12 | Karten, Multiview-Thumbnails, Fokus-Rahmen der Kacheln |
| 8 | Senderlogo |
| 18 (`.continuous`) | HUD |
| `Capsule` | `PlayerBadge`, `GroupChip` |
| `Circle` | runde Player-Buttons, Multiview-Schließen |

## Komponenten

### Öffentlich (in `PlayerTheme.swift`)

| Komponente | Aufbau | Verwendet in |
|---|---|---|
| `.playerCard()` | Padding 14, `playerCardBackground`, 1-pt-Rand `playerCardBorder`, Radius 12 | Playlist-Zeile, Sender-Zeile (Liste und Favoriten) |
| `PlayerHeader(subline:title:trailing:)` | Subline `caption2` semibold, getrackt 1,4, Akzent, **Großbuchstaben von Hand geschrieben** („MIKA+PLAYER · PLAYLISTS") · Titel `largeTitle` bold · optionale Trailing-Aktion | Playlists, Favoriten, Senderliste |
| `PlayerBadge(systemImage:text:tinted:)` | Kapsel, Symbol `caption2` + Text `caption` semibold monospaced, gedämpft oder akzentgetönt | Senderanzahl, Gruppe, Sendername mit Ton-Status im Multiview |

### Privat in einer View definiert

| Komponente | Datei | Aufbau |
|---|---|---|
| `GroupChip` | `ChannelListView.swift` | Kapsel, gewählt Akzent + Weiß, sonst `secondary` 16 % |
| `PlaylistRow` | `PlaylistsView.swift` | Symbol (Globus/Dokument) + Name + Badge + Chevron bzw. Spinner |
| `controlIcon(_:)` | `PlayerView.swift` | SF Symbol, weiß, Padding 12, Kreis schwarz 50 % |
| HUD | `PlayerView.swift` | Symbol 44/32 pt bold, Lautstärke als lineare `ProgressView` (140 pt, Akzent) + Prozent |
| `MultiviewTile` | `MultiviewTile.swift` | Videofläche + Status-Overlay + Badge + Schließen, Fokus-Rahmen 2 pt Akzent |

### Schaltflächen

| Art | Stil | Wo |
|---|---|---|
| Primär | `.borderedProminent`, `.tint(.playerAccent)` | „+" in Playlists (`.small`), „Playlist importieren" (`.regular`), „Erneut versuchen" |
| Zeile/Symbol | `.plain` | Karten als `NavigationLink`, Stern, Multiview, Player-Buttons, Chips |
| Formular | System-`Form`, Buttons mit `Label` | Import-Sheet |
| Kontextmenü | `Label` mit SF Symbol, Löschen `role: .destructive` | Playlist-Karte |

### Eingabefelder

Nur im Import-Sheet, als System-`Form`: `TextField` (Name, Host, Benutzer, URL) mit abgeschalteter
Autokorrektur und auf iOS `.keyboardType(.URL)` bzw. ohne Autokapitalisierung, `SecureField`
(Passwort), segmentierte `Picker` für Quelle und Format. Kein eigener Eingabestil.

## Zustände

| Zustand | Muster |
|---|---|
| Laden (Liste) | `ProgressView` anstelle des Chevrons in der Playlist-Karte |
| Laden (Import) | `ProgressView` + „Importiere…" als Formularzeile |
| Laden (Video) | `ProgressView` `.large`, weiß, mittig auf Schwarz |
| Leer (Listen) | eigener VStack: Symbol 44 pt `.secondary`, `.headline`, `.subheadline` `.secondary`, optional Button; Padding oben 60 — **dreimal dupliziert** (Playlists, Favoriten, Senderliste) |
| Leer (Suche, Multiview) | System-`ContentUnavailableView` — **zweites, abweichendes Muster** |
| Fehler (Aktion) | System-`.alert("Fehler")` mit `localizedDescription` |
| Fehler (Wiedergabe) | `ContentUnavailableView` „Wiedergabe fehlgeschlagen" auf `.ultraThinMaterial`, Fehlermeldung der Engine, Button „Erneut versuchen"; bei `.ts`-URLs zusätzlich „…benötigen VLCKit – siehe README" |
| Deaktiviert | System-`.disabled`, beim Multiview-Button zusätzlich `secondary` 30 % und Tooltip |
| Feedback | HUD 0,9 s, Steuerung blendet nach 3,5 s aus; Animationen `easeInOut` 0,15–0,3 s |

## Erscheinungsbild

Hell und dunkel folgen dem System. Einen Umschalter gibt es **nicht** — anders als in der
Mika+-Familie beschrieben (`AppearanceMode` über `@AppStorage`).

## Auffälligkeiten

Gemeldet, nicht bewertet und nicht bereinigt.

| # | Auffälligkeit | Fundstelle |
|---|---|---|
| DS-01 | Akzent als kleiner Text unter 4,5 : 1 (Header-Subline hell 3,43; gewählter Chip hell 3,76, dunkel 2,77) | `PlayerTheme.swift:97-100`, `ChannelListView.swift:150-154` |
| DS-02 | Sechs feste Schriftgrößen ohne Dynamic Type | `PlaylistsView.swift:83`, `ChannelListView.swift:124`, `FavoritesView.swift:50`, `PlayerView.swift:170,174,191` |
| DS-03 | Kein Abstandsraster; elf freie Werte neben den Tokens | siehe *Abstände* |
| DS-04 | Vier Deckkraftstufen von `secondary` (0,1 / 0,14 / 0,16 / 0,3) und zwei Schwarzstufen (0,5 / 0,55) für ähnliche Rollen | siehe *Außerhalb der Tokens* |
| DS-05 | Zwei Muster für leere Zustände; das eigene dreifach dupliziert | `PlaylistsView`, `FavoritesView`, `ChannelListView` |
| DS-06 | Fehleransicht verweist Endnutzer auf „README" | `PlayerView.swift:217` |
| DS-07 | App-Icon violett/mint, Akzentfarbe rot | `Assets.xcassets/AppIcon`, `PlayerTheme.swift:26` |
| DS-08 | Kein Erscheinungsbild-Umschalter, abweichend von der Familienkonvention | — |
| DS-09 | Oberflächentexte nur Deutsch, als Literale im Code; Header-Sublines von Hand in Großbuchstaben | alle Views |
