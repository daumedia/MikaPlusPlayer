export const SITE_NAME = "Mika+Player";
export const SITE_TAGLINE = "IPTV player for macOS";

export const REPO_OWNER = "daumedia";
export const REPO_NAME = "MikaPlusPlayer";
export const GITHUB_URL = `https://github.com/${REPO_OWNER}/${REPO_NAME}`;
export const RELEASES_URL = `${GITHUB_URL}/releases`;
export const ISSUES_URL = `${GITHUB_URL}/issues`;

export const MIN_MACOS = "macOS 14 Sonoma";
export const DEMO_PLAYLIST = "https://iptv-org.github.io/iptv/index.m3u";

export const SITE_URL = (
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : "http://localhost:3000")
).replace(/\/$/, "");

export const NAV = [
  { href: "/support", label: "Support" },
  { href: "/changelog", label: "Changelog" },
  { href: "/privacy", label: "Privacy" },
] as const;
