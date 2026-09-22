# Configuration

## snap set

A few settings are exposed as snap options. Changing one rewrites
`/var/snap/villagesql/common/etc/conf.d/00-snap.cnf` and restarts the
server. Invalid values are rejected and the previous value is kept.

| Option | Default | MySQL variable |
| --- | --- | --- |
| `port` | `3306` | `port` (also written to `[client]`) |
| `bind-address` | `127.0.0.1` | `bind_address` |
| `max-connections` | server default (151) | `max_connections` |

```shell
sudo snap set villagesql port=3307 bind-address=0.0.0.0
sudo snap get villagesql
sudo snap unset villagesql max-connections
```

## Everything else: conf.d

`my.cnf` ends with `!includedir /var/snap/villagesql/common/etc/conf.d`.
Drop a `<name>.cnf` file there and restart. Files are read in alphabetical
order, so `90-local.cnf` overrides `00-snap.cnf`:

```shell
sudo tee /var/snap/villagesql/common/etc/conf.d/90-local.cnf <<'EOT'
[mysqld]
innodb_buffer_pool_size = 1G
mysqlx = ON
EOT
sudo snap restart villagesql
```

The data directory, socket, PID file and error log are fixed by the snap
and set on the `mysqld` command line; values for them in `conf.d` are
ignored. To move the data elsewhere, bind-mount a directory over
`/var/snap/villagesql/common/data` while the service is stopped (this is
what the `storage` spread test does).

The X Plugin (`mysqlx`, port 33060) is off by default.
