# pantheon-mobile

Flutter app for the Pantheon runtime. It talks to the dashboard API over
your LAN and keeps its token on the device.

## Screens

- Home: runs, approvals, gateway and health at a glance
- Runs: open a session, rewind it, change its model or title
- Approvals: grant or deny requests before the runtime continues
- Usage: token spend, limits and schedules
- More: keys, plugins, skills, MCP servers, logs and settings

## Connect it

Start the dashboard on the machine running Pantheon:

```
pantheon dashboard --bind 0.0.0.0 --port 7171
```

Open the More tab, enter the host IP and port, then paste the dashboard
token. The app sends it as `x-pantheon-token` on every request. Nothing is
stored in the cloud.

## Develop

Needs Flutter 3.47 or newer.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

The app expects a reachable Pantheon dashboard. The fake API in `test/`
covers the widget contracts when no dashboard is running.
