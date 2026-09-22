#!/bin/bash
# Daemon entry point: run mysqld as the _daemon_ user.
# $SNAP        = /snap/villagesql/<revision>   # read-only at run time
# $SNAP_COMMON = /var/snap/villagesql/common   # data, config, logs (see docs/)
set -eu
if [ "${EUID}" != "0" ]; then
  echo "Error: run it as root (to utilize snap user _daemon_)." >&2
  exit 1
fi

# Record which MySQL major runs on this data directory; read by post-refresh.
if [ -d "$SNAP_COMMON/data/mysql" ]; then
  echo "$SNAP_VERSION" | cut -d. -f1-2 > "$SNAP_COMMON/.snap-data-major"
fi

# mysqld would try systemd's notify socket if the variable were set; the
# service is `daemon: simple`, so keep it unset to avoid confinement denials.
unset NOTIFY_SOCKET

exec "$SNAP/usr/bin/setpriv" --clear-groups --reuid _daemon_ --regid root -- \
  "$SNAP/usr/bin/mysqld" \
    --defaults-file="$SNAP_COMMON/etc/my.cnf" \
    --basedir="$SNAP/usr" \
    --datadir="$SNAP_COMMON/data" \
    --socket=/tmp/mysql.sock \
    --pid-file="$SNAP_COMMON/data/mysqld.pid" \
    --log-error="$SNAP_COMMON/log/error.log"
