#!/usr/bin/env bash
# Cross-compile, upload, and restart the Veb application on vinix-os.org.
# Override the destination when needed, e.g.:
# DEPLOY_TARGET='web@host:/var/www/vinix-os.org/' ./deploy.sh
# DEPLOY_RESTART_COMMAND='sudo systemctl restart vinix-website' ./deploy.sh

set -euo pipefail

# Use $0 rather than Bash's BASH_SOURCE so this also works when invoked as
# `zsh deploy.sh`. (The shebang still selects Bash for `./deploy.sh`.)
script_path="$0"
if [[ "$script_path" != */* ]]; then
	resolved_script_path="$(command -v "$script_path" 2>/dev/null || true)"
	if [[ -n "$resolved_script_path" ]]; then
		script_path="$resolved_script_path"
	fi
fi
site_dir="$(cd "$(dirname "$script_path")" && pwd)"
traffic_module_dir="${TRAFFIC_MODULE_DIR:-$site_dir/../traffic}"
deploy_target="${DEPLOY_TARGET:-vpm:/var/www/vinix-os.org/}"
dry_run=""
connect_timeout="${DEPLOY_CONNECT_TIMEOUT:-15}"
ssh_batch_mode="${DEPLOY_SSH_BATCH_MODE:-yes}"
service_name="${DEPLOY_SERVICE_NAME:-vinix-website}"

usage() {
	echo "usage: $0 [--dry-run]" >&2
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run)
			dry_run="--dry-run"
			;;
		*)
			usage
			exit 1
			;;
	esac
	shift
done

if [[ "$deploy_target" != *:* ]]; then
	echo "error: DEPLOY_TARGET must be in host:/absolute/path form" >&2
	exit 1
fi

command -v rsync >/dev/null || {
	echo "error: rsync is required to deploy" >&2
	exit 1
}

command -v ssh >/dev/null || {
	echo "error: ssh is required to deploy the application" >&2
	exit 1
}

command -v v >/dev/null || {
	echo "error: V is required to cross-compile the Linux release locally" >&2
	exit 1
}

[[ -f "$traffic_module_dir/traffic.v" && -f "$traffic_module_dir/stats.html" ]] || {
	echo "error: reusable traffic module not found at $traffic_module_dir" >&2
	echo "set TRAFFIC_MODULE_DIR to its checkout path" >&2
	exit 1
}
traffic_module_parent="$(cd "$(dirname "$traffic_module_dir")" && pwd)"

remote_host="${deploy_target%%:*}"
remote_dir="${deploy_target#*:}"
if [[ -z "$remote_host" || "$remote_dir" != /* ]]; then
	echo "error: DEPLOY_TARGET must be in host:/absolute/path form" >&2
	exit 1
fi

if [[ ! "$connect_timeout" =~ ^[1-9][0-9]*$ ]]; then
	echo "error: DEPLOY_CONNECT_TIMEOUT must be a positive number of seconds" >&2
	exit 1
fi

if [[ "$ssh_batch_mode" != "yes" && "$ssh_batch_mode" != "no" ]]; then
	echo "error: DEPLOY_SSH_BATCH_MODE must be yes or no" >&2
	exit 1
fi

if [[ ! "$service_name" =~ ^[A-Za-z0-9@_.-]+$ ]]; then
	echo "error: DEPLOY_SERVICE_NAME contains unsupported characters" >&2
	exit 1
fi

ssh_options=(
	-o "BatchMode=$ssh_batch_mode"
	-o "ConnectTimeout=$connect_timeout"
	-o "ServerAliveInterval=15"
	-o "ServerAliveCountMax=3"
)
ssh_transport="ssh"
for ssh_option in "${ssh_options[@]}"; do
	ssh_transport+=" $(printf '%q' "$ssh_option")"
done

# Catch missing local images before changing the destination.
while IFS= read -r asset; do
	[[ -f "$site_dir/$asset" ]] || {
		echo "error: missing site asset: $asset" >&2
		exit 1
	}
done < <(rg --no-filename -o 'assets/[A-Za-z0-9._/-]+' "$site_dir/index.html" | sort -u)

# Cross-compile locally so the 2 GiB web server only restarts the finished
# binary. V's bundled Linux linker cannot read the bitcode emitted by Apple's
# clang LTO mode, hence the explicit -fno-lto alongside -prod.
echo "Cross-compiling the Linux x86_64 production binary..."
v -path "$traffic_module_parent|@vlib|@vmodules" -os linux -arch amd64 -prod -cflags '-fno-lto' -o "$site_dir/vinix-website" "$site_dir"

echo "Checking SSH connectivity to $remote_host (timeout: ${connect_timeout}s)..."
ssh "${ssh_options[@]}" "$remote_host" true

echo "Uploading release files to $deploy_target..."
# macOS ships an rsync 2.6-compatible implementation; unlike rsync 3, it
# does not understand --info=progress2. --progress is supported by both.
rsync_options=(-az --delete-delay --progress --timeout=60 -e "$ssh_transport")
if [[ -n "$dry_run" ]]; then
	rsync_options+=("$dry_run")
fi

rsync "${rsync_options[@]}" \
	--exclude '.git/' \
	--exclude 'deploy.sh' \
	--exclude '/bkup/' \
	--exclude '/data/' \
	--exclude '.DS_Store' \
	--exclude '*.swp' \
	"$site_dir/" "$deploy_target"

if [[ -n "$dry_run" ]]; then
	echo "Dry run complete; skipped the remote restart."
	exit 0
fi

remote_dir_escaped="$(printf '%q' "$remote_dir")"
echo "Installing and restarting ${service_name}.service on $remote_host..."
ssh "${ssh_options[@]}" "$remote_host" "cd $remote_dir_escaped && test -x vinix-website && test -x migrate_sqlite_visits_to_postgres.sh && if ! sudo -u postgres psql -Atqc \"SELECT 1 FROM pg_roles WHERE rolname = 'vinix'\" | grep -qx 1; then sudo -u postgres createuser --login vinix; fi && if ! sudo -u postgres psql -Atqc \"SELECT 1 FROM pg_database WHERE datname = 'vinix'\" | grep -qx 1; then sudo -u postgres createdb --owner=vinix vinix; fi && systemctl stop ${service_name}.service && VINIX_DB_CONNINFO='host=127.0.0.1 port=5432 dbname=vinix user=vinix' ./migrate_sqlite_visits_to_postgres.sh data/vinix.db && install -m 0644 vinix-website.service /etc/systemd/system/${service_name}.service && install -m 0644 vinix-os.org.nginx.conf /etc/nginx/sites-available/vinix-os.org && ln -sfn /etc/nginx/sites-available/vinix-os.org /etc/nginx/sites-enabled/vinix-os.org && systemctl daemon-reload && systemctl enable ${service_name}.service && systemctl start ${service_name}.service && systemctl is-active --quiet ${service_name}.service && timeout 20 sh -c 'until curl --fail --silent --max-time 2 http://127.0.0.1:8095/ >/dev/null; do sleep 1; done' && nginx -t && systemctl reload nginx"

echo "Cross-compiled, uploaded, and restarted ${service_name}.service on $remote_host."
