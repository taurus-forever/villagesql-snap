# Releasing a new VillageSQL version (maintainer notes)

Everything a maintainer (human or agent) needs to move the snap to the
next upstream release without re-discovering the project. Written after
the 0.0.6 to 0.0.7 update (2026-10-16); the design is in
`docs/superpowers/specs/2026-10-16-villagesql-0.0.7-tracks-design.md`.

## Shape of the project

| Branch | Store track | Codebase (`$SNAP/codebase`) | Snap version pattern | Upstream tag |
| --- | --- | --- | --- | --- |
| `8.4/edge` | `8.4` | `mysql-8.4` | `8.4.<p>-<vsql>` | `publish/mysql-8.4_<vsql>` |
| `9.7/edge` | `9.7` | `mysql-9.7` | `9.7.<p>-<vsql>` | `publish/mysql-9.7_<vsql>` |
| `percona-8.4/edge` | `percona-8.4` | `percona-8.4` | `8.4.<p>-<vsql>+percona` | `publish/percona-8.4_<vsql>` |

- The store's default track is set to `9.7`: `snap install villagesql
  --edge` means `9.7/edge`. `latest` receives no releases. Docs and tests
  name the track they mean (`--channel 8.4/edge`).
- `8.4/edge` carries all shared work. The other branches are merged from
  it (`git merge 8.4/edge`) and differ **only** in `snap/snapcraft.yaml`,
  `spread.yaml` (`CODEBASE`), `README.md` (which row says "this branch")
  and, on Percona, `spread/tests/percona/task.yaml`. Check with
  `git diff 8.4/edge <branch> --stat` after every merge.
- The refresh guard (`snap/local/codebase.sh`, hooks, `mysqld.sh`) compares
  `$SNAP/codebase`, stamped at build time from upstream's `VSQL_VERSION`
  (`VSQL_CODE_BASE=`), with `$SNAP_COMMON/.snap-data-codebase`. Nothing in
  it is version-specific.
- Extension snaps (`extensions/villagesql-*`, one per catalogue entry, see
  `extensions/README.md`) are codebase-independent (one SDK tarball per
  release, protocol-versioned ABI) and live on `latest` only. Old bundles
  keep loading on newer servers.
- Publishing is manual: build, test locally, upload per track. The release
  workflow is `workflow_dispatch` only and derives the track from the
  branch name.

## Where to look upstream for a new release `<vsql>`

```shell
git ls-remote --tags https://github.com/villagesql/villagesql-server.git | grep "<vsql>"
# per codebase, from the publish/ tag:
#   MYSQL_VERSION  -> MYSQL_VERSION_MAJOR/MINOR/PATCH (the snap version's first part)
#   VSQL_VERSION   -> VSQL_CODE_BASE, VSQL_*_VERSION (VSQL_PRE_RELEASE_VERSION=dev is
#                     blanked by -DVSQL_PRE_RELEASE_VERSION= in the recipe)
#   villagesql/bld_tools/setup_linux_build_env.sh -> build-packages (diff codebases against mysql-8.4)
#   villagesql/bld_tools/build_ci.sh              -> cmake flags (Percona: ROCKSDB=0, COREDUMPER=OFF,
#                                                    WITHOUT_COMPONENT_KEYRING_KMIP=ON, AUTH_OPENID_CONNECT=OFF, CURL=system)
curl -fsSL https://api.github.com/repos/villagesql/villagesql-server/releases/tags/release%2F<vsql> \
  | python3 -c 'import json,sys;r=json.load(sys.stdin);print([a["name"] for a in r["assets"]]);print(r["body"])'
# SDK tarball: villagesql-extension-sdk-<vsql>.tar.gz under release/<vsql>; read the
# "Build & Compatibility" and "Extension Framework" sections of the notes for breaking changes.
# vsql-uuid tags: git ls-remote --tags https://github.com/villagesql/vsql-uuid.git
```

## Checklist on `8.4/edge`

1. Park the current release's artifacts for the refresh test: the server
   snap and both provider snaps of the release users have go under
   `spread/` (`spread/villagesql_<old>_<arch>.snap`,
   `spread/villagesql-hello_*`, `spread/villagesql-uuid_*`; `*.snap` is
   git-ignored). Without them (CI) the `refresh` test installs the previous
   release from the store: the branch's own track (`8.4/edge`), or the
   default track (`--edge` = `9.7/edge`) should the branch's track not
   exist yet (a new codebase). It works out the expected outcome from the
   codebase the previous release recorded: same codebase, the refresh must
   succeed; another one (the 0.0.6 builds on `9.7/edge`), the guard must
   roll it back. The providers come from `spread/` too, else from the
   store; when their content label differs from the previous release's
   (0.0.6 from the store, as on arm64 while `8.4/edge` has no 0.0.7 there),
   they are connected after the refresh instead of before.
2. `snap/snapcraft.yaml`: `version`, `source-tag`, summary/description if
   wording changes. `docs/commands.md`: the `SELECT VERSION()` sample.
3. Extensions: every `extensions/villagesql-*/snap/snapcraft.yaml`:
   `SDK_VERSION` (the C++ ones), and `version` + `source-tag` where upstream
   tagged a new release (`git ls-remote --tags https://github.com/<owner>/<repo>.git`
   per repo; the untagged community repos keep their `source-commit` unless
   there is a reason to move it). `villagesql-hello` only if the SDK
   compatibility story changes. Update the version columns in
   `spread/tests/extension_snaps_all/task.yaml` (`PROVIDERS`) and the greps
   in `extension_snap_hello` / `extension_snap_uuid`, and the pins in
   `extensions/README.md`. Docs: `docs/extensions.md` (SDK tarball name).
   The release workflow for providers is `release-extensions.yaml`
   (`workflow_dispatch`, `all` or a list of snap names), track `latest`.
   **Order:** release the servers of all three tracks first, then the
   providers. `villagesql-http`, `-oauth2`, `-stat-ch` and `-duckdb` link
   against libcurl/lz4/zstd, which the server snap ships only since
   2026-10-21; on an older server revision `INSTALL EXTENSION` fails with
   a dlopen error.
4. Build and test (times are for a 12-core host):

   ```shell
   snapcraft pack                                     # ~15 min server build
   (cd extensions/villagesql-hello && snapcraft pack) # seconds
   (cd extensions/villagesql-uuid  && snapcraft pack)
   snapcraft test -- craft:ubuntu-24.04:spread/tests/smoke   # ~3 min, one test
   snapcraft test                                     # ~16 min, 15 tests x 3 systems
   sudo snap install ./villagesql_*.snap --dangerous --jailmode && tox run -e smoke
   tox run -e lint
   ```
5. Commit. Keep the artifacts: `mkdir -p dist && mv villagesql_*.snap extensions/*/*.snap dist/`.

## Checklist per codebase branch

```shell
git switch 9.7/edge && git merge --no-edit 8.4/edge
# edit snap/snapcraft.yaml: version (9.7.<p>-<vsql>) and source-tag only
git diff 8.4/edge --stat          # must list only the branch-specific files
snapcraft pack && snapcraft test  # full suite; refresh takes the rollback path from the 0.0.6 builds under spread/
mv villagesql_*.snap dist/ && git commit -am "..."
```

Same for `percona-8.4/edge` (version `8.4.<p>-<vsql>+percona`). Re-check
the Percona build flags and packages against upstream's `build_ci.sh` and
`setup_linux_build_env.sh` when the Percona base version changes.

## Upload map

| Artifact | Channels |
| --- | --- |
| `villagesql_8.4.*` | `8.4/edge` |
| `villagesql_9.7.*` | `9.7/edge` |
| `villagesql_8.4.*+percona` | `percona-8.4/edge` |
| `villagesql-<name>_*` (every provider) | `latest/edge`, by `release-extensions.yaml` or by hand in the same session as the servers |

The store's self-serve track guardrail accepts only `major.minor` names;
other tracks go through a forum store-request (`percona-8.4` has releases since
2026-10-20).

## Gotchas learned the hard way

- Since 0.0.7 `villagesql_config --version` prints the bare version
  (`0.0.7`), no codebase. The codebase comes from `VSQL_VERSION`.
- Snapcraft's `spread.yaml` schema allows `environment:` only inside a
  suite, not at the top level.
- MySQL 9.7 enables GTIDs by default: `mysqldump` output restored onto the
  same server needs `--set-gtid-purged=OFF` (`cli_mysqldump` test, docs).
- Snapcraft keeps one LXD build instance per project directory. Switching
  branches changes `source-tag`, so the next `snapcraft pack` or
  `snapcraft test` rebuilds the server part (~15 min); `snapcraft test`
  re-packs on its own when the project changed. Keep only one
  `villagesql_*.snap` in the repo root, the one for the checked-out branch.
- Both `extension_snap_*` tests take the first `*.snap` next to the
  provider's `snap/` directory (`ls | head -1`): old provider builds left
  there shadow new ones. Move them to `spread/`.
- The `refresh_codebase_guard` test's `restore:` rewrites the marker; the
  wrapper never re-stamps an existing `.snap-data-codebase`.
- `snap warnings` about an `apiVersion` option after a host install comes
  from another core26 snap on the host, not from this one.
- Percona's client library is `libperconaserverclient.so`; the branch
  primes it out like `libmysqlclient.so` (snapcraft library lint).
- actionlint flags the team conventions `uses: $/.github/workflows/...`
  and `cache-mode: none`; they are intentional (postgresql-snap does the
  same).
