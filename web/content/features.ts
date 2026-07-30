export const FEATURE_GROUPS = ["Library", "Playback", "System"] as const;

export type Feature = {
  kicker: (typeof FEATURE_GROUPS)[number];
  title: string;
  body: string;
};

export const FEATURES: readonly Feature[] = [
  {
    kicker: "Library",
    title: "Search that keeps up with 17,000 channels",
    body: "Search and group filters run in the database, not in memory. Type a name, tap a group chip, and the list responds immediately — even on the oversized channel lists Xtream panels tend to hand out.",
  },
  {
    kicker: "Library",
    title: "Favourites that survive a refresh",
    body: "Star a channel anywhere and it shows up in one tab across every playlist. Refreshing a remote playlist matches favourites by their tvg-id, so a provider reordering their list does not wipe your selection.",
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
    title: "Picture in Picture",
    body: "Send the stream into the system PiP window and keep watching while you work. On iPhone and iPad it starts on its own when the app moves to the background.",
  },
  {
    kicker: "Playback",
    title: "Hands on the keyboard",
    body: "Space plays and pauses, arrow keys and +/− set the volume in 5% steps, M mutes, F goes full screen, P opens Picture in Picture, Esc comes back. On-screen feedback confirms each one, then disappears.",
  },
  {
    kicker: "System",
    title: "Updates that install themselves",
    body: "The Mac app checks for new versions through Sparkle and verifies every update with an EdDSA signature before installing. No package manager, no re-download from a web page.",
  },
  {
    kicker: "System",
    title: "Three ways in",
    body: "Sign in with Xtream Codes credentials, paste an M3U or M3U8 link, or open a playlist file from disk. Mika+Player also registers as a handler for .m3u files, so double-clicking one opens it here.",
  },
] as const;
