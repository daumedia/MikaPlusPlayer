export type FaqItem = {
  question: string;
  answer: string;
};

export const FAQ: readonly FaqItem[] = [
  {
    question: "macOS says the app cannot be opened. What now?",
    answer:
      "The build is ad-hoc signed rather than notarised, so Gatekeeper stops the first launch. Right-click the app in Applications, choose Open, then confirm. macOS remembers the decision and every later launch works normally.",
  },
  {
    question: "Does Mika+Player come with channels?",
    answer:
      "No. It plays what you give it. You bring an Xtream Codes login from your provider, an M3U link, or a playlist file — the app ships with none of that and does not sell or resolve any subscriptions.",
  },
  {
    question: "Which playlist formats does it read?",
    answer:
      "M3U and M3U8 files, from a URL or from disk, plus Xtream Codes logins. The parser reads tvg-id, tvg-logo and group-title, and handles channel names that contain commas inside quotes.",
  },
  {
    question: "My Xtream panel returns an error. Why?",
    answer:
      "A lot of panels block get.php and HLS output, often with an HTTP 407. Mika+Player builds the channel list through player_api.php and defaults to MPEG-TS, which is what those panels usually allow. If your provider does serve HLS, switch the format to .m3u8 when you log in.",
  },
  {
    question: "Can it play raw MPEG-TS streams?",
    answer:
      "Yes, through VLCKit. AVPlayer cannot open raw transport streams at all, so anything ending in .ts, .mpegts, .mts or .m2ts goes to the VLC engine automatically. Nothing to configure.",
  },
  {
    question: "How large a playlist can it handle?",
    answer:
      "Lists past 17,000 channels stay responsive because searching and filtering happen in the database rather than in memory. Importing a list that size takes a few seconds; browsing it afterwards does not.",
  },
  {
    question: "Where does my data go?",
    answer:
      "Nowhere. Playlists, credentials and favourites live in a local database on your Mac. The app talks to the provider you entered and, for updates, to GitHub. There is no account, no telemetry and no analytics.",
  },
  {
    question: "Is there an iPhone or iPad version?",
    answer:
      "The codebase builds for iOS 17 and up, and the app is written for both platforms. There is no distributed iOS build yet — no App Store listing and no TestFlight. Until then you would have to build it yourself in Xcode.",
  },
  {
    question: "How do updates arrive?",
    answer:
      "The Mac app checks for updates through Sparkle and can install them on its own. Each update is verified against an EdDSA signature first. You can also trigger a check from the app menu.",
  },
];
