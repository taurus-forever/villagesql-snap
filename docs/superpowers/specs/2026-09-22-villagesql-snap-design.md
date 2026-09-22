# VillageSQL snap: design

Date: 2026-09-22. Status: approved.

## Goal

A strictly confined, core26-based snap of [VillageSQL](https://villagesql.com)
(MySQL 8.4 with the VillageSQL Extension Framework), built from source,
installable on every supported Ubuntu LTS, with VillageSQL extensions
deliverable as separate snaps through the content interface. The repository
follows the conventions of [postgresql-snap](https://github.com/canonical/postgresql-snap):
spread tests, `docs/`, tox lint, and the same CI workflows.

The work is a demonstrator. It is delivered in four steps, each ending in a
built snap and a passing spread run:

1. an installable, usable snap (daemon, clients, smoke and CLI tests);
2. configuration (`snap set` and `conf.d`);
3. in-place refresh with data preserved and a major-version guard;
4. extensions through plugs and slots, with two example extension snaps.

## Decisions

| Topic | Decision |
| --- | --- |
| Upstream source | `https://github.com/villagesql/villagesql-server.git`, tag `release/0.0.6` (MySQL 8.4.11 + VillageSQL 0.0.6). |
| Snap name / version | `villagesql`, version `8.4.11-0.0.6`, base `core26`, `confinement: strict`, `grade: stable`, platforms amd64 and arm64. |
| License | `Apache-2.0 AND GPL-2.0` (snap packaging is Apache-2.0, VillageSQL/MySQL are GPL-2.0). |
| Git | Branch `8.4/edge`, one branch per MySQL major track as in postgresql-snap. |
| Runtime user | `_daemon_` (`system-usernames: _daemon_: shared`), entered with `setpriv` as in postgresql-snap. |
| Root access | `root@localhost` uses the `auth_socket` plugin: `sudo villagesql.mysql` connects without a password; TCP access needs an explicitly created user. |
| Second demo extension | upstream `vsql-uuid`; fallback to the bundled `vsql_complex` example if `vsql-uuid` needs the unstable dev ABI. |

## Build

One `cmake` part, `villagesql`, builds the server from the tag with the
packages listed in upstream's `villagesql/bld_tools/setup_linux_build_env.sh`
as `build-packages`. CMake flags: `-DCMAKE_BUILD_TYPE=Release`,
`-DWITH_SSL=system`, `-DWITH_UNIT_TESTS=OFF`, `-DWITH_ROUTER=OFF`,
`-DINSTALL_LAYOUT=STANDALONE`, `-DCMAKE_INSTALL_PREFIX=/usr`, `-DVILLAGESQL_WERROR=OFF`
(GCC 15 on core26 otherwise turns warnings into errors), with the unused
`storage/ndb` subtree removed at pull time. `make install`
produces `bin/`, `lib/`, `lib/veb/` (bundled `vsql_simple` and `vsql_complex`
bundles), `share/` and the extension SDK (`include/villagesql`, `bin/villagesql_config`,
`lib/cmake/VillageSQLExtensionFramework`). Binaries are stripped in
`override-build`; `mysql-test` and docs are excluded with `prime` filters to
keep the snap small. Runtime libraries come from `stage-packages`
(`libaio1t64`, `libnuma1`, `libtirpc3t64`, `libssl3t64`, `util-linux` for `setpriv`).

A second part, `wrapper`, dumps `snap/local/` (shell wrappers and hooks
helpers) and creates the empty `extensions/` mount point for the content plug.
A third part, `snap-license`, stages `LICENSE` as `licenses/LICENSE-snap`.

## Runtime layout

| Path | Purpose |
| --- | --- |
| `$SNAP_COMMON/data` | MySQL data directory (`--datadir`), `_daemon_:root` mode 750 so that hooks running as root can still see inside (confined root has no `dac_override`). |
| `$SNAP_COMMON/etc/my.cnf` | Main config, generated once by the install hook; ends with `!includedir $SNAP_COMMON/etc/conf.d`. |
| `$SNAP_COMMON/etc/conf.d/00-snap.cnf` | Written by the configure hook from `snap set` options. Not user editable. |
| `$SNAP_COMMON/etc/conf.d/*.cnf` | Free-form administrator config. |
| (`mysqld` command line) | `veb_dir=$SNAP_COMMON/veb` is passed by `mysqld.sh`, so `conf.d` stays fully owned by root and the administrator. |
| `$SNAP_COMMON/log/error.log` | Server error log. |
| `$SNAP_COMMON/veb/` | Effective `veb_dir`, regenerated on every daemon start (see Extensions). |
| `$SNAP_COMMON/.snap-data-major` | The MySQL major (`8.4`) that last ran on `data/`; read by the post-refresh hook. |
| `/tmp/mysql.sock` (snap-private `/tmp`) | Unix socket. Clients default to it through `my.cnf` `[client]`. |

`mysqld` is started by `snap/local/mysqld.sh` as `_daemon_` with
`--defaults-file=$SNAP_COMMON/etc/my.cnf`, `--basedir=$SNAP`,
`--datadir=$SNAP_COMMON/data`, `--socket=/tmp/mysql.sock`,
`--pid-file` in the data directory, `--log-error` under `$SNAP_COMMON/log`,
and `--veb-dir=$SNAP_COMMON/veb`. All paths are passed by the wrapper, so
`my.cnf` contains only settings (it ships `bind_address = 127.0.0.1` and
`mysqlx = OFF` as defaults).

### Apps

| App | Command | Plugs |
| --- | --- | --- |
| `villagesql` (daemon, simple) | `mysqld.sh` via the `extensions-env.sh` command chain | `network`, `network-bind`, optional `process-control` (silences InnoDB setpriority seccomp audit lines) |
| `mysql` | `mysql` client through a wrapper that adds `--defaults-file` | `network` |
| `mysqladmin`, `mysqldump`, `mysqlbinlog`, `mysqlcheck` | the upstream binaries through the same wrapper | `network` |
| `config` | `villagesql_config` (SDK flags for extension builders) | none |
| `extensions` | `extensions.sh list` (see Extensions) | `network` |

Wrappers run the client binaries as the calling user; `sudo` is only needed
for `root@localhost` (auth_socket) and for the daemon's helper scripts.

### Install hook

1. Create `$SNAP_COMMON/{data,etc/conf.d,log,veb}` with `umask` (never
   `chmod`: core26's coreutils `chmod` is rejected by snapd's seccomp
   filter), chown `data`, `log` and `veb` to `_daemon_`.
2. Write `my.cnf` from `$SNAP/default-config/my.cnf`.
3. Run `mysqld --initialize-insecure --init-file=$SNAP/default-config/init.sql`
   as `_daemon_`; `init.sql` installs the `auth_socket` plugin and runs
   `ALTER USER root@localhost IDENTIFIED WITH auth_socket;` during the
   initialisation, so no temporary server is started (a hook without
   `network-bind` cannot `listen()` anyway).
4. Write `.snap-data-major` = `8.4`.

## Configuration (step 2)

`snap set villagesql <key>=<value>` for a small, documented set:

| Key | Default | Maps to |
| --- | --- | --- |
| `port` | `3306` | `port` |
| `bind-address` | `127.0.0.1` | `bind_address` |
| `max-connections` | unset (server default 151) | `max_connections` |

The configure hook validates values (port is an integer 1..65535, bind
address is non-empty and shell-safe, max-connections is a positive integer),
writes `conf.d/00-snap.cnf`, and restarts the daemon if it is active. Invalid
values fail the hook so `snap set` reports the error and the previous value
stays. Anything else goes in the administrator's own `conf.d/*.cnf`,
followed by `sudo snap restart villagesql`.

## In-place refresh (step 3)

- The daemon wrapper writes `.snap-data-major` after every successful start.
- The `post-refresh` hook compares that file with the major of the new
  revision (`SNAP_VERSION` up to the second dot). On a mismatch, or if the
  data directory is missing or has no `mysql/` schema, it exits non-zero so
  snapd rolls back, with a message explaining the dump/restore path.
- Minor-version upgrades of the data dictionary are done by `mysqld` itself
  at startup (`--upgrade=AUTO`, the default).
- No `epoch`, for the same reason postgresql-snap avoids it.

## Extensions (step 4)

### Server side

`mysqld` reads bundles from exactly one directory (`veb_dir`), so the snap
assembles that directory at every daemon start. `snap/local/extensions-env.sh`
is the first link of the daemon's `command-chain` and, as `_daemon_`:

1. Empties `$SNAP_COMMON/veb/`.
2. Copies every `$SNAP/usr/lib/veb/*.veb` (built-in bundles) into it.
3. For each `$SNAP/extensions/<dir>/` in sorted order (connected providers),
   copies every `veb/*.veb` whose file name is not present yet; a clash is
   recorded and skipped, so built-ins win over providers and earlier
   providers win over later ones.
4. Writes `$SNAP_COMMON/veb/INVENTORY` with one line per bundle:
   `<file>\t<origin>\t<version>`, where origin is `built-in` or
   `snap:<dir>` and version comes from the provider's `manifest`
   (`VERSION=` line) or the bundle's own `manifest.json`.

`mysqld.sh` passes `--veb-dir=$SNAP_COMMON/veb` on the command line.

Failures never block the daemon: on error the script logs a warning and
`exec`s the daemon anyway.

The plug:

```yaml
plugs:
  extensions:
    interface: content
    content: villagesql-8.4-extensions
    target: $SNAP/extensions
```

`villagesql.extensions list` prints the inventory joined with
`INFORMATION_SCHEMA.EXTENSIONS` over the socket (as root, auth_socket):
name, version, origin, and whether it is installed. Installing remains an
explicit SQL step: `INSTALL EXTENSION <name>;`.

### Provider side

An extension snap exposes:

```yaml
slots:
  extensions:
    interface: content
    content: villagesql-8.4-extensions
    source:
      read:
        - $SNAP/<dir>
```

with `$SNAP/<dir>/veb/<name>.veb` and `$SNAP/<dir>/manifest`
(`VERSION=<x.y.z>`). The content label carries the MySQL major so a provider
built for another major can never be connected. Providers build against the
published SDK tarball (`villagesql-extension-sdk-0.0.6.tar.gz`), not against
a server build, so a provider build takes seconds.

Two providers live under `extensions/` in this repo, each its own snapcraft
project:

- `extensions/villagesql-hello`: written here in C++ with the v3 SDK,
  bundle `vsql_hello.veb` providing `hello(name)` (STRING, returns
  `Hello, <name>!`) and `reverse(str)` (STRING, deterministic).
- `extensions/villagesql-uuid`: packages `https://github.com/villagesql/vsql-uuid`
  (bundle `vsql_uuid.veb`, a custom `UUID` type). Fallback if it needs the dev
  ABI: package upstream's bundled `vsql_complex` example instead as
  `villagesql-complex`.

## Tests

`spread.yaml` mirrors postgresql-snap: craft backend, systems
`ubuntu-22.04`, `ubuntu-24.04`, `ubuntu-26.04`, `prepare-each` installs the
built snap `--dangerous --jailmode` and waits for the socket, `restore-each`
removes it with `--purge`.

| Test | Covers |
| --- | --- |
| `smoke` | version string, service active, every non-daemon app answers `--help`, no AppArmor denials from the daemon. |
| `cli_mysql`, `cli_mysqladmin`, `cli_mysqldump`, `cli_mysqlbinlog`, `cli_mysqlcheck`, `cli_config` | one real use of each app. |
| `auth` | root over socket needs no password; root over TCP is refused; a created user works over TCP. |
| `config` | `snap set` port and bind-address take effect, invalid values are rejected, `conf.d` snippet is honoured. |
| `storage` | data directory bind-mounted elsewhere, data survives. |
| `refresh` | install the previous local build, create data, refresh to the current build, data readable and writable, service active. |
| `refresh_major_guard` | fake `.snap-data-major=9.7`, refresh is rolled back. |
| `extensions_builtin` | `INSTALL EXTENSION vsql_simple`, function works, inventory lists it as built-in, `UNINSTALL`. |
| `extension_snap_hello` | connect, inventory shows `snap:hello`, install, call functions, restart persists, disconnect removes it. |
| `extension_snap_uuid` | same for the UUID type, plus a name clash with a second copy of the provider to prove precedence. |

Also `tox -e lint` (yamllint on `snap/` and `extensions/*/snap/`) and
`tests/test_smoke.py` (pytest over the apps in `snapcraft.yaml`).

## Documentation

`README.md` (install, build, test, license and trademark), `docs/commands.md`,
`docs/configuration.md`, `docs/refresh.md`, `docs/extensions.md` (server
side and how to write a provider), `extensions/README.md`.

## Out of scope

Snap components, in-place major upgrades, MySQL 9.7 track, Rust extensions,
publishing to the Snap Store.
