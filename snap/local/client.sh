#!/bin/bash
# Run a client tool (mysql, mysqladmin, ...) with the snap's my.cnf, so that
# it finds the server's socket without any options: `villagesql.mysql -uroot`.
set -eu
tool="$1"
shift
exec "$SNAP/usr/bin/$tool" --defaults-file="$SNAP_COMMON/etc/my.cnf" "$@"
