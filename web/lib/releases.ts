import { NOTE_OVERRIDES } from "@/content/changelog-overrides";
import { REPO_NAME, REPO_OWNER } from "@/lib/site";

const API = "https://api.github.com";
const REVALIDATE = 3600;

export type DmgAsset = {
  name: string;
  url: string;
  sizeBytes: number;
  downloadCount: number;
};

export type Release = {
  tag: string;
  version: string;
  title: string;
  publishedAt: string;
  htmlUrl: string;
  notes: string;
  dmg: DmgAsset | null;
  /** true when GitHub was unreachable or rate limited and we fell back. */
  isFallback: boolean;
};

type GhAsset = {
  name: string;
  size: number;
  content_type: string;
  browser_download_url: string;
  download_count: number;
};

type GhRelease = {
  tag_name: string;
  name: string | null;
  body: string | null;
  draft: boolean;
  prerelease: boolean;
  published_at: string;
  html_url: string;
  assets: GhAsset[];
};

/** Last known good release. Keeps the download working when the API does not answer. */
export const FALLBACK_RELEASE: Release = {
  tag: "v1.1",
  version: "1.1",
  title: "v1.1 – Multiview",
  publishedAt: "2026-06-23T12:42:50Z",
  htmlUrl: `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/v1.1`,
  notes: NOTE_OVERRIDES["v1.1"] ?? "",
  dmg: {
    name: "MikaPlusPlayer-v1.1.dmg",
    url: `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v1.1/MikaPlusPlayer-v1.1.dmg`,
    sizeBytes: 36_455_860,
    downloadCount: 0,
  },
  isFallback: true,
};

async function gh<T>(path: string): Promise<T | null> {
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "mikaplusplayer-website",
  };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  try {
    const res = await fetch(`${API}${path}`, {
      headers,
      next: { revalidate: REVALIDATE, tags: ["github-releases"] },
    });

    if (!res.ok) {
      console.warn(
        `[releases] ${path} -> ${res.status}; rate limit remaining: ${res.headers.get(
          "x-ratelimit-remaining",
        )}`,
      );
      return null;
    }
    return (await res.json()) as T;
  } catch (error) {
    console.warn(`[releases] request failed: ${path}`, error);
    return null; // A build must never fail because GitHub is down.
  }
}

function pickDmg(assets: GhAsset[] = []): DmgAsset | null {
  const asset =
    assets.find((a) => a.content_type === "application/x-apple-diskimage") ??
    assets.find((a) => a.name.toLowerCase().endsWith(".dmg"));
  if (!asset) return null;

  return {
    name: asset.name,
    url: asset.browser_download_url,
    sizeBytes: asset.size,
    downloadCount: asset.download_count,
  };
}

function toRelease(raw: GhRelease): Release {
  return {
    tag: raw.tag_name,
    version: raw.tag_name.replace(/^v/i, ""),
    title: raw.name?.trim() || raw.tag_name,
    publishedAt: raw.published_at,
    htmlUrl: raw.html_url,
    notes: NOTE_OVERRIDES[raw.tag_name] ?? raw.body?.trim() ?? "",
    dmg: pickDmg(raw.assets),
    isFallback: false,
  };
}

export async function getLatestRelease(): Promise<Release> {
  const raw = await gh<GhRelease>(`/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`);
  if (!raw) return FALLBACK_RELEASE;

  const release = toRelease(raw);
  // Release exists but the DMG is missing (upload still running) — keep the old link.
  return release.dmg ? release : { ...release, dmg: FALLBACK_RELEASE.dmg };
}

export async function getReleases(limit = 20): Promise<Release[]> {
  const raw = await gh<GhRelease[]>(
    `/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=${limit}`,
  );
  if (!raw?.length) return [FALLBACK_RELEASE];

  return raw.filter((r) => !r.draft).map(toRelease);
}
