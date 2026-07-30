/** The plus is the family mark — it stays accent-coloured everywhere. */
export function Wordmark({ className = "" }: { className?: string }) {
  return (
    <span className={className}>
      Mika<span className="text-accent-ink">+</span>Player
    </span>
  );
}
