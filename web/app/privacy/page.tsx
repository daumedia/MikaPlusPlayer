import type { ReactNode } from "react";
import { pageMetadata } from "@/lib/metadata";
import { GITHUB_URL, ISSUES_URL } from "@/lib/site";

export const generateMetadata = pageMetadata({
  path: "/privacy",
  title: "Privacy",
  description:
    "What Mika+Player stores, what it sends, and to whom. No accounts, no telemetry, no analytics.",
});

const LAST_UPDATED = "30 September 2026";

/**
 * Everything on this page describes the release people can download: version 1.1 of the Mac app
 * (tag v1.1). Fixes that exist only on main are not described here — when a release changes any
 * of this, the page changes with it.
 */
const DESCRIBED_VERSION = "1.1";
const SOURCE_OF_DESCRIBED_VERSION = `${GITHUB_URL}/tree/v${DESCRIBED_VERSION}`;

const codeClass = "break-all font-mono text-[0.85em] text-ink";

function Path({ children }: { children: ReactNode }) {
  return <code className={codeClass}>{children}</code>;
}

export default function PrivacyPage() {
  return (
    <div className="mx-auto max-w-3xl px-5 py-14 sm:px-8 sm:py-20">
      <p className="eyebrow">Privacy</p>
      <h1 className="headline mt-2 text-4xl sm:text-5xl">What leaves your Mac</h1>
      <p className="mt-5 text-lg leading-relaxed text-ink-soft">
        Short version: the app has no account, no telemetry and no analytics, and it sends nothing
        to the people who make it. It does talk to other servers — your provider, whatever servers
        your playlist names for streams and channel logos, and GitHub for updates — and it keeps
        your provider credentials unencrypted on your Mac. This page describes version{" "}
        {DESCRIBED_VERSION} of the Mac app, the version offered for download. You can check every
        point against{" "}
        <a
          href={SOURCE_OF_DESCRIBED_VERSION}
          target="_blank"
          rel="noopener noreferrer"
          className="text-accent-ink underline underline-offset-4"
        >
          the source of that version
        </a>
        .
      </p>

      <section className="mt-12 space-y-4">
        <h2 className="headline text-2xl">What the app stores</h2>
        <p className="leading-relaxed text-ink-soft">
          The app keeps your library in a single database file,{" "}
          <Path>~/Library/Application Support/default.store</Path>: playlist names and addresses,
          channel names, stream and logo addresses, groups and favourites. The file is not
          encrypted, and the app does not use the macOS Keychain. Xtream usernames and passwords are
          stored in plain text — in the address of the playlist and again in the address of every
          one of its channels. An M3U link is stored exactly as you entered it, including any token
          or password it contains. Any program running under your macOS user account can read the
          file, and Time Machine backs it up like any other file.
        </p>
        <p className="leading-relaxed text-ink-soft">Next to it, the app leaves:</p>
        <ul className="list-disc space-y-2 pl-5 leading-relaxed text-ink-soft marker:text-ink-faint">
          <li>
            <Path>~/Library/Caches/lu.daumedia.MikaPlusPlayer</Path> — the macOS network cache. It
            holds the requests for an Xtream channel list including username and password, the
            panel&rsquo;s answers, downloaded M3U lists with their addresses, and the channel logos.
          </li>
          <li>
            <Path>~/Library/HTTPStorages/lu.daumedia.MikaPlusPlayer</Path> and{" "}
            <Path>lu.daumedia.MikaPlusPlayer.binarycookies</Path> next to it — cookies, if a
            playlist or logo server sets any.
          </li>
          <li>
            <Path>~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist</Path> — settings such as
            when the app last checked for updates.
          </li>
        </ul>
        <p className="leading-relaxed text-ink-soft">
          There is no sync and no cloud service. Deleting a playlist removes it and its channels
          from the database, but not from the network cache, and names and addresses of deleted
          channels can stay inside the database file until it reuses that space.
        </p>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">Removing everything</h2>
        <p className="leading-relaxed text-ink-soft">
          Deleting the app does not remove any of this. To remove all of it, quit the app, move
          MikaPlusPlayer from Applications to the Trash, then choose{" "}
          <strong className="font-semibold text-ink">Go → Go to Folder…</strong> in the Finder and
          delete:
        </p>
        <ul className="list-disc space-y-2 pl-5 leading-relaxed text-ink-soft marker:text-ink-faint">
          <li>
            <Path>~/Library/Application Support/default.store</Path>, together with{" "}
            <Path>default.store-shm</Path> and <Path>default.store-wal</Path> in the same folder
          </li>
          <li>
            <Path>~/Library/Caches/lu.daumedia.MikaPlusPlayer</Path>
          </li>
          <li>
            <Path>~/Library/HTTPStorages/lu.daumedia.MikaPlusPlayer</Path> and{" "}
            <Path>lu.daumedia.MikaPlusPlayer.binarycookies</Path>
          </li>
          <li>
            <Path>~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist</Path>
          </li>
        </ul>
        <p className="leading-relaxed text-ink-soft">
          One caution: <Path>default.store</Path> is the name Apple&rsquo;s SwiftData framework
          gives a database by default, not a name that belongs to Mika+Player, and another app that
          runs outside the macOS sandbox can use the same file. If you are not sure, move it to the
          Trash first and check that your other apps still have their data before you empty it.
          Copies in Time Machine backups stay until those backups are deleted.
        </p>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">What the app connects to</h2>
        <p className="leading-relaxed text-ink-soft">
          Every connection below carries your IP address, as any connection does. The app&rsquo;s
          own requests — channel lists and logos — also name the app, its build number and the
          version of macOS&rsquo;s network components in the User-Agent header, and send your
          system language (Accept-Language).
        </p>
        <ul className="space-y-4">
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">Your provider.</strong> The channel list
            comes from the host you entered — the Xtream panel, or the server in an M3U link — and
            so does every refresh. Your provider sees your IP address and what you request, on their
            terms — their privacy policy applies, not this one. If that server answers with a
            redirect, the app follows the redirect and sends the same request, credentials included,
            to the new address. Servers can set cookies; the app keeps them and sends them back with
            later requests.
          </li>
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">Stream servers.</strong> Each channel plays
            from the address in the playlist. For Xtream that is normally the panel, and the address
            contains your username and password. An M3U playlist can point every channel at any other
            server. Whichever server it is sees your IP address and which channel you are watching.
          </li>
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">Channel logo servers.</strong> Playlists name
            a logo image for each channel, on any host. The app loads them automatically whenever it
            shows a channel list or your favourites — over plain HTTP if that is what the address
            says, and following redirects to other hosts. Besides your IP address and the headers
            above, a logo server learns from which logos are requested which list you are looking at
            and what you searched or filtered for, and every time you open the Favourites tab it
            receives requests for exactly the logos of your favourites. Version {DESCRIBED_VERSION}{" "}
            has no setting to turn logos off.
          </li>
          <li className="leading-relaxed text-ink-soft">
            <strong className="font-semibold text-ink">GitHub.</strong> Sparkle, the component that
            updates the Mac app, checks for a new version automatically, about once a day — the
            first time right after the first launch, without asking first. Version{" "}
            {DESCRIBED_VERSION} has no switch to turn this off. Each check fetches a small update
            feed from raw.githubusercontent.com and tells GitHub your IP address and, in the
            User-Agent header, the app&rsquo;s name and version and the Sparkle version. It sends no
            system profile and nothing from your library. When you install an update, the new
            version is downloaded from github.com.
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
          anyone between you and the panel could read them. They travel with every request to the
          panel: the channel list, each refresh and every stream you play. The same applies to an
          M3U link that starts with <code className="font-mono text-[0.85em]">http://</code>,
          including any token in it. That is a property of IPTV panels rather than a choice we would
          defend — treat those credentials as low-value and never reuse a password there.
        </p>
      </section>

      <section className="mt-10 space-y-4">
        <h2 className="headline text-2xl">This website</h2>
        <p className="leading-relaxed text-ink-soft">
          No cookies, no analytics, no tracking scripts, no fonts loaded from third parties. The
          site is hosted on Vercel, which keeps standard server logs, and the download button points
          at GitHub, which counts downloads per release. Both receive your IP address, as any web
          server does. The address <code className="font-mono text-[0.85em]">/download</code> is a
          small server function on Vercel that forwards to the newest file on GitHub.
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
