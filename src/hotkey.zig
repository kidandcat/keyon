const std = @import("std");
const main = @import("main.zig");

// CoreGraphics API for event tap (alternative to Carbon hotkeys)
const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

var global_app: ?*main.App = null;
var event_tap: c.CFMachPortRef = null;
var run_loop_source: c.CFRunLoopSourceRef = null;

// Key codes
const KEY_LESS_THAN: u16 = 50; // < key (dedicated key on international keyboards)

// Modifier flags
const kCGEventFlagMaskCommand: u64 = 0x100000;
const kCGEventFlagMaskShift: u64 = 0x20000;

pub fn register(app: *main.App) !void {
    global_app = app;

    // Create event tap to monitor key events
    const event_mask: c.CGEventMask = (1 << c.kCGEventKeyDown);

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
pub var click_at_mouse: bool = false;
pub var move_mouse_x: i32 = 0;
pub var move_mouse_y: i32 = 0;
pub var scroll_x: i32 = 0;
pub var scroll_y: i32 = 0;

fn eventCallback(
    proxy: c.CGEventTapProxy,
    event_type: c.CGEventType,
    event: c.CGEventRef,
    user_info: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    _ = proxy;
    _ = user_info;

    if (event_type == c.kCGEventKeyDown) {
        const keycode = c.CGEventGetIntegerValueField(event, c.kCGKeyboardEventKeycode);
        const flags = c.CGEventGetFlags(event);

        const has_cmd = (flags & kCGEventFlagMaskCommand) != 0;

        // Check for Cmd+< toggle overlay
        if (keycode == KEY_LESS_THAN and has_cmd) {
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
                    app.hideOverlay();
                    return null;
                }

                // Enter or Space - click selected element or click at mouse
                if (keycode == KEY_RETURN or keycode == KEY_SPACE_TRIGGER) {
                    if (typed_len > 0) {
                        should_click = true;
                    } else {
                        click_at_mouse = true;
                    }
                    return null;
                }

                // Arrow keys - move mouse or scroll (with Shift)
                const has_shift = (flags & kCGEventFlagMaskShift) != 0;

                if (keycode == KEY_UP) {
                    if (has_shift) {
                        scroll_y = 3; // Scroll up (positive = up)
                    } else {
                        move_mouse_y = -10;
                    }
                    return null;
                }
                if (keycode == KEY_DOWN) {
                    if (has_shift) {
                        scroll_y = -3; // Scroll down (negative = down)
                    } else {
                        move_mouse_y = 10;
                    }
                    return null;
                }
                if (keycode == KEY_LEFT) {
                    if (has_shift) {
                        scroll_x = 3; // Scroll left (positive = left)
                    } else {
                        move_mouse_x = -10;
                    }
                    return null;
                }
                if (keycode == KEY_RIGHT) {
                    if (has_shift) {
                        scroll_x = -3; // Scroll right (negative = right)
                    } else {
                        move_mouse_x = 10;
                    }
                    return null;
                }

                // Backspace - delete character
                if (keycode == KEY_BACKSPACE) {
                    if (typed_len > 0) {
                        typed_len -= 1;
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

fn keycodeToChar(keycode: i64) u8 {
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
