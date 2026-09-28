# Pantheon for Mobile

Mobile companion for the [Pantheon](https://github.com/k1ng0mar/pantheon) agent runtime.
It talks to the Pantheon dashboard API over your LAN — runs, approvals, usage stats,
and scheduled jobs, from your phone.

Built with Flutter. Dark-first, Pantheon purple (`#7223FF → #4B00CD → #0C0046`).

## Screens

- **Home** — gateway status, KPI cards (runs, pending approvals, 24h cost/tokens), runs by status, scheduler summary
- **Runs** — searchable, filterable run list; tap through to transcript + event timeline
- **Approvals** — pending approval queue with grant/deny (badge count on the tab)
- **Usage** — cost/token KPIs, per-day bars, per-model breakdown (7/30/90d windows)
- **More → Schedule** — recurring jobs, active/paused state
- **More → Settings** — edit connection, sign out

## Connect it

On the machine running Pantheon, expose the dashboard to your LAN:

```sh
pantheon dashboard --bind 0.0.0.0 --port 7171
```

It prints a URL with a per-instance token. In the app, enter the dashboard URL
(use the machine's LAN IP, e.g. `http://192.168.1.10:7171` — not `localhost`)
and paste the token. The token is stored only on your device.

The app sends the token as the `x-pantheon-token` header, the same auth the web
dashboard uses.

## Develop

Requires the Flutter SDK (3.47+ / Dart 3.13+):

```sh
flutter pub get
flutter run
```

Analyze + test:

```sh
flutter analyze
flutter test
```

## Project layout

```
lib/
  main.dart            app shell, bottom nav, connection gating
  theme.dart           Pantheon brand theme + formatting helpers
  models/              overview, run, approval, usage_stats, scheduled_job, gateway_status
  services/
    pantheon_api.dart  typed client for the dashboard REST API
    settings_store.dart persisted base URL (SharedPreferences) + token (platform keychain/keystore)
  screens/             connect, home, runs, run_detail, approvals, stats, schedule, settings
  widgets/             kpi_card, status_chip, gradient_header
```

## Status

v0.1 — read + approve control plane. Roadmap: push notifications for pending
approvals, run resume/trigger actions, log stream view, biometric lock for the
stored token.
