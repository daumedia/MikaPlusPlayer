export const FEATURE_GROUPS = ["Library", "Playback", "System"] as const;

export type Feature = {
  kicker: (typeof FEATURE_GROUPS)[number];
  title: string;
  body: string;
};

/**
 * Every claim here describes version 1.1 of the Mac app — the release offered for download (tag v1.1).
 * Features and fixes that are not in a release yet (Picture in Picture, double-click import, faster
 * lists) stay off this list until a release ships them. Numbers are measurements from the QA reports
 * of B01–B04 (features/…/qa-report.md).
 */
export const FEATURES: readonly Feature[] = [
  {
    kicker: "Library",
    title: "Search across 17,000 channels",
    body: "Search and the channel filter run as database queries, so even the oversized lists Xtream panels hand out stay searchable. Version 1.1 still pauses on lists that size: opening one takes up to about a second, and importing 17,000 channels takes several minutes.",
  },
  {
    kicker: "Library",
    title: "Favourites across playlists",
    body: "Star a channel in the list and it shows up in one Favourites tab across every playlist. After a refresh, a favourite keeps its star if the channel comes back with the same tvg-id — or, if it has none, the same name. If the provider changes that id or name, the star is gone, and channels that share one all get the star.",
  },
  {
    kicker: "Library",
    title: "Xtream logins that work with strict panels",
    body: "Many panels block get.php and HLS. Mika+Player builds the channel list through player_api.php instead, pulling categories and live streams directly. MPEG-TS is the default output format for exactly that reason.",
  },
  {
    kicker: "Playback",
    title: "Two engines, picked automatically",
    body: "AVKit handles HLS and everything else Apple decodes natively. Raw MPEG-TS — which AVPlayer cannot open at all — goes to VLCKit. The choice happens per stream, based on the URL. You never pick an engine.",
  },
  {
    kicker: "Playback",
    title: "Hands on the keyboard",
    body: "Space plays and pauses, arrow keys and +/− set the volume in 5% steps, M mutes, F switches to full screen and Esc leaves it. Play/pause, volume and mute show a short on-screen confirmation, then it disappears.",
  },
  {
    kicker: "System",
    title: "Updates through Sparkle",
    body: "The Mac app looks for a new version automatically, about once a day, and asks before installing it — unless you let Sparkle install future updates on its own. Every update is verified with an EdDSA signature first. No package manager, no re-download from a web page.",
  },
  {
    kicker: "System",
    title: "Three ways in",
    body: "Sign in with Xtream Codes credentials, paste an M3U or M3U8 link, or open a playlist file from inside the app. Double-clicking a playlist in Finder does not import it in version 1.1.",
  },
] as const;
