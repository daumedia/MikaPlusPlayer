# Mika+Player — website

Marketing site for the macOS app, deployed on Vercel. Next.js App Router, TypeScript, Tailwind v4.
Everything is a Server Component except `components/multiview-demo.tsx`.

```sh
npm install
npm run dev     # http://localhost:3000
npm run build
npm run lint
```

## Where content lives

Copy is separated from layout — edit `content/`, not the pages:

| File | Holds |
| --- | --- |
| `content/features.ts` | The feature grid, grouped into Library / Playback / System |
| `content/setup-steps.ts` | The three CH 01–03 steps, used on `/` and `/support` |
| `content/faq.ts` | Questions on `/support` |
| `content/changelog-overrides.ts` | English release notes that replace the German GitHub bodies |
| `content/screenshots.ts` | App screenshots. Empty by default — the section hides itself |
| `lib/site.ts` | URLs, repo name, minimum macOS version, nav |

## Download and changelog come from GitHub

`lib/releases.ts` reads the GitHub releases API with `revalidate: 3600`, picks the DMG asset by
content type, and reads the file size from the response. Nothing about the current version is
hard-coded into the pages — cutting a new release updates the site within the hour.

If the API fails or rate limits (60 requests/hour unauthenticated), `FALLBACK_RELEASE` takes over
and the build still succeeds. Verify that path with:

```sh
GITHUB_TOKEN=invalid npm run build   # logs a 401, builds anyway
```

Setting a real `GITHUB_TOKEN` (fine-grained, public repositories, read-only) raises the limit to
5000/hour.

`/download` is a stable short link that 302-redirects to the current DMG.

## Design

Palette and radii come from `Sources/Views/Theme/PlayerTheme.swift` — the app's accent red,
warm backgrounds, 12px card radius. They live as CSS custom properties in `app/globals.css` and
adapt to light and dark, the way the app does.

The app's `#EF4444` only reaches 3.5:1 on the light background, so text and filled buttons use
`--accent-ink` / `--accent-solid`: darker relatives in the same hue. Keep using those for anything
with text on it; plain `--accent` is for fills and for anything sitting on a dark picture.

Typography is Archivo across its width axis — wide for headlines, narrow for labels — with
IBM Plex Sans for body text and IBM Plex Mono for versions, sizes and channel numbers.

The Multiview and channel-list mockups are CSS, not screenshots, so they cannot go stale and hold
no real channel names. To add real screenshots later, drop the files in `public/screenshots/` and
fill in `content/screenshots.ts`.

## Deploying on Vercel

The repository root is an Xcode project, so Vercel needs pointing at this folder.

1. vercel.com → **Add New… → Project** → import `Mukaarts/MikaPlusPlayer`.
2. **Root Directory** → Edit → select `web`. The framework preset switches to Next.js afterwards.
   Leave "Include source files outside of the Root Directory" **off**.
3. Leave build, output and install commands on their defaults.
4. Environment variables: `NEXT_PUBLIC_SITE_URL` (production only, e.g. `https://mikaplusplayer.com`)
   and optionally `GITHUB_TOKEN`.
5. Deploy.

Afterwards, in project settings:

- **Git → Ignored Build Step** → `git diff --quiet HEAD^ HEAD -- .` so Swift-only commits do not
  trigger a rebuild.
- **General → Node.js Version** → 24.x.
- **Domains** → add a domain and set the DNS records Vercel shows.

No `vercel.json` is needed. Security headers live in `next.config.ts` so they also apply in
`next dev`.
