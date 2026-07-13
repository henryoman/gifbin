# Changelog

All notable changes to gifbin are tracked here.

## 0.0.3 - 2026-07-13

- Upgrade Native SDK from 0.4.4 to 0.5.1.
- Keep the app on its Zig-built native canvas path; the new TypeScript core
  scaffold is optional and does not replace runtime-registered image views.
- Refresh the checked-in Native SDK documentation and release workflow pin.
- Pick up the SDK's renderer memory reduction, safer worker teardown,
  hidden-titlebar collision handling, and stricter package-signing checks.

## 0.0.2 - 2026-07-11

- Upgrade Native SDK from 0.4.3 to 0.4.4.
- Refresh the Native SDK docs and add the matching Zig 0.16 guidance.
- Update release actions and remove stale v0.0.0 defaults and examples.
- Keep the checked-in manifest versions aligned with the latest release.
- Use Native SDK's explicit native-only host path and remove stale WebView/CEF policy.
- Make normal dev launches faster by reserving tests and automation for check/smoke runs.

## 0.0.1 - 2026-07-10

- Upgrade Native SDK from 0.4.1 to 0.4.3.
- Refresh the checked-in Native SDK documentation snapshot for the new release.
- Keep release packaging and local development on the same Native SDK version.

## 0.0.0 - 2026-07-09

- Initial native macOS preview release.
- Supports PNG/JPEG frame import, slide ordering, preview, GIF export, and README release assets.
