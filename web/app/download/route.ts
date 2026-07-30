import { NextResponse } from "next/server";
import { FALLBACK_RELEASE, getLatestRelease } from "@/lib/releases";

/** Stable short link. The lookup behind it is cached, so clicks do not hit the API. */
export async function GET() {
  const release = await getLatestRelease();
  const url = release.dmg?.url ?? FALLBACK_RELEASE.dmg!.url;
  return NextResponse.redirect(url, 302);
}
