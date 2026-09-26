#!/usr/bin/env python3
"""B07-QA: Bedienung des iOS-Simulators über AXe (nur die QA-Simulatoren „QA-B07 …“).

ios.py <udid> dump [datei]            Bedienungshilfen-Baum (kompakt) ausgeben / speichern
ios.py <udid> find <text>             Elemente, deren Label/Wert/Id <text> enthält
ios.py <udid> tap <text> [n]          n-tes passendes Element antippen (Mitte des Rahmens)
ios.py <udid> tapxy <x> <y>
ios.py <udid> type <text>             Text über die (Hardware-)Tastatur tippen – keine Tastaturklicks
ios.py <udid> key <hid>               einzelne Taste (HID-Keycode), z. B. 19 = p
ios.py <udid> home                    Home-Taste
ios.py <udid> shot <datei>            Bildschirmfoto des Simulators
"""
import json, os, subprocess, sys, time

AXE = os.environ.get("AXE", "axe")  # Pfad zur AXe-CLI (z. B. aus XcodeBuildMCP), per Umgebungsvariable


def run(args, check=True):
    r = subprocess.run([AXE] + args, capture_output=True, text=True)
    if check and r.returncode != 0:
        print("AXE-FEHLER", args, r.stderr.strip()[:300])
    return r.stdout


def tree(udid):
    out = run(["describe-ui", "--udid", udid])
    try:
        d = json.loads(out)
    except Exception:
        return []
    flat = []

    def walk(n, depth=0):
        f = n.get("frame", {}) or {}
        flat.append({
            "depth": depth, "type": n.get("type") or n.get("role") or "?",
            "label": n.get("AXLabel") or "", "value": str(n.get("AXValue") or ""), "id": n.get("AXUniqueId") or "",
            "x": f.get("x", 0), "y": f.get("y", 0), "w": f.get("width", 0), "h": f.get("height", 0),
            "enabled": n.get("enabled", True),
        })
        for c in n.get("children", []) or []:
            walk(c, depth + 1)

    for n in (d if isinstance(d, list) else [d]):
        walk(n)
    return flat


def line(e):
    return f"{'  ' * min(e['depth'], 12)}{e['type']} '{e['label']}' val='{e['value']}' id='{e['id']}' ({int(e['x'])},{int(e['y'])},{int(e['w'])}x{int(e['h'])})"


def matches(e, text):
    return text in e["label"] or text in e["value"] or text in e["id"]


def main():
    udid, cmd = sys.argv[1], sys.argv[2]
    if cmd == "dump":
        lines = [line(e) for e in tree(udid) if e["label"] or e["value"] or e["id"] or e["type"] not in ("Group",)]
        text = "\n".join(lines)
        if len(sys.argv) > 3:
            open(sys.argv[3], "w").write(text + "\n")
        print(text)
    elif cmd == "find":
        for e in tree(udid):
            if matches(e, sys.argv[3]):
                print(line(e).strip())
    elif cmd == "tap":
        n = int(sys.argv[4]) if len(sys.argv) > 4 else 0
        hits = [e for e in tree(udid) if matches(e, sys.argv[3]) and e["w"] > 0]
        if len(hits) <= n:
            print("NICHT GEFUNDEN", sys.argv[3]); sys.exit(1)
        e = hits[n]
        x, y = e["x"] + e["w"] / 2, e["y"] + e["h"] / 2
        run(["tap", "-x", str(int(x)), "-y", str(int(y)), "--udid", udid])
        print(f"tap '{e['label']}' @ {int(x)},{int(y)}")
    elif cmd == "tapxy":
        run(["tap", "-x", sys.argv[3], "-y", sys.argv[4], "--udid", udid])
    elif cmd == "type":
        run(["type", sys.argv[3], "--udid", udid])
    elif cmd == "key":
        run(["key", sys.argv[3], "--udid", udid])
    elif cmd == "home":
        run(["button", "home", "--udid", udid])
    elif cmd == "shot":
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", sys.argv[3]], capture_output=True)
        print("shot", sys.argv[3])


if __name__ == "__main__":
    main()
