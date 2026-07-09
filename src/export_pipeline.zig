const std = @import("std");
const builtin = @import("builtin");
const gif = @import("gif_writer.zig");
const model_mod = @import("model.zig");

extern fn gifbin_decode_image_rgba(path: [*:0]const u8, width: c_int, height: c_int, out_rgba: [*]u8) c_int;
const decodeImageRgba = if (builtin.is_test) testDecodeImageRgba else platformDecodeImageRgba;

pub const ExportOptions = struct {
    width: u16,
    quality: model_mod.Quality,
    fit_mode: model_mod.FitMode = .contain,
};

pub fn exportGif(allocator: std.mem.Allocator, slides: []const model_mod.Slide, output_path: []const u8, options: ExportOptions) !void {
    if (slides.len == 0) return error.NoSlides;
    const size = outputSize(slides[0], options.width);
    const width = size.width;
    const height = size.height;
    const frame_len = @as(usize, width) * @as(usize, height) * 4;
    const frame = try allocator.alloc(u8, frame_len);
    defer allocator.free(frame);

    var writer = try gif.Writer.begin(output_path, width, height);
    errdefer writer.abort();

    for (slides) |slide| {
        const path_z = try allocator.dupeZ(u8, slide.path());
        defer allocator.free(path_z);
        _ = options.fit_mode;
        if (decodeImageRgba(path_z.ptr, width, height, frame.ptr) == 0) {
            return error.ImageDecodeFailed;
        }
        try writer.frame(frame, slide.duration_cs, qualityValue(options.quality));
    }

    try writer.finish();
}

pub fn outputSize(first_slide: model_mod.Slide, requested_width: u16) struct { width: u16, height: u16 } {
    const width = @max(@as(u16, 1), requested_width);
    if (first_slide.source_width == 0 or first_slide.source_height == 0) {
        return .{ .width = width, .height = width };
    }

    const raw_height = (@as(u32, width) * @as(u32, first_slide.source_height) + @as(u32, first_slide.source_width) / 2) / @as(u32, first_slide.source_width);
    var height: u16 = @intCast(@max(@as(u32, 1), @min(raw_height, std.math.maxInt(u16))));
    if (height > 1 and height % 2 == 1 and height < std.math.maxInt(u16)) height += 1;
    return .{ .width = width, .height = height };
}

fn platformDecodeImageRgba(path: [*:0]const u8, width: c_int, height: c_int, out_rgba: [*]u8) c_int {
    return gifbin_decode_image_rgba(path, width, height, out_rgba);
}

fn testDecodeImageRgba(path: [*:0]const u8, width: c_int, height: c_int, out_rgba: [*]u8) c_int {
    _ = path;
    if (width <= 0 or height <= 0) return 0;
    const len = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * 4;
    @memset(out_rgba[0..len], 0xff);
    return 1;
}

fn qualityValue(quality: model_mod.Quality) u8 {
    return switch (quality) {
        .small => 6,
        .balanced => 12,
        .clean => 16,
    };
}

test "quality values map to msf range" {
    try std.testing.expectEqual(@as(u8, 6), qualityValue(.small));
    try std.testing.expectEqual(@as(u8, 12), qualityValue(.balanced));
    try std.testing.expectEqual(@as(u8, 16), qualityValue(.clean));
}

test "output size follows first frame aspect ratio" {
    const wide = model_mod.Slide{ .source_width = 1600, .source_height = 900 };
    try std.testing.expectEqual(@as(u16, 640), outputSize(wide, 640).width);
    try std.testing.expectEqual(@as(u16, 360), outputSize(wide, 640).height);

    const tall = model_mod.Slide{ .source_width = 900, .source_height = 1600 };
    try std.testing.expectEqual(@as(u16, 1138), outputSize(tall, 640).height);
}
