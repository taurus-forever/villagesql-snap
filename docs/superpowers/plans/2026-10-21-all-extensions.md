# All Upstream Extensions as Provider Snaps: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every extension in the upstream catalogue becomes a `villagesql-<name>` provider snap under `extensions/`, loads on the 0.0.7 server, is covered by one spread test, and is built and released by CI.

**Architecture:** Each provider is an independent snapcraft project copied from `extensions/villagesql-uuid` (CMake + SDK tarball) or a Rust variant (`cargo vsql package`). The server snap stages the three shared libraries the providers need. `ci.yaml` builds providers in a matrix and the test job downloads them; `release-extensions.yaml` releases them to `latest/edge`.

**Tech Stack:** snapcraft (core26), CMake, VillageSQL extension SDK 0.0.7, Rust + cargo-vsql 0.0.6, spread, GitHub Actions with canonical/data-platform-workflows v53.0.0.

**Spec:** `docs/superpowers/specs/2026-10-21-all-extensions-design.md`

## Global Constraints

- Branch `8.4/edge`; nothing here is codebase-specific (the other tracks merge it).
- Provider snap name `villagesql-<dir>`, content dir `$SNAP/<dir>`, slot label `villagesql-extensions`, layout `<dir>/veb/<bundle>.veb`, `<dir>/manifest` (`VERSION=<snap version>`), `<dir>/licenses/LICENSE-<snap name>`.
- SDK tarball: `https://github.com/villagesql/villagesql-server/releases/download/release%2F0.0.7/villagesql-extension-sdk-0.0.7.tar.gz`, unpacked with `--strip-components=1` into `sdk/`.
- Pins and versions exactly as the spec table: tagged repos use the tag as `source-tag` and the manifest version as snap `version`; untagged repos use `source-commit` and version `<manifest version>+git<7 chars>`.
- `grade: devel`, `confinement: strict`, `platforms: amd64, arm64, riscv64`, `base: core26` (as in uuid).
- Preview bundles (`vsql_rest`, `vsql_oauth2`, `vsql_stat_ch`, `vsql_mcp`, `vsql_duckdb`) need `snap set villagesql vsql-allow-preview-extensions=ON` and a restart.
- Lint: `tox run -e lint` must stay green; `actionlint` exceptions as in `docs/release.md`.
- Commit after every task; keep packed `*.snap` files out of git (already ignored).

## Review Focus

1. A provider that is connected but whose bundle cannot load must not stop the server from starting: Task 5's test connects all providers before one restart and asserts `mysqladmin ping` succeeds.
2. A preview bundle installed without the flag must fail with mysqld's error, not crash: Task 5 asserts `INSTALL EXTENSION vsql_rest` fails before the flag is set.
3. A missing shared library shows up only at `INSTALL EXTENSION` time with a dlopen error: Task 1 asserts the libraries are in the server snap and Task 5 installs the four libcurl users.
4. A new `extensions/<dir>` not added to the CI matrix would never be built: Task 8 adds a lint step comparing the matrix to the directory listing.
5. The `release-extensions.yaml` filter must not release everything when a typo is made in the input: Task 9 fails the workflow when a requested name matches no provider.

---

### Task 1: Server snap stages the shared libraries providers link against

**Files:**
- Modify: `snap/snapcraft.yaml` (`parts.villagesql.stage-packages`)
- Modify: `docs/extensions.md` ("Writing a provider snap")

**Interfaces:**
- Produces: `libcurl.so.4`, `liblz4.so.1`, `libzstd.so.1` resolvable by `mysqld` inside the snap.

- [ ] **Step 1: Add the packages**

Add `libcurl4t64`, `liblz4-1`, `libzstd1` to `stage-packages` with a comment: shared libraries that upstream extension bundles link against (http, oauth2, stat-ch, duckdb); `mysqld` dlopens bundles, so their libraries must live in this snap.

- [ ] **Step 2: Document the list**

In `docs/extensions.md`, after the provider layout paragraph, add a short "Libraries a bundle may link against" paragraph: `libssl`/`libcrypto` 3, `libcurl` 4, `liblz4` 1, `libzstd` 1, `libaio`, `libnuma`, `libtirpc`, and the core26 base; anything else must be linked statically into the bundle or added to the server snap.

- [ ] **Step 3: Build the server and check**

Run: `snapcraft pack` (~15 min; start it and continue with Task 2 while it runs)
Then: `unsquashfs -l villagesql_8.4.11-0.0.7_amd64.snap | grep -E 'libcurl.so.4|liblz4.so.1|libzstd.so.1'`
Expected: three matching lines.

- [ ] **Step 4: Commit**

```bash
git add snap/snapcraft.yaml docs/extensions.md
git commit -m "Stage libcurl, lz4 and zstd for extension bundles that link against them"
```

### Task 2: Template provider: villagesql-crypto, verified end to end

**Files:**
- Create: `extensions/villagesql-crypto/snap/snapcraft.yaml`

**Interfaces:**
- Produces: the CMake provider recipe every C++ provider in Task 3 copies. Variable fields: `name`, `version`, `summary`, `description`, source (`source`, `source-tag` or `source-commit`), extra `build-packages`, `DIR`, `BUNDLE`, licence file name.

- [ ] **Step 1: Write the recipe**

Copy `extensions/villagesql-uuid/snap/snapcraft.yaml`. Set `name: villagesql-crypto`, `version: '0.0.7'`, summary "vsql_crypto extension for the VillageSQL snap (content interface)", description from the upstream README's first paragraph plus the four-line install snippet (`INSTALL EXTENSION vsql_crypto; SELECT crypto_version();`), `source: https://github.com/villagesql/vsql-crypto.git`, `source-tag: '0.0.7'`, slot `read: [$SNAP/crypto]`, part `crypto`, build-packages as uuid (`libssl-dev` included), build step identical to uuid with `OUT="$CRAFT_PART_INSTALL/crypto"`, `vsql_crypto.veb`, `LICENSE-villagesql-crypto`.

- [ ] **Step 2: Pack**

Run: `(cd extensions/villagesql-crypto && snapcraft pack)`
Expected: `villagesql-crypto_0.0.7_amd64.snap`; `unsquashfs -l` shows `crypto/veb/vsql_crypto.veb`, `crypto/manifest`, `crypto/licenses/LICENSE-villagesql-crypto`.

- [ ] **Step 3: Verify on a running server**

Run (host, server from Task 1 installed with `--dangerous --jailmode`, or the dist 0.0.7 build):
```bash
sudo snap install ./extensions/villagesql-crypto/villagesql-crypto_0.0.7_amd64.snap --dangerous
sudo snap connect villagesql:extensions villagesql-crypto:extensions
sudo snap restart villagesql && sleep 5
sudo villagesql.extensions list | grep -E '^vsql_crypto\s+0\.0\.7\s+snap:crypto'
sudo villagesql.mysql -uroot -N -e "INSTALL EXTENSION vsql_crypto; SELECT crypto_version();"
```
Expected: a version string. Then `UNINSTALL EXTENSION vsql_crypto;` and `snap remove villagesql-crypto`.

- [ ] **Step 4: Commit**

```bash
git add extensions/villagesql-crypto
git commit -m "Add the villagesql-crypto provider snap (vsql_crypto 0.0.7)"
```

### Task 3: The remaining CMake providers

**Files:**
- Create: `extensions/villagesql-<dir>/snap/snapcraft.yaml` for: ai, cube, http, network-address, boolean, rest, trgm, fuzzystrmatch, oauth2, stat-ch, statistics, prometheus-exporter, luhn, nanoid, slugify, pgjwt, address-standardizer.

**Interfaces:**
- Consumes: the Task 2 recipe.
- Produces: one packed `*.snap` per directory, consumed by Task 5 and Task 8.

Per-provider values (dir | version | source | pin | extra build-packages | notes):

| dir | version | source repo | pin | extra build-packages | notes |
| --- | --- | --- | --- | --- | --- |
| ai | 0.0.7 | villagesql/vsql-ai | tag 0.0.7 | libssl-dev | ship `THIRD_PARTY_LICENSES.md` under `licenses/` too |
| cube | 0.0.6 | villagesql/vsql-cube | tag 0.0.6 | | |
| http | 0.0.3 | villagesql/vsql-http | tag 0.0.3 | libcurl4-openssl-dev | |
| network-address | 0.0.7 | villagesql/vsql-network-address | tag 0.0.7 | libssl-dev | |
| boolean | 0.0.3 | villagesql/vsql-boolean | tag 0.0.3 | | |
| rest | 0.0.10 | villagesql/vsql-rest | tag 0.0.10 | libssl-dev | preview; say so in description |
| trgm | 0.0.4 | villagesql/vsql-trgm | tag 0.0.4 | | |
| fuzzystrmatch | 0.0.1 | villagesql/vsql-fuzzystrmatch | tag 0.0.1 | | |
| oauth2 | 0.0.4 | villagesql/vsql-oauth2 | tag 0.0.4 | libssl-dev, libcurl4-openssl-dev | preview |
| stat-ch | 0.0.3 | villagesql/vsql-stat-ch | tag 0.0.3, `source-submodules: [core, third_party/clickhouse-c]` | libcurl4-openssl-dev, liblz4-dev, libzstd-dev, pkg-config | preview |
| statistics | 0.5.0 | ronaldbradford/vsql-statistics | tag v.0.3 | | manifest says 0.5.0; snap version follows the manifest |
| prometheus-exporter | 0.1.0 | ProxySQL/vsql-prometheus-exporter | tag v0.1.0 | | no LICENSE file: skip the licence install line; if the build fails on SDK 0.0.7, delete the directory and note it in `extensions/README.md` |
| luhn | 0.0.1+gitde5afe2 | intojhanurag/vsql-luhn | `source-commit: de5afe2af69d21c420c0e12102b937accef54168` | | |
| nanoid | 0.0.1+git9b03e82 | intojhanurag/vsql-nanoid | `source-commit: 9b03e8259bf79cca5a039cdd9f3116d869cad3fa` | libssl-dev | |
| slugify | 0.0.1+git0799b26 | intojhanurag/vsql-slugify | `source-commit: 0799b263689bc5321af67ac6e05ae3fa68bd1830` | | |
| pgjwt | 0.0.1+gitfd2e02d | intojhanurag/vsql-pgjwt | `source-commit: fd2e02d148670ba007c2bb50abf76e894d74ae3a` | libssl-dev | |
| address-standardizer | 0.0.1+gitebe73e3 | jobala/vsql-address-standardizer | `source-commit: ebe73e3c37ed48b88fef12b074e6fcbc6add34b6` | | pass `-DBUILD_TESTING=OFF` if its CMake builds GTest by default |

- [ ] **Step 1: Write the 17 recipes** from the Task 2 recipe with the values above (`source-depth: 1` only with `source-tag`; `source-commit` needs no depth).

- [ ] **Step 2: Pack all of them**

Run: `for d in extensions/villagesql-*/; do (cd "$d" && snapcraft pack) || echo "FAILED $d"; done`
Expected: one `*.snap` per directory, no `FAILED` line (except a decided prometheus-exporter removal).

- [ ] **Step 3: Commit**

```bash
git add extensions/
git commit -m "Add provider snaps for the CMake extensions of the upstream catalogue"
```

### Task 4: Rust providers: villagesql-currency and villagesql-mcp

**Files:**
- Create: `extensions/villagesql-currency/snap/snapcraft.yaml`
- Create: `extensions/villagesql-mcp/snap/snapcraft.yaml`

**Interfaces:**
- Produces: `currency/veb/vsql_currency.veb` (version 0.0.1), `mcp/veb/vsql_mcp.veb` (version 0.0.7).

- [ ] **Step 1: Write the currency recipe**

Same shape as Task 2, part `plugin: nil`, `source: https://github.com/villagesql/vsql-currency.git`, `source-tag: '0.0.1'`, `build-snaps: [rustup]`, `build-packages: [build-essential, ca-certificates, pkg-config, libssl-dev]`, override-build:
```bash
set -e
rustup default stable
cargo install cargo-vsql --locked --version 0.0.6
cargo vsql package
tar -tf dist/vsql_currency.veb
OUT="$CRAFT_PART_INSTALL/currency"
install -Dm644 dist/vsql_currency.veb "$OUT/veb/vsql_currency.veb"
printf 'VERSION=%s\n' "$CRAFT_PROJECT_VERSION" > "$OUT/manifest"
install -Dm644 LICENSE "$OUT/licenses/LICENSE-villagesql-currency"
```
If `rustup` as a build snap is unavailable inside the build container, use `build-packages: [cargo, rustc]` instead and check `rustc --version` is 1.87 or newer on core26.

- [ ] **Step 2: Write the mcp recipe** likewise (`source-tag: '0.0.7'`, `vsql_mcp.veb`, description marks it preview).

- [ ] **Step 3: Pack both**

Run: `(cd extensions/villagesql-currency && snapcraft pack) && (cd extensions/villagesql-mcp && snapcraft pack)`
Expected: `villagesql-currency_0.0.1_amd64.snap`, `villagesql-mcp_0.0.7_amd64.snap`; `tar -tf` of each bundle lists `manifest.json` and `lib/<name>.so`.

- [ ] **Step 4: Commit**

```bash
git add extensions/villagesql-currency extensions/villagesql-mcp
git commit -m "Add the Rust provider snaps villagesql-currency and villagesql-mcp"
```

### Task 5: One spread test for every provider

**Files:**
- Create: `spread/tests/extension_snaps_all/task.yaml`

**Interfaces:**
- Consumes: `extensions/*/*.snap` (first match per directory, as the hello/uuid tests do).

Smoke table (bundle | query | expected `grep`). Queries come from the upstream READMEs; adjust a query if the README of the pinned version differs, never the expectation of "answers something":

| bundle | query | expected |
| --- | --- | --- |
| vsql_crypto | `SELECT crypto_version();` | non-empty |
| vsql_cube | `SELECT cube_to_string(cube_point(5.0));` | `(5)` |
| vsql_http | `SELECT vsql_http.url_encode('a b');` | `a%20b` |
| vsql_network_address | `CREATE TABLE t.h (ip INET); INSERT INTO t.h VALUES ('10.1.2.3'); SELECT inet_to_string(ip) FROM t.h;` | `10.1.2.3` |
| vsql_boolean | `CREATE TABLE t.b (e STRICTBOOL); INSERT INTO t.b VALUES ('true'); SELECT boolean_to_int(e) FROM t.b;` | `1` |
| vsql_trgm | `SELECT vsql_trgm.trgm_similar('cat','car');` | `1` |
| vsql_fuzzystrmatch | `SELECT vsql_fuzzystrmatch.soundex('Robert');` | `R163` |
| vsql_statistics | `SELECT CAST(STATS_IQR(v) AS CHAR(300)) FROM (SELECT 1.0 v UNION ALL SELECT 2.0 UNION ALL SELECT 3.0 UNION ALL SELECT 4.0) x;` | contains `"q1"` |
| vsql_luhn | `SELECT vsql_luhn.luhn_valid('4539148803436467');` | `1` |
| vsql_nanoid | `SELECT LENGTH(vsql_nanoid.nanoid());` | `21` |
| vsql_slugify | `SELECT vsql_slugify.slugify('Hello, World!');` | `hello-world` |
| vsql_pgjwt | `SELECT JSON_VALUE(vsql_pgjwt.jwt_decode(vsql_pgjwt.jwt_sign('{"sub":"u"}','s','HS256')), '$.payload.sub');` | `u` |
| vsql_address_standardizer | `SELECT address_standardize('1600 Pennsylvania Ave NW Washington DC 20500');` | contains `Pennsylvania` (case-insensitive) |
| vsql_currency | `SELECT vsql_currency.currency_count();` | `164` |
| vsql_ai | installed row in `INFORMATION_SCHEMA.EXTENSIONS` (needs an API key to do more) | `vsql_ai` |
| prometheus_exporter | `SET GLOBAL prometheus_exporter.enabled = ON;` then `curl -s 127.0.0.1:9104/metrics` | contains `mysql_global_status_` |
| vsql_rest (preview) | `SELECT @@vsql_rest.port;` | `3000` |
| vsql_oauth2 (preview) | `SELECT @@vsql_oauth2.jwks_refresh_interval;` | `3600` |
| vsql_stat_ch (preview) | `SELECT @@vsql_stat_ch.clickhouse_port;` | `9000` |
| vsql_mcp (preview) | `SELECT @@vsql_mcp.vsql_mcp_enabled;` | `0` |
| vsql_duckdb (preview, Task 7) | `SELECT duckdb_status();` | contains `v1.5.5` |

- [ ] **Step 1: Write the test**

`summary: Every provider snap in extensions/ loads, installs and answers a query in one server`. `execute:` installs every `extensions/*/*.snap` with `--dangerous` (skip hello and uuid: they have their own tests, and the all-providers run must not depend on the SDK 0.0.6 build), connects each, then: assert `INSTALL EXTENSION vsql_rest` fails before the flag (Review Focus 2), `snap set villagesql vsql-allow-preview-extensions=ON`, one `restart` (helper as in the uuid test), `mysqladmin ping` (Review Focus 1), `cat INVENTORY`, then for each row of the table: `grep -P "^<bundle>\.veb\tsnap:<dir>\t<version>$" INVENTORY`, `INSTALL EXTENSION`, the query piped to the expected grep, `UNINSTALL EXTENSION`. Skip a bundle whose snap is absent only for `villagesql-duckdb` (print `SKIP duckdb (no snap packed)`), fail for any other missing directory snap. Finish with the AppArmor-denial check from the hello test. `restore:` removes every provider snap and `snap unset villagesql vsql-allow-preview-extensions`.

- [ ] **Step 2: Run it on one system**

Run: `snapcraft test -- craft:ubuntu-24.04:spread/tests/extension_snaps_all`
Expected: pass. Fix queries against the pinned READMEs until it does.

- [ ] **Step 3: Run the whole suite**

Run: `snapcraft test`
Expected: all tests pass on the three systems (the `refresh` test still passes with the Task 1 server).

- [ ] **Step 4: Commit**

```bash
git add spread/tests/extension_snaps_all
git commit -m "Spread: install every provider snap at once and smoke-test each bundle"
```

### Task 6: Documentation of the catalogue

**Files:**
- Modify: `extensions/README.md`
- Modify: `docs/extensions.md`
- Modify: `README.md` (extensions paragraph)
- Modify: `docs/release.md` (checklist step 3 and upload map)

- [ ] **Step 1: `extensions/README.md`**: replace the two bullets with a table of every provider (snap name, bundle, upstream repo and pin, "preview" column, one-line purpose), keep the hello/uuid walkthrough, add the preview-flag paragraph and the Rust build note. Mention `villagesql-uuid` 0.0.8 exists upstream and is picked up at the next server bump.

- [ ] **Step 2: `docs/extensions.md`**: under "Extension snaps", list the catalogue by name with `snap install villagesql-<name>`, add a "Preview extensions" subsection (`snap set villagesql vsql-allow-preview-extensions=ON`, `snap restart villagesql`).

- [ ] **Step 3: `docs/release.md`**: step 3 becomes "every `extensions/*/snap/snapcraft.yaml`: `SDK_VERSION`, and `source-tag` where upstream tagged a new version (`git ls-remote --tags` per repo); update the version column in `spread/tests/extension_snaps_all`". Upload map row: `villagesql-<name>_*` to `latest/edge` for every provider, by the release-extensions workflow.

- [ ] **Step 4: `tox run -e lint`** passes. Commit:

```bash
git add extensions/README.md docs/extensions.md README.md docs/release.md
git commit -m "Docs: the full extension catalogue as provider snaps"
```

### Task 7: villagesql-duckdb

**Files:**
- Create: `extensions/villagesql-duckdb/snap/snapcraft.yaml`

- [ ] **Step 1: Write the recipe**: Task 2 shape, `source-tag: '0.0.3'`, `version: '0.0.3'`, build-packages add `git`, `libcurl4-openssl-dev`, `libssl-dev`, `ninja-build`; cmake with `-G Ninja`, `-DVillageSQL_SDK_DIR`, default `DUCKDB_TAG`/`DUCKDB_READERS`; description says preview and that queries over `https://` need network. The build clones DuckDB v1.5.5 itself.

- [ ] **Step 2: Pack and time it**

Run: `time (cd extensions/villagesql-duckdb && snapcraft pack)`
Expected: `villagesql-duckdb_0.0.3_amd64.snap`. Record the wall time in the recipe's comment.

- [ ] **Step 3: Run the all-providers test again** (`snapcraft test -- craft:ubuntu-24.04:spread/tests/extension_snaps_all`): the duckdb row runs instead of `SKIP`.

- [ ] **Step 4: Commit**

```bash
git add extensions/villagesql-duckdb
git commit -m "Add the villagesql-duckdb provider snap (vsql_duckdb 0.0.3, preview)"
```

### Task 8: CI builds the providers and the test job consumes them

**Files:**
- Modify: `.github/workflows/ci.yaml`

**Interfaces:**
- Produces: artifacts `packed-extension-<path>--platform-<arch>` (one per provider and platform) and the matrix list `jobs.build-extensions.strategy.matrix.extension`, consumed by Task 9.

- [ ] **Step 1: Add the `build-extensions` job**

```yaml
  build-extensions:
    name: Build extension snap | ${{ matrix.extension }}
    uses: canonical/data-platform-workflows/.github/workflows/build_snap.yaml@v53.0.0
    strategy:
      fail-fast: false
      matrix:
        extension:
          - villagesql-address-standardizer
          # ... every extensions/ directory, sorted, including hello and uuid
    with:
      path-to-snap-project-directory: extensions/${{ matrix.extension }}
      artifact-prefix: packed-extension
      # Rust providers compile their dependency tree; DuckDB clones and builds DuckDB.
      build-timeout: ${{ matrix.extension == 'villagesql-duckdb' && 300 || 60 }}
    permissions:
      contents: read
    cache-mode: none
```
`ci.yaml`'s `workflow_call` gains the output `extension-artifact-prefix: packed-extension`.

- [ ] **Step 2: Test job downloads providers instead of packing them**

Add `build-extensions` to `needs`; add a step before "Run tests":
```yaml
      - name: Download extension snap(s)
        uses: actions/download-artifact@v8
        with:
          pattern: packed-extension-*--platform-${{ matrix.platform.arch }}
          path: extension-artifacts
      - name: Place extension snaps next to their projects
        run: |
          for f in extension-artifacts/*/*.snap; do
            name="$(basename "$f")"; name="${name%%_*}"
            mv "$f" "extensions/$name/"
          done
          ls extensions/*/*.snap
```
Delete the `for ext in extensions/*/` packing loop and keep the `snapcraft` install (still needed by `snapcraft test`).

- [ ] **Step 3: Lint step for matrix drift (Review Focus 4)**

In the `lint` job add:
```yaml
      - name: Every extensions/ directory is in the build-extensions matrix
        run: |
          diff <(ls -d extensions/*/ | xargs -n1 basename | sort) \
               <(python3 -c 'import yaml,sys;print("\n".join(sorted(yaml.safe_load(open(".github/workflows/ci.yaml"))["jobs"]["build-extensions"]["strategy"]["matrix"]["extension"])))')
```

- [ ] **Step 4: Validate locally**

Run: `tox run -e lint` and `actionlint .github/workflows/ci.yaml` (via `pipx run actionlint` if not installed; the two known conventions may warn, nothing else). Run the Step 3 `diff` locally: empty output.

- [ ] **Step 5: Commit, push, open a PR, watch the run**

```bash
git add .github/workflows/ci.yaml
git commit -m "CI: build every provider snap in a matrix and feed them to the spread run"
```
Expected on GitHub: `build-extensions` green for every provider on amd64 and arm64; DuckDB's time recorded in `docs/release.md`. If DuckDB exceeds its timeout, remove it from the matrix, let the lint diff ignore it explicitly, and document the manual build (spec decision 7).

### Task 9: Release workflow for the providers

**Files:**
- Create: `.github/workflows/release-extensions.yaml`

**Interfaces:**
- Consumes: `ci.yaml` outputs `extension-artifact-prefix`; the Task 8 matrix list (duplicated here: GitHub cannot share a matrix between workflows; the Task 8 lint diff also checks this file).

- [ ] **Step 1: Write the workflow**

`on: workflow_dispatch` with input `extensions` (string, default `all`, description "`all` or space-separated snap names"). Jobs: `ci-tests` (`uses: $/.github/workflows/ci.yaml`), `check-input` (fails when a requested name is not in the list: Review Focus 5), `release` (matrix over the same list, `if: inputs.extensions == 'all' || contains(format(' {0} ', inputs.extensions), format(' {0} ', matrix.extension))`, `uses: canonical/data-platform-workflows/.github/workflows/release_snap_edge.yaml@v53.0.0` with `track: latest`, `artifact-prefix: ${{ needs.ci-tests.outputs.extension-artifact-prefix }}`, `path-to-snap-project-directory: extensions/${{ matrix.extension }}`, secret `SNAP_STORE_TOKEN_EDGE`, `permissions: contents: write`, `cache-mode: none`). Header comment: the maintainer registers each name once (`snapcraft register villagesql-<name>`) and the store token must cover them.

- [ ] **Step 2: Extend the Task 8 lint diff** to this file's matrix too.

- [ ] **Step 3: `tox run -e lint`, `actionlint`; commit**

```bash
git add .github/workflows/release-extensions.yaml .github/workflows/ci.yaml
git commit -m "CI: dispatchable release of the provider snaps to latest/edge"
```

- [ ] **Step 4: Hand-over note for the maintainer** (in the PR description): register the 20 names, check that `release-snap-edge` tag naming does not collide between providers (it creates git tags), then dispatch with `all`.
