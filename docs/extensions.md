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

Every extension of the upstream catalogue is available this way, one
provider snap each, all named `villagesql-<name>`:

| Snap | Bundle | | Snap | Bundle |
| --- | --- | --- | --- | --- |
| `villagesql-ai` | `vsql_ai` | | `villagesql-network-address` | `vsql_network_address` |
| `villagesql-boolean` | `vsql_boolean` | | `villagesql-oauth2` | `vsql_oauth2` (preview) |
| `villagesql-crypto` | `vsql_crypto` | | `villagesql-pgjwt` | `vsql_pgjwt` |
| `villagesql-cube` | `vsql_cube` | | `villagesql-rest` | `vsql_rest` (preview) |
| `villagesql-currency` | `vsql_currency` | | `villagesql-slugify` | `vsql_slugify` |
| `villagesql-duckdb` | `vsql_duckdb` (preview) | | `villagesql-stat-ch` | `vsql_stat_ch` (preview) |
| `villagesql-fuzzystrmatch` | `vsql_fuzzystrmatch` | | `villagesql-statistics` | `vsql_statistics` |
| `villagesql-http` | `vsql_http` | | `villagesql-trgm` | `vsql_trgm` |
| `villagesql-luhn` | `vsql_luhn` | | `villagesql-uuid` | `vsql_uuid` |
| `villagesql-mcp` | `vsql_mcp` (preview) | | `villagesql-address-standardizer` | `vsql_address_standardizer` |
| `villagesql-nanoid` | `vsql_nanoid` | | `villagesql-hello` | `vsql_hello` (example) |

The sources, pins and one-line descriptions are in
[`extensions/README.md`](/extensions/README.md).

### Preview extensions

`vsql_rest`, `vsql_oauth2`, `vsql_stat_ch`, `vsql_mcp` and `vsql_duckdb` use
VEF APIs that upstream may still change. The server refuses to install them
unless preview extensions are allowed:

```shell
sudo snap set villagesql vsql-allow-preview-extensions=ON   # restarts the server
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_rest; SELECT @@vsql_rest.port;"
```

`sudo snap unset villagesql vsql-allow-preview-extensions` switches it off
again (uninstall the preview extensions first).

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

## One bundle, every track

The extension SDK and the VEF ABI are codebase-independent: upstream ships
one SDK tarball per VillageSQL release for all codebases, and a bundle talks
to the server through a protocol-versioned ABI, so a `.veb` built once
loads on the `8.4`, `9.7` and `percona-8.4` tracks alike. Provider snaps
therefore need no per-track builds and connect to any track through the
same content label, `villagesql-extensions`. Bundles built against an older
SDK keep loading on newer servers (protocol negotiation); the
`villagesql-hello` example is built with SDK 0.0.6 on purpose.

## Writing a provider snap

A provider is a normal strict snap with a content slot labelled
`villagesql-extensions`:

```yaml
slots:
  extensions:
    interface: content
    content: villagesql-extensions
    source:
      read:
        - $SNAP/<dir>
```

`$SNAP/<dir>/` must contain `veb/<name>.veb` (or `veb/<name>-<version>.veb`)
and may contain `manifest` with a `VERSION=` line.

**Libraries a bundle may link against.** `mysqld` dlopens the bundle's
shared object inside the `villagesql` snap, so every library it needs must
be there: the core26 base (glibc, libstdc++, zlib), `libssl`/`libcrypto` 3,
`libcurl` 4, `liblz4` 1, `libzstd` 1, `libaio`, `libnuma` and `libtirpc`.
Anything else has to be linked statically into the bundle, or added to the
server snap's `stage-packages` first. Build the bundle against
the published SDK tarball of the same VillageSQL version
(`villagesql-extension-sdk-0.0.7.tar.gz` from the upstream GitHub release):
no server build is needed, a provider builds in seconds. See
`extensions/villagesql-hello` for a from-scratch C++ extension and
`extensions/villagesql-uuid` for packaging an upstream extension repository.

The snap also ships the SDK it was built with (headers and the CMake
package), so an extension can be compiled on a machine that only has the
snap installed. `villagesql.config` prints the flags:

```shell
sudo villagesql.config --version        # 0.0.7
sudo villagesql.config --cmake          # -DCMAKE_PREFIX_PATH=/snap/villagesql/<rev>/usr
cmake -S . -B build $(sudo villagesql.config --cmake) && cmake --build build
sudo cp build/my_extension.veb /var/snap/villagesql/common/veb/   # until the next restart
```

Bundles copied into `/var/snap/villagesql/common/veb/` by hand are removed
at the next service start (the directory is regenerated); ship them as an
extension snap for anything permanent.
