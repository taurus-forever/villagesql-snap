#!/bin/bash
# villagesql.extensions list
# Show every extension bundle the server can see (from INVENTORY, assembled
# at daemon start), where it comes from, and whether INSTALL EXTENSION has
# been run for it (queried over the socket as root; needs sudo).
set -eu

INVENTORY="$SNAP_COMMON/veb/INVENTORY"

usage() {
  echo "usage: villagesql.extensions list"
  echo "  Lists extension bundles: built into the snap or provided by connected"
  echo "  extension snaps (snap connect villagesql:extensions <snap>:extensions)."
}

case "${1:-}" in
  list) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [ ! -f "$INVENTORY" ]; then
  echo "No inventory yet: start the service first (sudo snap start villagesql)." >&2
  exit 1
fi

installed=""
if [ "$(id -u)" = "0" ]; then
  installed="$("$SNAP/usr/bin/mysql" --defaults-file="$SNAP_COMMON/etc/my.cnf" -uroot -N -B \
    -e "SELECT EXTENSION_NAME FROM INFORMATION_SCHEMA.EXTENSIONS;" 2>/dev/null || echo "__unavailable__")"
else
  installed="__unavailable__"
fi

printf '%-24s %-12s %-28s %s\n' NAME VERSION ORIGIN INSTALLED
while IFS=$'\t' read -r file origin ver; do
  case "$file" in ''|'#'*) continue ;; esac
  name="${file%.veb}"
  name="$(printf '%s' "$name" | sed 's/-[0-9][0-9.]*$//')"   # strip -x.y.z of versioned bundles
  if [ "$installed" = "__unavailable__" ]; then
    state="? (run as root with the service up)"
  elif printf '%s\n' "$installed" | grep -qx "$name"; then
    state="yes"
  else
    state="no"
  fi
  printf '%-24s %-12s %-28s %s\n' "$name" "$ver" "$origin" "$state"
done < "$INVENTORY"

notes="$(grep '^# .* ignored: ' "$INVENTORY" || true)"
if [ -n "$notes" ]; then
  echo
  printf '%s\n' "$notes" | sed 's/^# /note: /'
fi
