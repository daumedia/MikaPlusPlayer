"use client";

import { useState } from "react";
import { WindowFrame } from "@/components/window-frame";

/**
 * The app's Multiview window, rebuilt in CSS.
 * Clicking a tile moves focus, the accent border and the sound — exactly what
 * MultiviewScreen.swift does. Not a screenshot: nothing here can go stale.
 */

type Channel = {
  number: string;
  group: string;
  /** Stand-in for a picture: out-of-focus light, not a real broadcast. */
  picture: string;
};

const CHANNELS: readonly Channel[] = [
  {
    number: "01",
    group: "News",
    picture:
      "radial-gradient(55% 65% at 22% 28%, #b1494a 0%, transparent 62%), radial-gradient(45% 55% at 78% 70%, #6d2226 0%, transparent 58%), radial-gradient(30% 40% at 58% 18%, #d98d6a 0%, transparent 60%), linear-gradient(155deg, #2c1517, #0b0809)",
  },
  {
    number: "02",
    group: "Sports",
    picture:
      "radial-gradient(50% 60% at 70% 30%, #2f8f83 0%, transparent 60%), radial-gradient(45% 55% at 25% 72%, #14514f 0%, transparent 58%), radial-gradient(26% 34% at 46% 46%, #9fd6c0 0%, transparent 62%), linear-gradient(155deg, #102b2b, #0b0809)",
  },
  {
    number: "03",
    group: "Documentary",
    picture:
      "radial-gradient(58% 62% at 30% 66%, #a8752b 0%, transparent 62%), radial-gradient(40% 50% at 74% 26%, #d8b271 0%, transparent 58%), radial-gradient(28% 32% at 52% 52%, #5e3d16 0%, transparent 60%), linear-gradient(155deg, #2a1d0d, #0b0809)",
  },
  {
    number: "04",
    group: "Kids",
    picture:
      "radial-gradient(52% 58% at 68% 62%, #5b4bb5 0%, transparent 60%), radial-gradient(44% 52% at 26% 30%, #8f6ecb 0%, transparent 58%), radial-gradient(24% 30% at 50% 78%, #c3a3e8 0%, transparent 62%), linear-gradient(155deg, #1e1938, #0b0809)",
  },
];

type Layout = "focus" | "grid";

function Picture({ picture }: { picture: string }) {
  return (
    <>
      <div className="absolute inset-0" style={{ backgroundImage: picture }} />
      {/* Faint scan structure and a vignette — reads as a screen, quietly. */}
      <div
        className="absolute inset-0 opacity-[0.06]"
        style={{
          backgroundImage:
            "repeating-linear-gradient(to bottom, #fff 0 1px, transparent 1px 3px)",
        }}
        aria-hidden="true"
      />
      <div
        className="absolute inset-0"
        style={{
          backgroundImage:
            "radial-gradient(120% 120% at 50% 50%, transparent 42%, rgb(0 0 0 / 0.55) 100%)",
        }}
        aria-hidden="true"
      />
    </>
  );
}

function SoundBadge({ compact = false }: { compact?: boolean }) {
  return (
    <span
      className={`badge bg-accent/20 text-accent backdrop-blur-sm ${
        compact ? "scale-90" : ""
      }`}
    >
      <svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
        <path d="M8 2.5 4.8 5.2H2.4v5.6h2.4L8 13.5zM10.6 5.4a3.6 3.6 0 0 1 0 5.2M12.6 3.4a6.4 6.4 0 0 1 0 9.2" />
      </svg>
      Sound
    </span>
  );
}

export function MultiviewDemo({
  withLayoutToggle = false,
}: {
  withLayoutToggle?: boolean;
}) {
  const [activeIndex, setActiveIndex] = useState(0);
  const [layout, setLayout] = useState<Layout>("focus");

  const active = CHANNELS[activeIndex];
  const others = CHANNELS.filter((_, i) => i !== activeIndex);

  /* The layout switch lives in the window toolbar, where the app puts it. */
  const layoutToggle = withLayoutToggle ? (
    <>
      <span className="sr-only" id="layout-label">
        Multiview layout
      </span>
      <div
        role="group"
        aria-labelledby="layout-label"
        className="inline-flex rounded-full bg-ink/[0.06] p-0.5"
      >
        {(["focus", "grid"] as const).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setLayout(option)}
            aria-pressed={layout === option}
            className={`rounded-full px-3 py-0.5 text-[0.7rem] font-medium capitalize transition-colors ${
              layout === option ? "bg-accent-solid text-on-accent" : "text-ink-soft hover:text-ink"
            }`}
          >
            {option}
          </button>
        ))}
      </div>
    </>
  ) : undefined;

  return (
    <WindowFrame title="Multiview" toolbar={layoutToggle}>
      <div
        role="group"
        aria-label="Multiview demonstration — pick the stream that plays sound"
        className="relative aspect-video w-full overflow-hidden bg-screen"
      >
        {layout === "focus" ? (
          <>
            <div className="absolute inset-0">
              <Picture picture={active.picture} />
              <div className="absolute inset-x-0 bottom-0 flex items-end justify-between gap-3 bg-gradient-to-t from-black/75 to-transparent p-4">
                <div>
                  <p className="font-mono text-[0.7rem] tracking-widest text-white/55">
                    CH {active.number}
                  </p>
                  <p className="font-display text-sm font-semibold text-white sm:text-base">
                    {active.group}
                  </p>
                </div>
                <SoundBadge />
              </div>
            </div>

            <div className="absolute right-2.5 top-2.5 flex gap-2 sm:right-3 sm:top-3">
              {others.map((channel) => (
                <button
                  key={channel.number}
                  type="button"
                  onClick={() =>
                    setActiveIndex(CHANNELS.findIndex((c) => c.number === channel.number))
                  }
                  aria-label={`Give sound and the large picture to channel ${channel.number}, ${channel.group}`}
                  className="group relative aspect-video w-[19%] min-w-[64px] overflow-hidden rounded-md border border-white/15 transition-transform duration-200 hover:scale-[1.04]"
                >
                  <Picture picture={channel.picture} />
                  <span className="absolute bottom-1 left-1.5 font-mono text-[0.6rem] text-white/70">
                    {channel.number}
                  </span>
                </button>
              ))}
            </div>
          </>
        ) : (
          <div className="grid h-full grid-cols-2 grid-rows-2 gap-1.5 p-1.5">
            {CHANNELS.map((channel, index) => {
              const isActive = index === activeIndex;
              return (
                <button
                  key={channel.number}
                  type="button"
                  onClick={() => setActiveIndex(index)}
                  aria-pressed={isActive}
                  aria-label={`Give sound to channel ${channel.number}, ${channel.group}`}
                  className={`relative overflow-hidden rounded-md transition-transform duration-200 hover:scale-[1.01] ${
                    isActive ? "ring-2 ring-inset ring-accent" : "ring-1 ring-inset ring-white/10"
                  }`}
                >
                  <Picture picture={channel.picture} />
                  <span className="absolute bottom-1.5 left-2 font-mono text-[0.65rem] text-white/70">
                    CH {channel.number}
                  </span>
                  {isActive && (
                    <span className="absolute right-1.5 top-1.5">
                      <SoundBadge compact />
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        )}
      </div>
    </WindowFrame>
  );
}
