# Vinix OS Website

The Vinix website is a V + Veb server backed by PostgreSQL. It serves the existing
home page at `/`, records one visit per browser session, and exposes traffic
statistics at `/stats228`. Country totals use Cloudflare's two-letter country
header when the site is served through Cloudflare; no IP addresses are stored.
Known crawler user agents and bot probe URLs are classified with
`medvednikov.botdetect` and reported separately from human traffic.

## Run locally

Install V and the PostgreSQL client development library (`libpq-dev` on Debian/
Ubuntu or `brew install libpq` on macOS), then run:

```sh
v run .
```

The site listens on `http://localhost:8080`. Set `PORT` to choose another port
and `VINIX_DB_CONNINFO` to a PostgreSQL libpq connection string, for example
`host=/var/run/postgresql dbname=vinix user=vinix`.

Build an optimized binary for production with:

```sh
v -prod -o vinix-website .
```

Keep PostgreSQL on persistent storage. The dashboard stores
the exact UTC timestamp and referrer hostname for each visit; it deliberately
does not retain IP addresses, user agents, or full referral URLs.

## Deploy

`./deploy.sh` cross-compiles a Linux x86_64 binary locally, then syncs the
release to `DEPLOY_TARGET` (default: `vpm:/var/www/vinix-os.org/`). This keeps
compilation off the 2 GiB production server. On the first deployment, it
creates the dedicated `vinix` PostgreSQL role and database, stops the service,
and imports the legacy `data/vinix.db` visit records. The SQLite file is kept
as a rollback backup. After upload it installs
[vinix-website.service](vinix-website.service), reloads systemd, enables the
service, and restarts it. It also installs the included Nginx virtual-host
configuration, validates it, and reloads Nginx so HTTPS traffic reaches the
local Veb listener on port 8095. The remote deploy user therefore needs
permission to write `/etc/systemd/system` and `/etc/nginx`, and manage services.

Use `./deploy.sh --dry-run` to build locally and review the upload without
changing the remote host or restarting its service.
Set `DEPLOY_SERVICE_NAME` only when the target uses a different unit name.

The script checks the SSH connection before uploading and defaults to a
15-second connection timeout. If the server uses password authentication, pass
`DEPLOY_SSH_BATCH_MODE=no`; otherwise it fails promptly rather than waiting for
an authentication prompt.
