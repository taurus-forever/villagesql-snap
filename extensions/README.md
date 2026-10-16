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
sudo villagesql.extensions list                        # vsql_hello  snap:hello  INSTALLED no
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap'), shout('snap');"
```

Connecting a provider only makes its bundle visible to the server; like
`CREATE EXTENSION` in PostgreSQL, `INSTALL EXTENSION <name>;` registers it,
and functions are then called inside a query: `SELECT hello('snap');`.
Before disconnecting or removing a provider, run `UNINSTALL EXTENSION <name>;`.

* `villagesql-hello` (1.0.1): a from-scratch C++ extension (`hello()`,
  `shout()`), built with SDK 0.0.6 on purpose: bundles built against an
  older SDK keep loading on newer servers.
* `villagesql-uuid` (0.0.7): packages the upstream
  [vsql-uuid](https://github.com/villagesql/vsql-uuid) extension (a `UUID`
  type and generators such as `UUID_V7()`), built with SDK 0.0.7.

The SDK and the VEF ABI are codebase-independent, so one provider build
serves the `8.4`, `9.7` and `percona-8.4` tracks of the `villagesql` snap
alike; providers are published on `latest` only. Store-installed providers
auto-connect (same publisher); side-loaded ones need `snap connect`.

The spread tests `spread/tests/extension_snap_*` expect the packed snaps next
to their `snap/` directories.
