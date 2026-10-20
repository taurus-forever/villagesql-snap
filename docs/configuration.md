# Configuration

## snap set

Any server option can be set as a snap option. Changing one rewrites
`/var/snap/villagesql/common/etc/conf.d/00-snap.cnf` and restarts the
server. The option name is the `mysqld` name written with dashes (snap
option names cannot contain underscores): `key-cache-age-threshold=500`
becomes `key_cache_age_threshold = 500` under `[mysqld]`.

```shell
sudo snap set villagesql port=3307 bind-address=0.0.0.0
sudo snap set villagesql key-cache-age-threshold=500 innodb-buffer-pool-size=1G
sudo snap set villagesql sql-mode=STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION
sudo snap get villagesql
sudo snap unset villagesql key-cache-age-threshold   # back to the server default
```

Before the server is restarted the new file is checked with
`mysqld --validate-config`. An unknown option or a value `mysqld` does not
accept makes `snap set` fail with the server's error message and the
previous configuration stays:

```
$ sudo snap set villagesql sql-mode=BOGUS
error: cannot perform the following tasks:
- Run configure hook of "villagesql" snap (run hook "configure":
-----
mysqld rejects the new configuration, keeping the previous one:
... [ERROR] [MY-000077] [Server] ... Error while setting value 'BOGUS' to 'sql_mode'.
-----)
```

| Option | Default | Notes |
| --- | --- | --- |
| `port` | `3306` | 1 to 65535; also written to `[client]` so that the snap's clients use it |
| `bind-address` | `127.0.0.1` | `bind_address` |
| `max-connections` | server default (151) | positive integer |
| any other `mysqld` option | server default | checked by `mysqld --validate-config` |

Rules:

- A boolean is set with `ON`/`OFF` (or `true`/`false`, `1`/`0`):
  `snap set villagesql skip-name-resolve=ON`. An empty value
  (`skip-name-resolve=""`) renders the bare option name, which is the option
  file way of switching a flag on.
- Values containing quotes, backslashes, `#` or control characters are
  rejected, as are nested (`a.b=1`) and list (`'[1,2]'`) values. Put such
  settings in `conf.d` instead (see below).
- `datadir`, `basedir`, `socket`, `pid-file`, `log-error` and `veb-dir` are
  fixed by the snap and rejected.

## Everything else: conf.d

`my.cnf` ends with `!includedir /var/snap/villagesql/common/etc/conf.d`.
Drop a `<name>.cnf` file there and restart. Files are read in alphabetical
order, so `90-local.cnf` overrides `00-snap.cnf`:

```shell
sudo tee /var/snap/villagesql/common/etc/conf.d/90-local.cnf <<'EOT'
[mysqld]
init_connect = "SET NAMES 'utf8mb4'"
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
