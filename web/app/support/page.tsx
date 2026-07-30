import type { Metadata } from "next";
import { FAQ } from "@/content/faq";
import { SETUP_STEPS } from "@/content/setup-steps";
import { DEMO_PLAYLIST, ISSUES_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Support",
  description:
    "Set up an Xtream Codes login or an M3U playlist in Mika+Player, get past the first-launch warning, and find answers to the questions that come up most.",
  alternates: { canonical: "/support" },
};

const KEYS: readonly { key: string; action: string }[] = [
  { key: "Space", action: "Play or pause" },
  { key: "↑ ↓ + −", action: "Volume, in 5% steps" },
  { key: "M", action: "Mute" },
  { key: "F", action: "Full screen" },
  { key: "P", action: "Picture in Picture" },
  { key: "Esc", action: "Leave full screen" },
];

export default function SupportPage() {
  return (
    <div className="mx-auto max-w-3xl px-5 py-14 sm:px-8 sm:py-20">
      <p className="eyebrow">Support</p>
      <h1 className="headline mt-2 text-4xl sm:text-5xl">Getting it working</h1>
      <p className="mt-5 text-lg leading-relaxed text-ink-soft">
        Two things trip people up: the first launch, and pointing the app at a playlist. Both are
        below.
      </p>

      {/* First launch */}
      <section className="mt-14">
        <h2 className="headline text-2xl">First launch on macOS</h2>
        <p className="mt-3 leading-relaxed text-ink-soft">
          Mika+Player is signed ad-hoc rather than notarised, so macOS refuses the first launch and
          says the developer cannot be verified. To get past it:
        </p>
        <ol className="mt-5 space-y-3">
          {[
            "Open the DMG and drag Mika+Player to Applications.",
            "Open the Applications folder in Finder.",
            "Right-click Mika+Player and choose Open.",
            "Confirm in the dialog. macOS remembers the choice — later launches are normal.",
          ].map((line, index) => (
            <li key={line} className="flex gap-3.5">
              <span className="font-mono text-xs leading-6 text-ink-faint">
                {String(index + 1).padStart(2, "0")}
              </span>
              <span className="leading-relaxed text-ink-soft">{line}</span>
            </li>
          ))}
        </ol>
      </section>

      {/* Playlists */}
      <section className="mt-14">
        <h2 className="headline text-2xl">Adding a playlist</h2>
        <div className="mt-5 space-y-5">
          {SETUP_STEPS.map((step) => (
            <div key={step.channel} className="card p-5">
              <p className="font-mono text-xs tracking-widest text-ink-faint">CH {step.channel}</p>
              <h3 className="mt-2 font-display text-lg font-semibold">{step.title}</h3>
              <p className="mt-2 leading-relaxed text-ink-soft">{step.body}</p>
            </div>
          ))}
        </div>
        <p className="mt-5 text-sm leading-relaxed text-ink-soft">
          No subscription to test with? Any public M3U list works — for example{" "}
          <a
            href={DEMO_PLAYLIST}
            target="_blank"
            rel="noopener noreferrer"
            className="break-all font-mono text-[0.8rem] text-accent-ink underline underline-offset-4"
          >
            {DEMO_PLAYLIST}
          </a>
          .
        </p>
      </section>

      {/* Keyboard */}
      <section className="mt-14">
        <h2 className="headline text-2xl">Keyboard controls</h2>
        <dl className="mt-5 divide-y divide-line border-y border-line">
          {KEYS.map((entry) => (
            <div key={entry.key} className="flex items-baseline justify-between gap-4 py-2.5">
              <dt className="font-mono text-sm">{entry.key}</dt>
              <dd className="text-sm text-ink-soft">{entry.action}</dd>
            </div>
          ))}
        </dl>
      </section>

      {/* FAQ */}
      <section className="mt-14">
        <h2 className="headline text-2xl">Questions</h2>
        <div className="mt-5 divide-y divide-line border-y border-line">
          {FAQ.map((item) => (
            <details key={item.question} className="group py-4">
              <summary className="flex cursor-pointer list-none items-start justify-between gap-4 font-display text-base font-semibold marker:content-none">
                {item.question}
                <span
                  className="mt-1 shrink-0 text-ink-faint transition-transform duration-200 group-open:rotate-45"
                  aria-hidden="true"
                >
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                    <path
                      d="M7 1v12M1 7h12"
                      stroke="currentColor"
                      strokeWidth="1.6"
                      strokeLinecap="round"
                    />
                  </svg>
                </span>
              </summary>
              <p className="mt-2.5 leading-relaxed text-ink-soft">{item.answer}</p>
            </details>
          ))}
        </div>
      </section>

      <p className="mt-12 text-sm leading-relaxed text-ink-soft">
        Something else broken?{" "}
        <a
          href={ISSUES_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="text-accent-ink underline underline-offset-4"
        >
          Open an issue on GitHub
        </a>{" "}
        with your macOS version and what the app did.
      </p>
    </div>
  );
}
