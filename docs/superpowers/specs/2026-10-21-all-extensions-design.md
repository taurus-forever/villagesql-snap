# Every upstream extension as a snap (design)

Date: 2026-10-21. Branch `8.4/edge` (shared work, merged into `9.7/edge` and
`percona-8.4/edge`). Follows the pattern of `extensions/villagesql-hello` and
`extensions/villagesql-uuid`.

## Intent

The upstream catalogue at <https://villagesql.com/docs/mysql-8.4/stable/extensions>
lists 22 extensions beyond the built-in examples. Today the snap offers two of
them as provider snaps. The goal is that someone with the `villagesql` snap
can install **any** extension from the catalogue with `snap install
villagesql-<name>` and play with it, on every track, and that each provider
is built and released by CI rather than by hand.

## Goals

- One provider snap per upstream extension, under `extensions/<name>/`,
  built from the upstream repository at a pinned tag (or commit when the
  repository has no tags) against the published SDK tarball, exactly like
  `villagesql-uuid`.
- Every provider loads on the current server (`0.0.7`, all three tracks).
  Where that needs a server change (shared libraries, see below) the server
  snap changes too.
- One spread test proves every provider installs, registers with
  `INSTALL EXTENSION` and answers one query, in a single server with all
  providers connected at once.
- CI builds the providers as artifacts, the spread run consumes them, and a
  dispatchable workflow releases them to the store.

## Non-goals

- Bundling all extensions into one snap. The user asked for the hello/uuid
  pattern; a single `villagesql-extensions` snap is a possible later
  convenience and nothing here prevents it (it would be one more provider
  directory exposing one `veb/` with every bundle).
- Shipping provider-specific shared libraries inside providers with an
  `LD_LIBRARY_PATH` scheme in the server. Rejected for now: a provider could
  then shadow the base's `libssl` for `mysqld`. Libraries live in the server
  snap (see Constraints).
- Per-extension functional coverage beyond one smoke query. Upstream's MTR
  suites own that.
- Bumping `villagesql-uuid` to its new `0.0.8` tag. It follows the server
  release cadence in `docs/release.md`; note it there for the next bump.
- riscv64 CI builds (see `docs/release.md`: no runner yet).

## Anti-goals

- A provider that builds but cannot load (missing library, preview API
  disabled) silently listed as "available". Every provider in the repo is in
  the all-providers spread test, or it is not in the repo.
- Turning the server's CI test job into a multi-hour job by packing twenty
  providers inside it (today it packs the two by hand).

## The catalogue, surveyed 2026-10-21

All repositories build with CMake, `find_package(VillageSQL)` through their own
`cmake/FindVillageSQL.cmake`, honour `-DVillageSQL_SDK_DIR=`, and produce
`build/<name>.veb`, unless noted. Licence GPL-2.0 everywhere (manifest), with
a `LICENSE` file in every repo except `vsql-prometheus-exporter`.

| Snap | Bundle | Source, pin | Build deps beyond SDK | Runtime libs | Notes |
| --- | --- | --- | --- | --- | --- |
| villagesql-ai | vsql_ai | villagesql/vsql-ai `0.0.7` | libssl-dev | libssl (in snap) | HTTP to AI APIs via OpenSSL |
| villagesql-crypto | vsql_crypto | villagesql/vsql-crypto `0.0.7` | libssl-dev | libssl | |
| villagesql-cube | vsql_cube | villagesql/vsql-cube `0.0.6` | | | |
| villagesql-http | vsql_http | villagesql/vsql-http `0.0.3` | libcurl4-openssl-dev | **libcurl** | |
| villagesql-network-address | vsql_network_address | villagesql/vsql-network-address `0.0.7` | libssl-dev | libssl | |
| villagesql-boolean | vsql_boolean | villagesql/vsql-boolean `0.0.3` | | | |
| villagesql-rest | vsql_rest | villagesql/vsql-rest `0.0.10` | libssl-dev | libssl | **preview**; listens on a port |
| villagesql-trgm | vsql_trgm | villagesql/vsql-trgm `0.0.4` | | | |
| villagesql-fuzzystrmatch | vsql_fuzzystrmatch | villagesql/vsql-fuzzystrmatch `0.0.1` | | | |
| villagesql-currency | vsql_currency | villagesql/vsql-currency `0.0.1` | **Rust 1.87+, cargo-vsql 0.0.6** | | Rust SDK from crates.io |
| villagesql-oauth2 | vsql_oauth2 | villagesql/vsql-oauth2 `0.0.4` | libssl-dev, libcurl4-openssl-dev | **libcurl** | **preview**; auth plugin |
| villagesql-stat-ch | vsql_stat_ch | villagesql/vsql-stat-ch `0.0.3` + submodules | libcurl4-openssl-dev, liblz4-dev, libzstd-dev | **libcurl, liblz4, libzstd** | **preview**; needs ClickHouse to do anything |
| villagesql-mcp | vsql_mcp | villagesql/vsql-mcp `0.0.7` | **Rust 1.88+, cargo-vsql 0.0.6** | | **preview**; listens on a port |
| villagesql-duckdb | vsql_duckdb | villagesql/vsql-duckdb `0.0.3` | libssl-dev, libcurl4-openssl-dev, git | **libcurl** | **preview**; builds DuckDB v1.5.5 from source (long) |
| villagesql-statistics | vsql_statistics | ronaldbradford/vsql-statistics `v.0.3` | | | manifest says 0.5.0 |
| villagesql-prometheus-exporter | prometheus_exporter | ProxySQL/vsql-prometheus-exporter `v0.1.0` | | | wants `include-dev/` headers; may not build on SDK 0.0.7 |
| villagesql-luhn | vsql_luhn | intojhanurag/vsql-luhn `de5afe2` | | | no tags |
| villagesql-nanoid | vsql_nanoid | intojhanurag/vsql-nanoid `9b03e82` | libssl-dev | libssl | no tags |
| villagesql-slugify | vsql_slugify | intojhanurag/vsql-slugify `0799b26` | | | no tags |
| villagesql-pgjwt | vsql_pgjwt | intojhanurag/vsql-pgjwt `fd2e02d` | libssl-dev | libssl | no tags |
| villagesql-address-standardizer | vsql_address_standardizer | jobala/vsql-address-standardizer `ebe73e3` | | | no tags |

`vsql_uuid` (already in the repo) completes the catalogue. `vsql_simple`,
`vsql_complex` and `vsql_tvector` are built into the server.

Preview extensions (`vsql_rest`, `vsql_oauth2`, `vsql_stat_ch`, `vsql_mcp`,
`vsql_duckdb`) only load when the server runs with
`vsql_allow_preview_extensions=ON`.

## Constraints and decisions

1. **Shared libraries come from the server snap.** `mysqld` dlopens the
   bundle's `.so`, so its `DT_NEEDED` libraries must resolve inside the
   `villagesql` snap. The server already stages `libssl3t64`. It additionally
   stages `libcurl4t64`, `liblz4-1` and `libzstd1` (a few MB; Ubuntu main) so
   http, oauth2, stat-ch and duckdb load. This is a server change on
   `8.4/edge`, merged to the other two tracks like any shared work, and the
   four providers need a server built from it (the 0.0.7 store revisions
   lack libcurl). `docs/extensions.md` documents the list of libraries a
   provider may rely on.
2. **Provider layout stays as documented**: `$SNAP/<dir>/veb/<bundle>.veb`,
   `manifest` with `VERSION=`, licence under `licenses/`. `<dir>` is the snap
   name without the `villagesql-` prefix.
3. **Pins.** Tagged repos: the newest tag. Untagged repos: the commit hash
   seen 2026-10-21, snap version `<manifest version>+git<7 chars>`.
   Version strings are the upstream manifest version so `villagesql.extensions
   list` and `snap list` agree.
4. **SDK 0.0.7 for every new provider** (the current server). `villagesql-hello`
   keeps SDK 0.0.6 on purpose (compatibility demonstration).
5. **Rust providers** use `plugin: nil` with the `rustup` build snap, install
   `cargo-vsql` (`cargo install cargo-vsql --locked`) and run
   `cargo vsql package`, which writes `dist/<name>.veb` with no server
   checkout. If `cargo vsql package` turns out to need a server build dir,
   fall back to `cargo build --release` plus hand-assembling the `.veb` (a
   tar of the `.so` and `manifest.json`, as `tar -tf` on the C++ bundles
   shows).
6. **Preview providers** are in the repo and in the test; the test sets
   `snap set villagesql vsql-allow-preview-extensions=ON` before the restart
   (the configure hook validates options with `mysqld --validate-config`).
   Their READMEs in the repo and `docs/extensions.md` say the flag is needed.
7. **DuckDB** is kept in the repo (it is in the catalogue) but is the one
   provider allowed to be absent from CI if the hosted runners cannot build
   it inside the job time limit; it is then built and uploaded by hand like
   riscv64, and documented so. Decided after one measured CI attempt.
8. **prometheus_exporter** is attempted against SDK 0.0.7; if it does not
   compile it is left out with a note in `extensions/README.md` (it targets
   a development branch of the server and has no licence file).
9. **One all-providers spread test** (`spread/tests/extension_snaps_all`)
   installs every `extensions/*/*.snap`, connects them, sets the preview
   flag, restarts once, then for each bundle checks the `INVENTORY` line,
   `INSTALL EXTENSION`, one query and `UNINSTALL EXTENSION`. Network-serving
   extensions (rest, mcp, prometheus) are checked by `INSTALL` plus a
   sysvar read, not by starting their listener. The existing hello and uuid
   tests stay as the detailed walkthroughs.
10. **CI.** `ci.yaml` gains a `build-extensions` job: a matrix over the
    provider directories calling `build_snap.yaml` with
    `path-to-snap-project-directory: extensions/<name>` and
    `artifact-prefix: packed-extension`. The test job downloads
    `packed-extension-*-<arch>` into `extensions/<name>/` instead of packing
    providers itself. The matrix list is the single source of truth and is
    checked by a lint step against `ls extensions/` so a new directory
    cannot be forgotten.
11. **CD.** `release-extensions.yaml` (`workflow_dispatch`, input
    `extensions`: `all` or a space-separated list) calls `ci.yaml` and then
    `release_snap_edge.yaml` per provider with `track: latest`. Store names
    must be registered by the maintainer first (`snapcraft register
    villagesql-<name>`, all 20 are free as of 2026-10-21). Only the
    maintainer's `SNAP_STORE_TOKEN_EDGE` secret needs to cover the new names.

## Implementation order (the proposal)

Extensions first, CI immediately after, in three deliveries each leaving a
working tree:

1. **C++ providers + server libraries + the all-providers test** (this is
   most of the value and each provider packs in seconds). Includes the CI
   restructuring (`build-extensions` matrix, test job downloads artifacts)
   because the existing "pack providers inside the test job" loop would not
   survive twenty providers. CI first without providers would have nothing
   to build; providers first without the CI change would break the test job.
2. **Rust providers** (currency, mcp): a different toolchain, worth isolating.
3. **DuckDB**, then the release workflow once at least one CI run has
   produced artifacts for every provider, then the store registrations and
   the first dispatched release (maintainer).

## Left to the builder

- Exact smoke query per extension (take it from each README's first example).
- Whether `cargo vsql package` works offline inside the snapcraft LXD build
  (it needs crates.io; network is available during `override-build`).
- DuckDB build time on the 4 vCPU runners and the resulting decision 7.
- Lint and `actionlint` conventions as in `docs/release.md`.
