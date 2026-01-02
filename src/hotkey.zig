const std = @import("std");
const main = @import("main.zig");

// CoreGraphics API for event tap (alternative to Carbon hotkeys)
const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

const statusbar = @cImport({
    @cInclude("statusbar.h");
});

var global_app: ?*main.App = null;
var event_tap: c.CFMachPortRef = null;
var run_loop_source: c.CFRunLoopSourceRef = null;

// Modifier flags
const kCGEventFlagMaskCommand: u64 = 0x100000;
const kCGEventFlagMaskShift: u64 = 0x20000;
const kCGEventFlagMaskOption: u64 = 0x80000;
const kCGEventFlagMaskControl: u64 = 0x40000;

pub fn register(app: *main.App) !void {
    global_app = app;

    // Create event tap to monitor key events (both down and up for smooth movement)
    const event_mask: c.CGEventMask = (1 << c.kCGEventKeyDown) | (1 << c.kCGEventKeyUp);

    event_tap = c.CGEventTapCreate(
        c.kCGSessionEventTap,
        c.kCGHeadInsertEventTap,
        c.kCGEventTapOptionDefault,
        event_mask,
        &eventCallback,
        null,
    );

    if (event_tap == null) {
        std.debug.print("Failed to create event tap. Make sure app has accessibility permissions.\n", .{});
        return error.FailedToCreateEventTap;
    }

    // Create run loop source
    run_loop_source = c.CFMachPortCreateRunLoopSource(null, event_tap, 0);

    if (run_loop_source == null) {
        c.CFRelease(event_tap);
        event_tap = null;
        return error.FailedToCreateRunLoopSource;
    }

    // Add to run loop
    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), run_loop_source, c.kCFRunLoopCommonModes);

    // Enable the tap
    c.CGEventTapEnable(event_tap, true);

    std.debug.print("Hotkey registered: Cmd+<\n", .{});
}

pub fn unregister() void {
    if (event_tap) |tap| {
        c.CGEventTapEnable(tap, false);
        c.CFRelease(tap);
        event_tap = null;
    }
    if (run_loop_source) |source| {
        c.CFRelease(source);
        run_loop_source = null;
    }
}

// Key codes for overlay input
const KEY_ESCAPE: u16 = 53;
const KEY_RETURN: u16 = 36;
const KEY_BACKSPACE: u16 = 51;
const KEY_SPACE_TRIGGER: u16 = 49;
const KEY_UP: u16 = 126;
const KEY_DOWN: u16 = 125;
const KEY_LEFT: u16 = 123;
const KEY_RIGHT: u16 = 124;

// Shared typed buffer for overlay
pub var typed_chars: [8]u8 = undefined;
pub var typed_len: usize = 0;
pub var should_click: bool = false;
pub var should_right_click: bool = false;
pub var should_middle_click: bool = false;
pub var click_at_mouse: bool = false;
pub var right_click_at_mouse: bool = false;
pub var middle_click_at_mouse: bool = false;
pub var scroll_x: i32 = 0;
pub var scroll_y: i32 = 0;

// Continuous mouse movement state
pub var arrow_up_held: bool = false;
pub var arrow_down_held: bool = false;
pub var arrow_left_held: bool = false;
pub var arrow_right_held: bool = false;
var movement_start_time: i64 = 0;

const BASE_SPEED: f32 = 150.0; // pixels per second
const MAX_SPEED: f32 = 2000.0; // pixels per second
const ACCEL_TIME: f32 = 1.0; // seconds to reach max speed

// Called from overlay loop to get current movement delta
pub fn getMouseMovement(delta_time: f32) struct { x: f32, y: f32 } {
    var dx: f32 = 0;
    var dy: f32 = 0;

    const any_held = arrow_up_held or arrow_down_held or arrow_left_held or arrow_right_held;

    if (!any_held) {
        movement_start_time = 0;
        return .{ .x = 0, .y = 0 };
    }

    const now = std.time.milliTimestamp();
    if (movement_start_time == 0) {
        movement_start_time = now;
    }

    // Calculate current speed based on how long keys have been held
    const elapsed_ms = now - movement_start_time;
    const elapsed_sec: f32 = @as(f32, @floatFromInt(elapsed_ms)) / 1000.0;
    const accel_progress = @min(elapsed_sec / ACCEL_TIME, 1.0);
    const current_speed = BASE_SPEED + (MAX_SPEED - BASE_SPEED) * accel_progress;

    const movement = current_speed * delta_time;

    if (arrow_up_held) dy -= movement;
    if (arrow_down_held) dy += movement;
    if (arrow_left_held) dx -= movement;
    if (arrow_right_held) dx += movement;

    return .{ .x = dx, .y = dy };
}

fn eventCallback(
    proxy: c.CGEventTapProxy,
    event_type: c.CGEventType,
    event: c.CGEventRef,
    user_info: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    _ = proxy;
    _ = user_info;

    const keycode = c.CGEventGetIntegerValueField(event, c.kCGKeyboardEventKeycode);
    const flags = c.CGEventGetFlags(event);

    // Handle key up events for arrow keys (release held state)
    if (event_type == c.kCGEventKeyUp) {
        if (global_app) |app| {
            if (app.overlay_visible) {
                if (keycode == KEY_UP) arrow_up_held = false;
                if (keycode == KEY_DOWN) arrow_down_held = false;
                if (keycode == KEY_LEFT) arrow_left_held = false;
                if (keycode == KEY_RIGHT) arrow_right_held = false;
                return null;
            }
        }
        return event;
    }

    if (event_type == c.kCGEventKeyDown) {
        // Check for dynamic hotkey toggle overlay (read current values from statusbar)
        const hotkey_keycode = statusbar.getCurrentHotkeyKeycode();
        const hotkey_modifiers = statusbar.getCurrentHotkeyModifiers();
        const modifier_mask = kCGEventFlagMaskCommand | kCGEventFlagMaskShift | kCGEventFlagMaskOption | kCGEventFlagMaskControl;
        const current_modifiers = flags & modifier_mask;

        if (keycode == hotkey_keycode and current_modifiers == hotkey_modifiers) {
            std.debug.print("Hotkey pressed!\n", .{});
            if (global_app) |app| {
                app.toggleOverlay();
            }
            return null;
        }

        // If overlay is visible, capture all keys
        if (global_app) |app| {
            if (app.overlay_visible) {
                // Escape - close overlay
                if (keycode == KEY_ESCAPE) {
                    // Reset arrow states
                    arrow_up_held = false;
                    arrow_down_held = false;
                    arrow_left_held = false;
                    arrow_right_held = false;
                    app.hideOverlay();
                    return null;
                }

                // Space - left click
                if (keycode == KEY_SPACE_TRIGGER) {
                    if (typed_len > 0) {
                        should_click = true;
                    } else {
                        click_at_mouse = true;
                    }
                    return null;
                }

                // Enter - right click
                if (keycode == KEY_RETURN) {
                    if (typed_len > 0) {
                        should_right_click = true;
                    } else {
                        right_click_at_mouse = true;
                    }
                    return null;
                }


                // Arrow keys - move mouse or scroll (with Shift)
                const has_shift = (flags & kCGEventFlagMaskShift) != 0;

                if (keycode == KEY_UP) {
                    if (has_shift) {
                        scroll_y = 3; // Scroll up
                    } else {
                        arrow_up_held = true;
                    }
                    return null;
                }
                if (keycode == KEY_DOWN) {
                    if (has_shift) {
                        scroll_y = -3; // Scroll down
                    } else {
                        arrow_down_held = true;
                    }
                    return null;
                }
                if (keycode == KEY_LEFT) {
                    if (has_shift) {
                        scroll_x = 3; // Scroll left
                    } else {
                        arrow_left_held = true;
                    }
                    return null;
                }
                if (keycode == KEY_RIGHT) {
                    if (has_shift) {
                        scroll_x = -3; // Scroll right
                    } else {
                        arrow_right_held = true;
                    }
                    return null;
                }

                // Backspace - delete character or middle click if no chars typed
                if (keycode == KEY_BACKSPACE) {
                    if (typed_len > 0) {
                        typed_len -= 1;
                    } else {
                        middle_click_at_mouse = true;
                    }
                    return null;
                }

                // A-Z keys (keycodes 0-5, 6-11, 12-17, etc. map to letters)
                const char = keycodeToChar(keycode);
                if (char != 0 and typed_len < typed_chars.len) {
                    typed_chars[typed_len] = char;
                    typed_len += 1;
                    return null;
                }

                // Suppress all other keys when overlay visible
                return null;
            }
        }
    }

    return event;
}

pub fn keycodeToChar(keycode: i64) u8 {
    // macOS keycodes for letters
    return switch (keycode) {
        0 => 'A',
        1 => 'S',
        2 => 'D',
        3 => 'F',
        4 => 'H',
        5 => 'G',
        6 => 'Z',
        7 => 'X',
        8 => 'C',
        9 => 'V',
        11 => 'B',
        12 => 'Q',
        13 => 'W',
        14 => 'E',
        15 => 'R',
        16 => 'Y',
        17 => 'T',
        31 => 'O',
        32 => 'U',
        34 => 'I',
        35 => 'P',
        37 => 'L',
        38 => 'J',
        40 => 'K',
        45 => 'N',
        46 => 'M',
        else => 0,
    };
}

pub fn runEventLoop() void {
    // Run the CoreFoundation run loop
    c.CFRunLoopRun();
}

pub fn processEvents() void {
    // Process pending events with a short timeout (non-blocking)
    _ = c.CFRunLoopRunInMode(c.kCFRunLoopDefaultMode, 0.01, 1);
}

pub fn stopEventLoop() void {
    c.CFRunLoopStop(c.CFRunLoopGetCurrent());
}

// Tests
test "keycodeToChar QWERTY row" {
    try std.testing.expectEqual(@as(u8, 'Q'), keycodeToChar(12));
    try std.testing.expectEqual(@as(u8, 'W'), keycodeToChar(13));
    try std.testing.expectEqual(@as(u8, 'E'), keycodeToChar(14));
    try std.testing.expectEqual(@as(u8, 'R'), keycodeToChar(15));
    try std.testing.expectEqual(@as(u8, 'T'), keycodeToChar(17));
    try std.testing.expectEqual(@as(u8, 'Y'), keycodeToChar(16));
    try std.testing.expectEqual(@as(u8, 'U'), keycodeToChar(32));
    try std.testing.expectEqual(@as(u8, 'I'), keycodeToChar(34));
    try std.testing.expectEqual(@as(u8, 'O'), keycodeToChar(31));
    try std.testing.expectEqual(@as(u8, 'P'), keycodeToChar(35));
}

test "keycodeToChar ASDF row" {
    try std.testing.expectEqual(@as(u8, 'A'), keycodeToChar(0));
    try std.testing.expectEqual(@as(u8, 'S'), keycodeToChar(1));
    try std.testing.expectEqual(@as(u8, 'D'), keycodeToChar(2));
    try std.testing.expectEqual(@as(u8, 'F'), keycodeToChar(3));
    try std.testing.expectEqual(@as(u8, 'G'), keycodeToChar(5));
    try std.testing.expectEqual(@as(u8, 'H'), keycodeToChar(4));
    try std.testing.expectEqual(@as(u8, 'J'), keycodeToChar(38));
    try std.testing.expectEqual(@as(u8, 'K'), keycodeToChar(40));
    try std.testing.expectEqual(@as(u8, 'L'), keycodeToChar(37));
}

test "keycodeToChar ZXCV row" {
    try std.testing.expectEqual(@as(u8, 'Z'), keycodeToChar(6));
    try std.testing.expectEqual(@as(u8, 'X'), keycodeToChar(7));
    try std.testing.expectEqual(@as(u8, 'C'), keycodeToChar(8));
    try std.testing.expectEqual(@as(u8, 'V'), keycodeToChar(9));
    try std.testing.expectEqual(@as(u8, 'B'), keycodeToChar(11));
    try std.testing.expectEqual(@as(u8, 'N'), keycodeToChar(45));
    try std.testing.expectEqual(@as(u8, 'M'), keycodeToChar(46));
}

test "keycodeToChar unknown returns 0" {
    try std.testing.expectEqual(@as(u8, 0), keycodeToChar(100));
    try std.testing.expectEqual(@as(u8, 0), keycodeToChar(-1));
    try std.testing.expectEqual(@as(u8, 0), keycodeToChar(50)); // ` key
}

test "getMouseMovement returns zero when no keys held" {
    // Reset state
    arrow_up_held = false;
    arrow_down_held = false;
    arrow_left_held = false;
    arrow_right_held = false;
    movement_start_time = 0;

    const result = getMouseMovement(0.016); // ~60fps
    try std.testing.expectEqual(@as(f32, 0), result.x);
    try std.testing.expectEqual(@as(f32, 0), result.y);
}

test "getMouseMovement returns non-zero when up held" {
    arrow_up_held = true;
    arrow_down_held = false;
    arrow_left_held = false;
    arrow_right_held = false;
    movement_start_time = 0;

    const result = getMouseMovement(0.016);
    try std.testing.expect(result.y < 0); // Moving up = negative y
    try std.testing.expectEqual(@as(f32, 0), result.x);

    // Cleanup
    arrow_up_held = false;
    movement_start_time = 0;
}

test "getMouseMovement returns non-zero when down held" {
    arrow_up_held = false;
    arrow_down_held = true;
    arrow_left_held = false;
    arrow_right_held = false;
    movement_start_time = 0;

    const result = getMouseMovement(0.016);
    try std.testing.expect(result.y > 0); // Moving down = positive y
    try std.testing.expectEqual(@as(f32, 0), result.x);

    // Cleanup
    arrow_down_held = false;
    movement_start_time = 0;
}

test "getMouseMovement returns non-zero when left held" {
    arrow_up_held = false;
    arrow_down_held = false;
    arrow_left_held = true;
    arrow_right_held = false;
    movement_start_time = 0;

    const result = getMouseMovement(0.016);
    try std.testing.expect(result.x < 0); // Moving left = negative x
    try std.testing.expectEqual(@as(f32, 0), result.y);

    // Cleanup
    arrow_left_held = false;
    movement_start_time = 0;
}

test "getMouseMovement returns non-zero when right held" {
    arrow_up_held = false;
    arrow_down_held = false;
    arrow_left_held = false;
    arrow_right_held = true;
    movement_start_time = 0;

    const result = getMouseMovement(0.016);
    try std.testing.expect(result.x > 0); // Moving right = positive x
    try std.testing.expectEqual(@as(f32, 0), result.y);

    // Cleanup
    arrow_right_held = false;
    movement_start_time = 0;
}

test "getMouseMovement diagonal movement" {
    arrow_up_held = true;
    arrow_right_held = true;
    arrow_down_held = false;
    arrow_left_held = false;
    movement_start_time = 0;

    const result = getMouseMovement(0.016);
    try std.testing.expect(result.x > 0); // Right
    try std.testing.expect(result.y < 0); // Up

    // Cleanup
    arrow_up_held = false;
    arrow_right_held = false;
    movement_start_time = 0;
}

test "speed constants are reasonable" {
    try std.testing.expect(BASE_SPEED > 0);
    try std.testing.expect(MAX_SPEED > BASE_SPEED);
    try std.testing.expect(ACCEL_TIME > 0);
}
