module main

fn test_referral_host_keeps_only_the_hostname() {
	assert referral_host('https://News.YCombinator.com/item?id=1') == 'news.ycombinator.com'
	assert referral_host('not a URL') == 'Direct / unknown'
	assert referral_host('') == 'Direct / unknown'
}

fn test_stats_groups_visits_by_referral_hostname_not_full_url() {
	app := &App{
		stats_template: '{{referral_table}}'
	}
	visits := [
		Visit{
			visited_at: '2026-09-09T18:06:13.123Z'
			referral: 'news.ycombinator.com'
			referral_url: 'https://news.ycombinator.com/item?id=1'
		},
		Visit{
			visited_at: '2026-09-09T18:07:13.123Z'
			referral: 'news.ycombinator.com'
			referral_url: 'https://news.ycombinator.com/item?id=2'
		},
	]

	html := app.render_stats(visits, '2026-09-09')
	assert html.contains('<td>news.ycombinator.com</td><td>2</td>')
	assert !html.contains('item?id=')
}

fn test_escape_html() {
	assert escape_html('<Vinix & "V">') == '&lt;Vinix &amp; &quot;V&quot;&gt;'
}

fn test_country_code_accepts_only_iso_alpha_2_values() {
	assert country_code('us') == 'US'
	assert country_code(' RU ') == 'RU'
	assert country_code('T1') == 'Unknown'
	assert country_code('XX') == 'Unknown'
	assert country_code('') == 'Unknown'
}

fn test_country_flag_uses_regional_indicator_symbols() {
	assert country_flag('US') == '🇺🇸'
	assert country_flag('Unknown') == '🏳️'
}

fn test_botdetect_classifies_known_bot_agents_and_probe_urls() {
	assert is_bot_visit('Mozilla/5.0 (compatible; Googlebot/2.1)', '/')
	assert is_bot_visit('Mozilla/5.0', '/wp-admin/')
	assert !is_bot_visit('Mozilla/5.0', '/')
}

fn test_visit_day_uses_the_date_portion_of_an_rfc3339_timestamp() {
	assert visit_day('2026-09-09T18:06:13.123Z') == '2026-09-09'
	assert visit_day('') == ''
}

fn test_visit_hour_reads_an_rfc3339_utc_timestamp() {
	assert visit_hour('2026-09-09T18:06:13.123Z') == 18
	assert visit_hour('2026-09-09T24:00:00.000Z') == -1
	assert visit_hour('not a timestamp') == -1
}

fn test_is_day_key_requires_a_date_shape() {
	assert is_day_key('2026-09-09')
	assert !is_day_key('2026-9-09')
	assert !is_day_key('2026-09-0x')
}

fn test_requested_stats_day_reads_the_day_query_parameter() {
	assert requested_stats_day('/stats228?day=2026-09-09') == '2026-09-09'
	assert requested_stats_day('/stats228') == ''
}

fn test_stats_lists_full_referrer_urls_separately_from_hostnames() {
	app := &App{
		stats_template: '{{referral_url_table}}'
	}
	visits := [
		Visit{
			visited_at: '2026-09-09T18:06:13.123Z'
			referral: 'news.ycombinator.com'
			referral_url: 'https://news.ycombinator.com/item?id=1'
		},
		Visit{
			visited_at: '2026-09-09T18:07:13.123Z'
			referral: 'news.ycombinator.com'
			referral_url: 'https://news.ycombinator.com/item?id=1'
		},
		Visit{
			visited_at: '2026-09-09T18:08:13.123Z'
			referral: 'news.ycombinator.com'
			referral_url: 'https://news.ycombinator.com/item?id=2'
		},
	]

	html := app.render_stats(visits, '2026-09-09')
	assert html.contains('https://news.ycombinator.com/item?id=1')
	assert html.contains('https://news.ycombinator.com/item?id=2')
	// The busiest URL ranks first.
	assert html.index('item?id=1') or { -1 } < html.index('item?id=2') or { -1 }
	assert html.contains('rel="nofollow noreferrer noopener"')
}

fn test_stats_referrer_url_table_omits_visits_without_a_referrer() {
	app := &App{
		stats_template: '{{referral_url_table}}'
	}
	visits := [
		Visit{
			visited_at: '2026-09-09T18:06:13.123Z'
			referral: 'Direct / unknown'
			referral_url: ''
		},
	]

	html := app.render_stats(visits, '2026-09-09')
	assert html.contains('No referrer URLs have been recorded yet.')
}

fn test_stats_referrer_url_table_stops_at_thirty_rows() {
	app := &App{
		stats_template: '{{referral_url_table}}'
	}
	mut visits := []Visit{}
	// 40 distinct URLs, each with a visit count that makes its rank predictable.
	for index in 0 .. 40 {
		for _ in 0 .. 40 - index {
			visits << Visit{
				visited_at: '2026-09-09T18:06:13.123Z'
				referral: 'example.com'
				referral_url: 'https://example.com/page-${index}'
			}
		}
	}

	html := app.render_stats(visits, '2026-09-09')
	assert html.count('<tr><td class="stats-rank">') == stats_referral_urls_to_show
	assert html.contains('/page-29')
	assert !html.contains('/page-30')
}

fn test_stats_referrer_url_table_escapes_and_shortens_long_urls() {
	app := &App{
		stats_template: '{{referral_url_table}}'
	}
	long_url := 'https://example.com/?q=' + 'a'.repeat(200) + '&x="><script>'
	visits := [
		Visit{
			visited_at: '2026-09-09T18:06:13.123Z'
			referral: 'example.com'
			referral_url: long_url
		},
	]

	html := app.render_stats(visits, '2026-09-09')
	assert !html.contains('<script>')
	assert html.contains('&lt;script&gt;')
	// The href keeps the whole URL while the visible label is shortened.
	assert html.contains('&amp;x=&quot;&gt;&lt;script&gt;"')
	assert html.contains('…')
}

fn test_truncate_counts_runes_not_bytes() {
	assert truncate('vinix', 5) == 'vinix'
	assert truncate('vinix', 3) == 'vin…'
	// Cyrillic is two bytes per rune, so a byte-based cut would corrupt it.
	assert truncate('привет', 3) == 'при…'
}

fn test_ranked_counts_orders_by_visits() {
	rows := ranked_counts({
		'a': 1
		'b': 5
		'c': 3
	})
	assert rows.len == 3
	assert rows[0].name == 'b'
	assert rows[0].visits == 5
	assert rows[1].name == 'c'
	assert rows[2].name == 'a'
}
