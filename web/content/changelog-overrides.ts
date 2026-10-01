/**
 * Release notes on GitHub are written in German, this site is English.
 * Anything listed here replaces the GitHub body for that tag.
 * Newer releases should be written in English on GitHub, then dropped from here.
 */
export const NOTE_OVERRIDES: Record<string, string> = {
  "v1.1": `**Multiview (macOS)** — watch up to four streams at once in a separate window.

- **Focus layout**: one large player, the other streams as small tiles in the top right corner.
- **Grid layout**: equally sized tiles, side by side or 2×2.
- **Audio follows focus**: only the focused stream plays sound. Clicking a tile moves both the sound and the large picture.
- Add channels to Multiview with the new **⊞ button** in the channel list and favourites.

Known issue in 1.1: after a click on a small tile, an MPEG-TS stream (the Xtream default) can stay black in the large tile while its sound plays; switching to grid and back brings the picture back.

Automatic updates ship through Sparkle and are signed with EdDSA.

Installation: open the DMG and drag the app to Applications. The build is ad-hoc signed and not notarised, so macOS blocks the first launch; the support page on this site shows how to allow it and how to check the download's SHA-256 checksum.`,
};
