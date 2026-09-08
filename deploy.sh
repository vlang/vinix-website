#!/usr/bin/env bash
# Deploy the static site with an explicit rsync destination.
# Example: DEPLOY_TARGET='web@host:/var/www/vinix/' ./deploy.sh

set -euo pipefail

site_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deploy_target="${DEPLOY_TARGET:-}"
dry_run=""

if [[ "${1:-}" == "--dry-run" ]]; then
	dry_run="--dry-run"
	 shift
fi

if [[ $# -ne 0 ]]; then
	echo "usage: DEPLOY_TARGET=user@host:/path/ $0 [--dry-run]" >&2
	exit 1
fi

if [[ -z "$deploy_target" ]]; then
	echo "error: set DEPLOY_TARGET to the server and directory to publish to" >&2
	exit 1
fi

command -v rsync >/dev/null || {
	echo "error: rsync is required to deploy" >&2
	exit 1
}

# Catch missing local images before changing the destination.
while IFS= read -r asset; do
	[[ -f "$site_dir/$asset" ]] || {
		echo "error: missing site asset: $asset" >&2
		exit 1
	}
done < <(rg --no-filename -o 'assets/[A-Za-z0-9._/-]+' "$site_dir/index.html" | sort -u)

rsync_options=(-az --delete)
if [[ -n "$dry_run" ]]; then
	rsync_options+=("$dry_run")
fi

rsync "${rsync_options[@]}" \
	--exclude '.git/' \
	--exclude 'deploy.sh' \
	"$site_dir/" "$deploy_target"

echo "Deployed Vinix website to $deploy_target"
