export type SetupStep = {
  channel: string;
  title: string;
  body: string;
};

/** A real sequence, so the channel numbering carries information. */
export const SETUP_STEPS: readonly SetupStep[] = [
  {
    channel: "01",
    title: "Add a playlist",
    body: "Pick Xtream and enter host, username and password — or switch to URL and paste an M3U link, or to File and open a playlist from disk. Naming the playlist is optional.",
  },
  {
    channel: "02",
    title: "Find your channels",
    body: "Search by name, narrow the list with the group chips your provider supplies, and star the channels you actually watch. Favourites collect in their own tab.",
  },
  {
    channel: "03",
    title: "Watch",
    body: "Click a channel to play it. The ⊞ button next to any channel adds it to Multiview instead, where up to four streams run side by side.",
  },
] as const;
