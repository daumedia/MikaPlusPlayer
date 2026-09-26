import type { Metadata, ResolvingMetadata } from "next";
import { SITE_NAME } from "@/lib/site";

export const OPEN_GRAPH_DEFAULTS = {
  type: "website",
  siteName: SITE_NAME,
  locale: "en_US",
} as const;

/**
 * `generateMetadata` for a page below `/`. Next.js replaces the layout's `openGraph` object as a
 * whole instead of merging it, so every page states its own URL, title and description — and
 * carries over the preview image from `app/opengraph-image.tsx`, which would otherwise be lost.
 */
export function pageMetadata({
  path,
  title,
  description,
}: {
  path: `/${string}`;
  title: string;
  description: string;
}) {
  return async function generateMetadata(
    _props: unknown,
    parent: ResolvingMetadata,
  ): Promise<Metadata> {
    const inherited = await parent;
    return {
      title,
      description,
      alternates: { canonical: path },
      openGraph: {
        ...OPEN_GRAPH_DEFAULTS,
        url: path,
        title: `${title} — ${SITE_NAME}`,
        description,
        images: inherited.openGraph?.images,
      },
    };
  };
}
