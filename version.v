module main

import json2
import net.http
import time
import veb

// A Vinix desktop asks /version which release is the newest at boot and tells
// its user to download that one when the release it runs is older. Releases
// are the `iso-*` GitHub releases deploy-iso.sh publishes. The nightly and M1
// installer releases in the same repository are not system images, so they do
// not count.
const releases_api_url = 'https://api.github.com/repos/vlang/vinix/releases?per_page=30'
// GitHub allows 60 unauthenticated API requests an hour from one address.
const release_refresh_interval = 10 * time.minute
const release_retry_interval = time.minute

struct GithubRelease {
	tag_name   string
	draft      bool
	prerelease bool
}

@['/version'; get]
pub fn (mut app App) version(mut ctx Context) veb.Result {
	app.latest_release_lock.rlock()
	tag := app.latest_release
	app.latest_release_lock.runlock()
	ctx.set_header(.cache_control, 'no-cache')
	if tag == '' {
		// Not known yet: a desktop that gets no tag simply says nothing.
		ctx.res.set_status(.service_unavailable)
		return ctx.text('unknown\n')
	}
	return ctx.text(tag + '\n')
}

// watch_latest_release keeps app.latest_release current. The request handler
// only reads the last answer, so a slow or failing GitHub never delays it.
fn (mut app App) watch_latest_release() {
	for {
		tag := fetch_newest_release() or {
			eprintln('Could not look up the newest Vinix release: ${err}')
			time.sleep(release_retry_interval)
			continue
		}
		app.latest_release_lock.lock()
		app.latest_release = tag
		app.latest_release_lock.unlock()
		time.sleep(release_refresh_interval)
	}
}

fn fetch_newest_release() !string {
	response := http.fetch(
		url:        releases_api_url
		user_agent: 'vinix-os.org'
		header:     http.new_header(key: .accept, value: 'application/vnd.github+json')
	)!
	if response.status_code != 200 {
		return error('GitHub answered ${response.status_code}')
	}
	return newest_release(response.body)
}

// newest_release picks the newest published system image release from a
// GitHub release list, which GitHub orders newest first.
fn newest_release(body string) !string {
	releases := json2.decode[[]GithubRelease](body)!
	for release in releases {
		if !release.draft && !release.prerelease && is_release_tag(release.tag_name) {
			return release.tag_name
		}
	}
	return error('none of the ${releases.len} newest releases is a system image')
}

// is_release_tag accepts the tags deploy-iso.sh gives releases: iso-YYYY-MM-DD,
// then -2, -3, ... for later releases on the same day.
fn is_release_tag(tag string) bool {
	if tag.len < 14 || !tag.starts_with('iso-') {
		return false
	}
	for i in 4 .. 14 {
		want_dash := i == 8 || i == 11
		if (tag[i] == `-`) != want_dash || (!want_dash && !tag[i].is_digit()) {
			return false
		}
	}
	if tag.len == 14 {
		return true
	}
	if tag.len == 15 || tag[14] != `-` {
		return false
	}
	for c in tag[15..] {
		if !c.is_digit() {
			return false
		}
	}
	return true
}
