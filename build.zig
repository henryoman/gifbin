const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    const native_dep = b.dependency("native_sdk", .{});
    const artifacts = native_sdk.addAppArtifacts(b, native_dep, .{ .name = "gifmaker" });

    artifacts.exe.root_module.addIncludePath(b.path("third_party/msf_gif"));
    artifacts.exe.root_module.addCSourceFile(.{
        .file = b.path("third_party/msf_gif/msf_gif_impl.c"),
        .flags = &.{ "-std=c99" },
    });
    artifacts.exe.root_module.addCSourceFile(.{
        .file = b.path("src/platform_image_macos.m"),
        .flags = &.{ "-ObjC", "-Wno-unguarded-availability-new", "-Wno-error=unguarded-availability-new" },
    });
    artifacts.exe.root_module.linkFramework("CoreFoundation", .{});
    artifacts.exe.root_module.linkFramework("CoreGraphics", .{});
    artifacts.exe.root_module.linkFramework("ImageIO", .{});
    artifacts.exe.root_module.linkSystemLibrary("c", .{});

    artifacts.tests.root_module.addIncludePath(b.path("third_party/msf_gif"));

    const dev_cmd = b.addSystemCommand(&.{ "./scripts/dev" });
    const dev_step = b.step("dev", "Run the Debug dev app with terminal logs");
    dev_step.dependOn(&dev_cmd.step);

    const dev_check_cmd = b.addSystemCommand(&.{ "./scripts/dev", "--check" });
    const dev_check_step = b.step("dev-check", "Run dev preflight checks");
    dev_check_step.dependOn(&dev_check_cmd.step);

    const dev_smoke_cmd = b.addSystemCommand(&.{ "./scripts/dev", "--smoke" });
    const dev_smoke_step = b.step("dev-smoke", "Launch the dev app, assert it renders, then stop");
    dev_smoke_step.dependOn(&dev_smoke_cmd.step);
}
