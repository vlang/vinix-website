module main

fn test_release_tags() {
	assert is_release_tag('iso-2026-09-29')
	assert is_release_tag('iso-2026-09-29-2')
	assert is_release_tag('iso-2026-09-29-12')
	assert !is_release_tag('nightly-2026-09-07')
	assert !is_release_tag('m1-installer-latest')
	assert !is_release_tag('iso-2026-09-29-')
	assert !is_release_tag('iso-2026-09-29x')
	assert !is_release_tag('iso-2026-9-29')
	assert !is_release_tag('iso-2026-09-29-2a')
}

fn test_newest_release_skips_nightlies_prereleases_and_drafts() {
	body := '[
		{"tag_name": "iso-2026-10-02", "draft": true, "prerelease": false},
		{"tag_name": "nightly-2026-10-01", "draft": false, "prerelease": false},
		{"tag_name": "m1-installer-latest", "draft": false, "prerelease": true},
		{"tag_name": "iso-2026-09-30", "draft": false, "prerelease": true},
		{"tag_name": "iso-2026-09-29-2", "draft": false, "prerelease": false},
		{"tag_name": "iso-2026-09-29", "draft": false, "prerelease": false}
	]'
	assert newest_release(body)! == 'iso-2026-09-29-2'
	if _ := newest_release('[{"tag_name": "nightly-2026-10-01"}]') {
		assert false
	}
}
