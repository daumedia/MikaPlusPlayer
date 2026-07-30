import Image from "next/image";
import { SCREENSHOTS } from "@/content/screenshots";

export function ScreenshotStrip() {
  if (SCREENSHOTS.length === 0) return null;

  return (
    <section className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
      <p className="eyebrow">The app itself</p>
      <h2 className="headline mt-2 text-3xl sm:text-4xl">Captured from a running build</h2>

      <div className="mt-8 grid gap-6 md:grid-cols-2">
        {SCREENSHOTS.map((shot) => (
          <figure key={shot.src} className="space-y-2.5">
            <div className="overflow-hidden rounded-[var(--radius-card)] border border-line bg-screen shadow-[var(--elevate)]">
              <Image
                src={shot.src}
                alt={shot.alt}
                width={shot.width}
                height={shot.height}
                className="h-auto w-full"
              />
            </div>
            <figcaption className="text-sm text-ink-soft">{shot.caption}</figcaption>
          </figure>
        ))}
      </div>
    </section>
  );
}
