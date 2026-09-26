import { NOTE_OVERRIDES } from "@/content/changelog-overrides";
import { REPO_NAME, REPO_OWNER } from "@/lib/site";

const API = "https://api.github.com";
const REVALIDATE = 3600;

/** After a failed lookup, `/download` waits this long before it asks GitHub again. */
export const DOWNLOAD_RETRY_AFTER_MS = 5 * 60 * 1000;

export type DmgAsset = {
  name: string;
  url: string;
  sizeBytes: number;
  downloadCount: number;
  /** SHA-256 of the file as reported by GitHub (asset `digest`), lowercase hex. null if GitHub has none. */
  sha256: string | null;
};

export type Release = {
  tag: string;
  version: string;
  title: string;
  publishedAt: string;
  htmlUrl: string;
  notes: string;
  dmg: DmgAsset | null;
};

type GhAsset = {
  name: string;
  size: number;
  content_type: string;
  browser_download_url: string;
  download_count: number;
  digest?: string | null;
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

function sha256FromDigest(digest: string | null | undefined): string | null {
  const match = /^sha256:([0-9a-f]{64})$/i.exec(digest ?? "");
  return match ? match[1].toLowerCase() : null;
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
    sha256: sha256FromDigest(asset.digest),
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
  };
}

/**
 * The newest published release, or null when GitHub did not answer.
 *
 * There is deliberately no built-in replacement release: hard-coded version data goes stale and
 * would quietly send visitors to an old build. Callers link to the release page instead —
 * `htmlUrl` when the release has no DMG yet, `LATEST_RELEASE_URL` when there is no release data.
 */
export async function getLatestRelease(): Promise<Release | null> {
  const raw = await gh<GhRelease>(`/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`);
  return raw ? toRelease(raw) : null;
}

let lastDownloadFailureAt = Number.NEGATIVE_INFINITY;
let pendingDownloadLookup: Promise<Release | null> | null = null;

/**
 * `getLatestRelease` for the `/download` route handler, which runs on every click.
 *
 * Next.js only keeps successful fetches in its data cache, so during a GitHub outage or an
 * exhausted rate limit every click would ask GitHub again. Here concurrent clicks share one
 * request, and after a failure the answer stays "unknown" for `DOWNLOAD_RETRY_AFTER_MS`.
 * The window lives in this server process (on Vercel: per function instance).
 *
 * Pages must not use this: an ISR render has to run the fetch itself, otherwise it loses the
 * fetch's hourly revalidation.
 */
export async function getLatestReleaseForDownload(now = Date.now()): Promise<Release | null> {
  if (now - lastDownloadFailureAt < DOWNLOAD_RETRY_AFTER_MS) return null;

  pendingDownloadLookup ??= getLatestRelease().finally(() => {
    pendingDownloadLookup = null;
  });
  const release = await pendingDownloadLookup;
  if (!release) lastDownloadFailureAt = Math.max(lastDownloadFailureAt, now);
  return release;
}

/** Up to `limit` releases in API order, drafts removed; null when GitHub did not answer. */
export async function getReleases(limit = 20): Promise<Release[] | null> {
  const raw = await gh<GhRelease[]>(
    `/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=${limit}`,
  );
  if (!Array.isArray(raw)) return null;

  return raw.filter((r) => !r.draft).map(toRelease);
}
