import type { ReactNode } from "react";
import Link from "next/link";
import { FAQ } from "@/content/faq";
import { SETUP_STEPS } from "@/content/setup-steps";
import { pageMetadata } from "@/lib/metadata";
import { DEMO_PLAYLIST, ISSUES_URL } from "@/lib/site";

export const generateMetadata = pageMetadata({
  path: "/support",
  title: "Support",
  description:
    "Set up an Xtream Codes login or an M3U playlist in Mika+Player, get past the first-launch warning, and find answers to the questions that come up most.",
});

const codeClass = "rounded bg-ink/[0.06] px-1 font-mono text-[0.85em] text-ink";

/**
 * Apple, "Updates to runtime protection in macOS Sequoia" (6 August 2024): Control-click no longer
 * overrides Gatekeeper; the way through is System Settings > Privacy & Security. Apple's Mac User
 * Guide "Open a Mac app from an unknown developer": Open Anyway, available for about an hour after
 * the blocked attempt, confirmed with the login password.
 */
const FIRST_LAUNCH_STEPS: readonly { id: string; body: ReactNode }[] = [
  { id: "drag", body: "Open the DMG and drag MikaPlusPlayer to Applications." },
  {
    id: "checksum",
    body: (
      <>
        Check the download before you open it. In Terminal, type{" "}
        <code className={codeClass}>shasum -a 256</code> and a space, drag the DMG into the window and
        press Return. The result has to match the SHA-256 shown under the download button on the{" "}
        <Link href="/" className="text-accent-ink underline underline-offset-4">
          home page
        </Link>{" "}
        and in the{" "}
        <Link href="/changelog" className="text-accent-ink underline underline-offset-4">
          changelog
        </Link>
        . A match means the file is exactly the one attached to the GitHub release.
      </>
    ),
  },
  {
    id: "attempt",
    body: "Open MikaPlusPlayer from the Applications folder once. macOS refuses and shows a warning — close it.",
  },
  {
    id: "open-anyway",
    body: (
      <>
        Open{" "}
        <strong className="font-semibold text-ink">System Settings → Privacy &amp; Security</strong>,
        scroll to Security and click{" "}
        <strong className="font-semibold text-ink">Open Anyway</strong>. The button is there for
        about an hour after the blocked attempt.
      </>
    ),
  },
  {
    id: "confirm",
    body: "Confirm with your login password. macOS keeps the exception — later launches are normal.",
  },
];

const KEYS: readonly { key: string; action: string }[] = [
  { key: "Space", action: "Play or pause" },
  { key: "↑ ↓ + −", action: "Volume, in 5% steps" },
  { key: "M", action: "Mute" },
  { key: "F", action: "Full screen" },
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
      <section id="first-launch" className="mt-14 scroll-mt-20">
        <h2 className="headline text-2xl">First launch on macOS</h2>
        <p className="mt-3 leading-relaxed text-ink-soft">
          Mika+Player is signed ad-hoc rather than notarised, so macOS blocks the first launch. In
          the Finder and in the warning the app is called MikaPlusPlayer. Since macOS 15 Sequoia,
          Control-clicking the app and choosing Open no longer gets past that — the way through is
          System Settings:
        </p>
        <ol className="mt-5 space-y-3">
          {FIRST_LAUNCH_STEPS.map((step, index) => (
            <li key={step.id} className="flex gap-3.5">
              <span className="font-mono text-xs leading-6 text-ink-faint">
                {String(index + 1).padStart(2, "0")}
              </span>
              <span className="leading-relaxed text-ink-soft">{step.body}</span>
            </li>
          ))}
        </ol>
        <p className="mt-5 text-sm leading-relaxed text-ink-soft">
          On macOS 14 Sonoma, Control-clicking MikaPlusPlayer in Applications and choosing Open
          works as well.
        </p>
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
        <p className="mt-4 text-sm leading-relaxed text-ink-soft">
          Space, the volume keys and M confirm with a short on-screen indicator; F and Esc only
          switch full screen.
        </p>
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
