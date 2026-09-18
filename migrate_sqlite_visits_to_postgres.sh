#!/usr/bin/env bash
# Copy the legacy SQLite visit table into PostgreSQL exactly once.
# The SQLite database is deliberately left untouched as a rollback backup.
set -euo pipefail

source_db="${1:-data/vinix.db}"
conninfo="${VINIX_DB_CONNINFO:?VINIX_DB_CONNINFO must contain the PostgreSQL connection string}"

fail() {
	echo "error: $*" >&2
	exit 1
}

command -v sqlite3 >/dev/null || fail "sqlite3 is required"
command -v psql >/dev/null || fail "psql is required"
[[ -f "$source_db" ]] || fail "SQLite database not found: $source_db"

columns="$(sqlite3 -readonly "$source_db" 'PRAGMA table_info(visits);' | cut -d'|' -f2)"
[[ -n "$columns" ]] || fail "SQLite database has no visits table"

has_column() {
	grep -Fxq "$1" <<<"$columns"
}

if has_column visited_at && has_column day; then
	timestamp_expr="COALESCE(NULLIF(visited_at, ''), day || 'T00:00:00.000Z')"
elif has_column visited_at; then
	timestamp_expr='visited_at'
elif has_column day; then
	# Day-only historical records cannot be made more precise than midnight UTC.
	timestamp_expr="day || 'T00:00:00.000Z'"
else
	fail "SQLite visits table has neither visited_at nor day"
fi

referral_expr="COALESCE(NULLIF(referral, ''), 'Direct / unknown')"
referral_url_expr="''"
country_expr="'Unknown'"
bot_expr='0'
user_agent_expr="''"
if has_column country; then country_expr="COALESCE(NULLIF(country, ''), 'Unknown')"; fi
if has_column is_bot; then bot_expr='COALESCE(is_bot, 0)'; fi
if has_column user_agent; then user_agent_expr="COALESCE(user_agent, '')"; fi
if has_column referral_url; then referral_url_expr="COALESCE(referral_url, '')"; fi

psql "$conninfo" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS visits (
	id BIGSERIAL PRIMARY KEY,
	site TEXT NOT NULL DEFAULT 'vinix',
	visited_at TIMESTAMPTZ NOT NULL,
	referral TEXT NOT NULL,
	referral_url TEXT NOT NULL DEFAULT '',
	user_agent TEXT NOT NULL DEFAULT '',
	country TEXT NOT NULL,
	is_bot BOOLEAN NOT NULL DEFAULT false
);
ALTER TABLE visits ADD COLUMN IF NOT EXISTS site TEXT NOT NULL DEFAULT 'vinix';
ALTER TABLE visits ADD COLUMN IF NOT EXISTS referral_url TEXT NOT NULL DEFAULT '';
ALTER TABLE visits ADD COLUMN IF NOT EXISTS user_agent TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS visits_site_visited_at_idx ON visits (site, visited_at);
SQL

source_count="$(sqlite3 -readonly "$source_db" 'SELECT COUNT(*) FROM visits;')"
target_count="$(psql "$conninfo" -v ON_ERROR_STOP=1 -Atqc "SELECT COUNT(*) FROM visits WHERE site = 'vinix';")"
if [[ "$target_count" != "0" ]]; then
	if (( target_count >= source_count )); then
		echo "PostgreSQL already contains the ${source_count} SQLite visit records."
		exit 0
	fi
	fail "PostgreSQL has ${target_count} visits but SQLite has ${source_count}. Refusing to duplicate or overwrite data."
fi

sqlite3 -readonly -csv "$source_db" "SELECT ${timestamp_expr}, ${referral_expr}, ${referral_url_expr}, ${user_agent_expr}, ${country_expr}, ${bot_expr} FROM visits ORDER BY id;" |
	psql "$conninfo" -v ON_ERROR_STOP=1 -q -c '\copy visits (visited_at, referral, referral_url, user_agent, country, is_bot) FROM STDIN WITH (FORMAT csv)'

imported_count="$(psql "$conninfo" -v ON_ERROR_STOP=1 -Atqc "SELECT COUNT(*) FROM visits WHERE site = 'vinix';")"
[[ "$imported_count" == "$source_count" ]] || fail "import verification failed: expected ${source_count}, got ${imported_count}"

echo "Migrated ${imported_count} visit records from SQLite to PostgreSQL."
