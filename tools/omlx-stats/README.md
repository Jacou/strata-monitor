# oMLX stats proxy

A read-only proxy that serves oMLX's stats without the API key, and the dashboard at `/`.

- `statsproxy.py` — listens on `:8001` (port is `sys.argv[1]`), forwards `GET /admin/api/activity`,
  `/admin/api/stats` and `/health` to `127.0.0.1:8000`, adding the key from `~/.omlx/settings.json`
  server-side and stripping `api_key` from the stats body. It also tails
  `~/.omlx/logs/server.log` incrementally and serves `GET /admin/api/recent`: a ring of the last 20
  finished requests, per-model context windows (from `/admin/api/models`, refreshed every 60 s) and
  the engine's concurrent lane count (`scheduler.max_concurrent_requests`). Seeding reads only the
  last 256 KB of the log; afterwards only appended bytes.
- `omlx-stats.html` — the dashboard served at `/`; it shows every returned field and the raw
  payloads, with the key stripped from the stats panel.

## Run

```sh
python3 statsproxy.py 8001   # port optional; 8001 is the default
```

On the Mac Studio both files live in `~/omlx-stats/`, and a LaunchDaemon
(`/Library/LaunchDaemons/com.omlx.stats.plist`: `RunAtLoad`, `KeepAlive`, `UserName jacou`) runs
it, logging to `~/omlx-stats/proxy.log`. After an edit:

```sh
sudo launchctl kickstart -k system/com.omlx.stats
```

The proxy needs no auth; only the engine on `:8000` does. Keep it on the LAN: it exposes the
server's stats and the recent request history.
