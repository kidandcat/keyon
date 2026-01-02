const std = @import("std");
const main = @import("main.zig");
const hotkey = @import("hotkey.zig");
const UIElement = @import("ui_element.zig").UIElement;
const accessibility = @import("accessibility.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

const statusbar = @cImport({
    @cInclude("statusbar.h");
});


// Label generation: A-Z, then AA-AZ, BA-BZ, etc.
const LABEL_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const LABEL_BG = rl.Color{ .r = 57, .g = 255, .b = 20, .a = 255 }; // #39FF14 matrix green
const LABEL_TEXT = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 }; // White text
const LABEL_BORDER = rl.Color{ .r = 180, .g = 90, .b = 60, .a = 255 }; // Darker coral border
const HINT_BG = rl.Color{ .r = 30, .g = 30, .b = 35, .a = 230 };
const HINT_TEXT = rl.Color{ .r = 240, .g = 240, .b = 245, .a = 255 };

var window_open = false;
var app_ptr: ?*main.App = null;

var screen_width: i32 = 0;
var screen_height: i32 = 0;
var custom_font: rl.Font = undefined;
var font_loaded: bool = false;

// Scroll debounce for label recalculation
var last_scroll_time: i64 = 0;
var needs_rescan: bool = false;
const SCROLL_DEBOUNCE_MS: i64 = 1000; // 1 second

pub fn show(app: *main.App) void {
    app_ptr = app;

    // Reset global keyboard state
    hotkey.typed_len = 0;
    hotkey.should_click = false;

    if (!window_open) {
        // First time - initialize window
        rl.SetConfigFlags(rl.FLAG_WINDOW_UNDECORATED | rl.FLAG_WINDOW_TRANSPARENT | rl.FLAG_WINDOW_TOPMOST | rl.FLAG_WINDOW_HIGHDPI | rl.FLAG_WINDOW_MOUSE_PASSTHROUGH);
        rl.InitWindow(100, 100, "KeyOn Overlay");

        // Hide from Dock and CMD+Tab after raylib creates its window
        statusbar.hideFromDock();

        // Set window above all other windows
        statusbar.setWindowAboveAll();

        if (rl.IsWindowReady() == false) {
            std.debug.print("Failed to create window\n", .{});
            return;
        }

        const monitor = rl.GetCurrentMonitor();
        screen_width = rl.GetMonitorWidth(monitor);
        screen_height = rl.GetMonitorHeight(monitor);
        rl.SetTargetFPS(60);

        // Load system font
        custom_font = rl.LoadFontEx("/System/Library/Fonts/SFNS.ttf", 32, null, 0);
        if (custom_font.texture.id != 0) {
            font_loaded = true;
            rl.SetTextureFilter(custom_font.texture, rl.TEXTURE_FILTER_BILINEAR);
        }

        window_open = true;
    }

    // Restore window to full screen
    rl.SetWindowSize(screen_width, screen_height);
    rl.SetWindowPosition(0, 0);
    rl.SetWindowFocused();

    runOverlayLoop(app);
}

pub fn hide() void {
    if (window_open) {
        // Don't close - just minimize/hide by moving off-screen
        rl.SetWindowPosition(-10000, -10000);
        rl.SetWindowSize(1, 1);
    }
}

fn runOverlayLoop(app: *main.App) void {
    // Make sure window is ready before drawing
    if (rl.IsWindowReady() == false) {
        std.debug.print("Window not ready, skipping overlay\n", .{});
        return;
    }

    while (!rl.WindowShouldClose() and app.overlay_visible) {
        handleInput(app);

        rl.BeginDrawing();
        rl.ClearBackground(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        // Draw labels on each element
        drawElementLabels(app);

        // Draw hint bar at bottom
        drawHintBar(app);

        rl.EndDrawing();
    }

    hide();
}

const click = @import("click.zig");

fn rescanElements(app: *main.App) void {
    // Release old AXUIElementRefs and clear elements
    for (app.elements.items) |*elem| {
        elem.deinit();
    }
    app.elements.clearRetainingCapacity();

    // Rescan
    if (app.target_pid) |pid| {
        if (accessibility.scanApp(pid, app.allocator)) |elements| {
            app.elements.appendSlice(app.allocator, elements) catch {};
            app.allocator.free(elements);
            std.debug.print("Rescanned: found {d} elements\n", .{app.elements.items.len});
        } else |_| {
            std.debug.print("Rescan failed\n", .{});
        }
    }

    // Reset search state
    hotkey.typed_len = 0;
    app.selected_index = 0;
    app.filtered_count = app.elements.items.len;
}

fn handleInput(app: *main.App) void {
    // Input is handled globally via hotkey.zig event tap

    // Handle continuous mouse movement via arrow keys
    const delta_time = rl.GetFrameTime();
    const movement = hotkey.getMouseMovement(delta_time);
    if (movement.x != 0 or movement.y != 0) {
        const current = getMousePosition();
        click.moveMouse(current.x + movement.x, current.y + movement.y);
    }

    // Handle scrolling via Shift+Arrow keys
    if (hotkey.scroll_x != 0 or hotkey.scroll_y != 0) {
        click.performScroll(hotkey.scroll_x, hotkey.scroll_y);
        hotkey.scroll_x = 0;
        hotkey.scroll_y = 0;
        // Mark that we need to rescan after scroll debounce
        last_scroll_time = std.time.milliTimestamp();
        needs_rescan = true;
    }

    // Check if we need to rescan elements after scrolling stopped
    if (needs_rescan) {
        const now = std.time.milliTimestamp();
        if (now - last_scroll_time >= SCROLL_DEBOUNCE_MS) {
            needs_rescan = false;
            std.debug.print("Rescanning elements after scroll\n", .{});
            rescanElements(app);
        }
    }

    // Handle click at current mouse position
    if (hotkey.click_at_mouse) {
        hotkey.click_at_mouse = false;
        const pos = getMousePosition();
        std.debug.print("Clicking at mouse position: ({d}, {d})\n", .{ @as(i32, @intFromFloat(pos.x)), @as(i32, @intFromFloat(pos.y)) });
        app.hideOverlay();
        std.Thread.sleep(30 * std.time.ns_per_ms);
        click.performClick(pos.x, pos.y);
    }

    // Handle right click at current mouse position
    if (hotkey.right_click_at_mouse) {
        hotkey.right_click_at_mouse = false;
        const pos = getMousePosition();
        app.hideOverlay();
        std.Thread.sleep(30 * std.time.ns_per_ms);
        click.performRightClick(pos.x, pos.y);
    }

    // Handle middle click at current mouse position
    if (hotkey.middle_click_at_mouse) {
        hotkey.middle_click_at_mouse = false;
        const pos = getMousePosition();
        app.hideOverlay();
        std.Thread.sleep(30 * std.time.ns_per_ms);
        click.performMiddleClick(pos.x, pos.y);
    }

    // Check if we should click a label
    if (hotkey.should_click) {
        hotkey.should_click = false;
        if (hotkey.typed_len > 0) {
            _ = tryClickLabel(app, hotkey.typed_chars[0..hotkey.typed_len], .left);
        }
    }

    // Check if we should right click a label
    if (hotkey.should_right_click) {
        hotkey.should_right_click = false;
        if (hotkey.typed_len > 0) {
            _ = tryClickLabel(app, hotkey.typed_chars[0..hotkey.typed_len], .right);
        }
    }

    // Check if we should middle click a label
    if (hotkey.should_middle_click) {
        hotkey.should_middle_click = false;
        if (hotkey.typed_len > 0) {
            _ = tryClickLabel(app, hotkey.typed_chars[0..hotkey.typed_len], .middle);
        }
    }

    // Also process CF events so the event tap works
    hotkey.processEvents();
}

fn getMousePosition() rl.Vector2 {
    // Get current mouse position using CGEvent
    const cg = @cImport({
        @cInclude("CoreGraphics/CoreGraphics.h");
    });
    const event = cg.CGEventCreate(null);
    if (event) |ev| {
        defer cg.CFRelease(ev);
        const point = cg.CGEventGetLocation(ev);
        return rl.Vector2{ .x = @floatCast(point.x), .y = @floatCast(point.y) };
    }
    return rl.Vector2{ .x = 0, .y = 0 };
}

const ClickType = enum { left, right, middle };

fn tryClickLabel(app: *main.App, label: []const u8, click_type: ClickType) bool {
    const elements = app.elements.items;

    var i: usize = 0;
    for (elements) |elem| {
        var elem_label: [8]u8 = undefined;
        const label_len = generateLabel(i, &elem_label);

        if (std.mem.eql(u8, label, elem_label[0..label_len])) {
            // Found a match - hide overlay FIRST, then click
            app.hideOverlay();
            // Give time for overlay to hide
            std.Thread.sleep(30 * std.time.ns_per_ms);

            const center_x = elem.x + elem.width / 2.0;
            const center_y = elem.y + elem.height / 2.0;

            switch (click_type) {
                .left => app.clickElement(elem),
                .right => app.rightClickElement(elem),
                .middle => click.performMiddleClick(center_x, center_y),
            }
            return true;
        }

        // Check if typed label is a prefix of this label (partial match)
        if (label_len > label.len and std.mem.startsWith(u8, elem_label[0..label_len], label)) {
            // Still typing, keep going
            return false;
        }

        i += 1;
    }

    // No match and no partial match - reset
    hotkey.typed_len = 0;
    return false;
}

fn drawElementLabels(app: *main.App) void {
    const elements = app.elements.items;
    const label_offset: i32 = 10; // Distance from element edge to label center

    var i: usize = 0;
    for (elements) |elem| {
        // Skip elements with zero size or off-screen
        if (elem.width <= 0 or elem.height <= 0) {
            i += 1;
            continue;
        }

        // Generate label for this element
        var label: [8]u8 = undefined;
        const label_len = generateLabel(i, &label);

        // Check if this label matches what user has typed
        const is_matching = hotkey.typed_len == 0 or std.mem.startsWith(u8, label[0..label_len], hotkey.typed_chars[0..hotkey.typed_len]);

        if (is_matching) {
            // Position label above or below element (not over it)
            const elem_x: i32 = @intFromFloat(elem.x);
            const elem_y: i32 = @intFromFloat(elem.y);
            const elem_h: i32 = @intFromFloat(elem.height);
            const elem_w: i32 = @intFromFloat(elem.width);

            // Center horizontally on element
            const x: i32 = elem_x + @divTrunc(elem_w, 2);

            // Put above by default, below if too close to top
            const above = elem_y > label_offset + 15;
            const y: i32 = if (above)
                elem_y - label_offset  // Above
            else
                elem_y + elem_h + label_offset;  // Below

            drawLabel(x, y, label[0..label_len], hotkey.typed_len, above);
        }

        i += 1;
    }
}

fn drawTextBold(text: *[16]u8, pos: rl.Vector2, font_size: f32, color: rl.Color) void {
    // Draw text twice with slight offset for fake bold effect
    if (font_loaded) {
        rl.DrawTextEx(custom_font, text, pos, font_size, 1, color);
        rl.DrawTextEx(custom_font, text, rl.Vector2{ .x = pos.x + 0.7, .y = pos.y }, font_size, 1, color);
    } else {
        const ix = @as(i32, @intFromFloat(pos.x));
        const iy = @as(i32, @intFromFloat(pos.y));
        const fs = @as(i32, @intFromFloat(font_size));
        rl.DrawText(text, ix, iy, fs, color);
        rl.DrawText(text, ix + 1, iy, fs, color);
    }
}

// Draw text with outline (stroke effect)
fn drawTextOutlined(text: [*:0]const u8, pos: rl.Vector2, font_size: f32, fill_color: rl.Color, outline_color: rl.Color) void {
    const outline_offsets = [_][2]f32{
        .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 },
        .{ -1,  0 },            .{ 1,  0 },
        .{ -1,  1 }, .{ 0,  1 }, .{ 1,  1 },
    };

    // Draw outline by rendering text at offsets
    for (outline_offsets) |offset| {
        const outline_pos = rl.Vector2{ .x = pos.x + offset[0], .y = pos.y + offset[1] };
        if (font_loaded) {
            rl.DrawTextEx(custom_font, text, outline_pos, font_size, 1, outline_color);
        } else {
            rl.DrawText(text, @intFromFloat(outline_pos.x), @intFromFloat(outline_pos.y), @intFromFloat(font_size), outline_color);
        }
    }

    // Draw fill on top
    if (font_loaded) {
        rl.DrawTextEx(custom_font, text, pos, font_size, 1, fill_color);
    } else {
        rl.DrawText(text, @intFromFloat(pos.x), @intFromFloat(pos.y), @intFromFloat(font_size), fill_color);
    }
}

fn drawLabel(x: i32, y: i32, label: []const u8, highlight_len: usize, points_down: bool) void {
    const font_size: f32 = 21;
    const outline_color = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 }; // Black outline
    const bg_color = rl.Color{ .r = 30, .g = 30, .b = 35, .a = 200 }; // Translucent dark background

    // Prepare null-terminated string
    var label_z: [16]u8 = undefined;
    @memcpy(label_z[0..label.len], label);
    label_z[label.len] = 0;

    // Measure text to center it
    const text_size = if (font_loaded)
        rl.MeasureTextEx(custom_font, &label_z, font_size, 1)
    else
        rl.Vector2{ .x = @floatFromInt(rl.MeasureText(&label_z, @intFromFloat(font_size))), .y = font_size };

    const cx: f32 = @floatFromInt(x);
    const cy: f32 = @floatFromInt(y);

    // Calculate circle radius based on text size
    const padding: f32 = 4;
    const radius: f32 = (@max(text_size.x, text_size.y) / 2 + padding) * 0.75;

    // Draw translucent circular background with green border
    rl.DrawCircle(x, y, radius, bg_color);
    rl.DrawCircleLines(x, y, radius, LABEL_BG);

    // Draw arrow pointing to target
    const arrow_size: f32 = 6;
    const arrow_offset: f32 = radius + 2;
    if (points_down) {
        // Arrow pointing down (label is above target)
        const arrow_y = cy + arrow_offset;
        rl.DrawTriangle(
            rl.Vector2{ .x = cx, .y = arrow_y + arrow_size },           // Bottom point
            rl.Vector2{ .x = cx + arrow_size, .y = arrow_y },           // Top right
            rl.Vector2{ .x = cx - arrow_size, .y = arrow_y },           // Top left
            LABEL_BG
        );
    } else {
        // Arrow pointing up (label is below target)
        const arrow_y = cy - arrow_offset;
        rl.DrawTriangle(
            rl.Vector2{ .x = cx, .y = arrow_y - arrow_size },           // Top point
            rl.Vector2{ .x = cx - arrow_size, .y = arrow_y },           // Bottom left
            rl.Vector2{ .x = cx + arrow_size, .y = arrow_y },           // Bottom right
            LABEL_BG
        );
    }

    // Center text at position
    const text_x = cx - text_size.x / 2;
    const text_y = cy - font_size / 2;
    const pos = rl.Vector2{ .x = text_x, .y = text_y };

    // Draw text with outline - highlight already-typed portion
    const highlight_color = rl.Color{ .r = 255, .g = 80, .b = 80, .a = 255 }; // Bright red for typed

    if (highlight_len > 0 and highlight_len <= label.len) {
        // Draw highlighted (typed) portion in red
        var typed_z: [16]u8 = undefined;
        @memcpy(typed_z[0..highlight_len], label[0..highlight_len]);
        typed_z[highlight_len] = 0;

        drawTextOutlined(@ptrCast(&typed_z), pos, font_size, highlight_color, outline_color);

        // Draw remaining portion in green
        if (highlight_len < label.len) {
            const typed_size = if (font_loaded)
                rl.MeasureTextEx(custom_font, &typed_z, font_size, 1)
            else
                rl.Vector2{ .x = @floatFromInt(rl.MeasureText(&typed_z, @intFromFloat(font_size))), .y = font_size };

            var rest_z: [16]u8 = undefined;
            const rest_len = label.len - highlight_len;
            @memcpy(rest_z[0..rest_len], label[highlight_len..label.len]);
            rest_z[rest_len] = 0;

            const rest_pos = rl.Vector2{ .x = pos.x + typed_size.x, .y = pos.y };
            drawTextOutlined(@ptrCast(&rest_z), rest_pos, font_size, LABEL_BG, outline_color);
        }
    } else {
        // Draw full label in green with black outline
        drawTextOutlined(@ptrCast(&label_z), pos, font_size, LABEL_BG, outline_color);
    }
}

fn drawHintBar(app: *main.App) void {
    const screen_w = rl.GetScreenWidth();
    const bar_h: i32 = 36;
    const bar_y = rl.GetScreenHeight() - bar_h;

    // Semi-transparent background
    rl.DrawRectangle(0, bar_y, screen_w, bar_h, HINT_BG);

    // Typed characters
    var typed_display: [64]u8 = undefined;
    var display_len: usize = 0;

    if (hotkey.typed_len > 0) {
        const prefix = "Type: ";
        @memcpy(typed_display[0..prefix.len], prefix);
        @memcpy(typed_display[prefix.len..prefix.len + hotkey.typed_len], hotkey.typed_chars[0..hotkey.typed_len]);
        display_len = prefix.len + hotkey.typed_len;
    } else {
        const hint = "Type label to click | Esc: Close";
        @memcpy(typed_display[0..hint.len], hint);
        display_len = hint.len;
    }
    typed_display[display_len] = 0;

    const hint_size: f32 = 18;
    const text_size = if (font_loaded)
        rl.MeasureTextEx(custom_font, &typed_display, hint_size, 1)
    else
        rl.Vector2{ .x = @floatFromInt(rl.MeasureText(&typed_display, @intFromFloat(hint_size))), .y = hint_size };

    const text_x = @divTrunc(screen_w - @as(i32, @intFromFloat(text_size.x)), 2);
    const text_pos = rl.Vector2{ .x = @floatFromInt(text_x), .y = @floatFromInt(bar_y + 9) };

    if (font_loaded) {
        rl.DrawTextEx(custom_font, &typed_display, text_pos, hint_size, 1, HINT_TEXT);
    } else {
        rl.DrawText(&typed_display, text_x, bar_y + 9, @intFromFloat(hint_size), HINT_TEXT);
    }

    // Element count on right
    var count_buf: [32]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d} elements", .{app.elements.items.len}) catch "? elements";
    var count_z: [32]u8 = undefined;
    @memcpy(count_z[0..count_str.len], count_str);
    count_z[count_str.len] = 0;

    const count_size: f32 = 16;
    const count_text_size = if (font_loaded)
        rl.MeasureTextEx(custom_font, &count_z, count_size, 1)
    else
        rl.Vector2{ .x = @floatFromInt(rl.MeasureText(&count_z, @intFromFloat(count_size))), .y = count_size };

    const count_x = screen_w - @as(i32, @intFromFloat(count_text_size.x)) - 16;
    const count_pos = rl.Vector2{ .x = @floatFromInt(count_x), .y = @floatFromInt(bar_y + 10) };
    const count_color = rl.Color{ .r = 160, .g = 160, .b = 170, .a = 255 };

    if (font_loaded) {
        rl.DrawTextEx(custom_font, &count_z, count_pos, count_size, 1, count_color);
    } else {
        rl.DrawText(&count_z, count_x, bar_y + 10, @intFromFloat(count_size), count_color);
    }
}

fn generateLabel(index: usize, buf: *[8]u8) usize {
    // Single letters: left hand first (ASDFG, QWERT, ZXCVB), then right hand
    const singles = "ASDFGQWERTZCXVBHJKLYUIOPNM";

    // Two-letter combos: left-hand only first (highest priority)
    const left_hand_combos = [_][2]u8{
        // Home row combos (easiest)
        .{ 'A', 'S' }, .{ 'A', 'D' }, .{ 'A', 'F' }, .{ 'S', 'A' }, .{ 'S', 'D' }, .{ 'S', 'F' },
        .{ 'D', 'A' }, .{ 'D', 'S' }, .{ 'D', 'F' }, .{ 'F', 'A' }, .{ 'F', 'S' }, .{ 'F', 'D' },
        .{ 'F', 'G' }, .{ 'G', 'F' }, .{ 'G', 'D' }, .{ 'G', 'S' }, .{ 'G', 'A' },
        // Home + top row
        .{ 'A', 'Q' }, .{ 'A', 'W' }, .{ 'A', 'E' }, .{ 'A', 'R' }, .{ 'A', 'T' },
        .{ 'S', 'Q' }, .{ 'S', 'W' }, .{ 'S', 'E' }, .{ 'S', 'R' }, .{ 'S', 'T' },
        .{ 'D', 'Q' }, .{ 'D', 'W' }, .{ 'D', 'E' }, .{ 'D', 'R' }, .{ 'D', 'T' },
        .{ 'F', 'Q' }, .{ 'F', 'W' }, .{ 'F', 'E' }, .{ 'F', 'R' }, .{ 'F', 'T' },
        .{ 'G', 'Q' }, .{ 'G', 'W' }, .{ 'G', 'E' }, .{ 'G', 'R' }, .{ 'G', 'T' },
        // Home + bottom row
        .{ 'A', 'Z' }, .{ 'A', 'X' }, .{ 'A', 'C' }, .{ 'A', 'V' }, .{ 'A', 'B' },
        .{ 'S', 'Z' }, .{ 'S', 'X' }, .{ 'S', 'C' }, .{ 'S', 'V' }, .{ 'S', 'B' },
        .{ 'D', 'Z' }, .{ 'D', 'X' }, .{ 'D', 'C' }, .{ 'D', 'V' }, .{ 'D', 'B' },
        .{ 'F', 'Z' }, .{ 'F', 'X' }, .{ 'F', 'C' }, .{ 'F', 'V' }, .{ 'F', 'B' },
        .{ 'G', 'Z' }, .{ 'G', 'X' }, .{ 'G', 'C' }, .{ 'G', 'V' }, .{ 'G', 'B' },
        // Top row combos
        .{ 'Q', 'W' }, .{ 'Q', 'E' }, .{ 'Q', 'R' }, .{ 'Q', 'A' }, .{ 'Q', 'S' },
        .{ 'W', 'Q' }, .{ 'W', 'E' }, .{ 'W', 'R' }, .{ 'W', 'A' }, .{ 'W', 'S' }, .{ 'W', 'D' },
        .{ 'E', 'Q' }, .{ 'E', 'W' }, .{ 'E', 'R' }, .{ 'E', 'T' }, .{ 'E', 'A' }, .{ 'E', 'S' }, .{ 'E', 'D' }, .{ 'E', 'F' },
        .{ 'R', 'Q' }, .{ 'R', 'W' }, .{ 'R', 'E' }, .{ 'R', 'T' }, .{ 'R', 'A' }, .{ 'R', 'S' }, .{ 'R', 'D' }, .{ 'R', 'F' }, .{ 'R', 'G' },
        .{ 'T', 'Q' }, .{ 'T', 'W' }, .{ 'T', 'E' }, .{ 'T', 'R' }, .{ 'T', 'A' }, .{ 'T', 'S' }, .{ 'T', 'D' }, .{ 'T', 'F' }, .{ 'T', 'G' },
        // Bottom row combos
        .{ 'Z', 'X' }, .{ 'Z', 'A' }, .{ 'Z', 'S' },
        .{ 'X', 'Z' }, .{ 'X', 'C' }, .{ 'X', 'A' }, .{ 'X', 'S' }, .{ 'X', 'D' },
        .{ 'C', 'Z' }, .{ 'C', 'X' }, .{ 'C', 'V' }, .{ 'C', 'A' }, .{ 'C', 'S' }, .{ 'C', 'D' }, .{ 'C', 'F' },
        .{ 'V', 'X' }, .{ 'V', 'C' }, .{ 'V', 'B' }, .{ 'V', 'A' }, .{ 'V', 'S' }, .{ 'V', 'D' }, .{ 'V', 'F' }, .{ 'V', 'G' },
        .{ 'B', 'C' }, .{ 'B', 'V' }, .{ 'B', 'D' }, .{ 'B', 'F' }, .{ 'B', 'G' },
    };

    if (index < singles.len) {
        buf[0] = singles[index];
        return 1;
    }

    const combo_index = index - singles.len;
    if (combo_index < left_hand_combos.len) {
        buf[0] = left_hand_combos[combo_index][0];
        buf[1] = left_hand_combos[combo_index][1];
        return 2;
    }

    // Fallback: right hand and mixed combos
    const distant_idx = combo_index - left_hand_combos.len;
    const left = "ASDFGQWERTZCXVB";
    const right = "HJKLYUIOPNM";

    // First use right-hand only combos
    if (distant_idx < right.len * right.len) {
        buf[0] = right[distant_idx / right.len];
        buf[1] = right[distant_idx % right.len];
        return 2;
    }

    // Then mixed combos
    const mixed_idx = distant_idx - (right.len * right.len);
    buf[0] = left[mixed_idx / 26 % left.len];
    buf[1] = right[mixed_idx % right.len];
    return 2;
}
