# Native SDK Source Docs Snapshot

This folder contains a local snapshot of the Native SDK documentation source
from `vercel-labs/native` v0.4.3, refreshed on 2026-07-10 for this project.

Use these files together with the installed Native SDK agent skills:

```sh
native skills get core --full
native skills get native-ui
native skills get automation
```

The downloaded docs are source `.mdx` and `.md` files, not rendered website
HTML. Search them with `rg`.

## High-Value Pages

- `native-sdk-source/docs/src/app/native-ui/page.mdx`: markup, widgets,
  bindings, templates, hidden titlebar notes, keyboard routing, accessibility,
  testing patterns.
- `native-sdk-source/docs/src/app/windows/page.mdx`: windows, titlebar modes,
  chrome behavior.
- `native-sdk-source/docs/src/app/native-surfaces/page.mdx`: GPU surfaces,
  native-rendered panes, WebView panes, and surface layout.
- `native-sdk-source/docs/src/app/menus/page.mdx`: context menus, app menus, and
  menu commands.
- `native-sdk-source/docs/src/app/keyboard-shortcuts/page.mdx`: shortcut
  declarations and command dispatch.
- `native-sdk-source/docs/src/app/native-controls/page.mdx`: platform-native
  control seams.
- `native-sdk-source/docs/src/app/state/page.mdx`: `Model`, `Msg`, `update`,
  bindings, and data flow rules.
- `native-sdk-source/docs/src/app/theming/page.mdx`: design tokens and
  appearance handling.
- `native-sdk-source/docs/src/app/automation/page.mdx`: runtime snapshots,
  widget driving, and screenshot automation.
- `native-sdk-source/docs/src/app/testing/page.mdx`: headless UI tests and
  runtime test patterns.
- `native-sdk-source/docs/src/app/packaging/page.mdx`: packaging flow and app
  bundle details.
- `native-sdk-source/docs/src/app/runtime/page.mdx`: runtime options, services,
  and lifecycle.
- `native-sdk-source/docs/src/app/security/page.mdx`: permissions, navigation
  policy, bridge policy, and trust boundaries.
- `native-sdk-source/skill-data/native-ui/SKILL.md`: installed agent-facing
  Native UI guide source.
- `native-sdk-source/skill-data/core/SKILL.md`: installed agent-facing core
  guide source.

## Hidden Titlebar Checklist

For a macOS hidden titlebar window, use the docs above plus this checklist:

1. Add `titlebar = "hidden_inset"` or `"hidden_inset_tall"` to the manifest
   window in `app.zon`.
2. Mirror the same titlebar mode in the `native_sdk.ShellWindow` declaration in
   `src/main.zig`.
3. Give the custom header row in `src/app.native` `window-drag="true"`.
4. Keep buttons and text fields as real controls inside the drag region; they
   remain interactive while the background drags the window.
5. For precise traffic-light spacing, wire `Options.on_chrome`, store the
   chrome insets in `Model`, and pad the header with a leading spacer.

Validate titlebar-related changes with:

```sh
native markup check src/app.native
zig build
zig build test
native doctor --manifest app.zon --strict
```

For live verification, build with automation enabled and inspect the snapshot:

```sh
zig build run -Dplatform=macos -Dautomation=true
native automate wait
native automate snapshot
```
