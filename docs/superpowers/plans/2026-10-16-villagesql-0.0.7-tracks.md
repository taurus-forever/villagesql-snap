# VillageSQL 0.0.7 and Codebase Tracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the `villagesql` snap to VillageSQL 0.0.7 with a safe in-place refresh from 0.0.6, then add the `mysql-9.7` and `percona-8.4` codebases as branches `9.7/edge` and `percona-8.4/edge` of the same snap.

**Architecture:** All shared work lands on `8.4/edge` first: the upstream tag bump, a codebase-aware refresh guard driven by a `$SNAP/codebase` file stamped at build time, the codebase-independent content label `villagesql-extensions`, a refresh test that starts from the store's previous release, and a manual release workflow. The two other branches are then created from `8.4/edge` and differ only in `snap/snapcraft.yaml`, `spread.yaml`'s `CODEBASE`, README wording and (Percona) one extra spread test, so later fixes flow by `git merge 8.4/edge`.

**Tech Stack:** snapcraft 9 (core26, cmake/nil/dump plugins), bash, spread via `snapcraft test` (craft backend), tox + yamllint, pytest, GitHub Actions with `canonical/data-platform-workflows`.

**Spec:** `docs/superpowers/specs/2026-10-16-villagesql-0.0.7-tracks-design.md`

## Global Constraints

- Snap name `villagesql` on every branch; versions `8.4.11-0.0.7` (`8.4/edge`), `9.7.2-0.0.7` (`9.7/edge`), `8.4.11-0.0.7+percona` (`percona-8.4/edge`).
- Upstream tags: `publish/mysql-8.4_0.0.7`, `publish/mysql-9.7_0.0.7`, `publish/percona-8.4_0.0.7` from `https://github.com/villagesql/villagesql-server.git`.
- Codebase names exactly as upstream: `mysql-8.4`, `mysql-9.7`, `percona-8.4`. `$SNAP/codebase` holds one of them, no newline problems (`cat` then compare with `$(...)`).
- Data marker `$SNAP_COMMON/.snap-data-codebase`; legacy marker `$SNAP_COMMON/.snap-data-major` with value `8.4` means `mysql-8.4`.
- Content label `villagesql-extensions` on the server plug and every provider slot.
- Example providers: `villagesql-hello` version `1.0.1` built with SDK 0.0.6; `villagesql-uuid` version `0.0.7` from upstream tag `0.0.7` with SDK 0.0.7 (`villagesql-extension-sdk-0.0.7.tar.gz` under GitHub release `release%2F0.0.7`).
- Branch-specific files are only `snap/snapcraft.yaml`, `spread.yaml`, `README.md` and, on `percona-8.4/edge`, `spread/tests/percona/task.yaml`. Everything else must be byte-identical across branches; `git diff 8.4/edge <branch> --stat` is the check.
- Every spread test is `spread/tests/<name>/task.yaml` with `summary:` and `execute:`; run one with `snapcraft test -- craft:ubuntu-24.04:spread/tests/<name>`, all with `snapcraft test`.
- A server build (`snapcraft pack`) takes about 15 minutes on this host. Rebuild only when `snap/` changed; spread tests reuse the packed artifact.
- Commit after every task with a message ending in `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Never push; the maintainer uploads to the store by hand.

## Review Focus

- A 0.0.6 install that was never started after install has `.snap-data-major` but the data directory may lack `mysql/`; the guard must still refuse with the "No initialized data directory" message, not crash on a missing file (Task 2 legacy case covers the marker, the existing `[ ! -d "$datadir/mysql" ]` check stays first).
- A user who already ran `snap refresh` to a foreign codebase and got rolled back must find the old revision serving and both markers untouched (Task 2 test asserts revision and data after rollback).
- The content label only governs auto-connection; a manual `snap connect` of a provider with the old `villagesql-8.4-extensions` label may still succeed, so the docs must say that store-installed providers auto-connect and side-loaded ones need `snap connect` (Task 3 docs, Task 4 verifies what a refresh keeps).
- The `+percona` suffix in the snap version must not leak into version parsing anywhere (`smoke`, `tests/test_smoke.py`), or the Percona branch fails its own smoke test (Task 1 strips it on `8.4/edge` already).
- If the store's `latest/edge` later holds 0.0.7, the refresh test still runs (it refreshes from whatever the channel has) but no longer proves 0.0.6 to 0.0.7; the local previous-build path under `spread/` is the reproducible one and Task 8 runs it before the first upload.

## File structure

| Path | Responsibility |
| --- | --- |
| `snap/snapcraft.yaml` | Build recipe; stamps `codebase`; plug label; version and tag (branch-specific). |
| `snap/local/codebase.sh` | Shell functions shared by hooks and wrapper: revision codebase, data codebase with legacy mapping, marker writer. |
| `snap/local/mysqld.sh`, `snap/hooks/install`, `snap/hooks/post-refresh` | Use `codebase.sh` instead of `cut -d. -f1-2` on `$SNAP_VERSION`. |
| `spread.yaml` | Adds the `CODEBASE` environment variable (branch-specific). |
| `spread/tests/smoke`, `refresh`, `refresh_codebase_guard`, `extension_snap_hello`, `extension_snap_uuid`, `percona` | Integration tests. |
| `extensions/villagesql-hello/snap/snapcraft.yaml`, `extensions/villagesql-uuid/snap/snapcraft.yaml` | Provider snaps. |
| `.github/workflows/release.yaml` | Manual dispatch, track derived from the branch name. |
| `README.md`, `docs/refresh.md`, `docs/extensions.md`, `docs/commands.md`, `extensions/README.md` | Documentation. |

---

## Part A: `8.4/edge`

### Task 1: Build VillageSQL 0.0.7 (mysql-8.4)

**Files:**
- Modify: `snap/snapcraft.yaml:3-11` (version, summary, description), `:91` (source-tag)
- Modify: `spread.yaml` (add `environment:`), `spread/tests/smoke/task.yaml:4-8`, `tests/test_smoke.py:40-46`, `docs/commands.md:35`

**Interfaces:**
- Produces: artifact `villagesql_8.4.11-0.0.7_<arch>.snap`; spread variable `CODEBASE=mysql-8.4`; server reports `8.4.11-villagesql-0.0.7` and `@@villagesql_server_version` = `mysql-8.4_0.0.7`.

- [ ] **Step 1: Add the codebase variable to `spread.yaml`**

Top-level block, after `project:`:

```yaml
environment:
  CODEBASE: mysql-8.4   # branch-specific: the upstream codebase this branch builds
```

- [ ] **Step 2: Make the smoke test 0.0.7- and codebase-aware**

In `spread/tests/smoke/task.yaml` replace the version block with:

```bash
SNAP_VERSION=$(awk -F"'" '/^version/{print $2}' "${PROJECT_PATH}/snap/snapcraft.yaml")
MYSQL_VERSION="${SNAP_VERSION%%-*}"
VSQL_VERSION="${SNAP_VERSION#*-}"; VSQL_VERSION="${VSQL_VERSION%%+*}"   # drop a +percona style suffix
villagesql.mysql -uroot -N -e "SELECT VERSION();" | grep -E "^${MYSQL_VERSION}-villagesql-${VSQL_VERSION}"
villagesql.mysql -uroot -N -e "SELECT @@villagesql_server_version;" | grep -x "${CODEBASE}_${VSQL_VERSION}"
```

Leave the `.snap-data-major` line for now (Task 2 replaces it).

- [ ] **Step 3: Strip the suffix in the host smoke test**

In `tests/test_smoke.py::test_version` use `vsql_version = vsql_version.split("+", 1)[0]` before the assertion.

- [ ] **Step 4: Bump the recipe**

`snap/snapcraft.yaml`: `version: '8.4.11-0.0.7'`, `source-tag: publish/mysql-8.4_0.0.7`, summary `VillageSQL 0.0.7 (MySQL 8.4 codebase) with extensions in a snap.`, and append to the description:

```
  This track builds the mysql-8.4 codebase. Tracks 9.7 (MySQL 9.7) and
  percona-8.4 (Percona Server 8.4) build the other codebases; a data
  directory belongs to one codebase and cannot be moved between tracks.
```

`docs/commands.md:35`: `8.4.11-villagesql-0.0.7`.

- [ ] **Step 5: Build**

Run: `snapcraft pack 2>&1 | tail -5`
Expected: `Packed villagesql_8.4.11-0.0.7_amd64.snap`. If cmake fails on a missing package, add it to `build-packages` and note it in the spec's Build table.

- [ ] **Step 6: Run the smoke test**

Run: `snapcraft test -- craft:ubuntu-24.04:spread/tests/smoke`
Expected: `Successful tasks: 1`.

- [ ] **Step 7: Commit**

```bash
git add snap/snapcraft.yaml spread.yaml spread/tests/smoke/task.yaml tests/test_smoke.py docs/commands.md
git commit -m "Build VillageSQL 0.0.7 from publish/mysql-8.4_0.0.7"
```

### Task 2: Codebase-aware refresh guard

**Files:**
- Create: `snap/local/codebase.sh`
- Modify: `snap/snapcraft.yaml` (villagesql part `override-build`; wrapper `organize`), `snap/local/mysqld.sh:11-14`, `snap/hooks/install:56`, `snap/hooks/post-refresh` (whole file), `spread/tests/smoke/task.yaml:16`, `spread/tests/refresh/task.yaml:47`, `docs/refresh.md`
- Rename: `spread/tests/refresh_major_guard/` to `spread/tests/refresh_codebase_guard/` and rewrite `task.yaml`

**Interfaces:**
- Produces: `$SNAP/codebase` (one line, e.g. `mysql-8.4`); `$SNAP/bin/codebase.sh` with functions
  `snap_codebase` (prints `$SNAP/codebase`),
  `data_codebase` (prints `.snap-data-codebase`; else `mysql-8.4` when `.snap-data-major` holds `8.4`; else prints nothing and returns 1),
  `write_data_codebase` (writes `.snap-data-codebase` from `snap_codebase`, removes `.snap-data-major`).
- Consumes: `CODEBASE` from Task 1.

- [ ] **Step 1: Rewrite the guard test**

`spread/tests/refresh_codebase_guard/task.yaml`, summary `A refresh onto data from another codebase is rolled back`. Keep the current structure (record `REV_BEFORE`, create `guard.t`, attempt `snap install "$CRAFT_ARTIFACT" --dangerous --jailmode`, expect failure, assert revision unchanged and `SELECT id FROM guard.t` = 1) and run it for three cases:

```bash
M=/var/snap/villagesql/common
case_foreign()   { echo "mysql-9.7" > "$M/.snap-data-codebase"; rm -f "$M/.snap-data-major"; }
case_legacy_84() { rm -f "$M/.snap-data-codebase"; echo "8.4" > "$M/.snap-data-major"; }
case_legacy_bad(){ rm -f "$M/.snap-data-codebase"; echo "9.7" > "$M/.snap-data-major"; }
```

Expectations: `case_foreign` is rolled back on every branch and the log contains `is from codebase mysql-9.7 but this revision provides ${CODEBASE}`; `case_legacy_bad` is rolled back everywhere with `cannot tell which codebase`; `case_legacy_84` is accepted when `CODEBASE = mysql-8.4` (afterwards `.snap-data-codebase` holds `mysql-8.4` and `.snap-data-major` is gone) and rolled back otherwise with `is from codebase mysql-8.4`. Each case ends with `wait_ready` and the data check. In `restore:` write `${CODEBASE}` back into `.snap-data-codebase`.

- [ ] **Step 2: Update the other tests' marker checks**

`smoke` line 16 and `refresh` line 47 become `grep -x "${CODEBASE}" /var/snap/villagesql/common/.snap-data-codebase`; `refresh` also asserts `test ! -e /var/snap/villagesql/common/.snap-data-major`.

- [ ] **Step 3: Run the guard test to verify it fails**

Run: `snapcraft test -- craft:ubuntu-24.04:spread/tests/refresh_codebase_guard`
Expected: FAIL (the current hook does not know `.snap-data-codebase`; `case_foreign` is accepted).

- [ ] **Step 4: Stamp the codebase at build time**

In the `villagesql` part's `override-build`, after `craftctl default`:

```bash
sed -n 's/^VSQL_CODE_BASE=//p' "$CRAFT_PART_SRC/VSQL_VERSION" | tr -d '[:space:]' > "$CRAFT_PART_INSTALL/codebase"
test -s "$CRAFT_PART_INSTALL/codebase"
```

- [ ] **Step 5: Write `snap/local/codebase.sh`** with the three functions from Interfaces (plain `sh`, sourced with `.`), and organize it to `bin/codebase.sh` in the `wrapper` part.

- [ ] **Step 6: Use it**

`mysqld.sh`: replace the `cut -d. -f1-2` block with `. "$SNAP/bin/codebase.sh"` and `[ -d "$SNAP_COMMON/data/mysql" ] && write_data_codebase`. `install` hook line 56: same call. `post-refresh`: keep the datadir check, then

```sh
new="$(snap_codebase)"
if ! old="$(data_codebase)"; then
  echo "ERROR: neither $SNAP_COMMON/.snap-data-codebase nor a usable $SNAP_COMMON/.snap-data-major found, cannot tell which codebase the data belongs to. Refresh aborted, rolling back." >&2; exit 1
fi
[ "$old" = "$new" ] || { echo "ERROR: Data in $datadir is from codebase $old but this revision provides $new. VillageSQL has no in-place migration between codebases: dump with villagesql.mysqldump, install the new track and restore. Refresh aborted, rolling back." >&2; exit 1; }
```

Update the hook's header comment (codebases, not MySQL majors).

- [ ] **Step 7: Build and run guard, smoke and refresh**

Run: `snapcraft pack 2>&1 | tail -2 && snapcraft test -- craft:ubuntu-24.04:spread/tests/refresh_codebase_guard craft:ubuntu-24.04:spread/tests/smoke craft:ubuntu-24.04:spread/tests/refresh`
Expected: `Successful tasks: 3`.

- [ ] **Step 8: Update `docs/refresh.md`**

Replace the "Major versions" section with "Codebases and tracks": one data directory belongs to one codebase (`mysql-8.4`, `mysql-9.7`, `percona-8.4`); the hook compares `.snap-data-codebase` with the new revision's codebase; moving between tracks is the dump-and-restore recipe with `--channel 9.7/stable` as the example. Keep "Minor versions" and "Rolling back".

- [ ] **Step 9: Commit**

```bash
git add snap spread docs/refresh.md
git commit -m "Guard refreshes by VillageSQL codebase instead of MySQL major"
```

### Task 3: Codebase-independent extension label and rebuilt providers

**Files:**
- Modify: `snap/snapcraft.yaml:30-35` (plug `content`), `extensions/villagesql-hello/snap/snapcraft.yaml:3,31`, `extensions/villagesql-uuid/snap/snapcraft.yaml:3,26,35,45`, `spread/tests/extension_snap_hello/task.yaml`, `spread/tests/extension_snap_uuid/task.yaml`, `docs/extensions.md`, `extensions/README.md`
- Move: `extensions/villagesql-hello/villagesql-hello_1.0.0_*.snap` and `extensions/villagesql-uuid/villagesql-uuid_0.0.6_*.snap` to `spread/` (previous builds for Task 4; `*.snap` is git-ignored)

**Interfaces:**
- Produces: plug and slots with `content: villagesql-extensions`; provider snaps `villagesql-hello_1.0.1_<arch>.snap` and `villagesql-uuid_0.0.7_<arch>.snap` next to their `snap/` directories.

- [ ] **Step 1: Move the 0.0.6-era provider snaps to `spread/`** (`git mv` is not needed, they are untracked).

- [ ] **Step 2: Update the tests**

`extension_snap_hello`: every `1\.0\.0` becomes `1\.0\.1`. `extension_snap_uuid`: `0\.0\.6` becomes `0\.0\.7` in both greps, `1\.0\.0` becomes `1\.0\.1`.

- [ ] **Step 3: Run `extension_snap_uuid` to verify it fails**

Run: `snapcraft test -- craft:ubuntu-24.04:spread/tests/extension_snap_uuid`
Expected: FAIL with `need extensions/villagesql-uuid/*.snap` (the 0.0.6 providers were moved away and nothing is packed yet).

- [ ] **Step 4: Change the labels and provider versions**

Server plug `content: villagesql-extensions` with the comment updated (one bundle serves every codebase). `villagesql-hello`: `version: '1.0.1'`, slot `content: villagesql-extensions`, description keeps "SDK 0.0.6". `villagesql-uuid`: `version: '0.0.7'`, `source-tag: '0.0.7'`, `SDK_VERSION=0.0.7`, slot label.

- [ ] **Step 5: Pack providers and the server, run both extension tests**

Run: `(cd extensions/villagesql-hello && snapcraft pack) && (cd extensions/villagesql-uuid && snapcraft pack) && snapcraft pack 2>&1 | tail -2 && snapcraft test -- craft:ubuntu-24.04:spread/tests/extension_snap_hello craft:ubuntu-24.04:spread/tests/extension_snap_uuid`
Expected: `Successful tasks: 2`.

- [ ] **Step 6: Docs**

`docs/extensions.md`: label in the YAML example, `villagesql-extension-sdk-0.0.7.tar.gz`, `villagesql.config --version  # 0.0.7`, and a paragraph "One bundle, every track": the SDK and the VEF ABI are codebase-independent, so a provider built once connects to the 8.4, 9.7 and percona-8.4 tracks alike. `extensions/README.md`: mention both versions and the same sentence.

- [ ] **Step 7: Commit**

```bash
git add snap/snapcraft.yaml extensions spread/tests docs/extensions.md
git commit -m "Use the codebase-independent label villagesql-extensions; vsql-uuid 0.0.7"
```

### Task 4: Refresh test from the previous release with providers connected

**Files:**
- Modify: `spread/tests/refresh/task.yaml` (whole file), `docs/refresh.md`

**Interfaces:**
- Consumes: `CODEBASE`; `spread/villagesql_8.4.11-0.0.6_<arch>.snap`, `spread/villagesql-hello_1.0.0_<arch>.snap`, `spread/villagesql-uuid_0.0.6_<arch>.snap` when present (Task 3 moved them there), else the store's `latest/edge`.

- [ ] **Step 1: Rewrite the test**

```bash
ARCH="$(dpkg --print-architecture)"
PREV="$(ls "${PROJECT_PATH}"/spread/villagesql_*_"$ARCH".snap 2>/dev/null | head -1)"
snap remove villagesql --purge --terminate
if [ -n "$PREV" ]; then
  snap install "$PREV" --dangerous --jailmode
  snap install "${PROJECT_PATH}"/spread/villagesql-hello_*_"$ARCH".snap --dangerous
  snap install "${PROJECT_PATH}"/spread/villagesql-uuid_*_"$ARCH".snap --dangerous
else
  snap install villagesql --edge
  snap install villagesql-hello --edge
  snap install villagesql-uuid --edge
fi
snap connect villagesql:extensions villagesql-hello:extensions
snap connect villagesql:extensions villagesql-uuid:extensions
snap restart villagesql; wait_ready
PREV_VERSION="$(snap list villagesql | awk 'NR == 2 {print $2}')"
```

Then the existing data and user set-up plus `INSTALL EXTENSION vsql_uuid; CREATE TABLE refresh.u (id UUID PRIMARY KEY, name TEXT); INSERT INTO refresh.u VALUES (UUID_V7(), 'before');`. Refresh with `snap install "$CRAFT_ARTIFACT" --dangerous --jailmode > /tmp/refresh.log 2>&1 || true`, then:

- `if [ "$CODEBASE" = mysql-8.4 ]`: revision changed, service active, existing checks, `.snap-data-codebase` = `mysql-8.4`, legacy file gone, `villagesql.extensions list | grep -E "^vsql_uuid\s+\S+\s+snap:uuid\s+yes$"`, `SELECT name FROM refresh.u` = `before`, `INSERT ... (UUID_V7(), 'after')` works, `SELECT UUID_VERSION(UUID_V7())` = 7.
- else: `grep -q "is from codebase mysql-8.4 but this revision provides ${CODEBASE}" /tmp/refresh.log`, revision unchanged, `snap list villagesql` still shows `$PREV_VERSION`, `wait_ready`, `SELECT name FROM refresh.u` = `before`.

Print `snap connections villagesql` right after the refresh in both branches.

- [ ] **Step 2: Run it with the local previous builds**

Run: `snapcraft test -- craft:ubuntu-24.04:spread/tests/refresh`
Expected: PASS on the data checks. Read the printed connections: if `villagesql-uuid:extensions` is still connected, the label change survived the refresh; if not, the `extensions list` check failed.

- [ ] **Step 3: Pin the connection behaviour**

If the connections survived: add `snap connections villagesql | grep -E "villagesql:extensions\s+villagesql-uuid:extensions"` to the success branch. If they did not: insert `snap connect villagesql:extensions villagesql-hello:extensions villagesql:extensions villagesql-uuid:extensions`-style reconnects (one per provider) plus `snap restart villagesql; wait_ready` before the extension checks, and document the one-off `snap connect` after the 0.0.7 refresh in `docs/refresh.md` under a new "Refreshing from 0.0.6" subsection. Either way the subsection states that providers built for 0.0.6 keep working.

- [ ] **Step 4: Run from the store path too**

Run: `mv spread/villagesql_*.snap spread/villagesql-*.snap /tmp/ && snapcraft test -- craft:ubuntu-24.04:spread/tests/refresh; mv /tmp/villagesql_*.snap /tmp/villagesql-*.snap spread/`
Expected: PASS (installs `latest/edge` from the store).

- [ ] **Step 5: Commit**

```bash
git add spread/tests/refresh/task.yaml docs/refresh.md
git commit -m "Refresh test starts from the previous release with extension snaps connected"
```

### Task 5: Manual release workflow and README

**Files:**
- Modify: `.github/workflows/release.yaml` (whole file), `README.md:1-20`

**Interfaces:**
- Produces: `workflow_dispatch`-only release that publishes the branch's build to the track named after the branch (`8.4/edge` gives `8.4`).

- [ ] **Step 1: Rewrite `release.yaml`**

Trigger `on: workflow_dispatch:` only. Jobs: `ci-tests` as today; new `track` job (`runs-on: ubuntu-latest`, `permissions: {}`) with one step that sets `track=${GITHUB_REF_NAME%/edge}` as an output and fails if the result equals `$GITHUB_REF_NAME`; `release` with `needs: [ci-tests, track]` and `track: ${{ needs.track.outputs.track }}`. Add a top comment: publishing is manual for now; dispatch this workflow from a `<track>/edge` branch to publish to `<track>/edge`.

- [ ] **Step 2: Lint**

Run: `tox run -e lint` and, if installed, `actionlint .github/workflows/release.yaml`
Expected: no errors (CI's `lint-workflows` job runs actionlint and zizmor on the PR).

- [ ] **Step 3: README**

Replace the intro and "Install the snap" with the three tracks: a table (track, codebase, base server) and

```shell
sudo snap install villagesql --channel 8.4/edge          # MySQL 8.4 codebase (latest/edge is the same build for now)
sudo snap install villagesql --channel 9.7/edge          # MySQL 9.7 codebase
sudo snap install villagesql --channel percona-8.4/edge  # Percona Server 8.4 codebase
```

plus one sentence: a data directory belongs to one codebase, see docs/refresh.md.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yaml README.md
git commit -m "Release by manual dispatch to the track named after the branch; document the tracks"
```

### Task 6: Full suite on `8.4/edge`

- [ ] **Step 1: Run everything**

Run: `snapcraft test`
Expected: all tasks successful on ubuntu-22.04, 24.04 and 26.04. Fix and commit anything that fails.

- [ ] **Step 2: Host smoke test**

Run: `sudo snap install ./villagesql_8.4.11-0.0.7_amd64.snap --dangerous --jailmode && tox run -e smoke`
Expected: 3 passed.

## Part B: `9.7/edge`

### Task 7: Branch `9.7/edge`

**Files:**
- Modify (on the new branch only): `snap/snapcraft.yaml`, `spread.yaml`, `README.md`

- [ ] **Step 1: Create the branch** from the `8.4/edge` head: `git switch -c 9.7/edge`.

- [ ] **Step 2: Recipe**

`version: '9.7.2-0.0.7'`, `source-tag: publish/mysql-9.7_0.0.7`, summary `VillageSQL 0.0.7 (MySQL 9.7 codebase) with extensions in a snap.`, description paragraph names this track as mysql-9.7; `build-packages` + `libcurl4-openssl-dev`; `stage-packages` + `libcurl4t64`; `cmake-parameters` + `-DWITH_CURL=system`. `spread.yaml`: `CODEBASE: mysql-9.7`. README: mark this branch's track in the table.

- [ ] **Step 3: Build (spike)**

Run: `snapcraft pack 2>&1 | tail -20`
Expected: `Packed villagesql_9.7.2-0.0.7_amd64.snap`. On a missing dependency add the package, record it in the spec's Build table on `8.4/edge` later, and rebuild.

- [ ] **Step 4: Full suite**

Run: `snapcraft test`
Expected: all successful, including `refresh` taking the rollback path and `refresh_codebase_guard` rejecting the legacy `8.4` marker. `smoke` must see `9.7.2-villagesql-0.0.7` and `mysql-9.7_0.0.7`.

- [ ] **Step 5: Verify the branch diff and commit**

Run: `git diff 8.4/edge --stat`
Expected: only `snap/snapcraft.yaml`, `spread.yaml`, `README.md`.

```bash
git add -A && git commit -m "Build the mysql-9.7 codebase (MySQL 9.7.2) for track 9.7"
```

## Part C: `percona-8.4/edge`

### Task 8: Branch `percona-8.4/edge`

**Files:**
- Modify (new branch): `snap/snapcraft.yaml`, `spread.yaml`, `README.md`
- Create: `spread/tests/percona/task.yaml`

- [ ] **Step 1: Create the branch** from `8.4/edge`: `git switch 8.4/edge && git switch -c percona-8.4/edge`.

- [ ] **Step 2: Write the Percona test**

`spread/tests/percona/task.yaml`, summary `Percona Server features match the upstream percona-8.4 page`:

```bash
MYSQL="villagesql.mysql -uroot -N"
$MYSQL -e "SELECT @@villagesql_server_version;" | grep -x "percona-8.4_0.0.7"
$MYSQL -e "SELECT @@have_backup_locks;" | grep -x YES          # Percona-only: LOCK TABLES FOR BACKUP
$MYSQL -e "LOCK TABLES FOR BACKUP; UNLOCK TABLES;"
! $MYSQL -e "CREATE TABLE test.r (id INT) ENGINE=ROCKSDB;" 2>/tmp/rocks.err; grep -qi "unknown storage engine" /tmp/rocks.err
! $MYSQL -e "INSTALL COMPONENT 'file://component_keyring_kmip';" 2>/tmp/kmip.err; grep -q "1126" /tmp/kmip.err
```

- [ ] **Step 3: Recipe**

`version: '8.4.11-0.0.7+percona'`, `source-tag: publish/percona-8.4_0.0.7`, summary `VillageSQL 0.0.7 (Percona Server 8.4 codebase) with extensions in a snap.`, description paragraph names percona-8.4 and the three exclusions (MyRocks, KMIP keyring, coredumper); `build-packages` + `libcurl4-openssl-dev libkrb5-dev libldap-dev libsasl2-dev libsasl2-modules-gssapi-mit`; `stage-packages` + `libcurl4t64 libldap2 libsasl2-2 libsasl2-modules-gssapi-mit`; `cmake-parameters` + `-DWITH_CURL=system -DWITH_ROCKSDB=0 -DWITH_COREDUMPER=OFF -DWITHOUT_COMPONENT_KEYRING_KMIP=ON -DWITH_AUTH_OPENID_CONNECT=OFF`. `spread.yaml`: `CODEBASE: percona-8.4`. README table row.

- [ ] **Step 4: Build (spike)**

Run: `snapcraft pack 2>&1 | tail -20`
Expected: `Packed villagesql_8.4.11-0.0.7+percona_amd64.snap`. Missing packages: add, note for the spec, rebuild. If `SELECT VERSION()` on the result is not `8.4.11-villagesql-0.0.7`, adjust the smoke test's expectation on `8.4/edge` in a way that stays true for all branches (for example match `^${MYSQL_VERSION}-.*villagesql-${VSQL_VERSION}`) and merge it forward.

- [ ] **Step 5: Full suite, including the Percona test**

Run: `snapcraft test`
Expected: all successful. If `@@have_backup_locks` does not exist on this build, replace that line and the `LOCK TABLES FOR BACKUP` line with another Percona-only variable found by `SHOW VARIABLES LIKE 'percona%'` or `'innodb_%percona%'`, and keep the ROCKSDB and KMIP assertions as they are.

- [ ] **Step 6: Verify the branch diff and commit**

Run: `git diff 8.4/edge --stat`
Expected: `snap/snapcraft.yaml`, `spread.yaml`, `README.md`, `spread/tests/percona/task.yaml`.

```bash
git add -A && git commit -m "Build the percona-8.4 codebase (Percona Server 8.4.11) for track percona-8.4"
```

### Task 9: Fold spike findings back and hand over

- [ ] **Step 1: Spec Build table**

If Task 7 or 8 added packages or flags, update the table in the spec on `8.4/edge`, commit, and `git merge 8.4/edge` into `9.7/edge` and `percona-8.4/edge` (expect clean merges).

- [ ] **Step 2: Local one-off verification before upload**

On `8.4/edge`, with the 0.0.6 artifacts under `spread/` (Task 3), run `snapcraft test -- craft:ubuntu-22.04:spread/tests/refresh craft:ubuntu-24.04:spread/tests/refresh`.
Expected: PASS on both. This is the exact upgrade the current `latest/edge` users will perform.

- [ ] **Step 3: Report** the artifacts to upload per track (`villagesql_8.4.11-0.0.7_*.snap` to `8.4/edge` and `latest/edge`, `villagesql_9.7.2-0.0.7_*.snap` to `9.7/edge`, `villagesql_8.4.11-0.0.7+percona_*.snap` to `percona-8.4/edge` once the track exists, `villagesql-hello_1.0.1_*.snap` and `villagesql-uuid_0.0.7_*.snap` to their `latest/edge`), and whether the 0.0.7 refresh needs a one-off `snap connect` (Task 4 Step 3).
