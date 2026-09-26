import { NextResponse } from "next/server";
import { getLatestReleaseForDownload } from "@/lib/releases";
import { LATEST_RELEASE_URL } from "@/lib/site";

/**
 * Stable short link to the DMG of the latest release. Without a DMG (upload still running) it
 * goes to that release's page; without release data (GitHub not answering) to the page of the
 * newest release — never to a hard-coded, possibly outdated build.
 */
export async function GET() {
  const release = await getLatestReleaseForDownload();
  const url = release?.dmg?.url ?? release?.htmlUrl ?? LATEST_RELEASE_URL;
  return NextResponse.redirect(url, 302);
}
