import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { SITE_NAME, SITE_TAGLINE } from "@/lib/site";

export const alt = `${SITE_NAME} — ${SITE_TAGLINE}`;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  const icon = await readFile(join(process.cwd(), "public/icon-512.png"));
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "0 88px",
          background: "#120f10",
          color: "#f4f0ee",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
          {/* next/image is not available inside ImageResponse — plain img is correct here. */}
          <img src={iconSrc} width={132} height={132} alt="" style={{ borderRadius: 30 }} />
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ fontSize: 30, color: "#f87171", letterSpacing: 4 }}>MIKA+PLAYER</div>
            <div style={{ fontSize: 26, color: "#a79d99" }}>{SITE_TAGLINE}</div>
          </div>
        </div>

        <div style={{ marginTop: 56, fontSize: 92, lineHeight: 1.05, letterSpacing: -2 }}>
          Four streams.
        </div>
        <div style={{ fontSize: 92, lineHeight: 1.05, letterSpacing: -2 }}>One window.</div>

        <div style={{ marginTop: 44, display: "flex", gap: 14 }}>
          {["#b1494a", "#2f8f83", "#a8752b", "#5b4bb5"].map((colour) => (
            <div
              key={colour}
              style={{
                width: 132,
                height: 74,
                borderRadius: 8,
                background: `linear-gradient(150deg, ${colour}, #0b0809)`,
              }}
            />
          ))}
        </div>
      </div>
    ),
    size,
  );
}
