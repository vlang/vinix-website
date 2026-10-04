module main

import net.http
import os
import sync
import traffic
import veb

const default_port = 8080
const visit_cookie_name = 'vinix_session_visit'

pub struct Context {
	veb.Context
}

pub struct App {
	veb.StaticHandler
mut:
	traffic      &traffic.Tracker
	stats_traffic &traffic.Tracker
	traffic_lock sync.Mutex
	home_html    string
	// The newest Vinix release, for /version. See version.v.
	latest_release      string
	latest_release_lock sync.RwMutex
}

@['/'; get]
pub fn (mut app App) index(mut ctx Context) veb.Result {
	user_agent := ctx.req.header.get(.user_agent) or { '' }
	if traffic.is_bot_request(user_agent, ctx.req.url) {
		// Crawlers do not reliably retain cookies, so preserve each event while
		// the tracker keeps it out of the human totals.
		app.record_home_visit(ctx)
		return ctx.html(app.home_html)
	}

	// Count at most once per browser session so reloading the home page does
	// not inflate the visit total. This cookie is not stored in the database.
	if ctx.get_cookie(visit_cookie_name) == none {
		app.record_home_visit(ctx)
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
	return ctx.html(app.stats_traffic.stats_html(ctx.req.url, traffic.PageConfig{
		site_name: 'Vinix'
		page_title: 'Vinix traffic statistics'
		home_url: '/'
		stats_path: '/stats228'
	}))
}

fn (mut app App) record_home_visit(ctx Context) {
	// Veb serves requests concurrently, while the tracker holds one PostgreSQL
	// connection. pg.DB does not permit concurrent queries on that connection.
	// Telemetry must never delay page delivery, so skip an event while another
	// request is writing rather than queueing request workers behind the database.
	if !app.traffic_lock.try_lock() {
		return
	}
	defer {
		app.traffic_lock.unlock()
	}
	app.traffic.record(traffic.Request{
		url: ctx.req.url
		referer: ctx.get_header(.referer) or { '' }
		user_agent: ctx.req.header.get(.user_agent) or { '' }
		country: ctx.get_custom_header('CF-IPCountry') or { '' }
	}) or {
		eprintln('Could not record page visit: ${err}')
	}
}

fn main() {
	conninfo := os.getenv('VINIX_DB_CONNINFO')
	mut tracker := traffic.new(traffic.Config{
		conninfo: conninfo
		site_id: 'vinix'
	}) or {
		panic('Could not initialise traffic tracking: ${err}')
	}
	mut stats_tracker := traffic.new(traffic.Config{
		conninfo: conninfo
		site_id: 'vinix'
	}) or {
		panic('Could not initialise traffic statistics: ${err}')
	}
	mut app := &App{
		traffic:       tracker
		stats_traffic: stats_tracker
		home_html:     os.read_file('index.html') or { panic('Could not load index.html: ${err}') }
	}
	app.latest_release_lock.init()
	spawn app.watch_latest_release()
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
