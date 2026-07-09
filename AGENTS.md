# Agent Notes

This project is a Native SDK desktop app named `gifmaker`.

Native SDK is a new native desktop toolkit from Vercel. The default app model is
native-rendered. This app uses a Zig-built Native SDK canvas UI so the preview
can render runtime-registered image resources. It is not a browser UI by
default. WebView surfaces are available, but this app currently uses a GPU
canvas/native UI surface.

## Project Shape

- `app.zon`: product manifest, app identity, windows, permissions, platform
  capabilities, icon inputs, security policy, and packaging metadata.
- `src/main.zig`: app wiring, shell window setup, Zig-built view, preview image
  registration, dialogs/drop handling, and `Model`/`Msg`/`update` integration.
- `src/model.zig`: app data model and business state.
- `src/tests.zig`: headless UI tests that build the real view tree and dispatch
  real typed messages.
- `build.zig` and `build.zig.zon`: owned Zig build graph and Native SDK
  dependency path.
- `docs/native-sdk-source/`: local snapshot of Native SDK `.mdx`/`.md` source
  docs from `vercel-labs/native`.

## Required Tooling

This repo currently targets:

- Zig `0.16.0`
- `@native-sdk/cli` / `native` `0.4.1`
- Bun `1.3.14`

Check versions with:

```sh
zig version
native --version
bun --version
```

## Native SDK References

Before changing Native SDK code, read the installed skills and the local docs:

```sh
native skills get core --full
native skills get native-ui
native skills get automation
```

Useful downloaded docs:

- `docs/native-sdk-source/docs/src/app/native-ui/page.mdx`
- `docs/native-sdk-source/docs/src/app/windows/page.mdx`
- `docs/native-sdk-source/docs/src/app/native-surfaces/page.mdx`
- `docs/native-sdk-source/docs/src/app/menus/page.mdx`
- `docs/native-sdk-source/docs/src/app/keyboard-shortcuts/page.mdx`
- `docs/native-sdk-source/docs/src/app/automation/page.mdx`
- `docs/native-sdk-source/docs/src/app/testing/page.mdx`
- `docs/native-sdk-source/docs/src/app/packaging/page.mdx`
- `docs/native-sdk-source/docs/src/app/runtime/page.mdx`
- `docs/native-sdk-source/docs/src/app/security/page.mdx`
- `docs/native-sdk-source/skill-data/native-ui/SKILL.md`
- `docs/native-sdk-source/skill-data/core/SKILL.md`

## Editing Rules

- Keep the view declarative at the builder level: view code builds widgets from
  model state and dispatches messages; it does not mutate state.
- Keep state changes in Zig `update` logic.
- Prefer model-derived values over cached display state.
- Use exact security policy and origins. Do not add wildcard permissions or
  origins for convenience.
- For UI controls, use real Native SDK controls instead of drawing fake button
  or input surfaces.
- Keep widget identity stable with `key` or `global-key` when lists can reorder
  or move between containers.

## Hidden Titlebar Work

To hide the macOS titlebar and build a custom draggable header:

1. Add `titlebar = "hidden_inset"` or `"hidden_inset_tall"` to the window in
   `app.zon`.
2. Mirror that mode in the `native_sdk.ShellWindow` in `src/main.zig`.
3. Add `.window_drag = true` to the custom header row in `src/main.zig`.
4. Use normal buttons/fields inside the header. Controls keep their own input
   behavior; empty header background becomes the drag region.
5. If traffic-light alignment matters, add `Options.on_chrome`, store the
   chrome inset/button geometry in the model, and pad the header with a spacer.

## Validation

Use the local dev runner for interactive checks:

```sh
zig run dev.zig -- help
zig run dev.zig -- run
zig run dev.zig -- native
zig run dev.zig -- smoke
zig run dev.zig -- check
zig build dev
zig build dev-smoke
zig build dev-check
```

Run the narrow checks after Native UI edits:

```sh
zig build test
zig build
```

Before calling a change done, run:

```sh
native validate app.zon
native doctor --manifest app.zon --strict
```

For live GUI verification:

```sh
zig build run -Dplatform=macos -Dautomation=true
native automate wait
native automate snapshot
```
