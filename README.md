# VillageSQL snap

This repository contains the packaging metadata for creating a
[snap](https://snapcraft.io/) of [VillageSQL](https://villagesql.com), the
extensible drop-in replacement for MySQL, built from the upstream sources.

For more information about using the snap see the [`docs/`](/docs/) folder:
[commands](docs/commands.md), [configuration](docs/configuration.md),
[refresh](docs/refresh.md), [extensions](docs/extensions.md) and, for
maintainers, [release](docs/release.md).

## Tracks

Upstream publishes every VillageSQL release for three *codebases*. The snap
offers one track per codebase, built from the git branch of the same name:

| Track | Codebase | Base server | Branch |
| --- | --- | --- | --- |
| `8.4` (`latest` is the same build for now) | `mysql-8.4` | MySQL 8.4 | `8.4/edge` |
| `9.7` | `mysql-9.7` | MySQL 9.7 | `9.7/edge` |
| `percona-8.4` (this branch) | `percona-8.4` | Percona Server 8.4 | `percona-8.4/edge` |

A data directory belongs to one codebase and cannot be moved between
tracks, see [docs/refresh.md](docs/refresh.md).

## Install the snap

```shell
sudo snap install villagesql --channel 8.4/edge          # MySQL 8.4 codebase
sudo snap install villagesql --channel 9.7/edge          # MySQL 9.7 codebase
sudo snap install villagesql --channel percona-8.4/edge  # Percona Server 8.4 codebase
sudo villagesql.mysql -uroot
```

`root@localhost` authenticates through the Unix socket (`auth_socket`), so
`sudo` is all that is needed locally and root can never log in over TCP.
Create ordinary accounts for applications:

```shell
sudo villagesql.mysql -uroot -e "CREATE USER app@'%' IDENTIFIED BY 'secret'; GRANT ALL ON app.* TO app@'%';"
```

## Extensions

Extensions are `.veb` bundles loaded with `INSTALL EXTENSION`. The snap
ships the upstream examples and accepts more from *extension snaps*
connected through the content interface:

```shell
sudo snap install villagesql-hello
sudo snap connect villagesql:extensions villagesql-hello:extensions
sudo snap restart villagesql
sudo villagesql.extensions list
sudo villagesql.mysql -uroot -e "INSTALL EXTENSION vsql_hello; SELECT hello('snap');"
```

See [docs/extensions.md](docs/extensions.md) and the example providers in
[`extensions/`](extensions/).

## Build the snap

Install and configure prerequisites:

```bash
sudo snap install snapcraft --classic
sudo snap install lxd
sudo lxd init --auto
```

Build (compiling MySQL takes about an hour on 12 cores) and install with the
`--dangerous` flag to keep strict confinement (see snap
[installation modes](https://snapcraft.io/docs/install-modes)):

```bash
snapcraft pack
sudo snap install ./villagesql_*.snap --dangerous --jailmode
```

## Test the snap

[Spread](https://github.com/canonical/spread) tests run through snapcraft on
Ubuntu 22.04, 24.04 and 26.04:

```bash
snapcraft test                                            # run all tests on all systems
ls -la spread/tests/                                      # list all tests
snapcraft test -- craft:ubuntu-24.04:spread/tests/smoke   # one test on one system
snapcraft test --debug                                    # open a shell in a failed test
tox run -e lint                                           # yamllint
```

The `extension_snap_*` tests expect the example extension snaps to be packed
next to their `snap/` directories, see [`extensions/`](/extensions/).

## License and trademark

The VillageSQL snap packaging is free software, distributed under the
[Apache Software License, version 2.0](LICENSE). It builds, installs and
depends on [VillageSQL Server](https://github.com/villagesql/villagesql-server)
and MySQL, which are licensed under the GNU General Public License, version 2.

MySQL is a trademark of Oracle Corporation. VillageSQL is a trademark of its
respective owners. This snap is not sponsored, endorsed, or affiliated with
either.
