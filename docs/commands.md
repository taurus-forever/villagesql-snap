# Commands

The [VillageSQL snap](https://snapcraft.io/villagesql) ships the server as a
service and the standard MySQL client tools, pre-configured to talk to it
over the snap's Unix socket.

## Service

* `villagesql.villagesql` - the server (`mysqld`), started at install time.

```shell
sudo snap services villagesql
sudo snap restart villagesql
sudo snap logs villagesql          # snapd's view; the error log is below
sudo tail /var/snap/villagesql/common/log/error.log
```

## Clients

* [villagesql.mysql](https://dev.mysql.com/doc/refman/8.4/en/mysql.html) - interactive terminal.
* [villagesql.mysqladmin](https://dev.mysql.com/doc/refman/8.4/en/mysqladmin.html) - ping, status, create/drop databases.
* [villagesql.mysqldump](https://dev.mysql.com/doc/refman/8.4/en/mysqldump.html) - logical backups.
* [villagesql.mysqlbinlog](https://dev.mysql.com/doc/refman/8.4/en/mysqlbinlog.html) - read binary logs (in `/var/snap/villagesql/common/data/`).
* [villagesql.mysqlcheck](https://dev.mysql.com/doc/refman/8.4/en/mysqlcheck.html) - check, repair, analyze tables.
* `villagesql.config` - `villagesql_config`, compiler flags for building extensions against this snap's SDK version.
* `villagesql.extensions` - list extension bundles and where they come from (see [extensions.md](extensions.md)).

<details><summary>Examples</summary>

```shell
> sudo villagesql.mysql -uroot -e "SELECT VERSION();"
+-------------------------+
| VERSION()               |
+-------------------------+
| 8.4.11-villagesql-0.0.7 |
+-------------------------+

> sudo villagesql.mysqladmin -uroot ping
mysqld is alive

> sudo villagesql.mysqldump -uroot --all-databases > all.sql
```
</details>

GTIDs are enabled by default on the `9.7` track (MySQL 9.7). A dump taken
there carries `GTID_PURGED` and can only be restored onto a server that has
not executed those transactions, such as a fresh install; to restore it
onto the same server (another database, for example) pass
`--set-gtid-purged=OFF` to `villagesql.mysqldump`.

## Paths

| Path | Content |
| --- | --- |
| `/var/snap/villagesql/common/data` | data directory (owned by `_daemon_`) |
| `/var/snap/villagesql/common/etc/my.cnf` | main configuration, includes `conf.d/*.cnf` |
| `/var/snap/villagesql/common/log/error.log` | server error log |
| `/tmp/mysql.sock` (inside the snap) | Unix socket; clients use it by default |
