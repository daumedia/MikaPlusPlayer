import { formatBytes } from "@/lib/format";
import { LATEST_RELEASE_URL, MIN_MACOS } from "@/lib/site";
import type { Release } from "@/lib/releases";

/**
 * `release` is null when GitHub did not answer. The button then opens the newest release page
 * instead of guessing a file, and the caption says so instead of naming a version.
 */
export function DownloadButton({ release }: { release: Release | null }) {
  const dmg = release?.dmg ?? null;
  const href = dmg?.url ?? release?.htmlUrl ?? LATEST_RELEASE_URL;

  return (
    <div className="space-y-2.5">
      <a
        href={href}
        className="inline-flex items-center gap-2.5 rounded-full bg-accent-solid px-6 py-3.5 font-display text-[0.95rem] font-semibold text-on-accent transition-transform duration-150 hover:scale-[1.02] active:scale-100"
      >
        <svg width="17" height="17" viewBox="0 0 20 20" fill="none" aria-hidden="true">
          <path
            d="M10 2.5v11m0 0 4-4m-4 4-4-4M3 16.5h14"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
        Download for macOS
      </a>

      <p className="font-mono text-xs text-ink-soft">
        {release ? `Version ${release.version}` : "Latest release on GitHub"}
        {dmg ? ` · ${formatBytes(dmg.sizeBytes)}` : ""} · {MIN_MACOS} or later
      </p>

      {dmg?.sha256 && (
        <p className="max-w-md break-all font-mono text-[0.7rem] leading-relaxed text-ink-faint">
          SHA-256 {dmg.sha256}
        </p>
      )}
    </div>
  );
}
