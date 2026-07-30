/**
 * The single biggest reason a download never becomes a launch.
 * This belongs next to the button, not buried in the FAQ.
 */
export function GatekeeperNote() {
  return (
    <aside className="max-w-md border-l-2 border-accent/40 pl-4">
      <p className="eyebrow">First launch</p>
      <p className="mt-1 text-sm leading-relaxed text-ink-soft">
        The build is ad-hoc signed, so macOS blocks the first launch. In Applications,{" "}
        <strong className="font-semibold text-ink">right-click Mika+Player and choose Open</strong>,
        then confirm once. Every launch after that behaves normally.
      </p>
    </aside>
  );
}
