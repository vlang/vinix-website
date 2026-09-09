module main

fn test_referral_host_keeps_only_the_hostname() {
	assert referral_host('https://News.YCombinator.com/item?id=1') == 'news.ycombinator.com'
	assert referral_host('not a URL') == 'Direct / unknown'
	assert referral_host('') == 'Direct / unknown'
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
