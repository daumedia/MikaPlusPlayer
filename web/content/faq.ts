export type FaqItem = {
  question: string;
  answer: string;
};

export const FAQ: readonly FaqItem[] = [
  {
    question: "macOS says the app cannot be opened. What now?",
    answer:
      "The build is ad-hoc signed rather than notarised, so Gatekeeper stops the first launch. Try to open the app once, then go to System Settings → Privacy & Security and click Open Anyway; the button stays there for about an hour after the blocked attempt. Since macOS 15 Sequoia that is the only way — on macOS 14 Sonoma, Control-clicking the app and choosing Open works as well. macOS remembers the decision and every later launch works normally. The first-launch steps above also show how to check the download against its SHA-256 checksum.",
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
      "Lists of 17,000 channels work, but version 1.1 is slow with them. Importing or refreshing a list that size takes several minutes — about four and a half minutes on our test Mac — and deleting it up to about two minutes; the app does not respond while that runs. Once the list is in, search and the channel filter run as database queries, but opening the list and the first letter you type still pause the app briefly, for up to about a second.",
  },
  {
    question: "Where does my data go?",
    answer:
      "To the servers your playlist names and to GitHub — not to us. The app fetches the channel list from your provider, plays each stream from the server the playlist points at, loads channel logos from wherever the playlist says, and asks GitHub about once a day for updates. Playlists, favourites and your provider credentials are stored unencrypted in a database file on your Mac, and deleting the app does not remove it. There is no account, no telemetry and no analytics. The privacy page lists every detail and how to remove everything.",
  },
  {
    question: "Is there an iPhone or iPad version?",
    answer:
      "The codebase builds for iOS 17 and up, and the app is written for both platforms. There is no distributed iOS build yet — no App Store listing and no TestFlight. Until then you would have to build it yourself in Xcode.",
  },
  {
    question: "How do updates arrive?",
    answer:
      "Through Sparkle. The Mac app asks GitHub for a newer version automatically, about once a day, without asking you first. If there is one, it shows the release notes and you choose whether to install it, skip that version or be reminded later. Only if you tick the option to download and install updates automatically in that window does it install future updates on its own. Each update is verified against an EdDSA signature before it is installed. To check by hand, open the app menu and choose “Nach Updates suchen …” — the app’s labels are in German.",
  },
];
