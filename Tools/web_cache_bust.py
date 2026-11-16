#!/usr/bin/env python3
"""Makes a reload of the exported web build fetch the new build.

Run on the folder Godot exported the Web preset into, with the build's
version (the commit sha in CI):

    python3 Tools/web_cache_bust.py build/web "$GITHUB_SHA"

It rewrites index.html so that:
- the engine script loads as index.js?v=<version>;
- every same-origin .js, .wasm and .pck the engine fetches (the main wasm,
  the GDExtension wasm, index.pck) gets ?v=<version> while the browser is
  online, so neither the HTTP cache nor the service worker's cache can hand
  back an older file (offline, the plain names still hit the service
  worker's cache, so the installed app keeps working);
- the page fetches version.txt without any cache; if it names another
  version than the page's, the page drops its service workers and caches
  and reloads once (a stale index.html served from a cache heals itself);
- no-cache meta tags ask browsers to revalidate index.html.

It writes version.txt next to index.html. Every rewrite is checked: if the
exported page does not look as expected (Godot changed its shell), it exits
with an error instead of shipping a build that would stay cached.
"""

import pathlib
import re
import sys

MARKER = "falemag-cache-bust"


def head_block(version: str) -> str:
    return f"""<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
<script id="{MARKER}">
(function () {{
	var build = "{version}";
	window.FALEMAG_BUILD = build;
	var plainFetch = window.fetch.bind(window);
	window.fetch = function (input, init) {{
		if (typeof input === "string" && navigator.onLine !== false) {{
			try {{
				var url = new URL(input, location.href);
				if (url.origin === location.origin && /\\.(js|wasm|pck)$/.test(url.pathname) && !url.search) {{
					url.search = "v=" + build;
					input = url.href;
				}}
			}} catch (error) {{}}
		}}
		return plainFetch(input, init);
	}};
	plainFetch("version.txt", {{ cache: "no-store" }}).then(function (response) {{
		return response.ok ? response.text() : null;
	}}).then(function (text) {{
		var live = text ? text.trim() : "";
		if (!live || live === build) {{
			return;
		}}
		var key = "falemag-reloaded-for-" + live;
		try {{
			if (sessionStorage.getItem(key)) {{
				return;
			}}
			sessionStorage.setItem(key, "1");
		}} catch (error) {{}}
		var drops = [];
		if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {{
			drops.push(navigator.serviceWorker.getRegistrations().then(function (registrations) {{
				return Promise.all(registrations.map(function (registration) {{ return registration.unregister(); }}));
			}}));
		}}
		if (window.caches && caches.keys) {{
			drops.push(caches.keys().then(function (keys) {{
				return Promise.all(keys.map(function (key) {{ return caches.delete(key); }}));
			}}));
		}}
		Promise.all(drops).catch(function () {{}}).then(function () {{
			location.replace(location.pathname + "?v=" + encodeURIComponent(live));
		}});
	}}).catch(function () {{}});
}})();
</script>
"""


def fail(message: str) -> None:
    print(f"web_cache_bust: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: web_cache_bust.py <export folder> <version>")
    folder = pathlib.Path(sys.argv[1])
    version = sys.argv[2].strip()
    if not re.fullmatch(r"[0-9A-Za-z._-]{1,64}", version):
        fail(f"the version {version!r} must be 1-64 letters, digits, '.', '_' or '-'")
    page = folder / "index.html"
    if not page.is_file():
        fail(f"{page} does not exist")
    html = page.read_text(encoding="utf-8")
    if MARKER in html:
        fail(f"{page} was already rewritten")

    heads = re.findall(r"<head[^>]*>", html)
    if len(heads) != 1:
        fail(f"expected one <head> in {page}, found {len(heads)}")
    html = html.replace(heads[0], heads[0] + "\n" + head_block(version), 1)

    scripts = re.findall(r'<script src="index\.js"></script>', html)
    if len(scripts) != 1:
        fail(f'expected one <script src="index.js"></script> in {page}, found {len(scripts)}')
    html = html.replace(scripts[0], f'<script src="index.js?v={version}"></script>', 1)

    # The engine must fetch the files this page knows by name.
    for name in ("index.pck", "index.wasm"):
        if not (folder / name).is_file():
            fail(f"{folder / name} does not exist")
    if '"executable":"index"' not in html.replace(" ", ""):
        fail(f'GODOT_CONFIG in {page} does not name "index" as the executable (index.wasm, index.pck)')

    page.write_text(html, encoding="utf-8")
    (folder / "version.txt").write_text(version + "\n", encoding="utf-8")

    check = page.read_text(encoding="utf-8")
    if check.count(MARKER) != 1 or f"index.js?v={version}" not in check or f'var build = "{version}"' not in check:
        fail(f"the rewrite of {page} did not stick")
    print(f"web_cache_bust: {page} loads build {version}; version.txt written")


if __name__ == "__main__":
    main()
