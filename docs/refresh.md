# Refresh (upgrades)

`snap refresh villagesql` stops the service, installs the new revision, runs
the snap's `post-refresh` hook and starts the service again. The data
directory lives in `/var/snap/villagesql/common`, which is shared by all
revisions, so data, accounts and configuration are kept.

## Minor versions (8.4.x to 8.4.y)

Handled in place: `mysqld` upgrades the data dictionary at start-up
(`--upgrade=AUTO`). Nothing to do.

## Major versions (for example 8.4 to 9.7)

Not done in place. The `post-refresh` hook compares the major recorded in
`/var/snap/villagesql/common/.snap-data-major` with the one the new revision
provides and aborts the refresh on a mismatch, so snapd rolls back to the
previous revision and the service keeps running on the old data. To move to
a new track, dump and restore:

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
