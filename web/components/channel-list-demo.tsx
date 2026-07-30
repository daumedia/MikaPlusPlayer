import { WindowFrame } from "@/components/window-frame";

/**
 * The channel list, rebuilt in CSS: search field, group chips, favourite stars,
 * the ⊞ button that sends a channel to Multiview.
 * Names are invented — the app ships no channels.
 */

const GROUPS = ["All", "News", "Sports", "Documentary", "Kids"] as const;

const ROWS: readonly {
  name: string;
  group: string;
  logo: string;
  starred: boolean;
}[] = [
  { name: "News Network HD", group: "News", logo: "#b1494a", starred: true },
  { name: "Sports Arena 1", group: "Sports", logo: "#2f8f83", starred: false },
  { name: "Nature & Science", group: "Documentary", logo: "#a8752b", starred: true },
  { name: "Cartoon Corner", group: "Kids", logo: "#5b4bb5", starred: false },
  { name: "Cinema Prime", group: "Movies", logo: "#8a4a2c", starred: false },
];

function Star({ filled }: { filled: boolean }) {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 20 20"
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.5"
      className={filled ? "text-accent" : "text-ink-faint"}
      aria-hidden="true"
    >
      <path d="m10 2.6 2.3 4.7 5.2.8-3.8 3.7.9 5.2-4.6-2.5-4.6 2.5.9-5.2L2.5 8.1l5.2-.8z" />
    </svg>
  );
}

export function ChannelListDemo() {
  return (
    <WindowFrame title="Playlists">
      <div className="bg-bg px-4 py-4 sm:px-5">
        <p className="eyebrow">Mika+Player · 17,058 channels</p>
        <p className="mt-1 font-display text-xl font-bold tracking-tight">Channels</p>

        {/* Search */}
        <div className="mt-3.5 flex items-center gap-2 rounded-lg border border-line bg-card px-3 py-2">
          <svg
            width="13"
            height="13"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.6"
            className="text-ink-faint"
            aria-hidden="true"
          >
            <circle cx="7" cy="7" r="4.5" />
            <path d="m10.5 10.5 4 4" strokeLinecap="round" />
          </svg>
          <span className="text-sm text-ink-faint">Search channels</span>
        </div>

        {/* Group chips */}
        <div className="mt-3 flex flex-wrap gap-1.5">
          {GROUPS.map((group, index) => (
            <span
              key={group}
              className={`rounded-full px-2.5 py-1 text-xs font-medium ${
                index === 0 ? "bg-accent-solid text-on-accent" : "bg-ink/[0.08] text-ink-soft"
              }`}
            >
              {group}
            </span>
          ))}
        </div>

        {/* Rows */}
        <ul className="mt-3 space-y-2">
          {ROWS.map((row) => (
            <li key={row.name} className="card flex items-center gap-3 px-3 py-2.5">
              <span
                className="size-9 shrink-0 rounded-lg"
                style={{ background: `linear-gradient(145deg, ${row.logo}, #0b0809)` }}
                aria-hidden="true"
              />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium">{row.name}</span>
                <span className="block truncate text-xs text-ink-soft">{row.group}</span>
              </span>
              <span className="flex shrink-0 items-center gap-2.5 text-ink-faint">
                <Star filled={row.starred} />
                <svg
                  width="15"
                  height="15"
                  viewBox="0 0 20 20"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  aria-hidden="true"
                >
                  <rect x="2.5" y="2.5" width="15" height="15" rx="2.5" />
                  <path d="M10 2.5v15M2.5 10h15" />
                </svg>
              </span>
            </li>
          ))}
        </ul>
      </div>
    </WindowFrame>
  );
}
