# Extension snaps

VillageSQL extensions shipped as *separate* snaps that plug into the
`villagesql` snap through the content interface (see
[docs/extensions.md](../docs/extensions.md)). Each directory is its own
snapcraft project and builds against the published extension SDK tarball (or,
for the Rust ones, the Rust SDK from crates.io), so no server build is needed:

```shell
cd extensions/villagesql-hello
snapcraft pack
sudo snap install ./villagesql-hello_*.snap --dangerous
sudo snap connect villagesql:extensions villagesql-hello:extensions
sudo snap restart villagesql
sudo villagesql.extensions list                        # vsql_hello  snap:hello  INSTALLED no
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap'), shout('snap');"
```

Connecting a provider only makes its bundle visible to the server; like
`CREATE EXTENSION` in PostgreSQL, `INSTALL EXTENSION <name>;` registers it,
and functions are then called inside a query: `SELECT hello('snap');`.
Before disconnecting or removing a provider, run `UNINSTALL EXTENSION <name>;`.

## The catalogue

Every extension of the [upstream catalogue](https://villagesql.com/docs/mysql-8.4/stable/extensions)
(2026-10-21), one provider snap each, plus the `villagesql-hello` example.
*Preview* extensions use VEF APIs that may change between VillageSQL
releases and only load when the server runs with
`sudo snap set villagesql vsql-allow-preview-extensions=ON`.

| Snap | Bundle | Upstream, pinned version | What it adds |
| --- | --- | --- | --- |
| `villagesql-hello` | `vsql_hello` | this repo, 1.0.1 (SDK 0.0.6 on purpose) | `hello()`, `shout()`: the from-scratch C++ example |
| `villagesql-uuid` | `vsql_uuid` | [villagesql/vsql-uuid](https://github.com/villagesql/vsql-uuid) 0.0.7 | `UUID` type, `UUID_V1()`..`UUID_V7()` |
| `villagesql-ai` | `vsql_ai` | [villagesql/vsql-ai](https://github.com/villagesql/vsql-ai) 0.0.7 | `ai_prompt()`, `ai_embed()` against Anthropic, OpenAI, Google or a local model |
| `villagesql-boolean` | `vsql_boolean` | [villagesql/vsql-boolean](https://github.com/villagesql/vsql-boolean) 0.0.3 | strict `STRICTBOOL` type with aggregates |
| `villagesql-crypto` | `vsql_crypto` | [villagesql/vsql-crypto](https://github.com/villagesql/vsql-crypto) 0.0.7 | hashing, HMAC, AES, password hashing, random bytes |
| `villagesql-cube` | `vsql_cube` | [villagesql/vsql-cube](https://github.com/villagesql/vsql-cube) 0.0.6 | n-dimensional `cube` type and geometry |
| `villagesql-currency` | `vsql_currency` | [villagesql/vsql-currency](https://github.com/villagesql/vsql-currency) 0.0.1 (Rust) | ISO 4217 `currency` type |
| `villagesql-duckdb` | `vsql_duckdb` | [villagesql/vsql-duckdb](https://github.com/villagesql/vsql-duckdb) 0.0.3, *preview* | embedded DuckDB over Parquet, CSV and JSON |
| `villagesql-fuzzystrmatch` | `vsql_fuzzystrmatch` | [villagesql/vsql-fuzzystrmatch](https://github.com/villagesql/vsql-fuzzystrmatch) 0.0.1 | Soundex, Levenshtein, Metaphone |
| `villagesql-http` | `vsql_http` | [villagesql/vsql-http](https://github.com/villagesql/vsql-http) 0.0.3 | HTTP client functions, URL encoding |
| `villagesql-mcp` | `vsql_mcp` | [villagesql/vsql-mcp](https://github.com/villagesql/vsql-mcp) 0.0.7 (Rust), *preview* | Model Context Protocol server for AI agents |
| `villagesql-network-address` | `vsql_network_address` | [villagesql/vsql-network-address](https://github.com/villagesql/vsql-network-address) 0.0.7 | `INET`, `CIDR`, `MACADDR`, `MACADDR8` types |
| `villagesql-oauth2` | `vsql_oauth2` | [villagesql/vsql-oauth2](https://github.com/villagesql/vsql-oauth2) 0.0.4, *preview* | JWT authentication via OAuth2/OIDC |
| `villagesql-rest` | `vsql_rest` | [villagesql/vsql-rest](https://github.com/villagesql/vsql-rest) 0.0.10, *preview* | tables as HTTP/HTTPS endpoints |
| `villagesql-stat-ch` | `vsql_stat_ch` | [villagesql/vsql-stat-ch](https://github.com/villagesql/vsql-stat-ch) 0.0.3, *preview* | per-statement telemetry to ClickHouse |
| `villagesql-trgm` | `vsql_trgm` | [villagesql/vsql-trgm](https://github.com/villagesql/vsql-trgm) 0.0.4 | trigram similarity search |
| `villagesql-statistics` | `vsql_statistics` | [ronaldbradford/vsql-statistics](https://github.com/ronaldbradford/vsql-statistics) v.0.3 (manifest 0.5.0) | statistical aggregates and tests as JSON |
| `villagesql-luhn` | `vsql_luhn` | [intojhanurag/vsql-luhn](https://github.com/intojhanurag/vsql-luhn) de5afe2 | Luhn check digits |
| `villagesql-nanoid` | `vsql_nanoid` | [intojhanurag/vsql-nanoid](https://github.com/intojhanurag/vsql-nanoid) 9b03e82 | URL-safe NanoIDs |
| `villagesql-slugify` | `vsql_slugify` | [intojhanurag/vsql-slugify](https://github.com/intojhanurag/vsql-slugify) 0799b26 | URL slugs from text |
| `villagesql-pgjwt` | `vsql_pgjwt` | [intojhanurag/vsql-pgjwt](https://github.com/intojhanurag/vsql-pgjwt) fd2e02d | sign, verify and decode JWTs |
| `villagesql-address-standardizer` | `vsql_address_standardizer` | [jobala/vsql-address-standardizer](https://github.com/jobala/vsql-address-standardizer) ebe73e3 | US postal address parsing |

Not packaged: `prometheus_exporter`
([ProxySQL/vsql-prometheus-exporter](https://github.com/ProxySQL/vsql-prometheus-exporter)
v0.1.0) is written against unreleased development SDK APIs (`run_query`,
`background_thread`, `InstallResult`, system-variable builders) and does not
compile against SDK 0.0.7. `vsql_simple`, `vsql_complex` and `vsql_tvector`
are built into the server snap.

Pins: tagged repositories use their newest tag; the community repositories
without tags are pinned to a commit and get a `+git<hash>` version suffix.
The snap version is the bundle's own manifest version, so `snap list` and
`villagesql.extensions list` agree. All providers except `villagesql-hello`
are built with SDK 0.0.7 (the current server); vsql-uuid 0.0.8 exists
upstream and is picked up at the next server bump (`docs/release.md`).

## Shared libraries

`mysqld` dlopens the bundles, so a bundle may only link against libraries
present in the `villagesql` snap: the core26 base, `libssl`/`libcrypto` 3,
`libcurl` 4, `liblz4` 1, `libzstd` 1 (the last three were added for
vsql_http, vsql_oauth2, vsql_duckdb and vsql_stat_ch). Anything else must be
linked statically or added to the server snap's `stage-packages`.

## Building

```shell
(cd extensions/villagesql-crypto && snapcraft pack)   # a C++ provider: about 2 min
(cd extensions/villagesql-currency && snapcraft pack) # a Rust provider: cargo-vsql from crates.io
(cd extensions/villagesql-duckdb && snapcraft pack)   # clones and builds DuckDB v1.5.5: hours
```

Every pack leaves a ~1.4 GB LXD build container behind; run `snapcraft
clean` in the directory when you are done with it. CI builds the providers
in `.github/workflows/ci.yaml` (`build-extensions`) and the
`release-extensions.yaml` workflow publishes them to `latest/edge`.

The SDK and the VEF ABI are codebase-independent, so one provider build
serves the `8.4`, `9.7` and `percona-8.4` tracks of the `villagesql` snap
alike; providers are published on `latest` only. Store-installed providers
auto-connect (same publisher); side-loaded ones need `snap connect`.

The spread tests expect the packed snaps next to their `snap/` directories:
`extension_snap_hello` and `extension_snap_uuid` are the detailed
walkthroughs, `extension_snaps_all` connects every other provider to one
server and runs one query per bundle.
