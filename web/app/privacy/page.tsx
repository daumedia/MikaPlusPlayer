import type { Metadata } from "next";
import { GITHUB_URL, ISSUES_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "What Mika+Player stores, what it sends, and to whom. No accounts, no telemetry, no analytics.",
  alternates: { canonical: "/privacy" },
};

const LAST_UPDATED = "30 July 2026";

export default function PrivacyPage() {
  return (
    <div className="mx-auto max-w-3xl px-5 py-14 sm:px-8 sm:py-20">
      <p className="eyebrow">Privacy</p>
      <h1 className="headline mt-2 text-4xl sm:text-5xl">What leaves your Mac</h1>
      <p className="mt-5 text-lg leading-relaxed text-ink-soft">
        Short version: nothing goes to us, because there is no us to send it to. No account, no
        server, no telemetry, no analytics — in the app or on this site. What follows describes
        what the app actually does, so you can check it against{" "}
        <a
          href={GITHUB_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="text-accent-ink underline underline-offset-4"
        >
          the source
        </a>
        .
      </p>

      <section className="mt-12 space-y-4">
        <h2 className="headline text-2xl">What the app stores</h2>
        <p className="leading-relaxed text-ink-soft">
          Playlists, channel lists, favourites and the credentials you enter for an Xtream login
          are written to a local database on your Mac. They stay in the app&rsquo;s own storage.
          There is no sync, no cloud backup by the app, and no copy anywhere else. Deleting a
          playlist removes its channels; deleting the app removes all of it.
        </p>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">What the app connects to</h2>
        <ul className="space-y-4">
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">Your provider.</strong> Every stream, channel
            list and logo request goes to the host you entered. That provider sees your IP address
            and what you request, on their terms — their privacy policy applies, not this one.
          </li>
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">Channel logo servers.</strong> Playlists
            reference logo images by URL. Displaying a channel list loads those images from
            whichever host the playlist points at.
          </li>
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">GitHub.</strong> The Mac app fetches an
            update feed from raw.githubusercontent.com and downloads new versions from github.com.
            That request tells GitHub your IP address, as any download would.
          </li>
        </ul>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">Xtream logins travel over plain HTTP</h2>
        <p className="leading-relaxed text-ink-soft">
          Worth knowing before you type credentials: the app talks to Xtream panels over{" "}
          <code className="font-mono text-[0.85em]">http://</code>, and rewrites an{" "}
          <code className="font-mono text-[0.85em]">https://</code> host to plain HTTP, because most
          panels serve nothing else. Your username and password are therefore sent unencrypted, and
          anyone between you and the panel could read them. That is a property of IPTV panels rather
          than a choice we would defend — treat those credentials as low-value and never reuse a
          password there.
        </p>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">This website</h2>
        <p className="leading-relaxed text-ink-soft">
          No cookies, no analytics, no tracking scripts, no fonts loaded from third parties. The
          site is hosted on Vercel, which keeps standard server logs, and the download button points
          at GitHub, which counts downloads per release. Neither of those tells us who you are.
        </p>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">Content</h2>
        <p className="leading-relaxed text-ink-soft">
          Mika+Player ships no channels and resolves no subscriptions. It plays the playlist you
          supply, and what you are entitled to watch is between you and your provider.
        </p>
      </section>

      <p className="mt-12 text-sm text-ink-soft">
        Last updated {LAST_UPDATED}. Questions about any of this belong in{" "}
        <a
          href={ISSUES_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="text-accent-ink underline underline-offset-4"
        >
          a GitHub issue
        </a>
        .
      </p>
    </div>
  );
}
