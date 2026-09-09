module main

import db.pg
import medvednikov.botdetect
import net.http
import net.urllib
import os
import strings
import time
import veb

const default_port = 8080
const stats_days_to_show = 30
const visit_cookie_name = 'vinix_session_visit'

@[table: 'visits']
struct Visit {
	id         int @[primary; sql: serial]
	visited_at string
	referral   string
	country    string
	is_bot     bool
}

struct ReferralCount {
	name   string
	visits int
}

struct CountryCount {
	code   string
	visits int
}

type VinixDb = pg.DB

pub struct Context {
	veb.Context
}

pub struct App {
	veb.StaticHandler
mut:
	db             VinixDb
	home_html      string
	stats_template string
}

@['/'; get]
pub fn (mut app App) index(mut ctx Context) veb.Result {
	if is_bot_visit(ctx.req.header.get(.user_agent) or { '' }, ctx.req.url) {
		// Crawlers do not reliably retain cookies, so keep every bot request as
		// a separate event while ensuring it never inflates human statistics.
		app.record_home_visit(ctx, true)
		return ctx.html(app.home_html)
	}

	// Count at most once per browser session so reloading the home page does
	// not inflate the visit total. This cookie is not stored in the database.
	if ctx.get_cookie(visit_cookie_name) == none {
		app.record_home_visit(ctx, false)
		ctx.set_cookie(http.Cookie{
			name: visit_cookie_name
			value: '1'
			path: '/'
			secure: true
			http_only: true
			same_site: .same_site_lax_mode
		})
	}
	return ctx.html(app.home_html)
}

@['/stats228']
pub fn (mut app App) stats228(mut ctx Context) veb.Result {
	visits := app.visits()
	requested_day := requested_stats_day(ctx.req.url)
	selected_day := if is_day_key(requested_day) { requested_day } else { day_key(time.now()) }
	return ctx.html(app.render_stats(visits, selected_day))
}

fn (mut app App) record_home_visit(ctx Context, is_bot bool) {
	now := time.now()
	visit := Visit{
		visited_at: now.format_rfc3339()
		referral: referral_host(ctx.get_header(.referer) or { '' })
		country: country_code(ctx.get_custom_header('CF-IPCountry') or { '' })
		is_bot: is_bot
	}

	sql app.db {
		insert visit into Visit
	} or {
		eprintln('Could not record page visit: ${err}')
	}
}

fn (mut app App) visits() []Visit {
	return sql app.db {
		select from Visit
	} or {
		eprintln('Could not load visitor statistics: ${err}')
		return []Visit{}
	}
}

fn (app &App) render_stats(visits []Visit, selected_day string) string {
	mut human_visits := []Visit{}
	mut bot_visits := []Visit{}
	for visit in visits {
		if visit.is_bot {
			bot_visits << visit
		} else {
			human_visits << visit
		}
	}

	mut daily_visits := map[string]int{}
	mut referrals := map[string]int{}
	mut countries := map[string]int{}
	mut hourly_visits := []int{len: 24}
	mut selected_day_humans := 0
	mut selected_day_bots := 0
	for visit in human_visits {
		recorded_day := visit_day(visit.visited_at)
		daily_visits[recorded_day]++
		referrals[visit.referral]++
		countries[visit.country]++
		if recorded_day == selected_day {
			selected_day_humans++
			hour := visit_hour(visit.visited_at)
			if hour >= 0 {
				hourly_visits[hour]++
			}
		}
	}
	for visit in bot_visits {
		if visit_day(visit.visited_at) == selected_day {
			selected_day_bots++
		}
	}

	mut chart := strings.new_builder(4096)
	mut total_last_30_days := 0
	mut bots_last_30_days := 0
	mut highest_day := 1
	now := time.now()
	for offset in 0 .. stats_days_to_show {
		day := day_key(now.add_days(offset - stats_days_to_show + 1))
		count := daily_visits[day]
		total_last_30_days += count
		if count > highest_day {
			highest_day = count
		}
	}
	for visit in bot_visits {
		if visit_day(visit.visited_at) >= day_key(now.add_days(-stats_days_to_show + 1)) {
			bots_last_30_days++
		}
	}

	for offset in 0 .. stats_days_to_show {
		day := day_key(now.add_days(offset - stats_days_to_show + 1))
		count := daily_visits[day]
		height := count * 100 / highest_day
		label := day[5..]
		active_class := if day == selected_day { ' is-selected' } else { '' }
		chart.write_string('<li class="stats-chart-day${active_class}" data-value="${day}: ${count} visit${plural_suffix(count)}"><a href="/stats228?day=${day}#hourly-visits" title="${day}: ${count} visit${plural_suffix(count)}" aria-label="Show ${day} by hour"><span class="stats-chart-bar" style="height: ${height}%"></span><span class="stats-chart-label">${label}</span></a></li>')
	}

	mut highest_hour := 1
	for count in hourly_visits {
		if count > highest_hour {
			highest_hour = count
		}
	}
	mut hourly_chart := strings.new_builder(4096)
	for hour in 0 .. 24 {
		count := hourly_visits[hour]
		height := count * 100 / highest_hour
		label := if hour < 10 { '0${hour}' } else { hour.str() }
		hourly_chart.write_string('<li class="stats-chart-day" data-value="${label}:00 UTC: ${count} human visit${plural_suffix(count)}" title="${selected_day} ${label}:00 UTC: ${count} human visit${plural_suffix(count)}"><span class="stats-chart-bar" style="height: ${height}%"></span><span class="stats-chart-label">${label}</span></li>')
	}

	mut referral_rows := []ReferralCount{}
	for name, count in referrals {
		referral_rows << ReferralCount{
			name: name
			visits: count
		}
	}
	referral_rows.sort(a.visits > b.visits)

	mut referral_table := strings.new_builder(2048)
	if referral_rows.len == 0 {
		referral_table.write_string('<p class="stats-empty">No visits have been recorded yet.</p>')
	} else {
		referral_table.write_string('<div class="stats-table-wrap"><table><thead><tr><th scope="col">Referral</th><th scope="col">Visits</th></tr></thead><tbody>')
		for index, referral in referral_rows {
			if index == 10 {
				break
			}
			referral_table.write_string('<tr><td>${escape_html(referral.name)}</td><td>${referral.visits}</td></tr>')
		}
		referral_table.write_string('</tbody></table></div>')
	}

	mut country_rows := []CountryCount{}
	for code, count in countries {
		country_rows << CountryCount{
			code: code
			visits: count
		}
	}
	country_rows.sort(a.visits > b.visits)

	mut country_table := strings.new_builder(2048)
	if country_rows.len == 0 {
		country_table.write_string('<p class="stats-empty">No visits have been recorded yet.</p>')
	} else {
		country_table.write_string('<div class="stats-table-wrap"><table><thead><tr><th scope="col">Country</th><th scope="col">Visits</th></tr></thead><tbody>')
		for index, country in country_rows {
			if index == 10 {
				break
			}
			country_table.write_string('<tr><td><span class="country-flag" aria-hidden="true">${country_flag(country.code)}</span><span>${escape_html(country_label(country.code))}</span></td><td>${country.visits}</td></tr>')
		}
		country_table.write_string('</tbody></table></div>')
	}

	return app.stats_template.replace('{{total_visits}}', human_visits.len.str()).replace('{{visits_last_30_days}}', total_last_30_days.str()).replace('{{total_bot_visits}}', bot_visits.len.str()).replace('{{bot_visits_last_30_days}}', bots_last_30_days.str()).replace('{{daily_chart}}', chart.str()).replace('{{selected_day}}', selected_day).replace('{{selected_day_human_visits}}', selected_day_humans.str()).replace('{{selected_day_bot_visits}}', selected_day_bots.str()).replace('{{hourly_chart}}', hourly_chart.str()).replace('{{referral_table}}', referral_table.str()).replace('{{country_table}}', country_table.str())
}

fn day_key(value time.Time) string {
	return value.format_rfc3339()[..10]
}

fn visit_day(visited_at string) string {
	return if visited_at.len >= 10 { visited_at[..10] } else { '' }
}

fn visit_hour(visited_at string) int {
	if visited_at.len < 13 || (visited_at[10] != `T` && visited_at[10] != ` `) || visited_at[11] < `0`
		|| visited_at[11] > `9` || visited_at[12] < `0` || visited_at[12] > `9` {
		return -1
	}
	hour := int(visited_at[11] - `0`) * 10 + int(visited_at[12] - `0`)
	return if hour < 24 { hour } else { -1 }
}

fn is_day_key(value string) bool {
	if value.len != 10 || value[4] != `-` || value[7] != `-` {
		return false
	}
	for index in [0, 1, 2, 3, 5, 6, 8, 9] {
		if value[index] < `0` || value[index] > `9` {
			return false
		}
	}
	return true
}

fn requested_stats_day(url string) string {
	parsed_url := urllib.parse(url) or { return '' }
	return parsed_url.query().get('day') or { '' }
}

fn referral_host(referer string) string {
	if referer == '' {
		return 'Direct / unknown'
	}
	url := urllib.parse(referer) or {
		return 'Direct / unknown'
	}
	host := url.hostname().to_lower()
	return if host == '' { 'Direct / unknown' } else { host }
}

fn country_code(value string) string {
	code := value.trim_space().to_upper_ascii()
	if code.len != 2 || code == 'XX' {
		return 'Unknown'
	}
	if code[0] < `A` || code[0] > `Z` || code[1] < `A` || code[1] > `Z` {
		return 'Unknown'
	}
	return code
}

fn is_bot_visit(user_agent string, url string) bool {
	return botdetect.ua_is_bot(user_agent) || botdetect.url_is_requested_by_bot(url)
}

fn country_flag(code string) string {
	if code.len != 2 || code == 'Unknown' {
		return '🏳️'
	}
	return rune(0x1f1e6 + int(code[0] - `A`)).str() + rune(0x1f1e6 + int(code[1] - `A`)).str()
}

fn country_label(code string) string {
	return match code {
		'US' { 'United States' }
		'RU' { 'Russia' }
		'GB' { 'United Kingdom' }
		'DE' { 'Germany' }
		'FR' { 'France' }
		'CA' { 'Canada' }
		'NL' { 'Netherlands' }
		'PL' { 'Poland' }
		'UA' { 'Ukraine' }
		'CN' { 'China' }
		'JP' { 'Japan' }
		'IN' { 'India' }
		'BR' { 'Brazil' }
		'AU' { 'Australia' }
		'Unknown' { 'Unknown' }
		else { code }
	}
}

fn plural_suffix(count int) string {
	return if count == 1 { '' } else { 's' }
}

fn escape_html(value string) string {
	return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace("'", '&#39;')
}

fn main() {
	mut db := connect_db() or { panic('Could not open PostgreSQL: ${err}') }
	db.exec('CREATE TABLE IF NOT EXISTS visits (id BIGSERIAL PRIMARY KEY, visited_at TIMESTAMPTZ NOT NULL, referral TEXT NOT NULL, country TEXT NOT NULL, is_bot BOOLEAN NOT NULL DEFAULT false)') or {
		panic('Could not create the visits table: ${err}')
	}
	db.exec('CREATE INDEX IF NOT EXISTS visits_visited_at_idx ON visits (visited_at)') or {
		panic('Could not create the visits timestamp index: ${err}')
	}

	mut app := &App{
		db: db
		home_html: os.read_file('index.html') or { panic('Could not load index.html: ${err}') }
		stats_template: os.read_file('stats228.html') or { panic('Could not load stats228.html: ${err}') }
	}
	app.handle_static('assets', false) or { panic(err) }
	app.serve_static('/style.css', 'style.css') or { panic(err) }
	app.serve_static('/theme.js', 'theme.js') or { panic(err) }

	port := os.getenv_opt('PORT') or { default_port.str() }
	// Production is reverse-proxied by Nginx. Keeping the Veb listener local
	// prevents it from being exposed directly and avoids collisions with other
	// Veb services on the host.
	veb.run_at[App, Context](mut app, host: '127.0.0.1', port: port.int(), family: .ip) or {
		panic(err)
	}
}

fn connect_db() !VinixDb {
	conninfo := os.getenv('VINIX_DB_CONNINFO')
	if conninfo == '' {
		return error('VINIX_DB_CONNINFO must contain the PostgreSQL connection string')
	}
	db := pg.connect_with_conninfo(conninfo, pg.PoolConfig{})!
	return VinixDb(*db)
}
