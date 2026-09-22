# VillageSQL Snap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A strictly confined core26 snap of VillageSQL (MySQL 8.4 + extension framework) built from source, with `snap set` configuration, safe in-place refresh, and extensions delivered by separate snaps over the content interface, all covered by spread tests.

**Architecture:** One `cmake` part builds upstream tag `release/0.0.6` into `usr/`; small bash wrappers in `snap/local/` run `mysqld` as `_daemon_` and route clients to the snap's `my.cnf`. Hooks own the lifecycle (install initialises data and switches root to `auth_socket`; configure renders `snap set` options; post-refresh guards the MySQL major). A daemon `command-chain` script assembles the single `veb_dir` from built-in bundles and connected extension snaps. Two provider snaps under `extensions/` demonstrate the plug/slot contract.

**Tech Stack:** snapcraft 9 (core26, cmake/nil/dump plugins), bash, spread via `snapcraft test` (craft backend, Ubuntu 22.04/24.04/26.04), tox + yamllint, pytest, C++17 with the VillageSQL v3 SDK.

**Spec:** `docs/superpowers/specs/2026-09-22-villagesql-snap-design.md`

## Global Constraints

- Snap name `villagesql`, version `8.4.11-0.0.6`, `base: core26`, `confinement: strict`, `grade: stable`, platforms `amd64` and `arm64`.
- Upstream: `https://github.com/villagesql/villagesql-server.git` tag `release/0.0.6`; cmake flags `-DCMAKE_BUILD_TYPE=Release -DWITH_SSL=system -DWITH_UNIT_TESTS=OFF -DWITH_ROUTER=OFF -DINSTALL_LAYOUT=STANDALONE -DVSQL_PRE_RELEASE_VERSION=""`.
- License field `Apache-2.0 AND GPL-2.0`; repo `LICENSE` is Apache-2.0 (copy from `../../postgresql-snap/LICENSE`).
- Runtime user `_daemon_` (uid 584792), entered with `$SNAP/usr/bin/setpriv --clear-groups --reuid _daemon_ --regid root --`.
- Paths: data `$SNAP_COMMON/data`, config `$SNAP_COMMON/etc/my.cnf` + `conf.d/`, logs `$SNAP_COMMON/log`, bundles `$SNAP_COMMON/veb`, marker `$SNAP_COMMON/.snap-data-major`, socket `/tmp/mysql.sock`.
- `root@localhost` authenticates with `auth_socket`; default `bind-address` `127.0.0.1`, `port` `3306`, X plugin off.
- Content interface label `villagesql-8.4-extensions`; plug `extensions` targets `$SNAP/extensions`; providers expose `<dir>/veb/*.veb` and `<dir>/manifest` with `VERSION=`.
- Every spread test is a `spread/tests/<name>/task.yaml` with a `summary:` and an `execute:` block, as in postgresql-snap.
- Commit after every task with a message ending in `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Build commands run from the repo root: `snapcraft pack` (main snap), `snapcraft test -- craft:ubuntu-24.04:spread/tests/<name>` (one test on one system), `snapcraft test` (everything).

## File structure

| Path | Responsibility |
| --- | --- |
| `snap/snapcraft.yaml` | Build recipe, apps, plugs, hooks declaration. |
| `snap/local/mysqld.sh` | Daemon entry: writes the major marker, execs `mysqld` as `_daemon_` with all path options. |
| `snap/local/client.sh` | Runs a client tool with the snap's `my.cnf`. |
| `snap/local/extensions-env.sh` | Command-chain: assembles `$SNAP_COMMON/veb` + `INVENTORY`. |
| `snap/local/extensions.sh` | `villagesql.extensions list`. |
| `snap/local/default-config/my.cnf`, `init.sql` | Templates used by the install hook. |
| `snap/hooks/install`, `configure`, `post-refresh` | Lifecycle hooks. |
| `spread.yaml`, `spread/tests/*/task.yaml` | Integration tests. |
| `tox.ini`, `pyproject.toml`, `tests/test_smoke.py` | Lint and host-side smoke test. |
| `.github/**` | CI mirrored from postgresql-snap. |
| `README.md`, `SECURITY.md`, `docs/*.md` | Documentation. |
| `extensions/README.md`, `extensions/villagesql-hello/**`, `extensions/villagesql-uuid/**` | Provider snaps. |

---

## Step 1: an installable, usable snap

### Task 1: Build recipe, wrappers and install hook

**Files:**
- Create: `snap/snapcraft.yaml`, `snap/local/mysqld.sh`, `snap/local/client.sh`, `snap/local/default-config/my.cnf`, `snap/local/default-config/init.sql`, `snap/hooks/install`, `LICENSE`
- Delete: nothing (the template `snap/snapcraft.yaml` is replaced)

**Interfaces:**
- Produces: apps `villagesql.villagesql` (daemon), `villagesql.mysql`, `villagesql.mysqladmin`, `villagesql.mysqldump`, `villagesql.mysqlbinlog`, `villagesql.mysqlcheck`, `villagesql.config`; files `$SNAP/bin/mysqld.sh`, `$SNAP/bin/client.sh`, `$SNAP/default-config/{my.cnf,init.sql}`; `$SNAP_COMMON/.snap-data-major` containing `8.4`.

- [x] **Step 1: Copy the license**

```bash
cp ../../postgresql-snap/LICENSE LICENSE
```

- [x] **Step 2: Write `snap/snapcraft.yaml`**

```yaml
name: villagesql
base: core26
version: '8.4.11-0.0.6'
summary: VillageSQL (MySQL 8.4 with extensions) in a snap.
description: |
  VillageSQL Server for MySQL is an open-source, drop-in replacement for
  MySQL 8.4 that adds an extension framework: custom data types and
  functions are loaded at run time with INSTALL EXTENSION. This snap builds
  VillageSQL from source and lets extensions be shipped as separate snaps
  connected through the content interface.
title: VillageSQL
contact: https://matrix.to/#/#charmhub-data-platform:ubuntu.com
license: "Apache-2.0 AND GPL-2.0"
issues: https://github.com/taurus-forever/villagesql-snap/issues
source-code: https://github.com/taurus-forever/villagesql-snap
website: https://villagesql.com

platforms:
  amd64:
  arm64:
grade: stable
confinement: strict

system-usernames:
  _daemon_: shared

hooks:
  install:
    plugs:
      - network

apps:
  villagesql:
    command: bin/mysqld.sh
    daemon: simple
    plugs:
      - network
      - network-bind
  mysql:
    command: bin/client.sh mysql
    plugs:
      - network
      - home
  mysqladmin:
    command: bin/client.sh mysqladmin
    plugs:
      - network
  mysqldump:
    command: bin/client.sh mysqldump
    plugs:
      - network
      - home
  mysqlbinlog:
    command: bin/client.sh mysqlbinlog
    plugs:
      - network
      - home
  mysqlcheck:
    command: bin/client.sh mysqlcheck
    plugs:
      - network
  config:
    command: usr/bin/villagesql_config

parts:
  villagesql:
    plugin: cmake
    source: https://github.com/villagesql/villagesql-server.git
    source-tag: release/0.0.6
    source-depth: 1
    cmake-generator: Ninja
    cmake-parameters:
      - -DCMAKE_INSTALL_PREFIX=/usr
      - -DCMAKE_BUILD_TYPE=Release
      - -DWITH_SSL=system
      - -DWITH_UNIT_TESTS=OFF
      - -DWITH_ROUTER=OFF
      - -DINSTALL_LAYOUT=STANDALONE
      - -DVSQL_PRE_RELEASE_VERSION=
      - -DCOMPILATION_COMMENT=VillageSQL snap
      - -DCOMPILATION_COMMENT_SERVER=VillageSQL snap
    build-packages:
      - bison
      - build-essential
      - ccache
      - curl
      - g++
      - libaio-dev
      - libncurses-dev
      - libnuma-dev
      - libssl-dev
      - libtirpc-dev
      - libz-dev
      - pkg-config
      - unzip
      - zip
    stage-packages:
      - libaio1t64
      - libnuma1
      - libssl3t64
      - libtirpc3t64
      - util-linux
    override-build: |
      craftctl default
      # Strip the server and clients: RelWithDebInfo-sized binaries would
      # make the snap several hundred MB.
      find "$CRAFT_PART_INSTALL/usr/bin" "$CRAFT_PART_INSTALL/usr/lib" \
        -type f \( -name '*.so*' -o -perm -u+x \) -exec strip --strip-unneeded {} + 2>/dev/null || true
    prime:
      - -usr/mysql-test
      - -usr/docs
      - -usr/man
      - -usr/include
      - -usr/include-dev
      - -usr/lib/cmake
      - -usr/lib/*.a
      - -usr/bin/mysql_client_test
      - -usr/bin/mysqltest*
      - -usr/bin/mysqlxtest
      - -usr/bin/mysqld-debug
    organize:
      usr/LICENSE: licenses/LICENSE-villagesql
      usr/README: licenses/README-villagesql
  snap-license:
    plugin: dump
    source: .
    source-type: local
    stage:
      - licenses/LICENSE-snap
    organize:
      LICENSE: licenses/LICENSE-snap
  wrapper:
    plugin: dump
    source: snap/local
    organize:
      mysqld.sh: bin/mysqld.sh
      client.sh: bin/client.sh
```

Notes for the implementer: the `include`, `include-dev` and `lib/cmake` directories are the extension SDK; `villagesql.config` is kept (it prints SDK flags) but the headers are excluded to keep the snap small. If `-DCOMPILATION_COMMENT_SERVER` is rejected by cmake as unused it is harmless. If a `stage-packages` name does not exist on the 26.04 build base, replace it with the name `apt-cache search <lib>` reports there (for example `libtirpc3` instead of `libtirpc3t64`).

- [x] **Step 3: Write `snap/local/mysqld.sh`**

```bash
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

exec "$SNAP/usr/bin/setpriv" --clear-groups --reuid _daemon_ --regid root -- \
  "$SNAP/usr/bin/mysqld" \
    --defaults-file="$SNAP_COMMON/etc/my.cnf" \
    --basedir="$SNAP/usr" \
    --datadir="$SNAP_COMMON/data" \
    --socket=/tmp/mysql.sock \
    --pid-file="$SNAP_COMMON/mysqld.pid" \
    --log-error="$SNAP_COMMON/log/error.log"
```

- [x] **Step 4: Write `snap/local/client.sh`**

```bash
#!/bin/bash
# Run a client tool (mysql, mysqladmin, ...) with the snap's my.cnf, so that
# it finds the server's socket without any options: `villagesql.mysql -uroot`.
set -eu
tool="$1"
shift
exec "$SNAP/usr/bin/$tool" --defaults-file="$SNAP_COMMON/etc/my.cnf" "$@"
```

- [x] **Step 5: Write `snap/local/default-config/my.cnf`**

```ini
# VillageSQL snap: main configuration file.
#
# Generated once by the install hook and never overwritten on refresh.
# The data directory, socket, PID file and error log are set by the snap on
# the mysqld command line and cannot be changed here.
#   - `sudo snap set villagesql port=... bind-address=... max-connections=...`
#     writes conf.d/00-snap.cnf (see docs/configuration.md).
#   - Any other server setting goes in your own conf.d/<name>.cnf, followed
#     by `sudo snap restart villagesql`.
[client]
socket = /tmp/mysql.sock

[mysqld]
# The X Plugin (port 33060) is off by default; enable it in conf.d if needed.
mysqlx = OFF

!includedir @SNAP_COMMON@/etc/conf.d
```

- [x] **Step 6: Write `snap/local/default-config/init.sql`**

```sql
-- Run once by the install hook on a freshly initialised data directory.
-- root@localhost authenticates through the Unix socket peer credentials, so
-- `sudo villagesql.mysql -uroot` needs no password and root can never log in
-- over TCP. Same convention as Ubuntu's mysql-server package.
INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
```

- [x] **Step 7: Write `snap/hooks/install`**

```bash
#!/bin/bash
# $SNAP        = /snap/villagesql/<revision>   # read-only at run time
# $SNAP_COMMON = /var/snap/villagesql/common   # read-write, shared by revisions
set -euo pipefail

DAEMON_UID=584792  # _daemon_ (system-usernames)

as_daemon() {
  "$SNAP/usr/bin/setpriv" --clear-groups --reuid _daemon_ --regid root -- "$@"
}

mkdir -p "$SNAP_COMMON/data" "$SNAP_COMMON/etc/conf.d" "$SNAP_COMMON/log" "$SNAP_COMMON/veb"
if [ ! -f "$SNAP_COMMON/etc/my.cnf" ]; then
  sed "s#@SNAP_COMMON@#$SNAP_COMMON#g" "$SNAP/default-config/my.cnf" > "$SNAP_COMMON/etc/my.cnf"
fi
chmod 755 "$SNAP_COMMON/etc" "$SNAP_COMMON/etc/conf.d"
chmod 644 "$SNAP_COMMON/etc/my.cnf"
chown -R "$DAEMON_UID:root" "$SNAP_COMMON/data" "$SNAP_COMMON/log" "$SNAP_COMMON/veb"
chmod 700 "$SNAP_COMMON/data"

MYSQLD=(
  "$SNAP/usr/bin/mysqld"
  --defaults-file="$SNAP_COMMON/etc/my.cnf"
  --basedir="$SNAP/usr"
  --datadir="$SNAP_COMMON/data"
  --log-error="$SNAP_COMMON/log/error.log"
)

if [ ! -d "$SNAP_COMMON/data/mysql" ]; then
  echo "Initializing the VillageSQL data directory..."
  as_daemon "${MYSQLD[@]}" --initialize-insecure

  echo "Switching root@localhost to auth_socket..."
  as_daemon "${MYSQLD[@]}" --socket=/tmp/mysql.sock --skip-networking \
    --pid-file="$SNAP_COMMON/mysqld.pid" --daemonize
  for _ in $(seq 1 60); do
    [ -S /tmp/mysql.sock ] && break
    sleep 1
  done
  "$SNAP/usr/bin/mysql" --defaults-file="$SNAP_COMMON/etc/my.cnf" -uroot \
    < "$SNAP/default-config/init.sql"
  "$SNAP/usr/bin/mysqladmin" --defaults-file="$SNAP_COMMON/etc/my.cnf" -uroot shutdown
  for _ in $(seq 1 60); do
    [ -S /tmp/mysql.sock ] || break
    sleep 1
  done
fi

echo "$SNAP_VERSION" | cut -d. -f1-2 > "$SNAP_COMMON/.snap-data-major"
```

- [x] **Step 8: Make scripts executable and build**

```bash
chmod +x snap/local/*.sh snap/hooks/install
snapcraft pack 2>&1 | tee /tmp/claude-1000/-home-ubuntu-canonical-taurus-forever-villagesql-snap/8179fb0a-5131-4629-9c8b-d007a25e672d/scratchpad/pack.log
```

Expected: `Packed villagesql_8.4.11-0.0.6_amd64.snap`. The build takes about an hour; run it in the background and fix any cmake or stage-package error it reports. Common fixes: missing `-dev` package (add to `build-packages`), unused cmake variable warnings (ignore), a lint warning about an unused staged library (add a `prime` exclusion).

- [x] **Step 9: Install and verify manually**

```bash
sudo snap install ./villagesql_8.4.11-0.0.6_amd64.snap --dangerous --jailmode
sudo snap services villagesql            # villagesql.villagesql enabled active
sudo villagesql.mysql -uroot -e "SELECT VERSION(), CURRENT_USER(), @@datadir, @@socket;"
sudo villagesql.mysql -uroot -e "SELECT plugin FROM mysql.user WHERE user='root';"   # auth_socket
sudo villagesql.mysql -uroot -e "SHOW VARIABLES LIKE 'veb_dir';"
cat /var/snap/villagesql/common/.snap-data-major   # 8.4
sudo journalctl -k | grep 'apparmor="DENIED"' | grep snap.villagesql || echo "no denials"
```

Record the exact `VERSION()` string (expected `8.4.11-villagesql-0.0.6` or similar); the smoke test in Task 2 greps for it. If the install hook fails, read `sudo journalctl -u snapd` and `/var/snap/villagesql/common/log/error.log`.

- [x] **Step 10: Commit**

```bash
git add LICENSE snap/
git commit -m "Build VillageSQL 8.4.11-0.0.6 from source as a strict core26 snap

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 2: Spread harness, smoke, CLI and auth tests

**Files:**
- Create: `spread.yaml`, `spread/tests/smoke/task.yaml`, `spread/tests/auth/task.yaml`, `spread/tests/cli_mysql/task.yaml`, `spread/tests/cli_mysqladmin/task.yaml`, `spread/tests/cli_mysqldump/task.yaml`, `spread/tests/cli_mysqlbinlog/task.yaml`, `spread/tests/cli_mysqlcheck/task.yaml`, `spread/tests/cli_config/task.yaml`

**Interfaces:**
- Consumes: apps from Task 1; `$CRAFT_ARTIFACT` (the packed snap) and `$PROJECT_PATH` provided by `snapcraft test`.

- [x] **Step 1: Write `spread.yaml`**

```yaml
project: villagesql-snap

backends:
  craft:
    type: craft
    systems:
      - ubuntu-26.04
      - ubuntu-24.04
      - ubuntu-22.04

suites:
  spread/tests/:
    summary: General integration tests
    prepare-each: |
      snap install "$CRAFT_ARTIFACT" --dangerous --jailmode
      timeout 90 /bin/bash -c \
        "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do echo Waiting for villagesql...; sleep 1; done"
    restore-each: |
      snap remove villagesql --purge --terminate

exclude:
  - .git
  - parts
  - stage
  - prime
  - extensions/*/parts
  - extensions/*/stage
  - extensions/*/prime

kill-timeout: 1h
```

- [x] **Step 2: Write `spread/tests/smoke/task.yaml`**

```yaml
summary: VillageSQL snap smoke tests

execute: |
  echo "Running smoke test..."
  SNAP_VERSION=$(awk -F"'" '/^version/{print $2}' "${PROJECT_PATH}/snap/snapcraft.yaml")
  MYSQL_VERSION="${SNAP_VERSION%%-*}"
  VSQL_VERSION="${SNAP_VERSION#*-}"
  villagesql.mysql -uroot -N -e "SELECT VERSION();" | \
    grep -E "^${MYSQL_VERSION}-villagesql-${VSQL_VERSION}"
  snap services villagesql | grep -E "villagesql.villagesql\s+enabled\s+active"

  echo "Ensure the server runs as _daemon_ with the snap's paths..."
  villagesql.mysql -uroot -N -e "SELECT @@datadir;" | grep -x "/var/snap/villagesql/common/data/"
  villagesql.mysql -uroot -N -e "SELECT @@socket;" | grep -x "/tmp/mysql.sock"
  test "$(stat -c %u /var/snap/villagesql/common/data)" = "584792"
  grep -x "8.4" /var/snap/villagesql/common/.snap-data-major

  echo "Ensure no AppArmor denials from the daemon..."
  if journalctl -k | grep 'apparmor="DENIED"' | grep 'profile="snap.villagesql.villagesql"'; then
    echo "ERROR: AppArmor denials produced by the daemon (see above)" >&2
    exit 1
  fi

  echo "Ensure all tools have been shipped..."
  villagesql.mysql --help >/dev/null
  villagesql.mysqladmin --help >/dev/null
  villagesql.mysqldump --help >/dev/null
  villagesql.mysqlbinlog --help >/dev/null
  villagesql.mysqlcheck --help >/dev/null
  villagesql.config --help >/dev/null
```

Adjust the `VERSION()` grep to the string recorded in Task 1 step 9 if it differs.

- [x] **Step 3: Write `spread/tests/auth/task.yaml`**

```yaml
summary: root uses auth_socket; TCP needs a real account

execute: |
  echo "root over the socket needs no password..."
  villagesql.mysql -uroot -N -e "SELECT CURRENT_USER();" | grep -x "root@localhost"
  villagesql.mysql -uroot -N -e "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" | grep -x auth_socket

  echo "root over TCP is refused (auth_socket has no peer credentials)..."
  if villagesql.mysql -uroot -h127.0.0.1 -e "SELECT 1;" 2>/dev/null; then
    echo "ERROR: root logged in over TCP" >&2
    exit 1
  fi

  echo "A created account works over TCP on 127.0.0.1..."
  villagesql.mysql -uroot -e "
    CREATE USER 'spread'@'127.0.0.1' IDENTIFIED BY 'spreadpass';
    GRANT ALL PRIVILEGES ON *.* TO 'spread'@'127.0.0.1';
  "
  villagesql.mysql -uspread -pspreadpass -h127.0.0.1 -N -e "SELECT CURRENT_USER();" | grep -x "spread@127.0.0.1"

  echo "Server is bound to localhost only by default..."
  villagesql.mysql -uroot -N -e "SELECT @@bind_address;" | grep -x "127.0.0.1"
  ss -ltn | grep -E "127.0.0.1:3306\s"
  ! ss -ltn | grep -E "0.0.0.0:3306\s"
```

- [x] **Step 4: Write the CLI tests**

`spread/tests/cli_mysql/task.yaml`:

```yaml
summary: villagesql.mysql CLI tests

execute: |
  echo "Testing mysql..."
  villagesql.mysql -uroot -e "SELECT NOW();"
  villagesql.mysql -uroot -e "
    CREATE DATABASE spread;
    CREATE TABLE spread.test (id INT AUTO_INCREMENT PRIMARY KEY, name TEXT);
    INSERT INTO spread.test (name) VALUES ('test1'), ('test2');
    DELETE FROM spread.test WHERE name='test1';
  "
  villagesql.mysql -uroot -N -e "SELECT name FROM spread.test;" | grep -x test2
  ! villagesql.mysql -uroot -N -e "SELECT name FROM spread.test;" | grep -x test1
```

`spread/tests/cli_mysqladmin/task.yaml`:

```yaml
summary: villagesql.mysqladmin CLI tests

execute: |
  echo "Testing mysqladmin..."
  villagesql.mysqladmin -uroot ping | grep -x "mysqld is alive"
  villagesql.mysqladmin -uroot status | grep -E "^Uptime: "
  villagesql.mysqladmin -uroot version | grep -E "^Server version"
  villagesql.mysqladmin -uroot variables | grep -E "\|\s+port\s+\|\s+3306\s+\|"
  villagesql.mysqladmin -uroot create spreadadmin
  villagesql.mysql -uroot -N -e "SHOW DATABASES;" | grep -x spreadadmin
  villagesql.mysqladmin -uroot --force drop spreadadmin
  ! villagesql.mysql -uroot -N -e "SHOW DATABASES;" | grep -x spreadadmin
```

`spread/tests/cli_mysqldump/task.yaml`:

```yaml
summary: villagesql.mysqldump CLI tests

execute: |
  echo "Creating test data..."
  villagesql.mysql -uroot -e "
    CREATE DATABASE dumpsrc;
    CREATE TABLE dumpsrc.t (id INT PRIMARY KEY, v VARCHAR(20));
    INSERT INTO dumpsrc.t VALUES (1, 'one'), (2, 'two');
  "
  echo "Dumping and restoring into another database..."
  villagesql.mysqldump -uroot dumpsrc > /root/dump.sql
  grep -q "INSERT INTO \`t\`" /root/dump.sql
  villagesql.mysql -uroot -e "CREATE DATABASE dumpdst;"
  villagesql.mysql -uroot dumpdst < /root/dump.sql
  villagesql.mysql -uroot -N -e "SELECT v FROM dumpdst.t WHERE id=2;" | grep -x two
```

`spread/tests/cli_mysqlbinlog/task.yaml`:

```yaml
summary: villagesql.mysqlbinlog CLI tests

execute: |
  echo "Binary logging is on by default in MySQL 8.4..."
  villagesql.mysql -uroot -N -e "SELECT @@log_bin;" | grep -x 1
  villagesql.mysql -uroot -e "CREATE DATABASE binlogtest; CREATE TABLE binlogtest.t (id INT); INSERT INTO binlogtest.t VALUES (42);"
  villagesql.mysql -uroot -e "FLUSH BINARY LOGS;"
  FIRST=$(villagesql.mysql -uroot -N -e "SHOW BINARY LOGS;" | head -1 | awk '{print $1}')
  echo "Reading $FIRST with mysqlbinlog..."
  villagesql.mysqlbinlog --verbose "/var/snap/villagesql/common/data/$FIRST" | grep -i "binlogtest"
```

`spread/tests/cli_mysqlcheck/task.yaml`:

```yaml
summary: villagesql.mysqlcheck CLI tests

execute: |
  villagesql.mysql -uroot -e "CREATE DATABASE checkme; CREATE TABLE checkme.t (id INT PRIMARY KEY); INSERT INTO checkme.t VALUES (1);"
  villagesql.mysqlcheck -uroot checkme | grep -E "^checkme.t\s+OK"
  villagesql.mysqlcheck -uroot --all-databases --check | grep -E "^mysql.user\s+OK"
```

`spread/tests/cli_config/task.yaml`:

```yaml
summary: villagesql.config (extension SDK configuration script) tests

execute: |
  villagesql.config --version | grep -E "0\.0\.6"
  villagesql.config --cflags | grep -E "\-I"
  villagesql.config --prefix | grep -E "^/snap/villagesql/"
```

If `villagesql_config --prefix` or `--cflags` is not a supported option (check `villagesql.config --help`), replace those lines with the options it does support.

- [x] **Step 5: Run the tests on one system**

```bash
snapcraft test -- craft:ubuntu-24.04:spread/tests/smoke craft:ubuntu-24.04:spread/tests/auth
snapcraft test -- 'craft:ubuntu-24.04:spread/tests/cli_*'
```

Expected: every task prints `Successful tasks: N`. On a failure, `snapcraft test --debug -- craft:ubuntu-24.04:spread/tests/<name>` opens a shell in the test VM.

- [x] **Step 6: Commit**

```bash
git add spread.yaml spread/
git commit -m "Add spread harness with smoke, auth and CLI tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 3: Docs, lint, host smoke test and CI

**Files:**
- Create: `README.md`, `SECURITY.md`, `docs/commands.md`, `tox.ini`, `pyproject.toml`, `poetry.lock`, `tests/test_smoke.py`, `.github/workflows/ci.yaml`, `.github/workflows/release.yaml`, `.github/CODEOWNERS`, `.github/zizmor.yaml`, `.github/actionlint.yaml`, `.github/renovate.json5`, `.github/ISSUE_TEMPLATE/bug_report.md`

- [x] **Step 1: Copy repo metadata from postgresql-snap and adapt**

```bash
PG=../../postgresql-snap
mkdir -p .github/workflows .github/ISSUE_TEMPLATE tests
cp $PG/.github/zizmor.yaml $PG/.github/actionlint.yaml .github/
cp $PG/.github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/
cp $PG/tox.ini $PG/pyproject.toml $PG/poetry.lock .
sed 's/postgresql-snap/villagesql-snap/g' $PG/SECURITY.md > SECURITY.md
sed 's#\* @canonical/data-postgresql#* @taurus-forever#' $PG/.github/CODEOWNERS > .github/CODEOWNERS
sed 's/"team:data-postgresql"/"taurus-forever"/' $PG/.github/renovate.json5 > .github/renovate.json5
sed -e "s/track: '18'/track: '8.4'/" $PG/.github/workflows/release.yaml > .github/workflows/release.yaml
cp $PG/.github/workflows/ci.yaml .github/workflows/ci.yaml
```

Then edit `.github/workflows/ci.yaml`: set the test job `timeout-minutes` to `60`, and insert before the `snapcraft test` line in the "Run tests" step:

```yaml
          # Extension snaps used by the extension_snap_* spread tests
          for ext in extensions/*/; do
            (cd "$ext" && sudo --user "$USER" --preserve-env --preserve-env=PATH -- env -- snapcraft pack)
          done
```

In `tox.ini` change the yamllint line to `poetry run yamllint --no-warnings ./snap/ ./extensions/*/snap/`.

- [x] **Step 2: Write `tests/test_smoke.py`**

```python
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.
"""Host-side smoke test: run with the snap installed (`tox -e smoke`)."""

import subprocess
import time

import yaml


def _snapcraft():
    with open("snap/snapcraft.yaml") as file:
        return yaml.safe_load(file)


def test_all_apps():
    snapcraft = _snapcraft()
    for app, data in snapcraft["apps"].items():
        if not data.get("daemon"):
            print(f"Running {snapcraft['name']}.{app} --help...")
            subprocess.check_output(["sudo", f"{snapcraft['name']}.{app}", "--help"])


def test_all_services():
    snapcraft = _snapcraft()
    for app, data in snapcraft["apps"].items():
        if data.get("daemon"):
            service = f"{snapcraft['name']}.{app}"
            subprocess.check_output(["sudo", "snap", "start", service])
            time.sleep(5)
            status = subprocess.check_output(["snap", "services", service]).decode()
            assert "active" in status


def test_version():
    snapcraft = _snapcraft()
    mysql_version, vsql_version = snapcraft["version"].split("-", 1)
    out = subprocess.check_output(
        ["sudo", f"{snapcraft['name']}.mysql", "-uroot", "-N", "-e", "SELECT VERSION();"]
    ).decode()
    assert out.startswith(f"{mysql_version}-villagesql-{vsql_version}")
```

- [x] **Step 3: Write `README.md`**

```markdown
# VillageSQL snap

This repository contains the packaging metadata for creating a
[snap](https://snapcraft.io/) of [VillageSQL](https://villagesql.com), the
extensible drop-in replacement for MySQL 8.4, built from the upstream sources.

For more information about using the snap, including commands, configuration,
refresh and extensions, see the [`docs/`](/docs/) folder.

## Install the snap

```shell
sudo snap install villagesql
sudo villagesql.mysql -uroot
```

`root@localhost` authenticates through the Unix socket (`auth_socket`), so
`sudo` is all that is needed locally and root can never log in over TCP.
Create ordinary accounts for applications:

```shell
sudo villagesql.mysql -uroot -e "CREATE USER app@'%' IDENTIFIED BY 'secret'; GRANT ALL ON app.* TO app@'%';"
```

## Build the snap

Install and configure prerequisites:

```bash
sudo snap install snapcraft --classic
sudo snap install lxd
sudo lxd init --auto
```

Build (compiling MySQL takes about an hour on 12 cores) and install with the
`--dangerous` flag to keep strict confinement (see snap
[installation modes](https://snapcraft.io/docs/install-modes)):

```bash
snapcraft pack
sudo snap install ./villagesql_*.snap --dangerous --jailmode
```

## Test the snap

[Spread](https://github.com/canonical/spread) tests run through snapcraft on
Ubuntu 22.04, 24.04 and 26.04:

```bash
snapcraft test                                            # run all tests on all systems
ls -la spread/tests/                                      # list all tests
snapcraft test -- craft:ubuntu-24.04:spread/tests/smoke   # one test on one system
snapcraft test --debug                                    # open a shell in a failed test
tox run -e lint                                           # yamllint
```

The `extension_snap_*` tests expect the example extension snaps to be packed
next to their `snap/` directories, see [`extensions/`](/extensions/).

## License and trademark

The VillageSQL snap packaging is free software, distributed under the
[Apache Software License, version 2.0](LICENSE). It builds, installs and
depends on [VillageSQL Server](https://github.com/villagesql/villagesql-server)
and MySQL, which are licensed under the GNU General Public License, version 2.

MySQL is a trademark of Oracle Corporation. VillageSQL is a trademark of its
respective owners. This snap is not sponsored, endorsed, or affiliated with
either.
```

- [x] **Step 4: Write `docs/commands.md`**

```markdown
# Commands

The [VillageSQL snap](https://snapcraft.io/villagesql) ships the server as a
service and the standard MySQL client tools, pre-configured to talk to it
over the snap's Unix socket.

## Service

* `villagesql.villagesql` - the server (`mysqld`), started at install time.

```shell
sudo snap services villagesql
sudo snap restart villagesql
sudo snap logs villagesql          # snapd's view; the error log is below
sudo tail /var/snap/villagesql/common/log/error.log
```

## Clients

* [villagesql.mysql](https://dev.mysql.com/doc/refman/8.4/en/mysql.html) - interactive terminal.
* [villagesql.mysqladmin](https://dev.mysql.com/doc/refman/8.4/en/mysqladmin.html) - ping, status, create/drop databases.
* [villagesql.mysqldump](https://dev.mysql.com/doc/refman/8.4/en/mysqldump.html) - logical backups.
* [villagesql.mysqlbinlog](https://dev.mysql.com/doc/refman/8.4/en/mysqlbinlog.html) - read binary logs (in `/var/snap/villagesql/common/data/`).
* [villagesql.mysqlcheck](https://dev.mysql.com/doc/refman/8.4/en/mysqlcheck.html) - check, repair, analyze tables.
* `villagesql.config` - `villagesql_config`, compiler flags for building extensions against this snap's SDK version.
* `villagesql.extensions` - list extension bundles and where they come from (see [extensions.md](extensions.md)).

<details><summary>Examples</summary>

```shell
> sudo villagesql.mysql -uroot -e "SELECT VERSION();"
+-------------------------+
| VERSION()               |
+-------------------------+
| 8.4.11-villagesql-0.0.6 |
+-------------------------+

> sudo villagesql.mysqladmin -uroot ping
mysqld is alive

> sudo villagesql.mysqldump -uroot --all-databases > all.sql
```
</details>

## Paths

| Path | Content |
| --- | --- |
| `/var/snap/villagesql/common/data` | data directory (owned by `_daemon_`) |
| `/var/snap/villagesql/common/etc/my.cnf` | main configuration, includes `conf.d/*.cnf` |
| `/var/snap/villagesql/common/log/error.log` | server error log |
| `/tmp/mysql.sock` (inside the snap) | Unix socket; clients use it by default |
```

- [x] **Step 5: Lint and run the host smoke test**

```bash
tox run -e lint
tox run -e smoke      # requires the snap from Task 1 to be installed
```

Expected: both pass. `poetry check --lock` may complain if `poetry.lock` does not match: run `poetry lock` once.

- [x] **Step 6: Commit**

```bash
git add README.md SECURITY.md docs/commands.md tox.ini pyproject.toml poetry.lock tests/ .github/
git commit -m "Add docs, lint, host smoke test and CI workflows

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

**Step 1 checkpoint:** show the user the snap file, `snap services`, a `SELECT VERSION()` and the spread summary.

---

## Step 2: configuration

### Task 4: `snap set` through a configure hook

**Files:**
- Create: `snap/hooks/configure`, `spread/tests/config/task.yaml`, `docs/configuration.md`
- Modify: `snap/snapcraft.yaml` (declare the hook), `README.md` (one line pointing at configuration.md)

**Interfaces:**
- Produces: `snap set villagesql port=<int> bind-address=<addr> max-connections=<int>` rendered into `$SNAP_COMMON/etc/conf.d/00-snap.cnf` with `[mysqld]` `port`, `bind_address`, `max_connections` and `[client]` `port`.

- [x] **Step 1: Write `snap/hooks/configure`**

```bash
#!/bin/bash
# Render `snap set villagesql <key>=<value>` into conf.d/00-snap.cnf and
# restart the server when it is running. Runs after the install hook too,
# so the file exists before the first start. Unknown keys are ignored.
set -euo pipefail

OUT="$SNAP_COMMON/etc/conf.d/00-snap.cnf"

get() { snapctl get "$1" 2>/dev/null || true; }

port="$(get port)";           port="${port:-3306}"
bind="$(get bind-address)";   bind="${bind:-127.0.0.1}"
maxc="$(get max-connections)"

case "$port" in
  ''|*[!0-9]*) echo "port must be an integer between 1 and 65535, got '$port'" >&2; exit 1 ;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo "port must be an integer between 1 and 65535, got '$port'" >&2
  exit 1
fi
case "$bind" in
  ''|*[!A-Za-z0-9.:,*_-]*) echo "bind-address contains unsupported characters: '$bind'" >&2; exit 1 ;;
esac
if [ -n "$maxc" ]; then
  case "$maxc" in
    *[!0-9]*|0) echo "max-connections must be a positive integer, got '$maxc'" >&2; exit 1 ;;
  esac
fi

# Persist the effective defaults so that `snap get villagesql` shows them.
snapctl set port="$port" bind-address="$bind"

{
  echo "# Generated by the villagesql snap from 'snap set villagesql ...'."
  echo "# Do not edit: put other settings in conf.d/<name>.cnf."
  echo "[client]"
  echo "port = $port"
  echo
  echo "[mysqld]"
  echo "port = $port"
  echo "bind_address = $bind"
  if [ -n "$maxc" ]; then
    echo "max_connections = $maxc"
  fi
} > "$OUT.tmp"
chmod 644 "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"

if snapctl services villagesql.villagesql 2>/dev/null | grep -qE "\sactive\s*$"; then
  snapctl restart villagesql.villagesql
fi
```

- [x] **Step 2: Declare the hook in `snap/snapcraft.yaml`**

Under `hooks:` add:

```yaml
  configure: {}
```

and `chmod +x snap/hooks/configure`.

- [x] **Step 3: Write `spread/tests/config/task.yaml`**

```yaml
summary: snap set options and conf.d snippets reach the server

execute: |
  wait_for_port() {
    timeout 90 /bin/bash -c \
      "until villagesql.mysql -uroot -N -e 'SELECT @@port;' 2>/dev/null | grep -qx $1; do sleep 1; done"
  }

  echo "Defaults are visible in snap get..."
  snap get villagesql port | grep -x 3306
  snap get villagesql bind-address | grep -x 127.0.0.1
  cat /var/snap/villagesql/common/etc/conf.d/00-snap.cnf

  echo "Changing port and bind-address restarts the server with the new values..."
  snap set villagesql port=3307 bind-address=0.0.0.0
  wait_for_port 3307
  villagesql.mysql -uroot -N -e "SELECT @@bind_address;" | grep -x "0.0.0.0"
  ss -ltn | grep -E "0.0.0.0:3307\s"
  villagesql.mysql -uroot -N -e "SELECT @@max_connections;" | grep -x 151

  echo "Invalid values are rejected and the old value stays..."
  ! snap set villagesql port=abc
  ! snap set villagesql port=70000
  ! snap set villagesql max-connections=0
  ! snap set villagesql bind-address='127.0.0.1;rm -rf /'
  snap get villagesql port | grep -x 3307
  villagesql.mysql -uroot -N -e "SELECT @@port;" | grep -x 3307

  echo "max-connections is optional and can be unset again..."
  snap set villagesql max-connections=77
  timeout 90 /bin/bash -c \
    "until villagesql.mysql -uroot -N -e 'SELECT @@max_connections;' 2>/dev/null | grep -qx 77; do sleep 1; done"
  snap unset villagesql max-connections
  timeout 90 /bin/bash -c \
    "until villagesql.mysql -uroot -N -e 'SELECT @@max_connections;' 2>/dev/null | grep -qx 151; do sleep 1; done"

  echo "Administrator snippets in conf.d are honoured after a restart..."
  cat > /var/snap/villagesql/common/etc/conf.d/90-spread.cnf <<'CNF'
  [mysqld]
  max_connections = 99
  CNF
  snap restart villagesql
  timeout 90 /bin/bash -c \
    "until villagesql.mysql -uroot -N -e 'SELECT @@max_connections;' 2>/dev/null | grep -qx 99; do sleep 1; done"

  echo "Clients pick up the port from [client] when connecting over TCP..."
  villagesql.mysql -uroot -e "CREATE USER 'cfg'@'%' IDENTIFIED BY 'cfgpass';"
  villagesql.mysql -ucfg -pcfgpass -h127.0.0.1 -N -e "SELECT @@port;" | grep -x 3307

  echo "Config test completed."
```

- [x] **Step 4: Write `docs/configuration.md`**

```markdown
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
sudo tee /var/snap/villagesql/common/etc/conf.d/90-local.cnf <<'EOF'
[mysqld]
innodb_buffer_pool_size = 1G
mysqlx = ON
EOF
sudo snap restart villagesql
```

The data directory, socket, PID file and error log are fixed by the snap
and set on the `mysqld` command line; values for them in `conf.d` are
ignored. To move the data elsewhere, bind-mount a directory over
`/var/snap/villagesql/common/data` while the service is stopped (this is
what the `storage` spread test does).

The X Plugin (`mysqlx`, port 33060) is off by default.
```

- [x] **Step 5: Rebuild, run the config and smoke tests**

```bash
snapcraft pack     # only the wrapper/hook parts rebuild; cmake part is cached
snapcraft test -- craft:ubuntu-24.04:spread/tests/config craft:ubuntu-24.04:spread/tests/smoke
```

Expected: both successful.

- [x] **Step 6: Commit**

```bash
git add snap/hooks/configure snap/snapcraft.yaml spread/tests/config docs/configuration.md README.md
git commit -m "Add snap set configuration (port, bind-address, max-connections)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

**Step 2 checkpoint:** show `snap set` / `snap get` output and the config test result.

---

## Step 3: in-place refresh

### Task 5: post-refresh guard, refresh and storage tests

**Files:**
- Create: `snap/hooks/post-refresh`, `spread/tests/refresh/task.yaml`, `spread/tests/refresh_major_guard/task.yaml`, `spread/tests/storage/task.yaml`, `docs/refresh.md`
- Modify: `snap/snapcraft.yaml` (declare the hook)

**Interfaces:**
- Consumes: `$SNAP_COMMON/.snap-data-major` written by `mysqld.sh` and the install hook (Task 1).

- [x] **Step 1: Write `snap/hooks/post-refresh`**

```bash
#!/bin/sh
# Abort refreshes that would run a different MySQL major on the existing
# data directory. A non-zero exit makes snapd roll back to the previous
# revision. Minor upgrades (8.4.x -> 8.4.y) are handled by mysqld itself at
# start-up (--upgrade=AUTO). No epoch is used, for the same reason as in
# postgresql-snap: a future in-place major upgrade should not have to step
# through every intermediate major.
set -eu

datadir="$SNAP_COMMON/data"
marker="$SNAP_COMMON/.snap-data-major"
new="$(echo "$SNAP_VERSION" | cut -d. -f1-2)"

if [ ! -d "$datadir/mysql" ]; then
  echo "ERROR: No initialized data directory in $datadir. Refresh aborted, rolling back." >&2
  exit 1
fi

if [ ! -f "$marker" ]; then
  echo "ERROR: $marker not found, cannot tell which MySQL major the data belongs to. Refresh aborted, rolling back." >&2
  exit 1
fi

old="$(cat "$marker")"
if [ "$old" != "$new" ]; then
  echo "ERROR: Data in $datadir is from MySQL $old but this revision provides $new. \
In-place major upgrades are not supported: dump with villagesql.mysqldump, install the \
new track and restore. Refresh aborted, rolling back." >&2
  exit 1
fi
```

Declare it in `snap/snapcraft.yaml` under `hooks:` as `post-refresh: {}` and `chmod +x snap/hooks/post-refresh`.

- [x] **Step 2: Write `spread/tests/refresh/task.yaml`**

```yaml
summary: In-place refresh keeps data and the service running

execute: |
  wait_ready() {
    timeout 90 /bin/bash -c \
      "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do echo Waiting for villagesql...; sleep 1; done"
  }

  # Refresh FROM an older local build when one is provided as
  # spread/villagesql_*.snap, otherwise from the artifact itself (still a real
  # refresh for snapd: new revision, hooks, service stop/start).
  PREV="$(ls "${PROJECT_PATH}"/spread/villagesql_*.snap 2>/dev/null | head -1)"
  if [ -n "$PREV" ]; then
    echo "Reinstalling the previous build $PREV..."
    snap remove villagesql --purge --terminate
    snap install "$PREV" --dangerous --jailmode
    wait_ready
  fi
  REV_BEFORE="$(snap list villagesql | awk 'NR == 2 {print $3}')"

  echo "Creating test data..."
  villagesql.mysql -uroot -e "
    CREATE DATABASE refresh;
    CREATE TABLE refresh.t (id INT AUTO_INCREMENT PRIMARY KEY, name TEXT);
    INSERT INTO refresh.t (name) VALUES ('test1');
  "
  villagesql.mysql -uroot -e "CREATE USER 'keep'@'%' IDENTIFIED BY 'keeppass';"

  echo "Refreshing to the current build..."
  if ! snap install "$CRAFT_ARTIFACT" --dangerous --jailmode > /tmp/refresh.log 2>&1; then
    cat /tmp/refresh.log
    echo "ERROR: refresh failed" >&2
    exit 1
  fi
  grep -E "villagesql [0-9.]+-[0-9.]+ installed" /tmp/refresh.log
  REV_AFTER="$(snap list villagesql | awk 'NR == 2 {print $3}')"
  test "$REV_BEFORE" != "$REV_AFTER"
  wait_ready
  snap services villagesql | grep -E "villagesql.villagesql\s+enabled\s+active"

  echo "Ensure data, accounts and config survived..."
  villagesql.mysql -uroot -N -e "SELECT name FROM refresh.t;" | grep -x test1
  villagesql.mysql -uroot -e "INSERT INTO refresh.t (name) VALUES ('test2');"
  villagesql.mysql -uroot -N -e "SELECT name FROM refresh.t;" | grep -x test2
  villagesql.mysql -uroot -N -e "SELECT plugin FROM mysql.user WHERE user='root';" | grep -x auth_socket
  villagesql.mysql -ukeep -pkeeppass -h127.0.0.1 -N -e "SELECT 1;" | grep -x 1
  grep -x "8.4" /var/snap/villagesql/common/.snap-data-major

  echo "Test refresh completed."
```

- [x] **Step 3: Write `spread/tests/refresh_major_guard/task.yaml`**

```yaml
summary: A refresh onto data from another MySQL major is rolled back

execute: |
  REV_BEFORE="$(snap list villagesql | awk 'NR == 2 {print $3}')"
  villagesql.mysql -uroot -e "CREATE DATABASE guard; CREATE TABLE guard.t (id INT); INSERT INTO guard.t VALUES (1);"

  echo "Pretending the data directory belongs to MySQL 9.7..."
  echo "9.7" > /var/snap/villagesql/common/.snap-data-major

  echo "The refresh must fail and roll back..."
  if snap install "$CRAFT_ARTIFACT" --dangerous --jailmode > /tmp/refresh.log 2>&1; then
    cat /tmp/refresh.log
    echo "ERROR: refresh succeeded despite a major mismatch" >&2
    exit 1
  fi
  cat /tmp/refresh.log
  grep -q "Data in /var/snap/villagesql/common/data is from MySQL 9.7" /tmp/refresh.log
  REV_AFTER="$(snap list villagesql | awk 'NR == 2 {print $3}')"
  test "$REV_BEFORE" = "$REV_AFTER"

  echo "The previous revision is back and serving the data..."
  timeout 90 /bin/bash -c \
    "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do sleep 1; done"
  villagesql.mysql -uroot -N -e "SELECT id FROM guard.t;" | grep -x 1

  echo "Restoring the marker (mysqld.sh rewrites it on every start)..."
  grep -x "8.4" /var/snap/villagesql/common/.snap-data-major || echo "8.4" > /var/snap/villagesql/common/.snap-data-major
```

- [x] **Step 4: Write `spread/tests/storage/task.yaml`**

```yaml
summary: Data directory can live on external storage (bind mount)

execute: |
  echo "Creating test data..."
  villagesql.mysql -uroot -e "CREATE DATABASE storage; CREATE TABLE storage.t (id INT); INSERT INTO storage.t VALUES (7);"

  echo "Stop VillageSQL to move data..."
  snap stop villagesql.villagesql
  mkdir -p /srv/myvsqldata/data /srv/myvsqldata/log
  cp -a /var/snap/villagesql/common/data/. /srv/myvsqldata/data/
  cp -a /var/snap/villagesql/common/log/. /srv/myvsqldata/log/

  echo "Mount the storage inside the snap's common dir..."
  mount --bind /srv/myvsqldata/data /var/snap/villagesql/common/data
  mount --bind /srv/myvsqldata/log /var/snap/villagesql/common/log

  echo "Start VillageSQL..."
  snap start villagesql.villagesql
  timeout 90 /bin/bash -c \
    "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do sleep 1; done"
  villagesql.mysql -uroot -N -e "SELECT id FROM storage.t;" | grep -x 7
  villagesql.mysql -uroot -e "INSERT INTO storage.t VALUES (8);"
  test -n "$(ls /srv/myvsqldata/data/storage/)"

  echo "Cleaning mounts so the snap can be purged on restore..."
  snap stop villagesql.villagesql
  umount /var/snap/villagesql/common/data
  umount /var/snap/villagesql/common/log

  echo "Storage test completed."
```

- [x] **Step 5: Write `docs/refresh.md`**

```markdown
# Refresh (upgrades)

`snap refresh villagesql` stops the service, installs the new revision, runs
the snap's `post-refresh` hook and starts the service again. The data
directory lives in `/var/snap/villagesql/common`, which is shared by all
revisions, so data, accounts and configuration are kept.

## Minor versions (8.4.x to 8.4.y)

Handled in place: `mysqld` upgrades the data dictionary at start-up
(`--upgrade=AUTO`). Nothing to do.

## Major versions (for example 8.4 to 9.7)

Not done in place. The `post-refresh` hook compares the major recorded in
`/var/snap/villagesql/common/.snap-data-major` with the one the new revision
provides and aborts the refresh on a mismatch, so snapd rolls back to the
previous revision and the service keeps running on the old data. To move to
a new track, dump and restore:

```shell
sudo villagesql.mysqldump -uroot --all-databases --routines --events > all.sql
sudo snap remove --purge villagesql
sudo snap install villagesql --channel 9.7/stable
sudo villagesql.mysql -uroot < all.sql
```

## Rolling back

`sudo snap revert villagesql` returns to the previous revision. Because the
data dictionary may already have been upgraded by the newer minor, prefer a
dump taken before the refresh if the revert fails to start.
```

- [x] **Step 6: Rebuild and run the three tests**

```bash
snapcraft pack
snapcraft test -- craft:ubuntu-24.04:spread/tests/refresh craft:ubuntu-24.04:spread/tests/refresh_major_guard craft:ubuntu-24.04:spread/tests/storage
```

Expected: successful. If `snap install` of the same file does not create a new revision, check with `snap list villagesql` that the revision increments (x1 to x2); `--dangerous` installs always do.

- [x] **Step 7: Commit**

```bash
git add snap/hooks/post-refresh snap/snapcraft.yaml spread/tests/refresh spread/tests/refresh_major_guard spread/tests/storage docs/refresh.md
git commit -m "Guard refreshes across MySQL majors; add refresh and storage tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

**Step 3 checkpoint:** show the refresh log excerpt and the rollback message from the guard test.

---

## Step 4: extensions

### Task 6: Server side: content plug, veb assembly, inventory CLI

**Files:**
- Create: `snap/local/extensions-env.sh`, `snap/local/extensions.sh`, `spread/tests/extensions_builtin/task.yaml`, `docs/extensions.md`
- Modify: `snap/snapcraft.yaml` (plug, command-chain, `extensions` app, wrapper organize), `snap/local/mysqld.sh` (add `--veb-dir`)

**Interfaces:**
- Produces: `$SNAP_COMMON/veb/*.veb` (effective `veb_dir`), `$SNAP_COMMON/veb/INVENTORY` (`<file>\t<origin>\t<version>` lines, `#` comments), app `villagesql.extensions list`.
- Contract for providers (Tasks 7 and 8): `$SNAP/extensions/<dir>/veb/<name>.veb` and optional `$SNAP/extensions/<dir>/manifest` with `VERSION=<x.y.z>`.

- [x] **Step 1: Write `snap/local/extensions-env.sh`**

```bash
#!/bin/bash
# command-chain entry for the villagesql daemon (runs as root before mysqld.sh).
#
# mysqld reads extension bundles (.veb) from exactly one directory (veb_dir),
# so on every daemon start this assembles $SNAP_COMMON/veb from:
#   1. the bundles built into the snap: $SNAP/usr/lib/veb/*.veb
#   2. extension snaps connected to the `extensions` content plug:
#      $SNAP/extensions/<dir>/veb/*.veb, in sorted <dir> order
# The first source providing a bundle file name wins: built-ins over snaps,
# earlier snaps over later ones. INVENTORY records where each bundle comes
# from (shown by `villagesql.extensions list`). Failures never block the
# daemon: it starts with whatever the directory contains.
set -u

if [ "${1:-}" != "--as-daemon" ]; then
  if [ "$(id -u)" = "0" ]; then
    if ! "$SNAP/usr/bin/setpriv" --clear-groups --reuid _daemon_ --regid root -- "$0" --as-daemon; then
      echo "WARNING: extensions-env.sh: could not assemble $SNAP_COMMON/veb, starting anyway" >&2
    fi
  fi
  exec "$@"
fi

VEB_DIR="$SNAP_COMMON/veb"
BUILTIN="$SNAP/usr/lib/veb"
PLUG_ROOT="$SNAP/extensions"

declare -A origin_of
inventory=""

# version from a bundle's manifest.json ("version": "x.y.z")
veb_version() {
  tar -xOf "$1" manifest.json 2>/dev/null | \
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# add_dir <dir> <origin> <version-or-empty>
add_dir() {
  local dir="$1" origin="$2" dver="$3" f name ver
  for f in "$dir"/*.veb; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if [ -n "${origin_of[$name]:-}" ]; then
      inventory="$inventory
# $name from $origin ignored: already provided by ${origin_of[$name]}"
      continue
    fi
    ver="$dver"
    [ -n "$ver" ] || ver="$(veb_version "$f")"
    cp -f "$f" "$VEB_DIR/$name" && chmod 644 "$VEB_DIR/$name"
    origin_of[$name]="$origin"
    inventory="$inventory
$name	$origin	${ver:-unknown}"
  done
}

mkdir -p "$VEB_DIR"
rm -f "$VEB_DIR"/*.veb "$VEB_DIR/INVENTORY"

add_dir "$BUILTIN" built-in ""

for d in "$PLUG_ROOT"/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  ver=""
  [ -f "$d/manifest" ] && ver="$(sed -n 's/^VERSION=//p' "$d/manifest" | tail -1 | tr -cd 'A-Za-z0-9.+~:-')"
  add_dir "$d/veb" "snap:$(basename "$d")" "$ver"
done

{
  echo "# Generated by the villagesql snap on every daemon start. Do not edit."
  echo "# bundle<TAB>origin<TAB>version"
  printf '%s\n' "$inventory" | sed '/^$/d'
} > "$VEB_DIR/INVENTORY.tmp"
mv -f "$VEB_DIR/INVENTORY.tmp" "$VEB_DIR/INVENTORY"
```

- [x] **Step 2: Write `snap/local/extensions.sh`**

```bash
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
```

- [x] **Step 3: Wire it into the snap**

In `snap/local/mysqld.sh` add the option line `--veb-dir="$SNAP_COMMON/veb" \` after `--log-error=...` (keep the backslash continuation valid).

In `snap/snapcraft.yaml`:

```yaml
plugs:
  # Extensions shipped as separate snaps (see docs/extensions.md). Each
  # connected provider appears under $SNAP/extensions/<dir>/ with
  # veb/<name>.veb and an optional manifest (VERSION=x.y.z).
  extensions:
    interface: content
    content: villagesql-8.4-extensions
    target: $SNAP/extensions
```

change the daemon app to:

```yaml
  villagesql:
    command: bin/mysqld.sh
    command-chain:
      - bin/extensions-env.sh
    daemon: simple
    plugs:
      - network
      - network-bind
```

add the app:

```yaml
  extensions:
    command: bin/extensions.sh
    plugs:
      - network
```

and extend the `wrapper` part:

```yaml
  wrapper:
    plugin: dump
    source: snap/local
    override-build: |
      craftctl default
      install -d "$CRAFT_PART_INSTALL/extensions"  # content plug mount point
    organize:
      mysqld.sh: bin/mysqld.sh
      client.sh: bin/client.sh
      extensions-env.sh: bin/extensions-env.sh
      extensions.sh: bin/extensions.sh
```

`chmod +x snap/local/extensions-env.sh snap/local/extensions.sh`.

- [x] **Step 4: Write `spread/tests/extensions_builtin/task.yaml`**

```yaml
summary: Built-in extension bundles are visible, installable and listed

execute: |
  echo "veb_dir points at the assembled directory..."
  villagesql.mysql -uroot -N -e "SELECT @@veb_dir;" | grep -x "/var/snap/villagesql/common/veb/"
  ls -la /var/snap/villagesql/common/veb/
  cat /var/snap/villagesql/common/veb/INVENTORY
  test -f /var/snap/villagesql/common/veb/vsql_simple.veb
  grep -P "^vsql_simple\.veb\tbuilt-in\t0\.0\.1$" /var/snap/villagesql/common/veb/INVENTORY

  echo "Nothing installed yet..."
  villagesql.extensions list | grep -E "^vsql_simple\s+0\.0\.1\s+built-in\s+no$"

  echo "INSTALL EXTENSION works and the function is callable..."
  villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_simple;"
  villagesql.mysql -uroot -N -e "SELECT EXTENSION_NAME FROM INFORMATION_SCHEMA.EXTENSIONS;" | grep -x vsql_simple
  villagesql.mysql -uroot -N -e "SELECT rot13('hello');" | grep -x uryyb
  villagesql.extensions list | grep -E "^vsql_simple\s+0\.0\.1\s+built-in\s+yes$"

  echo "The installation survives a restart..."
  snap restart villagesql
  timeout 90 /bin/bash -c \
    "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do sleep 1; done"
  villagesql.mysql -uroot -N -e "SELECT rot13('hello');" | grep -x uryyb

  echo "UNINSTALL EXTENSION removes it..."
  villagesql.mysql -uroot -e "UNINSTALL EXTENSION vsql_simple;"
  ! villagesql.mysql -uroot -N -e "SELECT rot13('hello');" 2>/dev/null
  villagesql.extensions list | grep -E "^vsql_simple\s+0\.0\.1\s+built-in\s+no$"

  echo "Ensure no AppArmor denials from the daemon..."
  if journalctl -k | grep 'apparmor="DENIED"' | grep 'profile="snap.villagesql.villagesql"'; then
    echo "ERROR: AppArmor denials produced by the daemon (see above)" >&2
    exit 1
  fi
```

If the bundle's function is not `rot13` (check `tar -xOf vsql_simple.veb manifest.json` and the upstream `villagesql/examples/vsql-simple/src/extension.cc`), use one that exists.

- [x] **Step 5: Write `docs/extensions.md`**

```markdown
# Extensions

VillageSQL loads extensions (custom types and functions) at run time from
`.veb` bundles with `INSTALL EXTENSION <name>`. The snap provides bundles
from two sources and lists them with `villagesql.extensions list`.

## Built-in bundles

The upstream examples `vsql_simple` and `vsql_complex` ship inside the snap:

```shell
sudo villagesql.extensions list
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_simple;"
sudo villagesql.mysql -uroot -e "SELECT rot13('hello');"
sudo villagesql.mysql -uroot -e "UNINSTALL EXTENSION vsql_simple;"
```

## Extension snaps (content interface)

Any extension can be shipped as a *separate* snap that exposes its bundle
through the content interface. Connect it to the `extensions` plug and
restart VillageSQL:

```shell
sudo snap install villagesql-hello
sudo snap connect villagesql:extensions villagesql-hello:extensions
sudo snap restart villagesql
sudo villagesql.extensions list
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap');"
```

Snaps from the same publisher connect automatically. Disconnecting (or
removing) the provider and restarting the service removes its bundles; run
`UNINSTALL EXTENSION` first so the server does not keep a stale registration.
Two example providers live in [`extensions/`](/extensions/).

## How it works

`mysqld` reads bundles from exactly one directory (`veb_dir`), so on every
start of the `villagesql` service the snap rebuilds
`/var/snap/villagesql/common/veb` from:

1. the built-in bundles in `$SNAP/usr/lib/veb/`;
2. every connected provider, mounted read-only at `$SNAP/extensions/<dir>/`,
   in sorted `<dir>` order, taking `veb/*.veb` and the version from its
   `manifest` (`VERSION=x.y.z`).

The first source that provides a bundle file name wins: a built-in bundle
cannot be shadowed by a snap, and an earlier provider wins over a later one.
The result is recorded in `veb/INVENTORY` and shown by
`villagesql.extensions list` (`ORIGIN` is `built-in` or `snap:<dir>`).
`INSTALLED` needs root (it queries `INFORMATION_SCHEMA.EXTENSIONS` over the
socket).

## Writing a provider snap

A provider is a normal strict snap with a content slot whose label carries
the MySQL major, so a bundle built for another major can never be connected:

```yaml
slots:
  extensions:
    interface: content
    content: villagesql-8.4-extensions
    source:
      read:
        - $SNAP/<dir>
```

`$SNAP/<dir>/` must contain `veb/<name>.veb` (or `veb/<name>-<version>.veb`)
and may contain `manifest` with a `VERSION=` line. Build the bundle against
the published SDK tarball of the same VillageSQL version
(`villagesql-extension-sdk-0.0.6.tar.gz` from the upstream GitHub release):
no server build is needed, a provider builds in seconds. See
`extensions/villagesql-hello` for a from-scratch C++ extension and
`extensions/villagesql-uuid` for packaging an upstream extension repository.
```

- [x] **Step 6: Rebuild, run the builtin test and the smoke test**

```bash
snapcraft pack
snapcraft test -- craft:ubuntu-24.04:spread/tests/extensions_builtin craft:ubuntu-24.04:spread/tests/smoke
```

Expected: successful. Also update `spread/tests/smoke/task.yaml` to add `villagesql.extensions --help >/dev/null` to the tool list.

- [x] **Step 7: Commit**

```bash
git add snap/ spread/tests/extensions_builtin spread/tests/smoke docs/extensions.md
git commit -m "Assemble veb_dir from built-in bundles and extension snaps; add villagesql.extensions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 7: Provider snap `villagesql-hello` (C++ from scratch)

**Files:**
- Create: `extensions/README.md`, `extensions/villagesql-hello/snap/snapcraft.yaml`, `extensions/villagesql-hello/CMakeLists.txt`, `extensions/villagesql-hello/manifest.json`, `extensions/villagesql-hello/src/extension.cc`, `extensions/villagesql-hello/LICENSE` (copy of the repo LICENSE), `spread/tests/extension_snap_hello/task.yaml`

**Interfaces:**
- Consumes: provider contract from Task 6.
- Produces: snap `villagesql-hello` slot `extensions`, bundle `vsql_hello.veb` with SQL functions `hello(STRING) -> STRING` and `shout(STRING) -> STRING`.

- [x] **Step 1: Write `extensions/villagesql-hello/manifest.json`**

```json
{
  "name": "vsql_hello",
  "version": "1.0.0",
  "description": "Example VillageSQL extension shipped as a snap: hello() and shout()",
  "author": "Canonical",
  "license": "Apache-2.0"
}
```

- [x] **Step 2: Write `extensions/villagesql-hello/src/extension.cc`**

```cpp
// Example VillageSQL extension (v3 SDK) shipped as a separate snap.
//   SELECT hello('snap');  -- 'Hello, snap!'
//   SELECT shout('snap');  -- 'SNAP!'
#include <villagesql/vsql.h>

#include <algorithm>
#include <cctype>
#include <string>

using namespace vsql;

static void write_string(StringResult &out, const std::string &s, const char *what) {
  auto buf = out.buffer();
  if (s.size() > buf.size()) {
    out.error(what);
    return;
  }
  std::copy(s.begin(), s.end(), buf.data());
  out.set_length(s.size());
}

void hello_impl(StringArg name, StringResult out) {
  if (name.is_null()) {
    out.set_null();
    return;
  }
  write_string(out, "Hello, " + std::string(name.value()) + "!", "hello: name too long");
}

void shout_impl(StringArg input, StringResult out) {
  if (input.is_null()) {
    out.set_null();
    return;
  }
  std::string s(input.value());
  std::transform(s.begin(), s.end(), s.begin(),
                 [](unsigned char c) { return std::toupper(c); });
  write_string(out, s + "!", "shout: input too long");
}

VEF_GENERATE_ENTRY_POINTS(
    make_extension()
        .func(make_func<&hello_impl>("hello").returns(STRING).param(STRING).deterministic().build())
        .func(make_func<&shout_impl>("shout").returns(STRING).param(STRING).deterministic().build()))
```

If the SDK's `StringResult` API differs (check `sdk/include/villagesql/vsql/` headers: names like `buffer()`, `set_length()`, `set_null()`, `error()`), adapt to the header, not the other way round.

- [x] **Step 3: Write `extensions/villagesql-hello/CMakeLists.txt`**

```cmake
cmake_minimum_required(VERSION 3.18)
project(vsql_hello_extension)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(EXTENSION_NAME "vsql_hello")

# The SDK is found through CMAKE_PREFIX_PATH (the unpacked SDK tarball).
find_package(VillageSQLExtensionFramework REQUIRED)
include_directories(${VillageSQLExtensionFramework_INCLUDE_DIR})

add_library(extension SHARED src/extension.cc)
target_compile_options(extension PRIVATE -fPIC)

VEF_CREATE_VEB(
    NAME ${EXTENSION_NAME}
    LIBRARY_TARGET extension
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/manifest.json
)
```

- [x] **Step 4: Write `extensions/villagesql-hello/snap/snapcraft.yaml`**

```yaml
name: villagesql-hello
base: core26
version: '1.0.0'
summary: Example extension for the VillageSQL snap (content interface)
description: |
  Example of shipping a VillageSQL extension as a separate snap that plugs
  into the villagesql snap through the content interface:

    sudo snap install villagesql-hello
    sudo snap connect villagesql:extensions villagesql-hello:extensions
    sudo snap restart villagesql
    sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap');"

  Provides hello(str) and shout(str), written in C++ with the VillageSQL v3
  SDK and built against the published SDK tarball (no server build needed).
grade: devel
confinement: strict

platforms:
  amd64:
  arm64:

# Consumed by the villagesql snap's `extensions` plug. The content label
# carries the MySQL major: a provider built for another major can never be
# connected.
slots:
  extensions:
    interface: content
    content: villagesql-8.4-extensions
    source:
      read:
        - $SNAP/hello

parts:
  hello:
    plugin: nil
    source: .
    source-type: local
    build-packages:
      - build-essential
      - ca-certificates
      - cmake
      - curl
    override-build: |
      set -e
      SDK_VERSION=0.0.6
      SDK_URL="https://github.com/villagesql/villagesql-server/releases/download/release%2F${SDK_VERSION}/villagesql-extension-sdk-${SDK_VERSION}.tar.gz"
      rm -rf sdk build && mkdir -p sdk
      curl -fsSL "$SDK_URL" | tar xz -C sdk --strip-components=1
      cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$PWD/sdk"
      cmake --build build
      tar -tf build/vsql_hello.veb
      # Layout consumed by the villagesql snap, see docs/extensions.md
      OUT="$CRAFT_PART_INSTALL/hello"
      install -Dm644 build/vsql_hello.veb "$OUT/veb/vsql_hello.veb"
      printf 'VERSION=%s\n' "$CRAFT_PROJECT_VERSION" > "$OUT/manifest"
      install -Dm644 LICENSE "$OUT/licenses/LICENSE-villagesql-hello"
```

Copy the license: `cp LICENSE extensions/villagesql-hello/LICENSE`.

- [x] **Step 5: Write `extensions/README.md`**

```markdown
# Extension snaps

Examples of VillageSQL extensions shipped as *separate* snaps that plug into
the `villagesql` snap through the content interface (see
[docs/extensions.md](../docs/extensions.md)). Each directory is its own
snapcraft project and builds against the published extension SDK tarball, so
no server build is needed:

```shell
cd extensions/villagesql-hello
snapcraft pack
sudo snap install ./villagesql-hello_*.snap --dangerous
sudo snap connect villagesql:extensions villagesql-hello:extensions
sudo snap restart villagesql
sudo villagesql.extensions list
```

* `villagesql-hello`: a from-scratch C++ extension (`hello()`, `shout()`).
* `villagesql-uuid`: packages the upstream
  [vsql-uuid](https://github.com/villagesql/vsql-uuid) extension (a `UUID`
  type and generators such as `UUID_V7()`).

The spread tests `spread/tests/extension_snap_*` expect the packed snaps next
to their `snap/` directories.
```

- [x] **Step 6: Build the provider and try it by hand**

```bash
(cd extensions/villagesql-hello && snapcraft pack)
sudo snap install ./extensions/villagesql-hello/villagesql-hello_1.0.0_amd64.snap --dangerous
sudo snap connect villagesql:extensions villagesql-hello:extensions
sudo snap restart villagesql
sudo villagesql.extensions list
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap'), shout('snap');"
```

Expected: `Hello, snap!` and `SNAP!`. If `INSTALL EXTENSION` fails with a load error, read `/var/snap/villagesql/common/log/error.log`.

- [x] **Step 7: Write `spread/tests/extension_snap_hello/task.yaml`**

```yaml
summary: An extension shipped as a snap through the content interface

execute: |
  EXT="$(ls "${PROJECT_PATH}"/extensions/villagesql-hello/villagesql-hello_*.snap 2>/dev/null | head -1)"
  if [ -z "$EXT" ]; then
    echo "ERROR: need extensions/villagesql-hello/*.snap (snapcraft pack there)" >&2
    exit 1
  fi
  INV=/var/snap/villagesql/common/veb/INVENTORY
  MYSQL="villagesql.mysql -uroot -N"
  restart() {
    snap restart villagesql
    timeout 90 /bin/bash -c \
      "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do echo Waiting for villagesql...; sleep 1; done"
  }

  echo "Installing and connecting the extension snap (no auto-connect for --dangerous)..."
  snap install "$EXT" --dangerous
  snap connect villagesql:extensions villagesql-hello:extensions
  snap connections villagesql | grep -E "villagesql:extensions\s+villagesql-hello:extensions"
  # content mounts exist only inside the snap's mount namespace
  snap run --shell villagesql.mysql -c 'test -f "$SNAP/extensions/hello/veb/vsql_hello.veb"'
  restart
  cat "$INV"
  grep -P "^vsql_hello\.veb\tsnap:hello\t1\.0\.0$" "$INV"
  villagesql.extensions list | grep -E "^vsql_hello\s+1\.0\.0\s+snap:hello\s+no$"

  echo "Installing and using the extension..."
  $MYSQL -e "INSTALL EXTENSION vsql_hello;"
  $MYSQL -e "SELECT hello('snap');" | grep -x "Hello, snap!"
  $MYSQL -e "SELECT shout('snap');" | grep -x "SNAP!"
  $MYSQL -e "SELECT hello(NULL) IS NULL;" | grep -x 1
  villagesql.extensions list | grep -E "^vsql_hello\s+1\.0\.0\s+snap:hello\s+yes$"

  echo "It is still there after a restart..."
  restart
  $MYSQL -e "SELECT hello('again');" | grep -x "Hello, again!"

  echo "Disconnecting the extension snap: the bundle is gone after restart..."
  $MYSQL -e "UNINSTALL EXTENSION vsql_hello;"
  snap disconnect villagesql:extensions villagesql-hello:extensions
  snap run --shell villagesql.mysql -c 'test ! -e "$SNAP/extensions/hello"'
  restart
  ! grep -q vsql_hello "$INV"
  ! test -e /var/snap/villagesql/common/veb/vsql_hello.veb
  ! $MYSQL -e "INSTALL EXTENSION vsql_hello;" 2>/dev/null

  echo "Ensure no AppArmor denials from the daemon..."
  if journalctl -k | grep 'apparmor="DENIED"' | grep 'profile="snap.villagesql.villagesql"'; then
    echo "ERROR: AppArmor denials produced by the daemon (see above)" >&2
    exit 1
  fi

  echo "Extension snap test completed."

restore: |
  snap remove villagesql-hello 2>/dev/null || true
```

- [x] **Step 8: Run the test and commit**

```bash
snapcraft test -- craft:ubuntu-24.04:spread/tests/extension_snap_hello
git add extensions/README.md extensions/villagesql-hello spread/tests/extension_snap_hello
git commit -m "Add villagesql-hello: example extension snap built with the VillageSQL SDK

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 8: Provider snap `villagesql-uuid` (upstream extension) and precedence test

**Files:**
- Create: `extensions/villagesql-uuid/snap/snapcraft.yaml`, `spread/tests/extension_snap_uuid/task.yaml`

**Interfaces:**
- Produces: snap `villagesql-uuid` slot `extensions`, bundle `vsql_uuid.veb` (upstream tag `0.0.6`) providing the `UUID` type and `UUID_V4()`, `UUID_V7()`, `UUID_VERSION()`, `UUID_IS_VALID()`.

- [x] **Step 1: Write `extensions/villagesql-uuid/snap/snapcraft.yaml`**

```yaml
name: villagesql-uuid
base: core26
version: '0.0.6'
summary: vsql_uuid extension for the VillageSQL snap (content interface)
description: |
  Packages the upstream vsql-uuid extension (a UUID column type plus
  UUID_V1/V3/V4/V5/V6/V7 generators and helpers) as a separate snap that
  plugs into the villagesql snap through the content interface:

    sudo snap install villagesql-uuid
    sudo snap connect villagesql:extensions villagesql-uuid:extensions
    sudo snap restart villagesql
    sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_uuid; SELECT UUID_V7();"
grade: devel
confinement: strict

platforms:
  amd64:
  arm64:

slots:
  extensions:
    interface: content
    content: villagesql-8.4-extensions
    source:
      read:
        - $SNAP/uuid

parts:
  uuid:
    plugin: nil
    source: https://github.com/villagesql/vsql-uuid.git
    source-tag: '0.0.6'
    source-depth: 1
    build-packages:
      - build-essential
      - ca-certificates
      - cmake
      - curl
      - libssl-dev
    override-build: |
      set -e
      SDK_VERSION=0.0.6
      SDK_URL="https://github.com/villagesql/villagesql-server/releases/download/release%2F${SDK_VERSION}/villagesql-extension-sdk-${SDK_VERSION}.tar.gz"
      rm -rf sdk build && mkdir -p sdk
      curl -fsSL "$SDK_URL" | tar xz -C sdk --strip-components=1
      cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DVillageSQL_SDK_DIR="$PWD/sdk"
      cmake --build build
      tar -tf build/vsql_uuid.veb
      # Layout consumed by the villagesql snap, see docs/extensions.md.
      # libcrypto is provided by the villagesql snap that loads the bundle.
      OUT="$CRAFT_PART_INSTALL/uuid"
      install -Dm644 build/vsql_uuid.veb "$OUT/veb/vsql_uuid.veb"
      printf 'VERSION=%s\n' "$CRAFT_PROJECT_VERSION" > "$OUT/manifest"
      install -Dm644 LICENSE "$OUT/licenses/LICENSE-vsql-uuid"
```

- [x] **Step 2: Build and try by hand**

```bash
(cd extensions/villagesql-uuid && snapcraft pack)
sudo snap install ./extensions/villagesql-uuid/villagesql-uuid_0.0.6_amd64.snap --dangerous
sudo snap connect villagesql:extensions villagesql-uuid:extensions
sudo snap restart villagesql
sudo villagesql.extensions list
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_uuid; SELECT UUID_V7(), UUID_VERSION(UUID_V4());"
```

Expected: a UUID and `4`. If `cmake` cannot find the SDK with `VillageSQL_SDK_DIR`, also pass `-DCMAKE_PREFIX_PATH="$PWD/sdk"`.

- [x] **Step 3: Write `spread/tests/extension_snap_uuid/task.yaml`**

This test also proves precedence: a second copy of the hello provider is installed under another snap name and its bundle is ignored because the earlier provider already supplies `vsql_hello.veb`. To get a second copy with a different name, the task repacks the hello snap with `name: villagesql-hello2` using `snap pack` on the unsquashed tree.

```yaml
summary: Upstream vsql-uuid as an extension snap, plus provider precedence

execute: |
  UUID_SNAP="$(ls "${PROJECT_PATH}"/extensions/villagesql-uuid/villagesql-uuid_*.snap 2>/dev/null | head -1)"
  HELLO_SNAP="$(ls "${PROJECT_PATH}"/extensions/villagesql-hello/villagesql-hello_*.snap 2>/dev/null | head -1)"
  if [ -z "$UUID_SNAP" ] || [ -z "$HELLO_SNAP" ]; then
    echo "ERROR: need extensions/villagesql-uuid/*.snap and extensions/villagesql-hello/*.snap (snapcraft pack there)" >&2
    exit 1
  fi
  INV=/var/snap/villagesql/common/veb/INVENTORY
  MYSQL="villagesql.mysql -uroot -N"
  restart() {
    snap restart villagesql
    timeout 90 /bin/bash -c \
      "while ! villagesql.mysqladmin -uroot ping >/dev/null 2>&1; do echo Waiting for villagesql...; sleep 1; done"
  }

  echo "Installing and connecting vsql-uuid..."
  snap install "$UUID_SNAP" --dangerous
  snap connect villagesql:extensions villagesql-uuid:extensions
  restart
  grep -P "^vsql_uuid\.veb\tsnap:uuid\t0\.0\.6$" "$INV"
  $MYSQL -e "INSTALL EXTENSION vsql_uuid;"
  villagesql.extensions list | grep -E "^vsql_uuid\s+0\.0\.6\s+snap:uuid\s+yes$"

  echo "Using the UUID type and functions..."
  $MYSQL -e "SELECT UUID_VERSION(UUID_V4());" | grep -x 4
  $MYSQL -e "SELECT UUID_VERSION(UUID_V7());" | grep -x 7
  $MYSQL -e "SELECT UUID_IS_VALID('not-a-uuid');" | grep -x 0
  $MYSQL -e "
    CREATE DATABASE u;
    CREATE TABLE u.users (id UUID PRIMARY KEY, name VARCHAR(40));
    INSERT INTO u.users VALUES (UUID_V7(), 'Ada'), (UUID_V7(), 'Grace');
  "
  $MYSQL -e "SELECT COUNT(*) FROM u.users;" | grep -x 2
  $MYSQL -e "SELECT name FROM u.users ORDER BY id;" | head -1 | grep -x Ada
  $MYSQL -e "SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='u' AND COLUMN_NAME='id';" | grep -qi uuid

  echo "Precedence: a second provider of the same bundle is ignored..."
  snap install "$HELLO_SNAP" --dangerous
  snap connect villagesql:extensions villagesql-hello:extensions
  # Repack the hello snap under another name to get a second provider of vsql_hello.veb
  rm -rf /tmp/hello2 && unsquashfs -q -d /tmp/hello2 "$HELLO_SNAP"
  sed -i 's/^name: villagesql-hello$/name: villagesql-hello2/' /tmp/hello2/meta/snap.yaml
  mv /tmp/hello2/hello /tmp/hello2/hello2
  sed -i 's#\$SNAP/hello$#$SNAP/hello2#; s#- \$SNAP/hello$#- $SNAP/hello2#' /tmp/hello2/meta/snap.yaml
  grep -n 'hello2' /tmp/hello2/meta/snap.yaml
  snap pack /tmp/hello2 /tmp/ --filename hello2.snap
  snap install /tmp/hello2.snap --dangerous
  snap connect villagesql:extensions villagesql-hello2:extensions
  restart
  cat "$INV"
  grep -P "^vsql_hello\.veb\tsnap:hello\t1\.0\.0$" "$INV"
  grep -F "# vsql_hello.veb from snap:hello2 ignored: already provided by snap:hello" "$INV"
  villagesql.extensions list | grep -F "note: vsql_hello.veb from snap:hello2 ignored"
  $MYSQL -e "INSTALL EXTENSION vsql_hello;"
  $MYSQL -e "SELECT hello('uuid');" | grep -x "Hello, uuid!"

  echo "Removing the first provider: the second one takes over after restart..."
  $MYSQL -e "UNINSTALL EXTENSION vsql_hello;"
  snap remove villagesql-hello
  restart
  grep -P "^vsql_hello\.veb\tsnap:hello2\t1\.0\.0$" "$INV"
  $MYSQL -e "INSTALL EXTENSION vsql_hello;"
  $MYSQL -e "SELECT shout('ok');" | grep -x "OK!"

  echo "Built-in bundles cannot be shadowed by a snap..."
  grep -P "^vsql_simple\.veb\tbuilt-in\t" "$INV"

  echo "Extension snap uuid test completed."

restore: |
  snap remove villagesql-uuid 2>/dev/null || true
  snap remove villagesql-hello 2>/dev/null || true
  snap remove villagesql-hello2 2>/dev/null || true
  rm -rf /tmp/hello2 /tmp/hello2.snap
```

If ordering `ORDER BY id` on a UUID column is not supported, drop that one line. If `unsquashfs` is missing on the test system, `apt-get install -y squashfs-tools` at the top of the task.

- [x] **Step 4: Run and commit**

```bash
snapcraft test -- craft:ubuntu-24.04:spread/tests/extension_snap_uuid
git add extensions/villagesql-uuid spread/tests/extension_snap_uuid
git commit -m "Add villagesql-uuid: upstream vsql-uuid as an extension snap; test provider precedence

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 9: Full run, docs cross-links, final polish

**Files:**
- Modify: `README.md` (extensions paragraph and doc links), `docs/superpowers/specs/2026-09-22-villagesql-snap-design.md` (record that `veb_dir` is passed on the command line rather than via `10-extensions.cnf`)
- Verify: everything

- [ ] **Step 1: Update README.md**

Add after the install section:

```markdown
## Extensions

Extensions are `.veb` bundles loaded with `INSTALL EXTENSION`. The snap
ships the upstream examples and accepts more from *extension snaps*
connected through the content interface:

```shell
sudo snap install villagesql-hello
sudo snap connect villagesql:extensions villagesql-hello:extensions
sudo snap restart villagesql
sudo villagesql.extensions list
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap');"
```

See [docs/extensions.md](docs/extensions.md) and the example providers in
[`extensions/`](extensions/).
```

And under "For more information" list: `docs/commands.md`, `docs/configuration.md`, `docs/refresh.md`, `docs/extensions.md`.

- [ ] **Step 2: Fix the spec detail**

In the spec's runtime layout table replace the `10-extensions.cnf` row with: `veb_dir` is passed on the `mysqld` command line by `mysqld.sh`, so `conf.d` stays fully owned by root and the administrator. Remove step 5 of the "Server side" list accordingly.

- [ ] **Step 3: Lint, then the full spread run on all three systems**

```bash
tox run -e lint
snapcraft test 2>&1 | tee /tmp/claude-1000/-home-ubuntu-canonical-taurus-forever-villagesql-snap/8179fb0a-5131-4629-9c8b-d007a25e672d/scratchpad/spread-full.log
tail -5 /tmp/claude-1000/-home-ubuntu-canonical-taurus-forever-villagesql-snap/8179fb0a-5131-4629-9c8b-d007a25e672d/scratchpad/spread-full.log
```

Expected: `Successful tasks: 45` (15 tests x 3 systems) and no failed tasks. Fix and re-run any failing task on its system with `snapcraft test -- craft:<system>:spread/tests/<name>`.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/
git commit -m "Document extensions in the README; full spread run green

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

**Step 4 checkpoint:** show `villagesql.extensions list` with both providers, a UUID query, and the final spread summary.
