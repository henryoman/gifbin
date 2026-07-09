//! Gifbin native app wiring. The view, app state, and native operations
//! live in Zig so the preview can use runtime-registered canvas images.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const gif_model = @import("model.zig");
const export_pipeline = @import("export_pipeline.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "main-canvas";
const window_width: f32 = 1440;
const window_height: f32 = 900;
const window_min_width: f32 = 600;
const window_min_height: f32 = 600;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view, native_sdk.security.permission_dialog };
const logo_image_id: canvas.ImageId = 2;
const preview_image_id: canvas.ImageId = 1;
const preview_max_side: u16 = 512;
const logo_image_bytes = @embedFile("gifbin-logo.png");

const ImageInfo = struct {
    width: u16,
    height: u16,
};

extern fn gifbin_read_image_info(path: [*:0]const u8, out_width: *c_int, out_height: *c_int) c_int;
extern fn gifbin_decode_image_rgba(path: [*:0]const u8, width: c_int, height: c_int, out_rgba: [*]u8) c_int;
const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "gifbin canvas", .accessibility_label = "gifbin", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "gifbin",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .restore_state = false,
    .titlebar = .hidden_inset,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

// ------------------------------------------------------------------ model

pub const Msg = gif_model.Msg;
pub const Model = gif_model.Model;
pub const Quality = gif_model.Quality;
pub const PendingAction = gif_model.PendingAction;
pub const addImagePath = gif_model.addImagePath;
pub const consumePendingAction = gif_model.consumePendingAction;

pub fn update(model: *Model, msg: Msg) void {
    gif_model.update(model, msg);
}

// ------------------------------------------------------------------- view

pub const AppUi = canvas.Ui(Msg);

pub fn appView(ui: *AppUi, model: *const Model) AppUi.Node {
    return ui.column(.{ .gap = 0, .grow = 1 }, .{
        appHeader(ui, model),
        ui.separator(.{}),
        ui.el(.split, .{ .value = model.sidebar_split, .on_resize = AppUi.valueMsg(.sidebar_resized), .grow = 1, .gap = 6 }, .{
            sidebarView(ui, model),
            previewView(ui, model),
        }),
        ui.separator(.{}),
        controlsView(ui, model),
        ui.statusBar(.{}, model.statusLine(ui.arena)),
    });
}

fn appHeader(ui: *AppUi, model: *const Model) AppUi.Node {
    return ui.row(.{ .padding = 12, .gap = 8, .cross = .center, .style_tokens = .{ .background = .surface }, .window_drag = true }, .{
        ui.el(.stack, .{ .width = model.chrome_leading }, .{}),
        appLogo(ui, model),
        ui.spacer(1),
        ui.button(.{ .icon = "plus", .variant = .secondary, .on_press = .add_images }, "Add Images"),
        ui.button(.{ .icon = "download", .variant = .primary, .disabled = model.exportDisabled(), .on_press = .export_gif }, "Export GIF"),
        ui.el(.stack, .{ .width = model.chrome_trailing }, .{}),
    });
}

fn appLogo(ui: *AppUi, model: *const Model) AppUi.Node {
    if (model.logo_image_id != 0) {
        var logo = ui.image(.{
            .image = model.logo_image_id,
            .width = 124,
            .height = 49,
            .semantics = .{ .role = .image, .label = "gifbin" },
        });
        logo.widget.image_fit = .contain;
        return logo;
    }
    return ui.text(.{ .size = .heading }, "gifbin");
}

fn onChrome(chrome: native_sdk.WindowChrome) ?Msg {
    return .{ .chrome_changed = .{
        .leading = chrome.insets.left,
        .trailing = chrome.insets.right,
    } };
}

fn sidebarView(ui: *AppUi, model: *const Model) AppUi.Node {
    return ui.column(.{ .padding = 12, .gap = 10, .min_width = 280 }, .{
        ui.row(.{ .gap = 6, .cross = .center }, .{
            ui.text(.{ .grow = 1 }, "Slides"),
            ui.button(.{ .icon = "arrow-up", .size = .icon, .variant = .outline, .disabled = !model.canMoveSelectedUp(), .on_press = .move_selected_up, .semantics = .{ .label = "Move up" } }, ""),
            ui.button(.{ .icon = "arrow-down", .size = .icon, .variant = .outline, .disabled = !model.canMoveSelectedDown(), .on_press = .move_selected_down, .semantics = .{ .label = "Move down" } }, ""),
        }),
        slideList(ui, model),
        ui.row(.{ .gap = 8 }, .{
            ui.button(.{ .icon = "plus", .grow = 1, .variant = .secondary, .on_press = .add_images }, "Add"),
            ui.button(.{ .icon = "copy", .grow = 1, .variant = .outline, .disabled = !model.hasSlides(), .on_press = .duplicate_selected }, "Duplicate"),
            ui.button(.{ .icon = "trash", .grow = 1, .variant = .ghost, .disabled = !model.hasSlides(), .on_press = .remove_selected }, "Remove"),
        }),
        ui.row(.{ .gap = 8 }, .{
            ui.button(.{ .icon = "skip-back", .grow = 1, .variant = .ghost, .disabled = !model.canMoveSelectedUp(), .on_press = .move_selected_top }, "Top"),
            ui.button(.{ .icon = "skip-forward", .grow = 1, .variant = .ghost, .disabled = !model.canMoveSelectedDown(), .on_press = .move_selected_bottom }, "Bottom"),
        }),
    });
}

fn slideList(ui: *AppUi, model: *const Model) AppUi.Node {
    if (model.slide_count == 0) {
        return ui.list(.{ .grow = 1 }, ui.listItem(.{ .disabled = true }, "No slides yet"));
    }

    const rows = ui.arena.alloc(AppUi.Node, model.slide_count) catch {
        ui.failed = true;
        return ui.list(.{ .grow = 1 }, .{});
    };
    const visible = model.visibleSlides(ui.arena);
    for (visible, 0..) |slide, index| {
        rows[index] = ui.el(.list_item, .{
            .key = .{ .int = slide.id },
            .selected = slide.selected,
            .on_press = .{ .select_slide = slide.id },
            .padding = 8,
            .semantics = .{ .label = slide.accessibility_label },
        }, .{
            ui.row(.{ .gap = 8, .cross = .center }, .{
                ui.el(.badge, .{ .text = slide.index_label }, .{}),
                ui.column(.{ .grow = 1, .gap = 2 }, .{
                    ui.text(.{ .overflow = .ellipsis }, slide.filename),
                    ui.text(.{ .style_tokens = .{ .foreground = .text_muted }, .overflow = .ellipsis }, slide.meta),
                }),
                ui.text(.{}, slide.duration_label),
            }),
        });
    }
    return ui.list(.{ .grow = 1 }, rows);
}

fn previewView(ui: *AppUi, model: *const Model) AppUi.Node {
    return ui.column(.{ .padding = 16, .gap = 12, .min_width = 420 }, .{
        ui.row(.{ .gap = 8, .cross = .center }, .{
            ui.text(.{ .grow = 1 }, "Preview"),
            ui.el(.badge, .{ .text = model.qualityLabel() }, .{}),
        }),
        ui.panel(.{ .grow = 1, .padding = 24, .main = .center, .cross = .center, .style_tokens = .{ .background = .surface_subtle, .radius = .md } }, previewContent(ui, model)),
    });
}

fn previewContent(ui: *AppUi, model: *const Model) AppUi.Node {
    if (model.preview_image_id != 0) {
        var image = ui.image(.{
            .image = model.preview_image_id,
            .grow = 1,
            .min_width = 320,
            .height = 360,
            .semantics = .{ .role = .image, .label = model.selectedFilename() },
        });
        image.widget.image_fit = .contain;
        return ui.column(.{ .gap = 12, .main = .center, .cross = .center }, .{
            image,
            ui.text(.{ .text_alignment = .center, .overflow = .ellipsis }, model.selectedFilename()),
            ui.text(.{ .style_tokens = .{ .foreground = .text_muted }, .text_alignment = .center }, model.selectedMeta(ui.arena)),
            ui.text(.{ .text_alignment = .center }, model.outputSummary(ui.arena)),
        });
    }
    return ui.column(.{ .gap = 12, .main = .center, .cross = .center }, .{
        ui.icon(.{ .width = 42, .height = 42, .style_tokens = .{ .foreground = .text_muted } }, "file-text"),
        ui.text(.{ .size = .heading, .text_alignment = .center }, model.selectedFilename()),
        ui.text(.{ .style_tokens = .{ .foreground = .text_muted }, .text_alignment = .center }, model.selectedMeta(ui.arena)),
        ui.text(.{ .text_alignment = .center }, model.outputSummary(ui.arena)),
    });
}

fn controlsView(ui: *AppUi, model: *const Model) AppUi.Node {
    return ui.row(.{ .padding = 12, .gap = 14, .cross = .center, .style_tokens = .{ .background = .surface } }, .{
        ui.text(.{}, ui.fmt("Speed {s}", .{model.speedLabel(ui.arena)})),
        ui.button(.{ .size = .sm, .variant = .outline, .on_press = .speed_faster }, "Faster"),
        ui.button(.{ .size = .sm, .variant = .outline, .on_press = .speed_slower }, "Slower"),
        ui.button(.{ .size = .sm, .variant = .ghost, .on_press = .speed_reset }, "Reset"),
        ui.separator(.{}),
        ui.button(.{ .size = .sm, .selected = model.qualitySmallSelected(), .on_press = .quality_small }, "Small"),
        ui.button(.{ .size = .sm, .selected = model.qualityBalancedSelected(), .on_press = .quality_balanced }, "Balanced"),
        ui.button(.{ .size = .sm, .selected = model.qualityCleanSelected(), .on_press = .quality_clean }, "Clean"),
        ui.separator(.{}),
        ui.text(.{}, ui.fmt("Width {d}px", .{model.output_width})),
        ui.button(.{ .size = .sm, .variant = .outline, .on_press = .width_smaller }, "Narrower"),
        ui.button(.{ .size = .sm, .variant = .outline, .on_press = .width_larger }, "Wider"),
    });
}

// -------------------------------------------------------------------- app

const GifbinApp = native_sdk.UiApp(Model, Msg);
const image_filters = [_]native_sdk.platform.FileFilter{.{
    .name = "Images",
    .extensions = &.{ "png", "jpg", "jpeg" },
}};

const ShellApp = struct {
    ui: *GifbinApp,

    fn app(self: *ShellApp) native_sdk.App {
        const inner = self.ui.app();
        return .{
            .context = self.ui,
            .name = inner.name,
            .source = inner.source,
            .source_fn = inner.source_fn,
            .scene_fn = inner.scene_fn,
            .event_fn = eventFn,
            .stop_fn = inner.stop_fn,
            .replay_fn = inner.replay_fn,
        };
    }

    fn eventFn(context: *anyopaque, runtime: *native_sdk.Runtime, event_value: native_sdk.Event) anyerror!void {
        const ui: *GifbinApp = @ptrCast(@alignCast(context));
        const logo_changed = ensureLogoImage(ui, runtime);
        switch (event_value) {
            .files_dropped => |drop| {
                for (drop.paths) |path| {
                    _ = addImageFile(&ui.model, path);
                }
                _ = try syncPreview(ui, runtime);
                if (ui.installed) try ui.rebuild(runtime, ui.canvas_window_id);
            },
            else => {
                try ui.app().event(runtime, event_value);
                try handlePending(ui, runtime);
                if (logo_changed or try syncPreview(ui, runtime)) {
                    if (ui.installed) try ui.rebuild(runtime, ui.canvas_window_id);
                }
            },
        }
    }

    fn ensureLogoImage(ui: *GifbinApp, runtime: *native_sdk.Runtime) bool {
        if (ui.model.logo_image_id == logo_image_id) return false;
        _ = runtime.registerCanvasImageBytes(logo_image_id, logo_image_bytes) catch return false;
        ui.model.logo_image_id = logo_image_id;
        return true;
    }

    fn handlePending(ui: *GifbinApp, runtime: *native_sdk.Runtime) !void {
        switch (gif_model.consumePendingAction(&ui.model)) {
            .none => {},
            .open_images => try openImages(ui, runtime),
            .export_gif => try exportGif(ui, runtime),
        }
    }

    fn openImages(ui: *GifbinApp, runtime: *native_sdk.Runtime) !void {
        var dialog_buffer: [native_sdk.platform.max_dialog_paths_bytes]u8 = undefined;
        const result = runtime.showOpenDialog(.{
            .title = "Add Images",
            .filters = &image_filters,
            .allow_multiple = true,
        }, &dialog_buffer) catch |err| {
            gif_model.setError(&ui.model, @errorName(err));
            try ui.rebuild(runtime, ui.canvas_window_id);
            return;
        };
        if (result.count > 0) {
            _ = addImageFilesNewlineSeparated(&ui.model, result.paths);
        }
        _ = try syncPreview(ui, runtime);
        try ui.rebuild(runtime, ui.canvas_window_id);
    }

    fn exportGif(ui: *GifbinApp, runtime: *native_sdk.Runtime) !void {
        var dialog_buffer: [native_sdk.platform.max_dialog_path_bytes]u8 = undefined;
        const output_path = (runtime.showSaveDialog(.{
            .title = "Export GIF",
            .default_name = "animation.gif",
        }, &dialog_buffer) catch |err| {
            gif_model.setError(&ui.model, @errorName(err));
            try ui.rebuild(runtime, ui.canvas_window_id);
            return;
        }) orelse {
            try ui.rebuild(runtime, ui.canvas_window_id);
            return;
        };

        export_pipeline.exportGif(std.heap.page_allocator, ui.model.slides[0..ui.model.slide_count], output_path, .{
            .width = ui.model.output_width,
            .quality = ui.model.quality,
            .fit_mode = ui.model.fit_mode,
        }) catch |err| {
            gif_model.setError(&ui.model, @errorName(err));
            try ui.rebuild(runtime, ui.canvas_window_id);
            return;
        };
        gif_model.markExported(&ui.model, output_path);
        try ui.rebuild(runtime, ui.canvas_window_id);
    }

    fn syncPreview(ui: *GifbinApp, runtime: *native_sdk.Runtime) !bool {
        const selected = ui.model.selectedSlide() orelse {
            if (ui.model.preview_image_id != 0) _ = runtime.unregisterCanvasImage(ui.model.preview_image_id);
            const changed = ui.model.preview_image_id != 0 or ui.model.preview_slide_id != 0;
            ui.model.preview_image_id = 0;
            ui.model.preview_slide_id = 0;
            return changed;
        };
        if (ui.model.preview_image_id == preview_image_id and ui.model.preview_slide_id == selected.id) return false;

        const info = imageInfoForSlide(selected) orelse {
            const changed = ui.model.preview_image_id != 0 or ui.model.preview_slide_id != 0;
            ui.model.preview_image_id = 0;
            ui.model.preview_slide_id = 0;
            return changed;
        };
        const preview_size = containedPreviewSize(info.width, info.height);
        const frame_len = @as(usize, preview_size.width) * @as(usize, preview_size.height) * 4;
        const frame = std.heap.page_allocator.alloc(u8, frame_len) catch |err| {
            gif_model.setError(&ui.model, @errorName(err));
            return false;
        };
        defer std.heap.page_allocator.free(frame);

        const path_z = std.heap.page_allocator.dupeZ(u8, selected.path()) catch |err| {
            gif_model.setError(&ui.model, @errorName(err));
            return false;
        };
        defer std.heap.page_allocator.free(path_z);

        if (gifbin_decode_image_rgba(path_z.ptr, preview_size.width, preview_size.height, frame.ptr) == 0) {
            gif_model.setError(&ui.model, "Preview image decode failed.");
            const changed = ui.model.preview_image_id != 0 or ui.model.preview_slide_id != 0;
            ui.model.preview_image_id = 0;
            ui.model.preview_slide_id = 0;
            return changed;
        }
        runtime.registerCanvasImage(preview_image_id, preview_size.width, preview_size.height, frame) catch |err| {
            gif_model.setError(&ui.model, @errorName(err));
            const changed = ui.model.preview_image_id != 0 or ui.model.preview_slide_id != 0;
            ui.model.preview_image_id = 0;
            ui.model.preview_slide_id = 0;
            return changed;
        };
        ui.model.preview_image_id = preview_image_id;
        ui.model.preview_slide_id = selected.id;
        gif_model.clearError(&ui.model);
        return true;
    }
};

fn addImageFile(model: *Model, path: []const u8) bool {
    const info = readImageInfo(path) catch |err| {
        gif_model.setError(model, @errorName(err));
        return false;
    };
    return gif_model.addImagePathWithInfo(model, path, info.width, info.height);
}

fn addImageFilesNewlineSeparated(model: *Model, paths: []const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= paths.len) {
        const end = std.mem.indexOfScalarPos(u8, paths, start, '\n') orelse paths.len;
        const path = std.mem.trim(u8, paths[start..end], " \t\r\n");
        if (path.len > 0 and addImageFile(model, path)) count += 1;
        if (end == paths.len) break;
        start = end + 1;
    }
    return count;
}

fn readImageInfo(path: []const u8) !ImageInfo {
    const path_z = try std.heap.page_allocator.dupeZ(u8, path);
    defer std.heap.page_allocator.free(path_z);

    var width: c_int = 0;
    var height: c_int = 0;
    if (gifbin_read_image_info(path_z.ptr, &width, &height) == 0 or width <= 0 or height <= 0) return error.ImageInfoFailed;
    return .{
        .width = @intCast(@min(width, std.math.maxInt(u16))),
        .height = @intCast(@min(height, std.math.maxInt(u16))),
    };
}

fn imageInfoForSlide(slide: *const gif_model.Slide) ?ImageInfo {
    if (slide.source_width == 0 or slide.source_height == 0) return null;
    return .{ .width = slide.source_width, .height = slide.source_height };
}

fn containedPreviewSize(width: u16, height: u16) ImageInfo {
    const max_side = @max(width, height);
    if (max_side <= preview_max_side) return .{ .width = width, .height = height };

    const next_width = @max(@as(u32, 1), (@as(u32, width) * preview_max_side + max_side / 2) / max_side);
    const next_height = @max(@as(u32, 1), (@as(u32, height) * preview_max_side + max_side / 2) / max_side);
    return .{ .width = @intCast(next_width), .height = @intCast(next_height) };
}

pub fn initialModel() Model {
    return gif_model.initialModel();
}

pub fn main(init: std.process.Init) !void {
    // The app struct (and any real Model) is multi-MB: `create`
    // heap-allocates and constructs everything in place, so neither
    // ever rides the stack. Mutate `app_state.model` through the
    // pointer before running if boot state is not the default.
    const app_state = try GifbinApp.create(std.heap.page_allocator, .{
        .name = "gifbin",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update = update,
        .view = appView,
        .theme = runner.manifestThemePack(),
        .on_chrome = onChrome,
    });
    defer app_state.destroy();
    app_state.model = initialModel();

    var shell = ShellApp{ .ui = app_state };

    try runner.runWithOptions(shell.app(), .{
        .app_name = "gifbin",
        .window_title = "gifbin",
        .bundle_id = "dev.native_sdk.gifbin",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
}
