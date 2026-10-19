# Deploying on TrueNAS SCALE

How the production stack (`compose.yaml`) is set up on the TrueNAS appliance.
Replace `<pool>` with your pool name throughout. Commands marked **NAS shell**
run as root on TrueNAS (System → Shell, or SSH as your admin user then
`sudo -i`). The TrueNAS shell is zsh, which by default does not
treat `#` as a comment when pasting interactively, so the commands here carry no
inline comments. Paths and dataset names are case-sensitive.

## 1. Datasets

Create three nested datasets, each with **Dataset Preset: Generic** (POSIX
permissions, so `chown`/`chmod` behave normally; the Apps/SMB presets use ACLs
that reject plain `chmod`). The UI takes only the last part of the name: select
the parent in the tree, click **Add Dataset**, and type the child's name.
Under **Advanced Options**, check **ACL Type** shows **POSIX**: if it says
*Inherit* and the parent uses NFSv4 (e.g. created with the Apps or SMB
preset), choose POSIX explicitly. NFSv4 ACLs turn `chmod` into ACL edits, and
Postgres refuses to start unless its data directory is exactly `0700`.

1. Select `apps` (create it under the pool first if needed), add `mealplan`.
2. Select `mealplan`, add `postgres`.
3. Select `mealplan`, add `backups`.

Use datasets, not zvols (zvols are block devices for VMs/iSCSI), and keep
`postgres` and `backups` nested under `mealplan`: `compose.yaml` expects them
inside `MEALPLAN_ROOT`, and one recursive snapshot task then covers all three.

| Dataset (full path) | Purpose | Advanced options |
|---|---|---|
| `<pool>/apps/mealplan` | `MEALPLAN_ROOT`: `.env` and `secrets/` | defaults |
| `<pool>/apps/mealplan/postgres` | database files | Record Size **16K**, ATime **Off** |
| `<pool>/apps/mealplan/backups` | nightly `pg_dump` output | defaults |

Compression can stay at the default (LZ4). 16K suits PostgreSQL's 8K pages; dumps are already compressed,
so the backups dataset needs no tuning.

## 2. Ownership and permissions

The containers run as fixed, non-root users, and Docker on TrueNAS is rootful
(no user-namespace remapping), so the host owners must match exactly:

| Path | Owner | Mode | Why |
|---|---|---|---|
| `mealplan/` | `root:root` | `750` | only Docker (root) needs to read it |
| `mealplan/.env` | `root:root` | `600` | read by Docker when starting the app |
| `mealplan/secrets/` | `root:root` | `700` | |
| `mealplan/secrets/db_password` | `10001:10999` | `440` | app (uid 10001) and Postgres (gid 10999) read it |
| `mealplan/postgres/` | `10999:10999` | `700` | Postgres runs as 10999 and requires `0700` |
| `mealplan/backups/` | `10999:10999` | `750` | backup service runs as 10999 |

**NAS shell:**

```sh
root=/mnt/<pool>/apps/mealplan
mkdir -p "$root/secrets"
chown root:root "$root" "$root/secrets"
chmod 750 "$root"
chmod 700 "$root/secrets"
chown 10999:10999 "$root/postgres" "$root/backups"
chmod 700 "$root/postgres"
chmod 750 "$root/backups"
```

## 3. Database password

Generated on the NAS so it never leaves it. **NAS shell:**

```sh
root=/mnt/<pool>/apps/mealplan
umask 077
openssl rand -base64 32 > "$root/secrets/db_password"
chown 10001:10999 "$root/secrets/db_password"
chmod 440 "$root/secrets/db_password"
```

Postgres reads this only when it first initialises an empty `postgres/`
directory. Changing the file later does not change the database password.

## 4. Application settings (`.env`)

Start from [`.env.example`](../.env.example). The secrets are generated in
place; edit the rest afterwards. **NAS shell:**

```sh
root=/mnt/<pool>/apps/mealplan
umask 077
cat > "$root/.env" <<EOF
SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')
RELEASE_COOKIE=$(openssl rand -hex 32)
PHX_HOST=mealplan.example.com
POOL_SIZE=10
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM=mealplan@example.com
SMTP_FROM_NAME=Mealplan
TRUSTED_PROXIES=
EOF
chown root:root "$root/.env"
chmod 600 "$root/.env"
```

Then fill in `PHX_HOST` (the hostname NPM will serve), the `SMTP_*` values for
your mail provider and `TRUSTED_PROXIES` (next step), e.g.
`nano "$root/.env"`.

Don't set `PHX_SERVER` or any `DATABASE_*` variables: `bin/server` and
`compose.yaml` handle those.

### `TRUSTED_PROXIES`

The app only believes `X-Forwarded-*` headers from Nginx Proxy Manager. Find
NPM's Docker network and its subnet. **NAS shell:**

```sh
docker ps --format '{{.Names}}\t{{.Networks}}' | grep -i proxy
docker network inspect <npm-network> --format '{{(index .IPAM.Config 0).Subnet}}'
```

Set `TRUSTED_PROXIES` to that subnet, e.g. `TRUSTED_PROXIES=172.16.5.0/24`.
The network name is also needed for the Custom App (`NPM_NETWORK`).

## 5. Snapshots

**Data Protection → Periodic Snapshot Tasks → Add**:

- Dataset: `<pool>/apps/mealplan`, **Recursive** on (covers `postgres` and
  `backups`)
- Schedule: hourly, Lifetime: 2 days
- Add a second task: daily, Lifetime: 30 days

ZFS snapshots are atomic, so a snapshot of `postgres/` is crash-consistent:
PostgreSQL recovers from it the same way it recovers from a power cut. The
nightly `pg_dump` files are the portable, restorable-anywhere backups; see
[backups.md](backups.md).

If you have another pool or machine, add a **Replication Task** for the same
datasets.

## 6. Check

**NAS shell:**

```sh
root=/mnt/<pool>/apps/mealplan
ls -lan "$root" "$root/secrets"
zfs get -r acltype <pool>/apps/mealplan
zfs get recordsize,atime,compression <pool>/apps/mealplan/postgres
grep -c '=$' "$root/.env"
```

The `zfs` commands take the dataset name (no `/mnt/`); replace `<pool>`
there too. Expect `acltype posix` on all three datasets, `recordsize 16K` and
`atime off` on `postgres`, and a count of `0` from `grep` (no empty values left
in `.env`).

Expected owners (numeric): `.env` 0:0 `-rw-------`, `secrets/db_password`
10001:10999 `-r--r-----`, `postgres` 10999:10999 `drwx------`, `backups` 10999:10999
`drwxr-x---`.

## 7. Install the Custom App

TrueNAS stores the app as a literal YAML document, so render `compose.yaml`
with this NAS's values on your workstation (needs `.env.deploy`, see
[`.env.deploy.example`](../.env.deploy.example)):

```sh
just truenas-yaml v0.1.0 > mealplan.yaml
```

In TrueNAS: **Apps → Discover Apps → ⋮ (top right) → Install via YAML**.

- **Name:** `mealplan`. TrueNAS runs it as Compose project `ix-mealplan`,
  which `just backup-now` and `just deploy` expect.
- **Custom Config:** paste the whole of `mealplan.yaml`.
- **Save.** TrueNAS pulls the images and starts `db`, then `app` (which runs
  migrations first) and `backup` once the database is healthy.

The app should reach **Running** within a couple of minutes. Changing it later
(a new version) is **Apps → mealplan → Edit**, which shows the same YAML; that
is what `just deploy` automates.

## 8. Check the running stack

**NAS shell:**

```sh
docker ps --filter label=com.docker.compose.project=ix-mealplan --format 'table {{.Names}}\t{{.Status}}'
docker logs ix-mealplan-app-1 --tail 15
docker logs ix-mealplan-backup-1 --tail 5
docker port ix-mealplan-db-1
docker port ix-mealplan-app-1
docker network inspect ix-nginx-proxy-manager_default --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker exec ix-nginx-proxy-manager-npm-1 curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: localhost' http://mealplan:4000/health/ready
```

Expected:

- all three containers `Up … (healthy)`
- app log lines are JSON, including the migrations on first start
- the backup log shows a `wrote /backups/daily/…` line (the catch-up dump)
- `docker port` prints nothing for both: no host ports are published
- the NPM network lists NPM and `ix-mealplan-app-1` only
- the last command prints `200`: NPM reaches the app as `mealplan:4000`

## 9. Nginx Proxy Manager proxy host

Prerequisites: ports 80 and 443 forwarded to NPM, and the hostname resolving
to your public IP (here via the `*.subvault.co.uk` wildcard).

**Hosts → Proxy Hosts → Add Proxy Host.** Details tab:

| Field | Value |
|---|---|
| Domain Names | `mealplan.subvault.co.uk` (must equal `PHX_HOST`) |
| Scheme / Forward Hostname / Port | `http` / `mealplan` / `4000` |
| Cache Assets | off (Phoenix sets cache headers on digested assets) |
| Block Common Exploits | on |
| **Websockets Support** | **on** (LiveView needs it) |
| Access List | Publicly Accessible (registration is invite-only) |

SSL tab: request a new Let's Encrypt certificate (HTTP challenge), **Force
SSL** on, **HTTP/2** on, **HSTS** off (the app sends its own
`Strict-Transport-Security`). Leave Advanced empty: NPM already passes
`X-Forwarded-For` and `X-Forwarded-Proto`, which `TRUSTED_PROXIES` relies on.

### From inside the LAN

If the router doesn't do hairpin NAT, LAN devices can't reach the public IP.
Add a local DNS override (router, Pi-hole/AdGuard, or Tailscale DNS for tailnet
devices) pointing `mealplan.subvault.co.uk` at the NAS's LAN address. Use the
hostname, not the IP: the app only accepts LiveView connections from pages
served at `https://PHX_HOST`.

### After NPM updates

Mealplan joins NPM's network (`ix-nginx-proxy-manager_default`). If an NPM
update recreates that network, the Mealplan app is left attached to the old
one and NPM answers **502 Bad Gateway**. Check, and Stop/Start the mealplan app
if `ix-mealplan-app-1` is missing:

```sh
docker network inspect ix-nginx-proxy-manager_default --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

NPM's startup runs a recursive `chown` over its bundled certbot, which can take
15 minutes or more on ZFS-backed app storage. Setting the environment variable
`SKIP_CERTBOT_OWNERSHIP=true` on the NPM app (Edit → environment variables)
skips it.

## 10. Deploying new versions

`just deploy vX.Y.Z` (from a workstation, over SSH) replaces the Custom App's
YAML with the new version pinned by digest. Steps it performs:

1. looks up the tag's digest on GHCR and verifies its build provenance with
   `gh attestation verify` (only images built by this repo's release workflow
   deploy)
2. renders `compose.yaml` with `image: …:vX.Y.Z@sha256:…`
3. copies it and `scripts/deploy-remote` to `~/.mealplan-deploy/` on the NAS
4. runs `deploy-remote` with `sudo` (**one password prompt**), which takes a
   pre-deploy `pg_dump`, calls `midclt call -j app.update mealplan …`, and
   waits until the app runs the new image and is healthy
5. checks `MEALPLAN_URL/health/ready` from outside

Running it again for the version already deployed is a no-op.

### One-time setup

1. **SSH key login for the admin user.** Credentials → Users →
   `truenas_admin` → Edit: paste your public key into **SSH Public Key**, keep
   **Allowed sudo commands: ALL** (password required, not "no password").
2. **SSH service.** System → Services → SSH: enable and start automatically.
   In its settings, leave password authentication off.
3. **Workstation settings.** `cp .env.deploy.example .env.deploy` and set
   `MEALPLAN_SSH=truenas_admin@truenas-scale` (the tailnet name). Check with
   `ssh truenas_admin@truenas-scale true`.

`gh` must be logged in on the workstation (`gh auth status`) for the
provenance check.

### Deploy, check, roll back

```sh
just deploy v0.1.1
just deploy --dry-run v0.1.1
just rollback v0.1.0
```

`--dry-run` verifies and renders without
touching the NAS. `just rollback` redeploys an earlier version after asking:
code is rolled back but the database is not, so if the newer release ran
migrations the older one doesn't expect, restore the pre-deploy dump
(`backups/manual/`, see [backups.md](backups.md)).

If the app doesn't become healthy, the script prints its last log lines and the
previous image. The Custom App then still has the new YAML; deploy the previous
version to go back.

### One-time: moving the database off uid 999

Installs made before the database and backup services ran as `10999:10999`
have their files owned by `999:999`, which on TrueNAS is the host's `netdata`
user and `docker` group. To move them (NAS shell as root for the `chown`s):

1. Take a dump while everything still runs: `just backup-now`.
2. **Apps → mealplan → Stop.**
3. Re-own the files:
   ```sh
   root=/mnt/storage/Apps/mealplan
   chown -R 10999:10999 "$root/postgres" "$root/backups"
   chown 10001:10999 "$root/secrets/db_password"
   ```
4. From the workstation: `just deploy <current version>`. The deploy sees the
   compose configuration changed, skips the pre-deploy dump because the app is
   stopped (step 1 took one), updates the app and starts it.
