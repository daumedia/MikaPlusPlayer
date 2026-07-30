import type { Metadata } from "next";
import { ReleaseNotes } from "@/components/release-notes";
import { formatBytes, formatDate } from "@/lib/format";
import { getReleases } from "@/lib/releases";
import { RELEASES_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Changelog",
  description: "Every released version of Mika+Player, with what changed and a download link.",
  alternates: { canonical: "/changelog" },
};

export default async function ChangelogPage() {
  const releases = await getReleases();

  return (
    <div className="mx-auto max-w-3xl px-5 py-14 sm:px-8 sm:py-20">
      <p className="eyebrow">Changelog</p>
      <h1 className="headline mt-2 text-4xl sm:text-5xl">Every version so far</h1>
      <p className="mt-5 text-lg leading-relaxed text-ink-soft">
        Pulled from GitHub releases. The Mac app also checks this list for itself through Sparkle.
      </p>

      <div className="mt-12 space-y-12">
        {releases.map((release) => (
          <article key={release.tag} className="border-t border-line pt-7">
            <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
              <h2 className="headline text-2xl">{release.title}</h2>
              <time
                dateTime={release.publishedAt}
                className="font-mono text-xs text-ink-faint"
              >
                {formatDate(release.publishedAt)}
              </time>
            </div>

            <div className="mt-5">
              <ReleaseNotes markdown={release.notes} />
            </div>

            <div className="mt-5 flex flex-wrap items-center gap-4 text-sm">
              {release.dmg && (
                <a
                  href={release.dmg.url}
                  className="font-medium text-accent-ink underline underline-offset-4"
                >
                  Download {release.dmg.name} ({formatBytes(release.dmg.sizeBytes)})
                </a>
              )}
              <a
                href={release.htmlUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="text-ink-soft underline underline-offset-4 hover:text-ink"
              >
                Release on GitHub
              </a>
            </div>
          </article>
        ))}
      </div>

      <p className="mt-12 text-sm text-ink-soft">
        Older builds stay available on the{" "}
        <a
          href={RELEASES_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="text-accent-ink underline underline-offset-4"
        >
          releases page
        </a>
        .
      </p>
    </div>
  );
}
