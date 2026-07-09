# gifbin: Native SDK + Zig Implementation Plan

This is the straight-up easiest plan for the project.

The app we are building:

```txt
gifbin

Drop images in.
Reorder them.
Set speed.
Pick quality.
Export GIF.
```

The stack:

```txt
Native SDK   = desktop app shell, native UI, dialogs, file drops, packaging
Zig          = app logic, state, export pipeline
Zignal       = image loading/resizing/processing
msf_gif.h    = tiny GIF encoder
CPU only     = no GPU, no game engine, no Electron, no WebView
```

The key decision:

```txt
Use Native SDK + Zignal + msf_gif.h.
Do not use Mach, SDL, GLFW, zgui, zgpu, or a full game-engine loop for v1.
```

---

# 1. First commands: create the project

## macOS / Linux shell

Run this first:

```bash
npm install -g @native-sdk/cli
native version

native init gifbin --full
cd gifbin

native dev
```

That should open the generated Native SDK starter app.

Then stop the dev app and run:

```bash
native check
native test
```

Now add the image library:

```bash
zig fetch --save git+https://github.com/arrufat/zignal
```

Add the GIF encoder:

```bash
mkdir -p third_party/msf_gif

curl -L https://raw.githubusercontent.com/notnullnotvoid/msf_gif/master/msf_gif.h \
  -o third_party/msf_gif/msf_gif.h

cat > third_party/msf_gif/msf_gif_impl.c <<'C_EOF'
#define MSF_GIF_IMPL
#include "msf_gif.h"
C_EOF
```

Create the source files we are going to fill in:

```bash
touch src/model.zig \
      src/image_pipeline.zig \
      src/preview_cache.zig \
      src/gif_writer.zig \
      src/export_pipeline.zig \
      src/fit.zig
```

Optional but useful: dump the Native SDK skills/guidance into local files so exact syntax matches your installed CLI version:

```bash
native skills list
native skills get core --full > NATIVE_SDK_CORE_SKILL.md
native skills get native-ui --full > NATIVE_SDK_NATIVE_UI_SKILL.md
```

After editing `build.zig`, run:

```bash
native check
native test
native dev
```

---

## Windows PowerShell

```powershell
npm install -g @native-sdk/cli
native version

native init gifbin --full
cd gifbin

native dev
```

Then:

```powershell
native check
native test
```

Add Zignal:

```powershell
zig fetch --save git+https://github.com/arrufat/zignal
```

Add `msf_gif.h`:

```powershell
New-Item -ItemType Directory -Path third_party/msf_gif -Force

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/notnullnotvoid/msf_gif/master/msf_gif.h" `
  -OutFile "third_party/msf_gif/msf_gif.h"

@"
#define MSF_GIF_IMPL
#include ""msf_gif.h""
"@ | Set-Content -Path "third_party/msf_gif/msf_gif_impl.c"
```

Create source files:

```powershell
New-Item -ItemType File -Path src/model.zig -Force
New-Item -ItemType File -Path src/image_pipeline.zig -Force
New-Item -ItemType File -Path src/preview_cache.zig -Force
New-Item -ItemType File -Path src/gif_writer.zig -Force
New-Item -ItemType File -Path src/export_pipeline.zig -Force
New-Item -ItemType File -Path src/fit.zig -Force
```

Then:

```powershell
native check
native test
native dev
```

---

# 2. Tooling assumptions

You need:

```txt
Node/npm      for Native SDK CLI install
Zig           for zig fetch and building deps
Git           for Zig package fetching from GitHub
curl          for downloading msf_gif.h, or PowerShell Invoke-WebRequest on Windows
```

Native SDK can manage the Zig toolchain for `native dev`, `native build`, and `native test`, but `zig fetch` still requires a `zig` command available on your PATH. If `zig fetch` fails because Zig is missing, install Zig first.

Quick checks:

```bash
node --version
npm --version
zig version
git --version
native version
```

---

# 3. Why this stack

## Native SDK

Use it for:

```txt
native window
native-rendered UI
buttons/sliders/lists/panels/status bar
open/save dialogs
file drops
packaging
simple Model / Msg / update loop
```

Native SDK gives us a predictable app structure:

```txt
Model  = all app state
Msg    = all possible user actions/events
update = only place state changes
View   = UI derived from model
```

That is perfect for a tiny utility app.

## Zignal

Use it for:

```txt
PNG/JPEG loading
resizing
crop/rotate if needed later
color/image processing if needed later
```

Why Zignal is the image library pick:

```txt
zero-dependency
mostly Zig
actively maintained
has spatial transforms like resize/crop/rotate
has PNG/JPEG codecs
has more useful image-processing features than a tiny stb wrapper
```

Important design choice:

```txt
Do not let Zignal types leak everywhere.
Wrap Zignal inside src/image_pipeline.zig.
```

That way, if Zignal changes APIs later, only one file needs to be updated.

## msf_gif.h

Use it for:

```txt
animated GIF encoding
RGBA frame input
simple C API
single-header dependency
```

Why not write GIF encoding ourselves:

```txt
GIF encoding needs palette selection, dithering, frame deltas, compression, timing, and looping.
That is not worth writing for v1.
```

## No GPU for v1

Do not use GPU for v1.

Reason:

```txt
GIF export needs CPU pixel buffers anyway.
A GPU pipeline would require:
  texture upload
  shader setup
  render target setup
  readback from GPU to CPU
  synchronization
  platform-specific graphics debugging

That is more code for almost no benefit in this app.
```

CPU image resize/composite/export is simpler and good enough.

---

# 4. Project layout

Use this layout:

```txt
gifbin/
  app.zon
  build.zig
  build.zig.zon

  src/
    app.native
    main.zig
    model.zig
    image_pipeline.zig
    preview_cache.zig
    gif_writer.zig
    export_pipeline.zig
    fit.zig
    tests.zig

  third_party/
    msf_gif/
      msf_gif.h
      msf_gif_impl.c

  assets/
    icon.png
```

Dependency ownership:

```txt
main.zig
  owns app wiring and update loop

model.zig
  owns pure app state and enums

image_pipeline.zig
  owns Zignal usage

gif_writer.zig
  owns msf_gif C interop

fit.zig
  owns contain/cover/stretch rectangle math

export_pipeline.zig
  owns full export process

preview_cache.zig
  owns selected-slide preview image lifecycle

app.native
  owns most of the native UI layout
```

---

# 5. build.zig edits

After running:

```bash
zig fetch --save git+https://github.com/arrufat/zignal
```

open `build.zig`.

Find the executable variable. It is often named something like `exe`.

Add this near where other dependencies/imports are configured:

```zig
const zignal = b.dependency("zignal", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zignal", zignal.module("zignal"));
```

Then add the C GIF encoder:

```zig
exe.addIncludePath(b.path("third_party/msf_gif"));
exe.addCSourceFile(.{
    .file = b.path("third_party/msf_gif/msf_gif_impl.c"),
    .flags = &.{ "-std=c99" },
});
exe.linkLibC();
```

The block should end up conceptually like this:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Existing Native SDK setup stays here.

    const zignal = b.dependency("zignal", .{
        .target = target,
        .optimize = optimize,
    });

    // Existing executable setup.
    // const exe = ...

    exe.root_module.addImport("zignal", zignal.module("zignal"));

    exe.addIncludePath(b.path("third_party/msf_gif"));
    exe.addCSourceFile(.{
        .file = b.path("third_party/msf_gif/msf_gif_impl.c"),
        .flags = &.{ "-std=c99" },
    });
    exe.linkLibC();

    // Existing install/test/package setup stays here.
}
```

Then run:

```bash
native check
native test
native dev
```

---

# 6. Product behavior

The app should feel like this:

```txt
Open app
Drop images in or click Add Images
Slides appear in order
Move slides up/down
Set speed
Pick Small / Balanced / Clean
Click Export GIF
Choose output path
Done
```

MVP import formats:

```txt
PNG
JPG/JPEG
```

Later formats:

```txt
BMP
TGA
QOI
GIF input
TIFF partial
```

For broader format support later, consider adding `zigimg` as an optional import backend. Do not start there unless PNG/JPEG is not enough.

---

# 7. UI plan

Use one simple two-pane native app.

```txt
┌──────────────────────────────────────────────────────────────────┐
│ gifbin                                    Add Images  Export GIF│
├──────────────────────────────┬───────────────────────────────────┤
│ Slides                       │ Preview                           │
│                              │                                   │
│ 01  launch.png      1.00s    │                                   │
│ 02  screen.jpg      1.00s    │          selected slide            │
│ 03  outro.png       1.00s    │                                   │
│                              │                                   │
│ + Add  ↑  ↓  Remove          │                                   │
├──────────────────────────────┴───────────────────────────────────┤
│ Speed 1.00s/slide | Small Balanced Clean | Width 640 | Loop ∞     │
└──────────────────────────────────────────────────────────────────┘
```

Do not implement drag reorder first.

Use buttons first:

```txt
Move up
Move down
Move to top
Move to bottom
Remove
Duplicate
```

Why:

```txt
button reorder is easier
testable
keyboard-friendly
less fragile
no weird pointer edge cases
```

Drag reorder can be phase 2.

---

# 8. Native SDK image strategy

Do not load/register every full-size image into Native SDK UI memory.

Use this:

```txt
Full source images:
  store only file paths

Preview image:
  decode only currently selected slide
  resize to preview size
  register one runtime image

Thumbnails:
  skip in v1, or add a tiny visible-row/LRU cache later

Export:
  decode each source image one at a time
  resize/composite
  encode frame
  free pixels
```

This keeps the app lightweight and avoids turning the UI into an image cache.

MVP slide rows can just be text:

```txt
01  filename.png  1.00s
02  filename.jpg  1.00s
03  filename.png  1.00s
```

Add thumbnails later only after export works.

---

# 9. First UI shape in Native syntax

Start with this shape in `src/app.native`.

Treat this as the UI structure. If exact attribute names differ in your installed Native SDK version, use:

```bash
native skills get native-ui --full > NATIVE_SDK_NATIVE_UI_SKILL.md
```

and adjust names to match.

```xml
<column gap="0" grow="1">
  <row padding="12" gap="8" cross="center" background="surface" window-drag="true">
    <text weight="bold" grow="1">gifbin</text>
    <button variant="secondary" on-press="add_images">Add Images</button>
    <button variant="primary" disabled="{export_disabled}" on-press="export_gif">Export GIF</button>
  </row>

  <separator />

  <split value="{sidebar_fraction}" on-resize="sidebar_resized" grow="1">
    <panel padding="12" min-width="280">
      <column gap="10" grow="1">
        <row gap="8" cross="center">
          <text weight="medium" grow="1">Slides</text>
          <button variant="outline" on-press="move_selected_up">↑</button>
          <button variant="outline" on-press="move_selected_down">↓</button>
        </row>

        <list grow="1">
          <for each="slides" as="slide" key="id">
            <list-item selected="{slide.id == selected_slide_id}" on-press="select_slide:{slide.id}">
              {slide.row_title}
            </list-item>
          </for>
        </list>

        <row gap="8">
          <button grow="1" variant="secondary" on-press="add_images">Add</button>
          <button grow="1" variant="ghost" on-press="remove_selected">Remove</button>
        </row>
      </column>
    </panel>

    <panel padding="16" min-width="420">
      <column gap="12" grow="1">
        <text weight="medium">Preview</text>
        <panel grow="1" padding="12">
          <text foreground="text_muted">{preview_status}</text>
        </panel>
      </column>
    </panel>
  </split>

  <separator />

  <row padding="12" gap="16" cross="center" background="surface">
    <text>Speed</text>
    <slider value="{speed_fraction}" on-change="speed_changed" label="Slide speed" />

    <toggle-group>
      <toggle-button selected="{quality_small_selected}" on-toggle="quality_small">Small</toggle-button>
      <toggle-button selected="{quality_balanced_selected}" on-toggle="quality_balanced">Balanced</toggle-button>
      <toggle-button selected="{quality_clean_selected}" on-toggle="quality_clean">Clean</toggle-button>
    </toggle-group>

    <checkbox checked="{loop_forever}" on-toggle="toggle_loop" text="Loop" />
  </row>

  <status-bar>{status_text}</status-bar>
</column>
```

For real image preview, we may need a Zig-root view or a custom image node because general image rendering is usually easier from Zig builder code. Keep `app.native` for the shell and add the preview image from Zig if needed.

---

# 10. Data model

Put this in `src/model.zig` as the starting shape.

```zig
const std = @import("std");

pub const QualityPreset = enum {
    small,
    balanced,
    clean,

    pub fn maxWidth(self: QualityPreset) u32 {
        return switch (self) {
            .small => 480,
            .balanced => 640,
            .clean => 960,
        };
    }

    pub fn gifQuality(self: QualityPreset) i32 {
        return switch (self) {
            .small => 6,
            .balanced => 12,
            .clean => 18,
        };
    }
};

pub const FitMode = enum {
    contain,
    cover,
    stretch,
};

pub const Slide = struct {
    id: u64,
    path: []const u8,
    filename: []const u8,

    source_width: u32,
    source_height: u32,

    duration_cs: u16 = 100,
    enabled: bool = true,
};

pub const ExportState = union(enum) {
    idle,
    running: struct {
        current: u32,
        total: u32,
        fraction: f32,
    },
    done: []const u8,
    failed: []const u8,
};

pub const Model = struct {
    slides: std.ArrayListUnmanaged(Slide) = .{},
    selected_slide_id: ?u64 = null,
    next_slide_id: u64 = 1,

    default_duration_cs: u16 = 100,
    quality: QualityPreset = .balanced,
    fit_mode: FitMode = .contain,
    loop_forever: bool = true,

    sidebar_fraction: f32 = 0.32,
    export_state: ExportState = .idle,

    preview_image_id: u64 = 1,
    preview_slide_id: ?u64 = null,
};

pub fn secondsToCentiseconds(seconds: f32) u16 {
    const clamped = std.math.clamp(seconds, 0.06, 60.0);
    return @intFromFloat(@round(clamped * 100.0));
}

pub fn centisecondsToSeconds(cs: u16) f32 {
    return @as(f32, @floatFromInt(cs)) / 100.0;
}
```

Timing rule:

```txt
GIF delays are naturally handled in centiseconds.
1.00 second = 100 cs
0.50 second = 50 cs
0.10 second = 10 cs
```

Do not allow absurdly tiny delays. Clamp minimum to around `0.06s`.

---

# 11. Messages

In `src/main.zig`, the message union should look like this:

```zig
pub const Msg = union(enum) {
    add_images,
    files_chosen: []const []const u8,
    files_dropped: []const []const u8,

    select_slide: u64,
    remove_slide: u64,
    duplicate_slide: u64,

    move_selected_up,
    move_selected_down,
    move_selected_top,
    move_selected_bottom,

    move_slide_up: u64,
    move_slide_down: u64,
    move_slide_top: u64,
    move_slide_bottom: u64,

    speed_changed: f32,
    apply_duration_to_all,

    quality_small,
    quality_balanced,
    quality_clean,

    toggle_loop,
    fit_contain,
    fit_cover,
    fit_stretch,

    sidebar_resized: f32,

    export_gif,
    export_progress: struct {
        current: u32,
        total: u32,
    },
    export_done: []const u8,
    export_failed: []const u8,
};
```

Keep `update` boring and explicit.

```zig
pub fn update(model: *Model, msg: Msg) void {
    switch (msg) {
        .quality_small => model.quality = .small,
        .quality_balanced => model.quality = .balanced,
        .quality_clean => model.quality = .clean,
        .toggle_loop => model.loop_forever = !model.loop_forever,
        .sidebar_resized => |fraction| model.sidebar_fraction = std.math.clamp(fraction, 0.2, 0.5),
        else => {},
    }
}
```

Then fill in the import/reorder/export message arms.

---

# 12. Reordering functions

Keep these pure and easy to test.

```zig
fn indexOfSlide(slides: []const Slide, id: u64) ?usize {
    for (slides, 0..) |slide, i| {
        if (slide.id == id) return i;
    }
    return null;
}

fn moveSlideUp(slides: []Slide, id: u64) void {
    const i = indexOfSlide(slides, id) orelse return;
    if (i == 0) return;
    std.mem.swap(Slide, &slides[i], &slides[i - 1]);
}

fn moveSlideDown(slides: []Slide, id: u64) void {
    const i = indexOfSlide(slides, id) orelse return;
    if (i + 1 >= slides.len) return;
    std.mem.swap(Slide, &slides[i], &slides[i + 1]);
}
```

MVP ordering should be buttons, not drag/drop.

---

# 13. Image pipeline API

Make `src/image_pipeline.zig` the only file that imports Zignal.

Public shape:

```zig
const std = @import("std");
const zignal = @import("zignal");

pub const ImageInfo = struct {
    width: u32,
    height: u32,
};

pub const RgbaImage = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8, // RGBA8, len = width * height * 4

    pub fn deinit(self: *RgbaImage) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

pub fn readInfo(allocator: std.mem.Allocator, path: []const u8) !ImageInfo {
    _ = allocator;
    _ = path;
    // Implement using Zignal's current API.
    // If no cheap metadata-only path exists, load and immediately free.
    return error.NotImplemented;
}

pub fn loadRgba8(allocator: std.mem.Allocator, path: []const u8) !RgbaImage {
    _ = allocator;
    _ = path;
    // Implement with Zignal decode, then convert/copy to RGBA8.
    return error.NotImplemented;
}

pub fn resizeRgba8(
    allocator: std.mem.Allocator,
    src: RgbaImage,
    width: u32,
    height: u32,
) !RgbaImage {
    _ = allocator;
    _ = src;
    _ = width;
    _ = height;
    // Implement with Zignal resize.
    return error.NotImplemented;
}
```

Why this wrapper matters:

```txt
Zignal is active and useful, but APIs can evolve.
Our app should not be full of direct Zignal calls.
```

---

# 14. Fit rectangle math

Every GIF frame must be the same canvas size.

Put this in `src/fit.zig`.

```zig
const std = @import("std");
const model = @import("model.zig");

pub const Rect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub fn fitRect(
    source_width: u32,
    source_height: u32,
    canvas_width: u32,
    canvas_height: u32,
    fit_mode: model.FitMode,
) Rect {
    if (fit_mode == .stretch) {
        return .{
            .x = 0,
            .y = 0,
            .width = canvas_width,
            .height = canvas_height,
        };
    }

    const sx = @as(f32, @floatFromInt(canvas_width)) / @as(f32, @floatFromInt(source_width));
    const sy = @as(f32, @floatFromInt(canvas_height)) / @as(f32, @floatFromInt(source_height));

    const scale = switch (fit_mode) {
        .contain => @min(sx, sy),
        .cover => @max(sx, sy),
        .stretch => unreachable,
    };

    const draw_w: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(source_width)) * scale));
    const draw_h: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(source_height)) * scale));

    return .{
        .x = if (canvas_width > draw_w) (canvas_width - draw_w) / 2 else 0,
        .y = if (canvas_height > draw_h) (canvas_height - draw_h) / 2 else 0,
        .width = draw_w,
        .height = draw_h,
    };
}
```

Default fit mode:

```txt
contain
```

Meaning:

```txt
show the whole slide
letterbox/pillarbox if necessary
no surprise cropping
```

---

# 15. Export settings

Put this shape in `src/export_pipeline.zig`.

```zig
const std = @import("std");
const model = @import("model.zig");

pub const ExportSettings = struct {
    max_width: u32 = 640,
    loop_forever: bool = true,
    fit_mode: model.FitMode = .contain,
    quality: model.QualityPreset = .balanced,
    background_rgba: [4]u8 = .{ 255, 255, 255, 255 },
};
```

Smart defaults:

```txt
Quality:      Balanced
Max width:    640 px
Speed:        1.00 second / slide
Loop:         on
Fit:          contain
Background:   white
```

Quality presets:

```txt
Small:
  480 px max width
  smaller file
  faster export

Balanced:
  640 px max width
  default

Clean:
  960 px max width
  bigger file
  better detail
```

Do not expose encoder internals first. Users understand output width and quality words.

---

# 16. Canvas size calculation

Use the first enabled slide as the aspect-ratio source.

```zig
fn computeCanvasSize(first_w: u32, first_h: u32, max_width: u32) struct { width: u32, height: u32 } {
    const width = @min(first_w, max_width);
    const aspect = @as(f32, @floatFromInt(first_h)) / @as(f32, @floatFromInt(first_w));
    var height: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(width)) * aspect));

    if (height < 1) height = 1;

    // Even dimensions are nicer for many image/video-ish pipelines.
    if (height % 2 == 1) height += 1;

    return .{ .width = width, .height = height };
}
```

Example:

```txt
first slide: 1920x1080
quality: Balanced
max width: 640
output: 640x360
```

---

# 17. GIF writer wrapper

Only `src/gif_writer.zig` should import C.

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("msf_gif.h");
});

pub const GifWriter = struct {
    state: c.MsfGifState,
    width: u32,
    height: u32,
    started: bool = false,

    pub fn begin(width: u32, height: u32) !GifWriter {
        var writer: GifWriter = .{
            .state = undefined,
            .width = width,
            .height = height,
            .started = false,
        };

        const ok = c.msf_gif_begin(&writer.state, @intCast(width), @intCast(height));
        if (ok == 0) return error.GifBeginFailed;

        writer.started = true;
        return writer;
    }

    pub fn addFrame(self: *GifWriter, rgba: []const u8, delay_cs: u16, quality: i32) !void {
        if (!self.started) return error.GifNotStarted;
        if (rgba.len != self.width * self.height * 4) return error.InvalidFrameSize;

        const ok = c.msf_gif_frame(
            &self.state,
            rgba.ptr,
            @intCast(delay_cs),
            @intCast(quality),
            @intCast(self.width * 4),
        );

        if (ok == 0) return error.GifFrameFailed;
    }

    pub fn finishToFile(self: *GifWriter, allocator: std.mem.Allocator, output_path: []const u8) !void {
        if (!self.started) return error.GifNotStarted;

        const result = c.msf_gif_end(&self.state);
        defer c.msf_gif_free(result);

        if (result.data == null or result.dataSize == 0) return error.GifEndFailed;

        var file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        const bytes = @as([*]const u8, @ptrCast(result.data))[0..@intCast(result.dataSize)];
        try file.writeAll(bytes);

        _ = allocator;
        self.started = false;
    }
};
```

Note: adjust exact C function signatures if `msf_gif.h` changes. The wrapper keeps that pain isolated.

---

# 18. Export pipeline

Export flow:

```txt
User clicks Export GIF
Save dialog asks output path
Compute output canvas from first enabled slide
Start GIF writer
For each enabled slide in current order:
  load source image
  fit to canvas
  create full RGBA frame
  add frame to GIF
  free source image
Finish GIF
Write file
Show success
```

Skeleton:

```zig
const std = @import("std");
const model = @import("model.zig");
const image = @import("image_pipeline.zig");
const fit = @import("fit.zig");
const gif = @import("gif_writer.zig");

pub const ExportSettings = struct {
    max_width: u32 = 640,
    loop_forever: bool = true,
    fit_mode: model.FitMode = .contain,
    quality: model.QualityPreset = .balanced,
    background_rgba: [4]u8 = .{ 255, 255, 255, 255 },
};

pub fn exportGif(
    allocator: std.mem.Allocator,
    slides: []const model.Slide,
    settings: ExportSettings,
    output_path: []const u8,
) !void {
    const first = findFirstEnabled(slides) orelse return error.NoEnabledSlides;

    const canvas = computeCanvasSize(first.source_width, first.source_height, settings.max_width);

    var writer = try gif.GifWriter.begin(canvas.width, canvas.height);

    for (slides) |slide| {
        if (!slide.enabled) continue;

        var src = try image.loadRgba8(allocator, slide.path);
        defer src.deinit();

        var frame = try allocator.alloc(u8, canvas.width * canvas.height * 4);
        defer allocator.free(frame);

        fillRgba(frame, settings.background_rgba);

        try compositeSlide(
            allocator,
            src,
            frame,
            canvas.width,
            canvas.height,
            settings.fit_mode,
        );

        try writer.addFrame(frame, slide.duration_cs, settings.quality.gifQuality());
    }

    try writer.finishToFile(allocator, output_path);
}

fn findFirstEnabled(slides: []const model.Slide) ?model.Slide {
    for (slides) |slide| {
        if (slide.enabled) return slide;
    }
    return null;
}

fn fillRgba(pixels: []u8, color: [4]u8) void {
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i + 0] = color[0];
        pixels[i + 1] = color[1];
        pixels[i + 2] = color[2];
        pixels[i + 3] = color[3];
    }
}
```

Composite logic:

```txt
contain:
  resize source to fitted rectangle
  copy into centered canvas

cover:
  resize source large enough to fill canvas
  crop center into canvas

stretch:
  resize directly to canvas size
```

Implement `contain` first. Add `cover` and `stretch` after the export works.

---

# 19. Import flow

When user clicks Add Images:

```txt
show open dialog
allow multiple files
filter PNG/JPEG
for each path:
  read image info
  create Slide
  append to model.slides
select first imported slide if nothing selected
update status text
```

Slide creation:

```zig
fn appendSlide(model: *Model, allocator: std.mem.Allocator, path: []const u8, info: image.ImageInfo) !void {
    const owned_path = try allocator.dupe(u8, path);
    const filename = std.fs.path.basename(owned_path);

    try model.slides.append(allocator, .{
        .id = model.next_slide_id,
        .path = owned_path,
        .filename = filename,
        .source_width = info.width,
        .source_height = info.height,
        .duration_cs = model.default_duration_cs,
        .enabled = true,
    });

    if (model.selected_slide_id == null) {
        model.selected_slide_id = model.next_slide_id;
    }

    model.next_slide_id += 1;
}
```

Important ownership note:

```txt
If filename points into owned_path, do not separately free filename.
Free owned_path when removing slides or destroying model.
```

---

# 20. Preview flow

MVP preview should only render the selected slide.

```txt
select slide
load file
resize to preview max size, e.g. 512 px
register runtime image id
free CPU decode buffer
show image widget
```

Do not cache every image.

Preview cache shape:

```zig
pub const PreviewCache = struct {
    image_id: u64 = 1,
    slide_id: ?u64 = null,
    width: u32 = 0,
    height: u32 = 0,
};
```

If Native SDK image registration code is annoying from markup, use a Zig root view for the preview pane and keep the rest of the UI in native markup.

---

# 21. Speed UI

Start global.

Presets:

```txt
0.10s
0.25s
0.50s
1.00s
2.00s
3.00s
```

Default:

```txt
1.00s per slide
```

Implementation:

```txt
speed slider changes model.default_duration_cs
new imported slides use default_duration_cs
Apply to all sets every slide.duration_cs = default_duration_cs
```

Later:

```txt
selected slide duration override
per-slide duration input
```

Do not start with per-slide duration editor unless needed.

---

# 22. Quality UI

Use three buttons:

```txt
Small
Balanced
Clean
```

Map them to:

```txt
Small     = 480 px max width
Balanced  = 640 px max width
Clean     = 960 px max width
```

Why width matters:

```txt
GIF size explodes with pixels × frames.
The easiest quality/file-size control is output dimensions.
```

Later advanced settings:

```txt
custom max width
fit mode
background color
loop on/off
```

---

# 23. Save/export UI

When user clicks Export GIF:

```txt
if no slides:
  show message: Add images first

else:
  show save dialog defaulting to animation.gif
  if user cancels: do nothing
  export
  show success/failure
```

Disable Export button while exporting.

Status text examples:

```txt
No images yet. Drop PNG/JPEG files here.
3 slides loaded.
Exporting 2/8...
Exported animation.gif.
Export failed: unsupported image.
```

---

# 24. Testing plan

Unit tests:

```txt
secondsToCentiseconds
centisecondsToSeconds
quality preset max width
quality preset GIF quality
fit contain rectangle
fit cover rectangle
move first up does nothing
move last down does nothing
move middle up works
move middle down works
remove selected slide chooses sane next selection
canvas size calculation
```

Manual tests:

```txt
1 PNG
1 JPEG
2 same-size images
portrait + landscape
square + landscape
huge 4000px image
bad file extension
corrupt file
remove selected slide
reorder then export
Small/Balanced/Clean exports
cancel save dialog
empty export blocked
```

Add these before adding fancy UI.

---

# 25. Milestone plan

## Milestone 1: Native shell

Commands:

```bash
npm install -g @native-sdk/cli
native init gifbin --full
cd gifbin
native dev
native check
native test
```

Build:

```txt
header
left panel
right preview placeholder
bottom speed/quality/status bar
fake slides
```

Done when:

```txt
UI opens
fake list renders
buttons dispatch messages
check/test pass
```

## Milestone 2: Real import

Add:

```txt
Add Images button
open dialog
PNG/JPEG filter
append real slides
store path/filename/width/height
```

Done when:

```txt
selected files show as rows
bad files do not crash app
```

## Milestone 3: Reorder

Add:

```txt
move up
move down
remove
duplicate
```

Done when:

```txt
export order will match row order
unit tests pass
```

## Milestone 4: Preview

Add:

```txt
selected slide preview
single runtime image id
reload preview when selection changes
```

Done when:

```txt
clicking different rows updates preview
large images do not stall forever
```

## Milestone 5: GIF export

Add:

```txt
save dialog
canvas size calculation
contain fit
Zignal resize
msf_gif encoding
success/failure message
```

Done when:

```txt
real GIF opens in browser/Preview/Finder
slide order is correct
speed is correct enough
```

## Milestone 6: Quality

Add:

```txt
Small / Balanced / Clean
max width mapping
export status
```

Done when:

```txt
Small exports smaller than Balanced
Clean exports bigger/cleaner than Balanced
```

## Milestone 7: Packaging

Commands:

```bash
native build
native package --target macos
```

For Linux/Windows, use the supported target for the installed Native SDK/package setup.

---

# 26. Things not to build in v1

Do not build these yet:

```txt
GPU renderer
Mach engine
SDL window
GLFW window
Dear ImGui/zgui UI
timeline editor
drag reorder
transitions
filters
text captions
video input
animated GIF input
audio
FFmpeg dependency
gifsicle dependency
cloud upload
project files/workspaces
```

Reason:

```txt
Those turn a simple gifbin into a media editor.
The MVP is image slides -> ordered animated GIF.
```

---

# 27. Future upgrades after MVP

Good later upgrades:

```txt
thumbnail list with small LRU cache
drag reorder
per-slide duration
custom output width
fit mode picker
background color picker
transparent background attempt
animated preview playback
batch export
recent files
save/load project file
zigimg fallback for more import formats
```

Only add these after the basic app exports correct GIFs.

---

# 28. Source links checked

Native SDK quick start:

```txt
https://native-sdk.dev/quick-start
```

Native SDK app model:

```txt
https://native-sdk.dev/app-model
```

Native SDK packaging:

```txt
https://native-sdk.dev/packaging
```

Zignal:

```txt
https://github.com/arrufat/zignal
```

msf_gif:

```txt
https://github.com/notnullnotvoid/msf_gif
```

zigimg, optional later fallback:

```txt
https://github.com/zigimg/zigimg
```

---

# 29. Final implementation call

Use this:

```txt
Native SDK + Zignal + msf_gif.h
```

Start with this exact feature set:

```txt
Add images
Drop images
Text slide list
Move up/down
Remove
Global speed
Small/Balanced/Clean quality
Export GIF
```

Do not overbuild it.

The fastest route is:

```txt
1. Scaffold Native SDK app.
2. Add Zignal.
3. Add msf_gif.h.
4. Build the UI shell.
5. Import PNG/JPEG.
6. Reorder rows.
7. Export GIF.
8. Add preview.
9. Add quality polish.
```
