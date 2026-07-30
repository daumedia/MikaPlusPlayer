import Link from "next/link";
import { Wordmark } from "@/components/wordmark";
import { GITHUB_URL, ISSUES_URL, NAV } from "@/lib/site";

export function SiteFooter() {
  return (
    <footer className="mt-24 border-t border-line">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-5 py-10 sm:px-8 md:flex-row md:items-center md:justify-between">
        <div className="space-y-1.5">
          <p className="font-display text-sm font-semibold">
            <Wordmark />
          </p>
          <p className="max-w-md text-sm text-ink-soft">
            An open-source IPTV player. It plays the playlist you bring and is not affiliated
            with any provider.
          </p>
        </div>

        <nav className="flex flex-wrap gap-x-5 gap-y-2 text-sm text-ink-soft">
          {NAV.map((item) => (
            <Link key={item.href} href={item.href} className="hover:text-ink">
              {item.label}
            </Link>
          ))}
          <a href={ISSUES_URL} target="_blank" rel="noopener noreferrer" className="hover:text-ink">
            Report an issue
          </a>
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer" className="hover:text-ink">
            Source
          </a>
        </nav>
      </div>
    </footer>
  );
}
