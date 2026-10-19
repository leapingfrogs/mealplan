# Backups and restore

Two layers protect the database:

1. **Logical dumps** by the `backup` service in `compose.yaml`: `pg_dump` in
   PostgreSQL's custom format, written to `MEALPLAN_ROOT/backups`. They are
   portable across machines and PostgreSQL versions, and can be restored
   selectively.
2. **ZFS snapshots** of the app dataset on the NAS: fast, whole-dataset
   rollback, including `.env` and the secrets. Configured in TrueNAS (see the
   datasets task); not covered here.

## What the backup service does

| | |
|---|---|
| Schedule | daily at 03:00 UTC (`BACKUP_AT`), plus a catch-up dump on start if the newest daily dump is over a day old |
| Location | `MEALPLAN_ROOT/backups/{daily,weekly,monthly,manual}/mealplan-<UTC timestamp>.dump` |
| Retention | 7 daily, 4 weekly (Sundays), 6 monthly (the 1st), 10 manual |
| Integrity | each dump is written to `.partial`, checked with `pg_restore --list`, then renamed |
| Health | the container is unhealthy if no daily dump is newer than 26 hours |

Weekly and monthly entries are hard links to the daily file, so they take no
extra space until the daily copy is pruned.

The service runs as uid 10999 with no capabilities, so `MEALPLAN_ROOT/backups`
must be owned by `10999:10999`.

## Take a dump now

From your workstation checkout (`just deploy` already takes one before every
deploy). It uses `MEALPLAN_SSH` from `.env.deploy` and asks for your sudo
password on the NAS, since Docker there needs root:

```sh
just backup-now
```

Or on the NAS:

```sh
docker exec <backup container> bash /tmp/backup.sh manual
```

Find the container with
`docker ps --filter label=com.docker.compose.service=backup`.

## Restore

Restores run inside the `backup` container, which has the PostgreSQL client
tools, the database password and the backups mounted. On the NAS:

```sh
backup=$(docker ps -q --filter label=com.docker.compose.service=backup)
app=$(docker ps -q --filter label=com.docker.compose.service=app)
docker exec -it "$backup" bash
```

Then, inside the container:

```sh
export PGPASSWORD="$(cat /run/secrets/db_password)"
ls -1t /backups/*/*.dump | head          # pick the dump to restore
```

### Check a dump without touching production

Restore into a scratch database, inspect it, then drop it:

```sh
createdb restore_check
pg_restore --no-owner --exit-on-error -d restore_check /backups/daily/mealplan-YYYYMMDDTHHMMSSZ.dump
psql -d restore_check -c 'select count(*) from users'
dropdb restore_check
```

CI runs this same check on every pull request (`scripts/compose-smoke-test`).

### Replace the production database

1. **Take a fresh dump first**, so the restore itself can be undone:
   `bash /tmp/backup.sh manual` (inside the backup container).
2. **Stop the app** (from the NAS shell, outside the container) so nothing
   writes during the restore: `docker stop "$app"`, or stop the app in the
   TrueNAS UI. Stopping the whole app also stops the database, so prefer
   stopping only the `app` container.
3. **Recreate and restore** (inside the backup container):

   ```sh
   dropdb --force mealplan
   createdb mealplan
   pg_restore --no-owner --exit-on-error -d mealplan /backups/daily/mealplan-YYYYMMDDTHHMMSSZ.dump
   ```

4. **Start the app** again: `docker start "$app"`. On start it runs any
   migrations newer than the dump, so restoring an older dump under a newer
   release works. Restoring a dump *newer* than the running release is not
   supported: deploy the matching release first.
5. **Check** `https://<PHX_HOST>/health/ready` and log in.

If `pg_restore` fails part-way, the database is incomplete: repeat step 3 with
the same or an earlier dump, or restore the dump taken in step 1.
