# Device QA — Pantheon Mobile UI Protocol

## Status

- `flutter analyze`: 0 errors
- `flutter test test/ui_protocol_test.dart`: 24/24 pass
- Server-side HTTP: form submit, UI_REPLAY, UI_STALE, UI_BAD_ACTION verified
- **NOT device-verified.** Do not commit or push until the APK builds
  and device-level form/revision tests pass.

## Build (unproxied machine only)

```bash
cd ~/workspace/pantheon-mobile
flutter pub get
flutter analyze
flutter test test/ui_protocol_test.dart
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

## Dashboard

```bash
cd ~/workspace/pantheon          # branch chloe/agent-ui
cargo build -p pantheon-tui
./target/debug/pantheon dashboard --host 0.0.0.0 --port 7171
# Copy the printed token. It is the dashboard password.
# Plain HTTP on a LAN is NOT encrypted. Trusted networks only.
```

LAN IP: `ip route get 1.1.1.1 | awk '{print $7}'` (Linux)
or `ipconfig getifaddr en0` (macOS).

In the app: enter `http://<LAN-IP>:7171` and paste the token.
Never commit, screenshot, or log the token.

## Already verified (do not re-prove)

- Form submit → 200 `{"outcome":"executed"}`; secret not echoed
- Same nonce → 409 `UI_REPLAY`
- Wrong revision → 409 `UI_STALE`
- Unknown action → 409 `UI_BAD_ACTION`
- Approval without parked turn → 409 `UI_STALE`
- Timeout retry reuses nonce (unit test)
- Malformed/unknown/deep input degrades safely (unit tests)

## Requires a real device

1. **Connect** with valid token; verify error messages for bad token/URL.
2. **Render** all 15 component types from a fixture document.
3. **Form**: fill, validate required fields, verify secret masking, submit.
4. **Stale**: display rev N, publish rev N+1, submit from old view →
   expect refresh to new revision.
5. **Replay**: submit twice rapidly → second shows already-submitted state.
6. **Interrupt**: airplane mode mid-submit → truthful "may have run"
   message; retry reuses the same nonce.
7. **Reconnect**: kill/restart dashboard → app recovers via polling.

## Approval park/resume (needs provider)

Requires a configured model provider (may incur API cost).
Do not run without explicit authorization.

1. Start a turn that calls `render_ui` with an approval card.
2. Confirm the turn parks (dashboard shows parked status).
3. Tap Approve in the app → expect `{"outcome":"decided","approved":true}`
   and the turn to resume.
4. Tap Approve again → expect 409 `UI_STALE` ("already decided").
5. Deny path: expect `{"outcome":"decided","approved":false}`.

## Constraints

- Do NOT commit or push until APK builds and device tests 1–7 pass.
- Do NOT claim exactly-once or global atomicity: mobile, dashboard,
  and TUI are separate processes; nonce dedup is per-process.
- Fixture tooling must stay test-only and be removed after use.
