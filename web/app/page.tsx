import Link from "next/link";
import { ChannelListDemo } from "@/components/channel-list-demo";
import { DownloadButton } from "@/components/download-button";
import { GatekeeperNote } from "@/components/gatekeeper-note";
import { MultiviewDemo } from "@/components/multiview-demo";
import { ScreenshotStrip } from "@/components/screenshot-strip";
import { Section } from "@/components/section";
import { Wordmark } from "@/components/wordmark";
import { FEATURE_GROUPS, FEATURES } from "@/content/features";
import { SETUP_STEPS } from "@/content/setup-steps";
import { getLatestRelease } from "@/lib/releases";
import { GITHUB_URL, MIN_MACOS } from "@/lib/site";

export default async function Home() {
  const release = await getLatestRelease();

  return (
    <>
      {/* Hero */}
      <section className="mx-auto max-w-6xl px-5 pb-12 pt-12 sm:px-8 sm:pb-16 sm:pt-16">
        <div className="grid items-start gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] lg:gap-14">
          <div className="lg:pt-6">
            <p className="eyebrow">
              <Wordmark /> · IPTV for macOS
            </p>
            <h1 className="headline mt-3 text-[2.6rem] leading-[0.98] sm:text-6xl">
              Four streams. One window.
            </h1>
            <p className="mt-5 max-w-xl text-lg leading-relaxed text-ink-soft">
              A native player for the playlist you already have. Sign in with Xtream Codes or open
              an M3U file, and a list of seventeen thousand channels turns into something you can
              search, filter and actually watch.
            </p>

            <div className="mt-8 space-y-6">
              <DownloadButton release={release} />
              <GatekeeperNote />
            </div>
          </div>

          <div>
            <MultiviewDemo />
            <p className="mt-3 text-sm leading-relaxed text-ink-soft">
              Multiview, rebuilt on this page. Click a small tile — the border, the large picture
              and the sound move with it, the same way they do in the app.
            </p>
          </div>
        </div>
      </section>

      {/* What you bring */}
      <section className="border-y border-line bg-card">
        <div className="mx-auto grid max-w-6xl gap-8 px-5 py-14 sm:px-8 md:grid-cols-3">
          <div>
            <p className="eyebrow">You bring</p>
            <p className="mt-2 text-base leading-relaxed text-ink-soft">
              An Xtream Codes login from your provider, an M3U link, or a playlist file. Whatever
              you already subscribe to.
            </p>
          </div>
          <div>
            <p className="eyebrow">The app adds</p>
            <p className="mt-2 text-base leading-relaxed text-ink-soft">
              Search, group filters, favourites across playlists, two playback engines and a
              Multiview window — all on your Mac, all local.
            </p>
          </div>
          <div>
            <p className="eyebrow">It never does</p>
            <p className="mt-2 text-base leading-relaxed text-ink-soft">
              Supply channels, sell subscriptions, or send your data anywhere. There is no account
              and no analytics.
            </p>
          </div>
        </div>
      </section>

      {/* Setup */}
      <Section
        eyebrow="Getting started"
        title="Three steps from download to picture"
        lead="No configuration files, no engine to pick, no server to run."
      >
        <ol className="mt-9 grid gap-5 md:grid-cols-3">
          {SETUP_STEPS.map((step) => (
            <li key={step.channel} className="card p-5">
              <p className="font-mono text-xs tracking-widest text-ink-faint">
                CH {step.channel}
              </p>
              <h3 className="mt-2.5 font-display text-lg font-semibold">{step.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-soft">{step.body}</p>
            </li>
          ))}
        </ol>
      </Section>

      {/* Library */}
      <section className="mx-auto max-w-6xl px-5 pb-16 pt-4 sm:px-8 sm:pb-20 sm:pt-6">
        <div className="grid items-center gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-16">
          <ChannelListDemo />

          <div>
            <p className="eyebrow">The channel list</p>
            <h2 className="headline mt-2 text-3xl sm:text-4xl">
              Seventeen thousand channels, still usable
            </h2>
            <p className="mt-4 text-lg leading-relaxed text-ink-soft">
              Providers hand out lists nobody can scroll. Search and the group chips your provider
              supplies run as database queries, so the list narrows as fast as you can type. Star
              what you actually watch and it collects in a favourites tab that spans every playlist
              you have added.
            </p>
            <p className="mt-4 text-lg leading-relaxed text-ink-soft">
              The ⊞ button on each row sends that channel to Multiview instead of playing it.
            </p>
          </div>
        </div>
      </section>

      {/* Features */}
      <Section
        eyebrow="What it does"
        title="Built for playlists that are far too long"
        className="border-t border-line"
      >
        <div className="mt-10 grid gap-x-10 gap-y-12 md:grid-cols-3">
          {FEATURE_GROUPS.map((group) => (
            <div key={group}>
              <h3 className="border-b border-line pb-2 font-mono text-[0.7rem] uppercase tracking-widest text-ink-faint">
                {group}
              </h3>
              <div className="mt-5 space-y-7">
                {FEATURES.filter((feature) => feature.kicker === group).map((feature) => (
                  <article key={feature.title}>
                    <h4 className="font-display text-base font-semibold">{feature.title}</h4>
                    <p className="mt-1.5 text-[0.95rem] leading-relaxed text-ink-soft">
                      {feature.body}
                    </p>
                  </article>
                ))}
              </div>
            </div>
          ))}
        </div>
      </Section>

      {/* Multiview */}
      <section className="border-y border-line bg-card">
        <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
          <p className="eyebrow">Multiview · macOS</p>
          <h2 className="headline mt-2 max-w-3xl text-3xl sm:text-4xl">
            Up to four streams, in a window of their own
          </h2>
          <p className="mt-4 max-w-2xl text-lg leading-relaxed text-ink-soft">
            Add channels with the ⊞ button in the channel list. Focus layout keeps one stream large
            with the rest as small tiles; grid layout gives every stream the same size. Only the
            focused stream plays sound, so four matches at once do not turn into noise.
          </p>

          <div className="mt-9 max-w-4xl">
            <MultiviewDemo withLayoutToggle />
          </div>
        </div>
      </section>

      <ScreenshotStrip />

      {/* Requirements */}
      <Section eyebrow="Before you download" title="What it needs">
        <div className="mt-8 grid gap-5 md:grid-cols-3">
          <div className="card p-5">
            <h3 className="font-display text-base font-semibold">{MIN_MACOS} or later</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-soft">
              Universal build for Apple silicon and Intel. Distributed as a disk image, not through
              the App Store.
            </p>
          </div>
          <div className="card p-5">
            <h3 className="font-display text-base font-semibold">A playlist of your own</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-soft">
              Xtream credentials, an M3U link or a local file. To try the app without a
              subscription, any public M3U list will do.
            </p>
          </div>
          <div className="card p-5">
            <h3 className="font-display text-base font-semibold">iPhone and iPad</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-soft">
              The app is written for both platforms and builds for iOS 17. There is no distributed
              iOS version yet — for now the Mac app is the one you can install.
            </p>
          </div>
        </div>

        <div className="mt-10 flex flex-col gap-5 sm:flex-row sm:items-center sm:gap-8">
          <DownloadButton release={release} />
          <p className="text-sm text-ink-soft">
            Prefer to build it yourself? The full source is{" "}
            <a
              href={GITHUB_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="text-accent-ink underline underline-offset-4"
            >
              on GitHub
            </a>
            , and the <Link href="/support" className="text-accent-ink underline underline-offset-4">
              support page
            </Link>{" "}
            covers setup and the questions that come up most.
          </p>
        </div>
      </Section>
    </>
  );
}
