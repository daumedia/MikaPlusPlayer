import Link from "next/link";

/**
 * The single biggest reason a download never becomes a launch.
 * This belongs next to the button, not buried in the FAQ.
 */
export function GatekeeperNote() {
  return (
    <aside className="max-w-md border-l-2 border-accent/40 pl-4">
      <p className="eyebrow">First launch</p>
      <p className="mt-1 text-sm leading-relaxed text-ink-soft">
        The build is ad-hoc signed and not notarised, so macOS blocks the first launch. Open the app
        once, then go to{" "}
        <strong className="font-semibold text-ink">System Settings → Privacy &amp; Security</strong>{" "}
        and click <strong className="font-semibold text-ink">Open Anyway</strong>. On macOS 14
        Sonoma, Control-click → Open works as well.{" "}
        <Link href="/support#first-launch" className="text-accent-ink underline underline-offset-4">
          All steps, including the checksum check
        </Link>
        .
      </p>
    </aside>
  );
}
