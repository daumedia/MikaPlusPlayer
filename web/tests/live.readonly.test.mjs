// B10 · Website — lesende Prüfung der öffentlichen Adressen (QA-Durchlauf 1, 2026-09-15)
//
// Ausführen (braucht Internet, nur GET-Anfragen, kein Login, kein Deployment):
//   cd web && node --test tests/live.readonly.test.mjs
//
// Geprüft wird die Homepage-Adresse aus dem GitHub-Repository, die zuletzt von GitHub gemeldete
// Production-Deployment-Adresse und die Domain aus web/README.md. Tests, die den Befund belegen,
// tragen { todo: "BUG-01 …" } — die Suite bleibt grün, der Befund bleibt sichtbar.

import { test } from "node:test";
import assert from "node:assert/strict";
import { resolve4 } from "node:dns/promises";

const GH = "https://api.github.com/repos/daumedia/MikaPlusPlayer";
const gh = (path) => fetch(GH + path, { headers: { Accept: "application/vnd.github+json", "User-Agent": "b10-qa-readonly" } });

async function productionUrls() {
  const repo = await (await gh("")).json();
  const deployments = await (await gh("/deployments?environment=Production&per_page=1")).json();
  const urls = new Set([repo.homepage].filter(Boolean));
  if (deployments[0]) {
    const statuses = await (await gh(`/deployments/${deployments[0].id}/statuses`)).json();
    for (const s of statuses) if (s.environment_url) urls.add(s.environment_url);
  }
  return [...urls];
}

test("FB-15 (Befund): Datenschutzseite ist unter einer öffentlichen Adresse ohne Anmeldung und ohne Cookie abrufbar", { todo: "BUG-01 Website öffentlich nicht erreichbar" }, async (t) => {
  const urls = await productionUrls();
  const results = [];
  for (const base of urls) {
    const res = await fetch(`${base.replace(/\/$/, "")}/privacy`, { redirect: "manual" });
    results.push({
      url: `${base}/privacy`,
      status: res.status,
      vercelError: res.headers.get("x-vercel-error"),
      location: res.headers.get("location")?.split("?")[0] ?? null,
      setsCookie: (res.headers.get("set-cookie") ?? "").split("=")[0] || null,
      body: res.status === 200 ? (await res.text()).includes("What leaves your Mac") : false,
    });
  }
  let domain = "unbekannt";
  try { domain = (await resolve4("mikaplusplayer.com")).join(","); } catch (e) { domain = e.code; }
  t.diagnostic(JSON.stringify({ results, "mikaplusplayer.com": domain }));
  assert.ok(results.some((r) => r.status === 200 && r.body && !r.setsCookie), "keine Adresse liefert /privacy öffentlich aus");
});
