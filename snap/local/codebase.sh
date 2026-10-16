#!/bin/sh
# Shared by the daemon wrapper and the hooks (sourced with `.`, plain sh).
#
# A VillageSQL data directory belongs to one upstream codebase (mysql-8.4,
# mysql-9.7 or percona-8.4) and upstream has no migration between them, so
# the snap records the codebase of the data in $SNAP_COMMON and refuses a
# refresh that would run another codebase on it (see hooks/post-refresh).
# The codebase of a revision is stamped into $SNAP/codebase at build time
# from upstream's VSQL_VERSION file (VSQL_CODE_BASE=...).

# Codebase this revision was built from.
snap_codebase() {
  cat "$SNAP/codebase"
}

# Codebase recorded for $SNAP_COMMON/data. Prints nothing and returns 1
# when it cannot be told. Installs made by 0.0.6 only have the legacy
# marker .snap-data-major holding the MySQL major "8.4" (= mysql-8.4).
data_codebase() {
  if [ -f "$SNAP_COMMON/.snap-data-codebase" ]; then
    cat "$SNAP_COMMON/.snap-data-codebase"
    return 0
  fi
  if [ -f "$SNAP_COMMON/.snap-data-major" ] && [ "$(cat "$SNAP_COMMON/.snap-data-major")" = "8.4" ]; then
    echo "mysql-8.4"
    return 0
  fi
  return 1
}

# Record this revision's codebase for the data directory; drop the legacy marker.
write_data_codebase() {
  snap_codebase > "$SNAP_COMMON/.snap-data-codebase"
  rm -f "$SNAP_COMMON/.snap-data-major"
}
