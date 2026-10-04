(() => {
	const storageKey = "vinix-theme";
	const root = document.documentElement;
	let toggle;

	function readPreference() {
		try {
			const saved = localStorage.getItem(storageKey);
			return saved === "light" || saved === "dark" ? saved : null;
		} catch {
			return null;
		}
	}

	const media = window.matchMedia("(prefers-color-scheme: dark)");
	function systemPreference() {
		return media.matches ? "dark" : "light";
	}

	let preference = readPreference();

	function applyTheme() {
		const theme = preference || systemPreference();
		root.dataset.theme = theme;
		document.querySelector('meta[name="theme-color"]').content =
			theme === "dark" ? "#000000" : "#ffffff";

		if (toggle) {
			const nextTheme = theme === "dark" ? "light" : "dark";
			const label = `Switch to ${nextTheme} mode`;
			toggle.setAttribute("aria-label", label);
			toggle.title = label;
			toggle.querySelector("span").textContent =
				nextTheme === "dark" ? "Dark mode" : "Light mode";
		}
	}

	applyTheme();

	document.addEventListener("DOMContentLoaded", () => {
		toggle = document.getElementById("theme-toggle");
		applyTheme();
		toggle.hidden = false;
		toggle.addEventListener("click", () => {
			preference = root.dataset.theme === "dark" ? "light" : "dark";
			applyTheme();
			try {
				localStorage.setItem(storageKey, preference);
			} catch {
				// The switch still works when browser storage is unavailable.
			}
		});
	});

	window.addEventListener("storage", (event) => {
		if (event.key === storageKey || event.key === null) {
			preference = readPreference();
			applyTheme();
		}
	});

	media.addEventListener("change", () => {
		if (!preference) {
			applyTheme();
		}
	});
})();
