#!/bin/bash
# Helfer außerhalb des Test-Hosts (B07-QA). Nimmt nur drei Aufträge an:
#   shot <fensternummer> <zieldatei>   – Aufnahme genau dieses einen Fensters (screencapture -l)
#   front <pid>                        – holt den Test-Host (Prozessname MikaPlusPlayer) nach vorn
#   pipax <fensternummer> list|press <knopf-id>
#                                      – Bedienungshilfen des Bild-in-Bild-Systemfensters; nur wenn das Fenster
#                                        dem Systemprozess PIPAgent gehört (Knöpfe close / restore / pause)
C=$(cd "$(dirname "$0")" && pwd)
B=$C/bridge; mkdir -p $B
END=$(( $(date +%s) + ${1:-3600} ))
while [ $(date +%s) -lt $END ]; do
  for f in $B/req-*.cmd; do
    [ -f "$f" ] || continue
    read -r cmd a1 a2 a3 < "$f"; rm -f "$f"
    done=${f%.cmd}.done
    if [ "$cmd" = "shot" ] && [[ "$a1" =~ ^[0-9]+$ ]]; then
      mkdir -p "$(dirname "$a2")"
      if /usr/sbin/screencapture -x -o -l "$a1" "$a2" 2>$B/sc.err; then
        echo "ok $(sips -g pixelWidth -g pixelHeight "$a2" 2>/dev/null | tail -2 | awk '{print $2}' | tr '\n' 'x')" > "$done.tmp"
      else echo "fail $(cat $B/sc.err)" > "$done.tmp"; fi
    elif [ "$cmd" = "front" ] && [[ "$a1" =~ ^[0-9]+$ ]]; then
      name=$(ps -p "$a1" -o comm= 2>/dev/null)
      if [[ "$name" == *MikaPlusPlayer* ]]; then
        osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $a1) to true" >/dev/null 2>$B/fr.err && echo "ok front" > "$done.tmp" || echo "fail $(cat $B/fr.err)" > "$done.tmp"
      else echo "abgelehnt $name" > "$done.tmp"; fi
    elif [ "$cmd" = "pipax" ] && [[ "$a1" =~ ^[0-9]+$ ]] && [[ "$a2" =~ ^(list|press)$ ]] && [[ "$a3" =~ ^[a-z]*$ ]]; then
      pid=$($C/pipwin | awk -v w="id=$a1" '$1=="PIP" && $2==w {for(i=1;i<=NF;i++) if($i ~ /^pid=/){sub("pid=","",$i); print $i}}')
      comm=$(ps -p "${pid:-0}" -o comm= 2>/dev/null)
      if [[ "$comm" == */PIPAgent ]]; then
        osascript -l JavaScript $C/pipax.js "$pid" "$a2" "$a3" > "$done.tmp" 2>&1
      else echo "abgelehnt: Fenster $a1 gehört nicht PIPAgent (pid=${pid:-?} $comm)" > "$done.tmp"; fi
    else echo "abgelehnt" > "$done.tmp"; fi
    mv "$done.tmp" "$done"
    echo "$(date +%T) $cmd $a1 $a2 $a3 -> $(head -c 300 $done | tr '\n' ' ')" >> $B/bridge.log
  done
  sleep 0.2
done
