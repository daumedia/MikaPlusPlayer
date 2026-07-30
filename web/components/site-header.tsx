import Image from "next/image";
import Link from "next/link";
import { Wordmark } from "@/components/wordmark";
import { GITHUB_URL, NAV } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-50 border-b border-line bg-bg/85 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center gap-3 px-5 sm:gap-4 sm:px-8">
        <Link
          href="/"
          className="flex items-center gap-2.5 font-display text-[0.95rem] font-semibold tracking-tight"
        >
          <Image
            src="/icon-512.png"
            alt=""
            width={28}
            height={28}
            className="rounded-[22%]"
            priority
          />
          {/* Below ~380px the wordmark and the nav cannot both fit. */}
          <Wordmark className="hidden min-[380px]:inline" />
          <span className="sr-only min-[380px]:hidden">Mika+Player</span>
        </Link>

        <nav className="ml-auto flex items-center gap-0.5 text-[0.8rem] sm:gap-1 sm:text-sm">
          {NAV.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              /* Privacy also sits in the footer, so it can go on narrow screens. */
              className={`rounded-md px-2 py-1.5 text-ink-soft transition-colors hover:bg-card hover:text-ink sm:px-3 ${
                item.href === "/privacy" ? "hidden sm:block" : ""
              }`}
            >
              {item.label}
            </Link>
          ))}
          <a
            href={GITHUB_URL}
            className="rounded-md px-2 py-1.5 text-ink-soft transition-colors hover:bg-card hover:text-ink sm:ml-1 sm:px-3"
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}
