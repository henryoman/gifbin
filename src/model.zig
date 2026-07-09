const std = @import("std");

pub const max_slides = 32;
pub const max_path_bytes = 4096;
pub const max_name_bytes = 256;

pub const Quality = enum {
    small,
    balanced,
    clean,
};

pub const FitMode = enum {
    contain,
};

pub const ChromeInsets = struct {
    leading: f32 = 0,
    trailing: f32 = 0,
};

pub const Slide = struct {
    id: u32 = 0,
    path_buffer: [max_path_bytes]u8 = [_]u8{0} ** max_path_bytes,
    path_len: usize = 0,
    name_buffer: [max_name_bytes]u8 = [_]u8{0} ** max_name_bytes,
    name_len: usize = 0,
    duration_cs: u16 = 100,
    source_width: u16 = 0,
    source_height: u16 = 0,

    pub fn path(self: *const Slide) []const u8 {
        return self.path_buffer[0..self.path_len];
    }

    pub fn name(self: *const Slide) []const u8 {
        return self.name_buffer[0..self.name_len];
    }
};

pub const VisibleSlide = struct {
    id: u32,
    selected: bool,
    filename: []const u8,
    index_label: []const u8,
    duration_label: []const u8,
    meta: []const u8,
    accessibility_label: []const u8,
};

pub const Msg = union(enum) {
    add_images,
    export_gif,
    select_slide: u32,
    remove_selected,
    duplicate_selected,
    move_selected_up,
    move_selected_down,
    move_selected_top,
    move_selected_bottom,
    speed_slower,
    speed_faster,
    speed_reset,
    quality_small,
    quality_balanced,
    quality_clean,
    width_smaller,
    width_larger,
    sidebar_resized: f32,
    chrome_changed: ChromeInsets,
};

pub const Model = struct {
    slides: [max_slides]Slide = [_]Slide{.{}} ** max_slides,
    slide_count: usize = 0,
    selected_slide_id: u32 = 0,
    next_id: u32 = 1,
    default_duration_cs: u16 = 100,
    output_width: u16 = 640,
    quality: Quality = .balanced,
    fit_mode: FitMode = .contain,
    sidebar_split: f32 = 0.38,
    export_count: u32 = 0,
    preview_image_id: u64 = 0,
    preview_slide_id: u32 = 0,
    chrome_leading: f32 = 0,
    chrome_trailing: f32 = 0,
    last_error_buffer: [256]u8 = [_]u8{0} ** 256,
    last_error_len: usize = 0,
    pending_action: PendingAction = .none,

    pub const view_unbound = .{
        "slides",
        "slide_count",
        "selected_slide_id",
        "next_id",
        "default_duration_cs",
        "quality",
        "fit_mode",
        "export_count",
        "preview_image_id",
        "preview_slide_id",
        "last_error_buffer",
        "last_error_len",
        "pending_action",
    };

    pub fn hasSlides(model: *const Model) bool {
        return model.slide_count > 0;
    }

    pub fn exportDisabled(model: *const Model) bool {
        return model.slide_count == 0;
    }

    pub fn canMoveSelectedUp(model: *const Model) bool {
        const index = model.selectedIndex() orelse return false;
        return index > 0;
    }

    pub fn canMoveSelectedDown(model: *const Model) bool {
        const index = model.selectedIndex() orelse return false;
        return index + 1 < model.slide_count;
    }

    pub fn speedLabel(model: *const Model, arena: std.mem.Allocator) []const u8 {
        return formatDuration(arena, model.default_duration_cs);
    }

    pub fn qualityLabel(model: *const Model) []const u8 {
        return switch (model.quality) {
            .small => "Small",
            .balanced => "Balanced",
            .clean => "Clean",
        };
    }

    pub fn qualitySmallSelected(model: *const Model) bool {
        return model.quality == .small;
    }

    pub fn qualityBalancedSelected(model: *const Model) bool {
        return model.quality == .balanced;
    }

    pub fn qualityCleanSelected(model: *const Model) bool {
        return model.quality == .clean;
    }

    pub fn selectedFilename(model: *const Model) []const u8 {
        const index = model.selectedIndex() orelse return "No slide selected";
        return model.slides[index].name();
    }

    pub fn selectedSlide(model: *const Model) ?*const Slide {
        const index = model.selectedIndex() orelse return null;
        return &model.slides[index];
    }

    pub fn selectedMeta(model: *const Model, arena: std.mem.Allocator) []const u8 {
        const index = model.selectedIndex() orelse return "Add images to start a GIF.";
        const slide = model.slides[index];
        if (slide.source_width > 0 and slide.source_height > 0) {
            return std.fmt.allocPrint(arena, "Frame {d} of {d} - {s} per slide - {d}x{d}", .{
                index + 1,
                model.slide_count,
                formatDuration(arena, slide.duration_cs),
                slide.source_width,
                slide.source_height,
            }) catch "";
        }
        return std.fmt.allocPrint(arena, "Frame {d} of {d} - {s} per slide", .{
            index + 1,
            model.slide_count,
            formatDuration(arena, slide.duration_cs),
        }) catch "";
    }

    pub fn outputSummary(model: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d}px wide - {s} quality - contain fit - loop forever", .{
            model.output_width,
            model.qualityLabel(),
        }) catch "";
    }

    pub fn statusLine(model: *const Model, arena: std.mem.Allocator) []const u8 {
        if (model.last_error_len > 0) return std.fmt.allocPrint(arena, "Error: {s}", .{lastError(model)}) catch "";
        if (model.slide_count == 0) return "0 slides - ready for PNG or JPEG frames";
        const total_cs = model.totalDurationCs();
        if (model.export_count > 0) {
            return std.fmt.allocPrint(arena, "Export settings captured - {d} {s}, {s} total", .{
                model.slide_count,
                if (model.slide_count == 1) "slide" else "slides",
                formatDuration(arena, total_cs),
            }) catch "";
        }
        return std.fmt.allocPrint(arena, "{d} {s} - {s} total - {s}", .{
            model.slide_count,
            if (model.slide_count == 1) "slide" else "slides",
            formatDuration(arena, total_cs),
            model.outputSummary(arena),
        }) catch "";
    }

    pub fn visibleSlides(model: *const Model, arena: std.mem.Allocator) []const VisibleSlide {
        const out = arena.alloc(VisibleSlide, model.slide_count) catch return &.{};
        for (model.slides[0..model.slide_count], 0..) |slide, index| {
            const index_label = std.fmt.allocPrint(arena, "{d:0>2}", .{index + 1}) catch "";
            const duration_label = formatDuration(arena, slide.duration_cs);
            const meta = if (slide.source_width > 0 and slide.source_height > 0)
                std.fmt.allocPrint(arena, "{s} - {d}x{d} - frame {d}", .{ duration_label, slide.source_width, slide.source_height, index + 1 }) catch ""
            else
                std.fmt.allocPrint(arena, "{s} - frame {d}", .{ duration_label, index + 1 }) catch "";
            out[index] = .{
                .id = slide.id,
                .selected = slide.id == model.selected_slide_id,
                .filename = slide.name(),
                .index_label = index_label,
                .duration_label = duration_label,
                .meta = meta,
                .accessibility_label = std.fmt.allocPrint(arena, "Frame {d}: {s}", .{ index + 1, slide.name() }) catch slide.name(),
            };
        }
        return out;
    }

    fn selectedIndex(model: *const Model) ?usize {
        if (model.selected_slide_id == 0) return null;
        for (model.slides[0..model.slide_count], 0..) |slide, index| {
            if (slide.id == model.selected_slide_id) return index;
        }
        return null;
    }

    fn totalDurationCs(model: *const Model) u32 {
        var total: u32 = 0;
        for (model.slides[0..model.slide_count]) |slide| total += slide.duration_cs;
        return total;
    }
};

pub const PendingAction = enum {
    none,
    open_images,
    export_gif,
};

pub fn initialModel() Model {
    return .{};
}

pub fn update(model: *Model, msg: Msg) void {
    switch (msg) {
        .add_images => model.pending_action = .open_images,
        .export_gif => {
            if (model.slide_count > 0) model.pending_action = .export_gif;
        },
        .select_slide => |id| {
            if (indexOf(model, id) != null) model.selected_slide_id = id;
        },
        .remove_selected => removeSelected(model),
        .duplicate_selected => duplicateSelected(model),
        .move_selected_up => moveSelected(model, .up),
        .move_selected_down => moveSelected(model, .down),
        .move_selected_top => moveSelected(model, .top),
        .move_selected_bottom => moveSelected(model, .bottom),
        .speed_slower => {
            model.default_duration_cs = @min(model.default_duration_cs + 10, 500);
            applyDefaultDuration(model);
        },
        .speed_faster => {
            model.default_duration_cs = if (model.default_duration_cs > 20) model.default_duration_cs - 10 else 10;
            applyDefaultDuration(model);
        },
        .speed_reset => {
            model.default_duration_cs = 100;
            applyDefaultDuration(model);
        },
        .quality_small => model.quality = .small,
        .quality_balanced => model.quality = .balanced,
        .quality_clean => model.quality = .clean,
        .width_smaller => model.output_width = if (model.output_width > 320) model.output_width - 160 else 320,
        .width_larger => model.output_width = @min(model.output_width + 160, 1280),
        .sidebar_resized => |fraction| model.sidebar_split = clamp(fraction, 0.25, 0.6),
        .chrome_changed => |chrome| {
            model.chrome_leading = chrome.leading;
            model.chrome_trailing = chrome.trailing;
        },
    }
}

pub fn consumePendingAction(model: *Model) PendingAction {
    const action = model.pending_action;
    model.pending_action = .none;
    return action;
}

pub fn addImagePath(model: *Model, path: []const u8) bool {
    return addImagePathWithInfo(model, path, 0, 0);
}

pub fn addImagePathWithInfo(model: *Model, path: []const u8, source_width: u16, source_height: u16) bool {
    if (model.slide_count >= max_slides) {
        setError(model, "Too many slides; remove one before adding more.");
        return false;
    }
    if (!isSupportedImagePath(path)) {
        setError(model, "Only PNG and JPEG files are supported.");
        return false;
    }

    const id = model.next_id;
    model.next_id += 1;
    var slide = Slide{ .id = id, .duration_cs = model.default_duration_cs };
    slide.source_width = source_width;
    slide.source_height = source_height;
    slide.path_len = @min(path.len, slide.path_buffer.len);
    @memcpy(slide.path_buffer[0..slide.path_len], path[0..slide.path_len]);

    const filename = basename(path);
    slide.name_len = @min(filename.len, slide.name_buffer.len);
    @memcpy(slide.name_buffer[0..slide.name_len], filename[0..slide.name_len]);

    model.slides[model.slide_count] = slide;
    model.slide_count += 1;
    if (model.selected_slide_id == 0) model.selected_slide_id = id;
    clearError(model);
    return true;
}

pub fn addImagePathsNewlineSeparated(model: *Model, paths: []const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= paths.len) {
        const end = std.mem.indexOfScalarPos(u8, paths, start, '\n') orelse paths.len;
        const path = std.mem.trim(u8, paths[start..end], " \t\r\n");
        if (path.len > 0 and addImagePath(model, path)) count += 1;
        if (end == paths.len) break;
        start = end + 1;
    }
    return count;
}

pub fn markExported(model: *Model, output_path: []const u8) void {
    model.export_count += 1;
    clearError(model);
    _ = output_path;
}

pub fn setError(model: *Model, message: []const u8) void {
    model.last_error_len = @min(message.len, model.last_error_buffer.len);
    @memcpy(model.last_error_buffer[0..model.last_error_len], message[0..model.last_error_len]);
}

pub fn clearError(model: *Model) void {
    model.last_error_len = 0;
}

pub fn lastError(model: *const Model) []const u8 {
    return model.last_error_buffer[0..model.last_error_len];
}

fn removeSelected(model: *Model) void {
    const index = model.selectedIndex() orelse return;
    var i = index;
    while (i + 1 < model.slide_count) : (i += 1) {
        model.slides[i] = model.slides[i + 1];
    }
    model.slide_count -= 1;
    model.slides[model.slide_count] = .{};
    if (model.slide_count == 0) {
        model.selected_slide_id = 0;
    } else {
        const next_index = @min(index, model.slide_count - 1);
        model.selected_slide_id = model.slides[next_index].id;
    }
}

fn duplicateSelected(model: *Model) void {
    const index = model.selectedIndex() orelse return;
    if (model.slide_count >= max_slides) return;
    var i = model.slide_count;
    while (i > index + 1) : (i -= 1) {
        model.slides[i] = model.slides[i - 1];
    }
    const id = model.next_id;
    model.next_id += 1;
    model.slides[index + 1] = model.slides[index];
    model.slides[index + 1].id = id;
    model.selected_slide_id = id;
    model.slide_count += 1;
}

const MoveDirection = enum { up, down, top, bottom };

fn moveSelected(model: *Model, direction: MoveDirection) void {
    const index = model.selectedIndex() orelse return;
    switch (direction) {
        .up => if (index > 0) swapSlides(model, index, index - 1),
        .down => if (index + 1 < model.slide_count) swapSlides(model, index, index + 1),
        .top => {
            var i = index;
            while (i > 0) : (i -= 1) swapSlides(model, i, i - 1);
        },
        .bottom => {
            var i = index;
            while (i + 1 < model.slide_count) : (i += 1) swapSlides(model, i, i + 1);
        },
    }
}

fn swapSlides(model: *Model, a: usize, b: usize) void {
    const tmp = model.slides[a];
    model.slides[a] = model.slides[b];
    model.slides[b] = tmp;
}

fn applyDefaultDuration(model: *Model) void {
    for (model.slides[0..model.slide_count]) |*slide| {
        slide.duration_cs = model.default_duration_cs;
    }
}

fn indexOf(model: *const Model, id: u32) ?usize {
    for (model.slides[0..model.slide_count], 0..) |slide, index| {
        if (slide.id == id) return index;
    }
    return null;
}

fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfAny(u8, path, "/\\")) |index| return path[index + 1 ..];
    return path;
}

fn isSupportedImagePath(path: []const u8) bool {
    const lower_ext = extension(path);
    return std.ascii.eqlIgnoreCase(lower_ext, ".png") or
        std.ascii.eqlIgnoreCase(lower_ext, ".jpg") or
        std.ascii.eqlIgnoreCase(lower_ext, ".jpeg");
}

fn extension(path: []const u8) []const u8 {
    const base = basename(path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |index| return base[index..];
    return "";
}

fn formatDuration(arena: std.mem.Allocator, centiseconds: u32) []const u8 {
    return std.fmt.allocPrint(arena, "{d}.{d:0>2}s", .{ centiseconds / 100, centiseconds % 100 }) catch "";
}

fn clamp(value: f32, min: f32, max: f32) f32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

test "slide operations keep selection stable" {
    var model = initialModel();
    try std.testing.expect(addImagePath(&model, "/tmp/landing.png"));
    try std.testing.expect(addImagePath(&model, "/tmp/feature-shot.jpg"));
    try std.testing.expect(addImagePath(&model, "/tmp/confirmation.png"));
    try std.testing.expectEqual(@as(usize, 3), model.slide_count);
    try std.testing.expectEqual(model.slides[0].id, model.selected_slide_id);

    update(&model, .move_selected_down);
    try std.testing.expectEqual(model.slides[1].id, model.selected_slide_id);

    update(&model, .duplicate_selected);
    try std.testing.expectEqual(@as(usize, 4), model.slide_count);
    try std.testing.expectEqual(model.slides[2].id, model.selected_slide_id);

    update(&model, .remove_selected);
    try std.testing.expectEqual(@as(usize, 3), model.slide_count);
    try std.testing.expectEqual(model.slides[2].id, model.selected_slide_id);
}
