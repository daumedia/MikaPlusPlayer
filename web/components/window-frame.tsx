/** A Mac window around the mockups — it makes clear this is a desktop app. */
export function WindowFrame({
  title,
  toolbar,
  children,
}: {
  title: string;
  toolbar?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="overflow-hidden rounded-[var(--radius-card)] border border-line bg-card shadow-[var(--elevate)]">
      <div className="flex items-center gap-2 border-b border-line px-3.5 py-2.5">
        <span className="flex gap-1.5" aria-hidden="true">
          <span className="size-2.5 rounded-full bg-[#ff5f57]" />
          <span className="size-2.5 rounded-full bg-[#febc2e]" />
          <span className="size-2.5 rounded-full bg-[#28c840]" />
        </span>
        <span className="ml-1 font-display text-xs font-medium text-ink-soft">{title}</span>
        {toolbar && <div className="ml-auto">{toolbar}</div>}
      </div>
      {children}
    </div>
  );
}
