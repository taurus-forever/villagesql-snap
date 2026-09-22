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
