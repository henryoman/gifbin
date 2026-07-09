# GIFMaker

[![Built with Native SDK](https://img.shields.io/badge/Native%20SDK-Vercel%20Labs-000000?logo=vercel&logoColor=white)](https://github.com/vercel-labs/native)
[![Zig](https://img.shields.io/badge/Zig-0.16-f7a41d?logo=zig&logoColor=111111)](https://ziglang.org/)
[![Platform](https://img.shields.io/badge/platform-macOS-111111?logo=apple&logoColor=white)](app.zon)
[![UI](https://img.shields.io/badge/UI-native%20GPU%20surface-35c2ff)](src/main.zig)
[![GIF encoder](https://img.shields.io/badge/GIF-msf__gif%202.4-8a63d2)](third_party/msf_gif/msf_gif.h)
[![No WebView](https://img.shields.io/badge/WebView-not%20used-25a244)](app.zon)

GIFMaker is a small native desktop app for turning PNG/JPEG image frames into an
animated GIF. It is built with the Vercel Labs Native SDK and Zig: the window,
controls, preview, dialogs, app model, export path, and dev runner all live in
this repository as native code.

This is not an Electron app, not a web frontend, and not a WebView shell. The
app uses a Native SDK GPU surface and Native SDK canvas widgets for the UI, with
Zig handling state updates, drag/drop, native file dialogs, preview image
registration, and GIF export.

## Native SDK

The important architectural choice in this repo is the Vercel Labs Native SDK.
Native SDK gives the app a real desktop window, native lifecycle/runtime
services, GPU-rendered surfaces, canvas UI widgets, automation hooks, dialogs,
and packaging/build tooling while keeping application behavior in Zig.

In this app:

- `app.zon` is the product manifest: app id, display name, icon, macOS platform,
  permissions, GPU surface window, and security policy.
- `src/main.zig` wires the Native SDK `UiApp`, declares the canvas view, handles
  drag/drop and dialogs, registers preview images, and runs the app.
- `src/model.zig` is the app state machine: slides, selection, ordering, speed,
  quality, output width, status text, and pending native actions.
- `build.zig` owns the Native SDK build graph for this expanded app and links
  the platform image bridge plus GIF encoder.
- `dev.zig` and `scripts/dev` are the repo-local developer runner so the app can
  be launched from the terminal with useful errors and quiet default logs.
- `docs/native-sdk-source/` is a small local snapshot of the Native SDK docs
  from `vercel-labs/native`, kept so the implementation choices are easy to
  audit without hunting through external docs.

The manifest explicitly uses a GPU surface:

```zig
.capabilities = .{ "native_views", "gpu_surfaces" },
```

and the runtime path disables the JavaScript window API:

```zig
.js_window_api = false,
```

That is the core point of the project: a native-rendered GIF tool, written in
Zig, using Native SDK as the desktop runtime.

## Libraries

- **Vercel Labs Native SDK**: desktop runtime, app manifest, GPU surface,
  Native SDK canvas UI, dialogs, drag/drop events, automation, and packaging
  hooks.
- **Zig 0.16**: app state, update loop, Native SDK wiring, dev CLI, build
  graph, tests, and GIF export pipeline.
- **Apple CoreFoundation/CoreGraphics/ImageIO**: macOS PNG/JPEG metadata and
  decode path in `src/platform_image_macos.m`.
- **msf_gif 2.4**: tiny C GIF encoder vendored in `third_party/msf_gif/`, used
  through `src/gif_writer.zig`.
- **Native SDK automation**: smoke checks for rendered GPU canvas output through
  `native automate`.
- **Bash + Zig runner**: `scripts/dev` and `dev.zig` provide the project CLI
  instead of relying on Finder double-click behavior.

## Features

- Import PNG/JPEG frames through native open dialogs.
- Drag and drop image files into the Native SDK window.
- Reorder, duplicate, remove, and select frames.
- Preview the selected image using Native SDK canvas image registration.
- Tune frame speed, output width, and encoder quality.
- Preserve frame aspect ratio with contain-fit output, avoiding unnecessary
  crop when source images differ in shape.
- Export an actual animated GIF with `msf_gif`.
- Run quiet terminal-first dev builds that show real errors without dumping
  every input event.

## Commands

```sh
zig run dev.zig                        # tiny interactive project CLI
zig run dev.zig -- help                # CLI commands and options
zig run dev.zig -- run                 # dev run: checks, Debug build, quiet logs
zig run dev.zig -- native              # official Native SDK CLI path: native dev .
zig run dev.zig -- smoke               # launch, assert the canvas renders, stop
zig run dev.zig -- check               # run app Zig tests

zig build dev                          # short alias for the dev run
zig build dev-smoke                    # short alias for smoke verification
zig build dev-check                    # short alias for preflight checks
zig build test                         # run app tests
zig build                              # build the app binary
```

`zig run dev.zig -- run` is the recommended development path for this repo. It
runs the local checks, builds the app in Debug mode, enables Native SDK
automation, and keeps event tracing off by default. Build errors, panics, and
app stderr still print in the terminal.

Use verbose tracing only when debugging low-level Native SDK runtime/input
events:

```sh
zig run dev.zig -- run --verbose
TRACE=events zig build dev
```

Zig source changes need a restart of the dev runner.

## Native SDK CLI

The repo also keeps the official Native SDK CLI path available:

```sh
zig run dev.zig -- native
```

That delegates to:

```sh
native dev .
```

For this app, `zig run dev.zig -- run` is usually cleaner because the repo owns
`build.zig` and has project-specific ImageIO, CoreGraphics, and `msf_gif` wiring.

## Development Notes

Do not double-click `zig-out/bin/gifmaker` in Finder during development. macOS
treats it as a Unix executable and may open it in a separate Terminal app. Use
the project runner instead:

```sh
./scripts/dev
```

The Native SDK dependency is local in `build.zig.zon`:

```zig
.native_sdk = .{ .path = "../../../../../Users/henryoman/.bun/install/global/node_modules/@native-sdk/cli" },
```

Edit `.dependencies.native_sdk.path` in `build.zig.zon` if you move this app or
the Native SDK checkout.
