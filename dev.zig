const std = @import("std");

const Command = enum {
    help,
    run,
    native_dev,
    check,
    smoke,
    build,
    test_app,
    package,
};

const Options = struct {
    command: Command = .help,
    trace: []const u8 = "off",
    platform: []const u8 = "macos",
    optimize: []const u8 = "Debug",
    automation: []const u8 = "false",
};

pub fn main(init: std.process.Init) !void {
    var args_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args_it.deinit();
    _ = args_it.skip();

    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(init.gpa);
    while (args_it.next()) |arg| try args.append(init.gpa, arg);

    const options = if (args.items.len == 0) try menu(init.io) else parseArgs(args.items) catch |err| {
        std.debug.print("dev: {s}\n\n", .{@errorName(err)});
        usage();
        std.process.exit(2);
    };

    switch (options.command) {
        .help => usage(),
        .run => try runScript(init.gpa, init.io, &.{}, options),
        .native_dev => try runNativeDev(init.gpa, init.io, options),
        .check => try runScript(init.gpa, init.io, &.{"--check"}, options),
        .smoke => try runScript(init.gpa, init.io, &.{"--smoke"}, options),
        .build => try runCommand(init.gpa, init.io, &.{ "zig", "build" }, options),
        .test_app => try runCommand(init.gpa, init.io, &.{ "zig", "build", "test" }, options),
        .package => try runCommand(init.gpa, init.io, &.{ "zig", "build", "package" }, options),
    }
}

fn parseArgs(args: []const []const u8) !Options {
    var options = Options{};
    var command_seen = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            options.command = .help;
            return options;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            options.trace = "off";
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            options.trace = "events";
        } else if (std.mem.startsWith(u8, arg, "--trace=")) {
            options.trace = arg["--trace=".len..];
        } else if (std.mem.eql(u8, arg, "--trace")) {
            i += 1;
            if (i >= args.len) return error.MissingTraceValue;
            options.trace = args[i];
        } else if (std.mem.startsWith(u8, arg, "--platform=")) {
            options.platform = arg["--platform=".len..];
        } else if (std.mem.eql(u8, arg, "--platform")) {
            i += 1;
            if (i >= args.len) return error.MissingPlatformValue;
            options.platform = args[i];
        } else if (std.mem.startsWith(u8, arg, "--optimize=")) {
            options.optimize = arg["--optimize=".len..];
        } else if (std.mem.eql(u8, arg, "--optimize")) {
            i += 1;
            if (i >= args.len) return error.MissingOptimizeValue;
            options.optimize = args[i];
        } else if (std.mem.eql(u8, arg, "--release")) {
            options.optimize = "ReleaseFast";
        } else if (std.mem.eql(u8, arg, "--no-automation")) {
            options.automation = "false";
        } else if (std.mem.eql(u8, arg, "--automation")) {
            options.automation = "true";
        } else if (!command_seen) {
            options.command = parseCommand(arg) orelse return error.UnknownCommand;
            command_seen = true;
        } else {
            return error.UnexpectedArgument;
        }
    }

    return options;
}

fn parseCommand(value: []const u8) ?Command {
    if (std.mem.eql(u8, value, "run")) return .run;
    if (std.mem.eql(u8, value, "native")) return .native_dev;
    if (std.mem.eql(u8, value, "native-dev")) return .native_dev;
    if (std.mem.eql(u8, value, "check")) return .check;
    if (std.mem.eql(u8, value, "smoke")) return .smoke;
    if (std.mem.eql(u8, value, "build")) return .build;
    if (std.mem.eql(u8, value, "test")) return .test_app;
    if (std.mem.eql(u8, value, "package")) return .package;
    if (std.mem.eql(u8, value, "help")) return .help;
    return null;
}

fn menu(io: std.Io) !Options {
    std.debug.print(
        \\gifbin dev
        \\
        \\  1. Run app (recommended: zig build dev path)
        \\  2. Run via native dev (SDK CLI path)
        \\  3. Smoke test
        \\  4. Check only
        \\  5. Build
        \\  6. Test
        \\
        \\Choose [1]: 
    , .{});

    var read_buffer: [128]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &read_buffer);
    const raw = stdin_reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => "",
        else => return err,
    };
    const choice = std.mem.trim(u8, raw, " \t\r\n");
    return .{ .command = if (choice.len == 0 or std.mem.eql(u8, choice, "1"))
        .run
    else if (std.mem.eql(u8, choice, "2"))
        .native_dev
    else if (std.mem.eql(u8, choice, "3"))
        .smoke
    else if (std.mem.eql(u8, choice, "4"))
        .check
    else if (std.mem.eql(u8, choice, "5"))
        .build
    else if (std.mem.eql(u8, choice, "6"))
        .test_app
    else
        return error.UnknownMenuChoice };
}

fn runScript(allocator: std.mem.Allocator, io: std.Io, script_args: []const []const u8, options: Options) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try appendEnv(allocator, &argv, options);
    try argv.append(allocator, "./scripts/dev");
    try argv.appendSlice(allocator, script_args);

    try spawnAndExit(io, argv.items);
}

fn runNativeDev(allocator: std.mem.Allocator, io: std.Io, options: Options) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try appendEnv(allocator, &argv, options);
    try argv.appendSlice(allocator, &.{ "native", "dev", "." });
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "-Dplatform={s}", .{options.platform}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "-Doptimize={s}", .{options.optimize}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "-Dautomation={s}", .{options.automation}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "-Dtrace={s}", .{options.trace}));

    try spawnAndExit(io, argv.items);
}

fn runCommand(allocator: std.mem.Allocator, io: std.Io, command_args: []const []const u8, options: Options) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try appendEnv(allocator, &argv, options);
    try argv.appendSlice(allocator, command_args);

    try spawnAndExit(io, argv.items);
}

fn appendEnv(allocator: std.mem.Allocator, argv: *std.ArrayList([]const u8), options: Options) !void {
    try argv.append(allocator, "env");
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "TRACE={s}", .{options.trace}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "PLATFORM={s}", .{options.platform}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "OPTIMIZE={s}", .{options.optimize}));
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "AUTOMATION={s}", .{options.automation}));
}

fn spawnAndExit(io: std.Io, argv: []const []const u8) !void {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        std.debug.print("failed to start {s}: {s}\n", .{ argv[0], @errorName(err) });
        std.process.exit(127);
    };

    const term = child.wait(io) catch |err| {
        std.debug.print("failed while waiting for {s}: {s}\n", .{ argv[0], @errorName(err) });
        std.process.exit(1);
    };

    switch (term) {
        .exited => |code| std.process.exit(code),
        .signal => |signal| {
            std.debug.print("{s} stopped by signal {t}\n", .{ argv[0], signal });
            std.process.exit(130);
        },
        else => std.process.exit(1),
    }
}

fn usage() void {
    std.debug.print(
        \\gifbin dev runner
        \\
        \\Usage:
        \\  zig run dev.zig -- <command> [options]
        \\
        \\Commands:
        \\  run       Run the Debug dev app with terminal logs (no preflight)
        \\  native    Run through the Native SDK CLI: native dev .
        \\  check     Run Native SDK checks and the app's Zig tests
        \\  smoke     Launch, assert rendered UI, screenshot, then stop
        \\  build     Run zig build
        \\  test      Run zig build test
        \\  package   Run zig build package
        \\  help      Show this help
        \\
        \\Options:
        \\  --quiet                    Set TRACE=off (default)
        \\  --verbose                  Set TRACE=events for SDK event debugging
        \\  --trace <mode>             off, events, runtime, all
        \\  --platform <platform>      macos, linux, windows (default: macos)
        \\  --optimize <mode>          Debug, ReleaseFast, ReleaseSafe, ReleaseSmall
        \\  --release                  Shortcut for --optimize ReleaseFast
        \\  --automation               Enable Native SDK automation (smoke always enables it)
        \\  --no-automation            Disable Native SDK automation (default)
        \\
        \\Examples:
        \\  zig run dev.zig
        \\  zig run dev.zig -- run
        \\  zig run dev.zig -- native
        \\  zig run dev.zig -- run --verbose
        \\  zig run dev.zig -- smoke
        \\  zig run dev.zig -- check
        \\
        \\Short aliases also exist:
        \\  zig build dev
        \\  zig build dev-smoke
        \\  zig build dev-check
        \\
    , .{});
}
