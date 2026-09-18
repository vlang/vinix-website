module main

import traffic

fn test_home_route_uses_the_shared_traffic_module() {
	assert traffic.is_bot_request('Mozilla/5.0 (compatible; Googlebot/2.1)', '/')
	assert !traffic.is_bot_request('Mozilla/5.0', '/')
}
