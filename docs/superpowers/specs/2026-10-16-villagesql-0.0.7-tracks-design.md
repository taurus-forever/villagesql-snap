# VillageSQL snap 0.0.7 and codebase tracks: design

Date: 2026-10-16. Follows the 2026-09-22 design, which this document
amends where the two differ.

## Goal

Move the snap from VillageSQL 0.0.6 to 0.0.7 so that existing installs
refresh in place, and publish the two other upstream codebases (MySQL 9.7
and Percona Server 8.4) as further tracks of the same `villagesql` snap.
Extension snaps built for 0.0.6 must keep working.

Upstream 0.0.7 (released 2026-10-13) ships three codebases from one
repository, one tag each:

| Codebase | Tag | Base server | Snap track | Git branch | Snap version |
| --- | --- | --- | --- | --- | --- |
| `mysql-8.4` | `publish/mysql-8.4_0.0.7` | MySQL 8.4.11 | `8.4` (and `latest`, see Release) | `8.4/edge` | `8.4.11-0.0.7` |
| `mysql-9.7` | `publish/mysql-9.7_0.0.7` | MySQL 9.7.2 | `9.7` | `9.7/edge` | `9.7.2-0.0.7` |
| `percona-8.4` | `publish/percona-8.4_0.0.7` | Percona Server 8.4.11 | `percona-8.4` | `percona-8.4/edge` | `8.4.11-0.0.7+percona` |

`release/0.0.7` is the same commit as `publish/mysql-8.4_0.0.7`; the
branches use the `publish/` tags so that every branch names its codebase.

## Decisions

| Topic | Decision |
| --- | --- |
| Snap name | One snap, `villagesql`, for all codebases. No `villagesql-percona`. |
| Tracks | One Snap Store track per upstream codebase, named as upstream names it: `8.4`, `9.7`, `percona-8.4`. Tracks `8.4` and `9.7` exist; `percona-8.4` is requested from the store team (the self-serve guardrail only accepts `major.minor`). |
| Branches | One git branch per track, `<track>/edge`, as in postgresql-snap and as upstream keeps one branch per codebase. `8.4/edge` carries all shared work; `9.7/edge` and `percona-8.4/edge` are branched from it and differ only in `snap/snapcraft.yaml`, the spread `CODEBASE` variable, wording in README and, on `percona-8.4/edge`, one Percona-only spread test. Later fixes flow by `git merge 8.4/edge` into the other branches. |
| Publishing | Manual: the maintainer builds, tests locally and uploads to the track. The release workflow becomes a manual dispatch that derives the track from the branch name, ready for later automation. |
| Codebase guard | The refresh guard compares codebases (`mysql-8.4`, `mysql-9.7`, `percona-8.4`), not MySQL majors. The codebase is stamped into `$SNAP/codebase` at build time from upstream's `VSQL_VERSION` file (`VSQL_CODE_BASE=`); `villagesql_config --version` prints plain `0.0.7` since 0.0.7 and cannot serve. |
| Extension label | The content interface label becomes `villagesql-extensions` on every track. One `.veb` serves every codebase: upstream ships one SDK tarball per release and the VEF ABI is protocol-versioned, not server-versioned. |
| Example providers | `villagesql-uuid` is rebuilt from upstream tag `0.0.7` against SDK 0.0.7 (snap version `0.0.7`). `villagesql-hello` keeps SDK 0.0.6 on purpose, as the proof that older bundles still load; it gets version `1.0.1` for the label change. Both stay single-track on `latest`. |
| Percona feature set | Follows upstream's own CI build (`villagesql/bld_tools/build_ci.sh` on the `percona-8.4` tag): MyRocks, coredumper and the KMIP keyring component off, OpenID Connect auth off, LDAP and Kerberos authentication on, curl from the system. |

## Build

Each branch's `snap/snapcraft.yaml` differs from today's in `version`,
`summary`, `description`, `source-tag` and the lists below. Everything
else, including the NDB removal, stripping and prime filters, is shared.

| Branch | Extra build-packages | Extra stage-packages | Extra cmake-parameters |
| --- | --- | --- | --- |
| `8.4/edge` | none | none | none |
| `9.7/edge` | `libcurl4-openssl-dev` | `libcurl4t64` | `-DWITH_CURL=system` |
| `percona-8.4/edge` | `libcurl4-openssl-dev`, `libkrb5-dev`, `libldap-dev`, `libsasl2-dev`, `libsasl2-modules-gssapi-mit` | `libcurl4t64`, `libldap2`, `libsasl2-2`, `libsasl2-modules-gssapi-mit` | `-DWITH_CURL=system`, `-DWITH_ROCKSDB=0`, `-DWITH_COREDUMPER=OFF`, `-DWITHOUT_COMPONENT_KEYRING_KMIP=ON`, `-DWITH_AUTH_OPENID_CONNECT=OFF` |

The dependency lists come from upstream's `setup_linux_build_env.sh` on
each tag. Percona's tree turns the LDAP and Kerberos auth plugins on by
default and fails to configure without their libraries, hence the extra
packages; snapcraft pulls the transitive runtime libraries (krb5, gssapi)
in with the listed stage packages. The first builds of `9.7/edge` and
`percona-8.4/edge` (2026-10-16) needed nothing beyond this table. The
Percona tree names its client library `libperconaserverclient.so`, which
the branch primes out like `libmysqlclient.so` on the others (nothing in
the snap links to it).

`-DVSQL_PRE_RELEASE_VERSION=` stays, so the server reports
`<codebase>_0.0.7` rather than `0.0.7-dev` (the tags still carry
`VSQL_PRE_RELEASE_VERSION=dev` in `VSQL_VERSION`).

## Codebase guard

Upstream refuses to start a server on a data directory initialised by
another codebase, and there is no supported migration between codebases.
The snap must therefore reject a refresh across codebases before the
service is stopped, exactly as it rejects a MySQL major change today.

- The codebase of a revision is the content of `$SNAP/codebase`, written
  by the `villagesql` part's `override-build` from the `VSQL_CODE_BASE=`
  line of upstream's `VSQL_VERSION` (`mysql-8.4`, `mysql-9.7` or
  `percona-8.4`), so no branch hand-maintains the value. Shell functions in
  `snap/local/codebase.sh` read it and the data marker for the hooks and
  the wrapper.
- `mysqld.sh` and the `install` hook write the codebase to
  `$SNAP_COMMON/.snap-data-codebase` where they write
  `.snap-data-major` today, and `mysqld.sh` removes the legacy file once
  the new one exists.
- `post-refresh` reads `.snap-data-codebase`. If it is missing but the
  legacy `.snap-data-major` holds `8.4`, that counts as `mysql-8.4`: this
  is the state of every 0.0.6 install. Any other legacy value, or neither
  file, aborts the refresh as today.
- On a mismatch the hook exits non-zero with a message naming both
  codebases and the dump-and-restore path, so snapd rolls back.
- Nothing else changes: within a codebase, `mysqld --upgrade=AUTO`
  upgrades the data dictionary and the VillageSQL schema from 0.0.6 to
  0.0.7 at the first start.

## Extensions

- The server plug `extensions` keeps its name and target; only its
  `content` label changes to `villagesql-extensions`. All three tracks use
  the same label, so one provider snap connects to any of them.
- Both example providers change their slot label accordingly.
  `villagesql-uuid` moves to upstream tag `0.0.7` and SDK 0.0.7;
  `villagesql-hello` only changes the label and version.
- The 0.0.6 providers on `latest/edge` carry the old label. Whether snapd
  keeps an existing connection when both sides are refreshed with a new
  label is verified by the refresh test below, not assumed; the docs
  describe the outcome, including the one-off `snap connect` if needed.
- `villagesql.extensions list`, the inventory and the `veb` assembly are
  unchanged.

## Release and CI

- `.github/workflows/release.yaml` is triggered by `workflow_dispatch`
  only. A first job derives the track from the branch name
  (`8.4/edge` gives `8.4`) and passes it to the shared release workflow,
  so the file is identical on every branch. Pushing to `*/edge` no longer
  publishes: the maintainer uploads after local testing.
- `ci.yaml` is unchanged in structure. It builds the branch's snap and
  runs the spread suite; the suite now also talks to the Snap Store (see
  Tests), which the GitHub runners allow.
- `latest`: today's users installed with `--edge` and track
  `latest/edge`. The maintainer uploads every `8.4` build to `latest` as
  well until the store's default track is set to `8.4`; docs/refresh.md
  tells users how to move to `8.4/edge` explicitly.

## Tests

`spread.yaml` gains one branch-specific variable, `CODEBASE`, set to the
branch's codebase. Changes to `spread/tests/`:

- `refresh` is extended. When no local previous build is present under
  `spread/`, it installs the previous release from the store
  (`villagesql --edge`) together with both example providers from
  `latest/edge`, connects them, runs `INSTALL EXTENSION vsql_uuid` and
  creates a table with a `uuid` column, then refreshes to the built
  artifact. On a `mysql-8.4` branch the refresh must succeed, the service
  must come back, data and accounts must survive, the providers must still
  be listed by `villagesql.extensions list` and `SELECT UUID_V7()` must
  work. On any other codebase the same refresh must be rolled back with
  the codebase message and the old revision must keep serving. The test
  reads `CODEBASE` to pick the expectation.
- `refresh_major_guard` is renamed `refresh_codebase_guard`. It writes a
  foreign codebase into `.snap-data-codebase` and expects a rollback, and
  it also removes the new marker and writes `8.4` into the legacy one and
  expects the refresh to be accepted on `mysql-8.4` and rejected
  elsewhere.
- `extension_snap_hello` and `extension_snap_uuid` run unchanged on every
  branch, which is what shows a single provider build serving all three
  codebases. `extension_snap_uuid` asserts version `0.0.7`.
- `smoke` additionally checks `.snap-data-codebase` and
  `@@villagesql_server_version` (`${CODEBASE}_0.0.7`) against `CODEBASE`.
- `cli_config` derives the SDK version from the recipe: since 0.0.7
  `villagesql_config --version` prints `0.0.7` without a codebase.
- `cli_mysqldump` passes `--set-gtid-purged=OFF`: MySQL 9.7 enables GTIDs
  by default, so a dump restored onto the same server fails otherwise.
  docs/commands.md documents this for users of the `9.7` track.
- A `percona` smoke check on `percona-8.4/edge` only: the audit log
  plugin loads and `CREATE TABLE ... ENGINE=ROCKSDB` fails, matching the
  upstream Percona page.

Local one-off verification before the first upload: the 0.0.6 artifacts
already in the working tree (server and both providers) are placed under
`spread/` so that `refresh` starts from the exact revision users have.

## Documentation

- README: the snap offers three tracks; install commands per track;
  `latest` currently equals `8.4`. The description in `snapcraft.yaml`
  says which codebase the branch builds.
- docs/refresh.md: "major versions" becomes "codebases and tracks", with
  the dump-and-restore recipe kept and `--channel <track>/stable` in it.
- docs/extensions.md and extensions/README.md: new label, the statement
  that one bundle serves all tracks, SDK 0.0.7 in the build example.
- SECURITY.md and the snap metadata are unchanged.

## Out of scope

- In-place migration between codebases (upstream has none).
- Moving existing `latest/edge` users to the `8.4` track automatically;
  snapd has no mechanism for it.
- Exposing `vsql_allow_preview_extensions` (custom indexes preview) as a
  snap option.
- Rust SDK extensions and any third example provider.
- Automatic store publishing from CI (the dispatch workflow is kept ready
  for it).
