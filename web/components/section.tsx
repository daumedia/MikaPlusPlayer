/** Eyebrow over a large title — the PlayerHeader pattern from the app. */
export function Section({
  eyebrow,
  title,
  lead,
  children,
  className = "",
}: {
  eyebrow: string;
  title: string;
  lead?: string;
  children?: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={`mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20 ${className}`}>
      <p className="eyebrow">{eyebrow}</p>
      <h2 className="headline mt-2 max-w-3xl text-3xl sm:text-4xl">{title}</h2>
      {lead && <p className="mt-4 max-w-2xl text-lg leading-relaxed text-ink-soft">{lead}</p>}
      {children}
    </section>
  );
}
