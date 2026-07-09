const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");

const canvas = native_sdk.canvas;
const testing = std.testing;

const AppUi = main.AppUi;
const Model = main.Model;
const Msg = main.Msg;

fn buildTree(arena: std.mem.Allocator, model: *const Model) !AppUi.Tree {
    var ui = AppUi.init(arena);
    const node = main.appView(&ui, model);
    return ui.finalize(node);
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findByText(child, kind, text)) |found| return found;
    }
    return null;
}

/// A miss fails the test with the mismatch spelled out instead of a
/// null-unwrap panic: the usual cause is the Zig view and this test
/// drifting apart after an edit.
fn expectByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) !canvas.Widget {
    return findByText(widget, kind, text) orelse {
        std.debug.print("no {t} with text \"{s}\" in the view - if you changed the Zig view, update this test to match\n", .{ kind, text });
        return error.WidgetNotFound;
    };
}

fn findByKind(widget: canvas.Widget, kind: canvas.WidgetKind) ?canvas.Widget {
    if (widget.kind == kind) return widget;
    for (widget.children) |child| {
        if (findByKind(child, kind)) |found| return found;
    }
    return null;
}

fn findButtonByIcon(widget: canvas.Widget, icon: []const u8) ?canvas.Widget {
    if (widget.kind == .button and std.mem.eql(u8, widget.icon, icon)) return widget;
    for (widget.children) |child| {
        if (findButtonByIcon(child, icon)) |found| return found;
    }
    return null;
}

test "clicking app controls drives gifmaker state through typed dispatch" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = main.initialModel();

    var tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "GIFMaker");
    _ = try expectByText(tree.root, .status_bar, "0 slides - ready for PNG or JPEG frames");

    const add = try expectByText(tree.root, .button, "Add Images");
    main.update(&model, tree.msgForPointer(add.id, .up).?);
    try testing.expectEqual(main.PendingAction.open_images, main.consumePendingAction(&model));

    try testing.expect(main.addImagePath(&model, "/tmp/landing.png"));
    try testing.expect(main.addImagePath(&model, "/tmp/feature-shot.jpg"));
    try testing.expect(main.addImagePath(&model, "/tmp/confirmation.png"));
    try testing.expectEqual(@as(usize, 3), model.slide_count);
    try testing.expectEqual(model.slides[0].id, model.selected_slide_id);

    tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "landing.png");
    try testing.expectEqualStrings("feature-shot.jpg", model.slides[1].name());
    try testing.expectEqual(add.id, (try expectByText(tree.root, .button, "Add Images")).id);

    const move_down = findButtonByIcon(tree.root, "arrow-down") orelse return error.WidgetNotFound;
    main.update(&model, tree.msgForPointer(move_down.id, .up).?);
    try testing.expectEqual(model.slides[1].id, model.selected_slide_id);

    tree = try buildTree(arena, &model);
    const duplicate = try expectByText(tree.root, .button, "Duplicate");
    main.update(&model, tree.msgForPointer(duplicate.id, .up).?);
    try testing.expectEqual(@as(usize, 4), model.slide_count);

    tree = try buildTree(arena, &model);
    const clean = try expectByText(tree.root, .button, "Clean");
    main.update(&model, tree.msgForPointer(clean.id, .up).?);
    try testing.expectEqual(main.Quality.clean, model.quality);

    const export_button = try expectByText(tree.root, .button, "Export GIF");
    main.update(&model, tree.msgForPointer(export_button.id, .up).?);
    try testing.expectEqual(main.PendingAction.export_gif, main.consumePendingAction(&model));
}

test "the view lays out through the canvas engine" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var model = main.initialModel();
    try testing.expect(main.addImagePath(&model, "/tmp/landing.png"));
    try testing.expect(main.addImagePath(&model, "/tmp/feature-shot.jpg"));
    try testing.expect(main.addImagePath(&model, "/tmp/confirmation.png"));
    const tree = try buildTree(arena_state.allocator(), &model);

    var nodes: [256]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, native_sdk.geometry.RectF.init(0, 0, 1040, 680), &nodes);
    try testing.expect(layout.nodes.len > 0);

    const plus = try expectByText(tree.root, .button, "Add Images");
    var saw_button = false;
    for (layout.nodes) |node| {
        if (node.widget.id == plus.id) saw_button = true;
    }
    try testing.expect(saw_button);

    _ = findByKind(tree.root, .split) orelse return error.WidgetNotFound;
}
