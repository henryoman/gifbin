const std = @import("std");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("msf_gif.h");
});

fn writeToFile(data: ?*const anyopaque, size: usize, count: usize, stream: ?*anyopaque) callconv(.c) usize {
    const file: [*c]c.FILE = @ptrCast(@alignCast(stream.?));
    return c.fwrite(data, size, count, file);
}

pub const Writer = struct {
    file: ?*c.FILE = null,
    state: c.MsfGifState = undefined,
    width: u16 = 0,
    height: u16 = 0,

    pub fn begin(path: []const u8, width: u16, height: u16) !Writer {
        const path_z = try std.heap.page_allocator.dupeZ(u8, path);
        defer std.heap.page_allocator.free(path_z);
        const file = c.fopen(path_z.ptr, "wb") orelse return error.OutputOpenFailed;
        errdefer _ = c.fclose(file);

        var writer = Writer{ .file = file, .width = width, .height = height };
        if (c.msf_gif_begin_to_file(&writer.state, width, height, writeToFile, @ptrCast(file)) == 0) {
            return error.GifBeginFailed;
        }
        return writer;
    }

    pub fn frame(self: *Writer, rgba: []u8, duration_cs: u16, quality: u8) !void {
        const expected = @as(usize, self.width) * @as(usize, self.height) * 4;
        if (rgba.len < expected) return error.InvalidFrameBuffer;
        const ok = c.msf_gif_frame_to_file(
            &self.state,
            rgba.ptr,
            @intCast(@max(duration_cs, 1)),
            @intCast(std.math.clamp(quality, 1, 16)),
            @intCast(@as(usize, self.width) * 4),
        );
        if (ok == 0) return error.GifFrameFailed;
    }

    pub fn finish(self: *Writer) !void {
        if (self.file == null) return;
        const ok = c.msf_gif_end_to_file(&self.state);
        const file = self.file.?;
        self.file = null;
        if (c.fclose(file) != 0) return error.OutputCloseFailed;
        if (ok == 0) return error.GifEndFailed;
    }

    pub fn abort(self: *Writer) void {
        if (self.file) |file| {
            _ = c.fclose(file);
            self.file = null;
        }
    }
};
