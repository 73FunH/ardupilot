#!/bin/bash
# Delete SITL dataflash logs (*.BIN) and MAVProxy tlogs dated before today.

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# Reference: midnight of today
REF=$(mktemp)
touch -t "$(date +%Y%m%d)0000" "$REF"

mapfile -t FILES < <(
    find "$REPO/logs" -name "*.BIN" -type f ! -newer "$REF"
    find "$REPO" -maxdepth 2 \( -name "mav.tlog" -o -name "mav.tlog.raw" \) -type f ! -newer "$REF"
)
rm -f "$REF"

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "[clean_logs] Nothing to delete (all logs are from today)."
    exit 0
fi

TOTAL=$(du -ch "${FILES[@]}" 2>/dev/null | tail -1 | cut -f1)
echo "[clean_logs] ${#FILES[@]} file(s), $TOTAL:"
printf '  %s\n' "${FILES[@]}"
echo

read -rp "Delete? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "[clean_logs] Aborted."; exit 0; }

rm -f "${FILES[@]}"
echo "[clean_logs] Done."
