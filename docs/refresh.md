# Refresh (upgrades)

`snap refresh villagesql` stops the service, installs the new revision, runs
the snap's `post-refresh` hook and starts the service again. The data
directory lives in `/var/snap/villagesql/common`, which is shared by all
revisions, so data, accounts and configuration are kept.

## Releases within a codebase (0.0.6 to 0.0.7, 8.4.x to 8.4.y)

Handled in place: `mysqld` upgrades the data dictionary and the VillageSQL
schema at start-up (`--upgrade=AUTO`). Nothing to do.

## Codebases and tracks

Upstream publishes VillageSQL for three *codebases*, each on its own snap
track: `8.4` (`mysql-8.4`), `9.7` (`mysql-9.7`) and `percona-8.4`
(`percona-8.4`). A data directory belongs to the codebase that initialised
it and upstream has no in-place migration between codebases, so a refresh
across tracks is refused. The `post-refresh` hook compares the codebase
recorded in `/var/snap/villagesql/common/.snap-data-codebase` with the one
the new revision was built from (`/snap/villagesql/current/codebase`) and
aborts on a mismatch; snapd rolls back to the previous revision and the
service keeps running on the old data. An install made by 0.0.6 only has
the older marker `.snap-data-major` holding `8.4`, which counts as
`mysql-8.4` and is replaced at the next start.

To move to another track, dump and restore:

```shell
sudo villagesql.mysqldump -uroot --all-databases --routines --events > all.sql
sudo snap remove --purge villagesql
sudo snap install villagesql --channel 9.7/stable
sudo villagesql.mysql -uroot < all.sql
```

## Rolling back

`sudo snap revert villagesql` returns to the previous revision. Because the
data dictionary may already have been upgraded by the newer minor, prefer a
dump taken before the refresh if the revert fails to start.
