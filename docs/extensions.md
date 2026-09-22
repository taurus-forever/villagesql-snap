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

The snap also ships the SDK it was built with (headers and the CMake
package), so an extension can be compiled on a machine that only has the
snap installed. `villagesql.config` prints the flags:

```shell
sudo villagesql.config --version        # mysql-8.4_0.0.6
sudo villagesql.config --cmake          # -DCMAKE_PREFIX_PATH=/snap/villagesql/<rev>/usr
cmake -S . -B build $(sudo villagesql.config --cmake) && cmake --build build
sudo cp build/my_extension.veb /var/snap/villagesql/common/veb/   # until the next restart
```

Bundles copied into `/var/snap/villagesql/common/veb/` by hand are removed
at the next service start (the directory is regenerated); ship them as an
extension snap for anything permanent.
