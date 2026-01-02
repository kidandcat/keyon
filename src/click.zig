const std = @import("std");

const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("stdlib.h");
});

var target_pid: c.pid_t = 0;

pub fn setTargetPid(pid: c.pid_t) void {
    target_pid = pid;
}

pub fn activateTargetApp() void {
    if (target_pid != 0) {
        var cmd_buf: [256]u8 = undefined;
        const cmd = std.fmt.bufPrint(&cmd_buf, "osascript -e 'tell application \"System Events\" to set frontmost of (first process whose unix id is {d}) to true' 2>/dev/null", .{target_pid}) catch return;
        if (cmd.len < cmd_buf.len) {
            cmd_buf[cmd.len] = 0;
            _ = c.system(&cmd_buf);
        }
    }
}

// Get current mouse location (like robotgo's location())
fn getMouseLocation() c.CGPoint {
    const event = c.CGEventCreate(null);
    if (event) |ev| {
        defer c.CFRelease(ev);
        return c.CGEventGetLocation(ev);
    }
    return c.CGPoint{ .x = 0, .y = 0 };
}

// Move mouse (like robotgo's moveMouse)
pub fn moveMouse(x: f32, y: f32) void {
    const point = c.CGPoint{ .x = @floatCast(x), .y = @floatCast(y) };

    // Create event source (like robotgo)
    const source = c.CGEventSourceCreate(c.kCGEventSourceStateHIDSystemState);
    defer if (source) |s| c.CFRelease(s);

    // Create move event
    const move = c.CGEventCreateMouseEvent(source, c.kCGEventMouseMoved, point, c.kCGMouseButtonLeft);
    if (move) |m| {
        defer c.CFRelease(m);

        // Set delta fields (like robotgo's calculateDeltas)
        const current = getMouseLocation();
        const dx = point.x - current.x;
        const dy = point.y - current.y;
        c.CGEventSetIntegerValueField(m, c.kCGMouseEventDeltaX, @intFromFloat(dx));
        c.CGEventSetIntegerValueField(m, c.kCGMouseEventDeltaY, @intFromFloat(dy));

        // Post to HID tap (like robotgo)
        c.CGEventPost(c.kCGHIDEventTap, m);
    }
}

// Toggle mouse button (like robotgo's toggleMouse)
fn toggleMouse(down: bool, button: c.CGMouseButton) void {
    // Get current position (like robotgo)
    const currentPos = getMouseLocation();

    // Determine event type
    const eventType: c.CGEventType = if (button == c.kCGMouseButtonLeft)
        (if (down) c.kCGEventLeftMouseDown else c.kCGEventLeftMouseUp)
    else
        (if (down) c.kCGEventRightMouseDown else c.kCGEventRightMouseUp);

    // Create event source (like robotgo)
    const source = c.CGEventSourceCreate(c.kCGEventSourceStateHIDSystemState);
    defer if (source) |s| c.CFRelease(s);

    // Create mouse event at current position
    const event = c.CGEventCreateMouseEvent(source, eventType, currentPos, button);
    if (event) |ev| {
        defer c.CFRelease(ev);
        c.CGEventPost(c.kCGHIDEventTap, ev);
    }
}

// Click mouse (like robotgo's clickMouse)
fn clickMouse(button: c.CGMouseButton) void {
    toggleMouse(true, button);
    std.Thread.sleep(5 * std.time.ns_per_ms); // 5ms like robotgo's microsleep(5.0)
    toggleMouse(false, button);
}

// Main click function - use cliclick for reliability
pub fn performClick(x: f32, y: f32) void {
    const xi: i32 = @intFromFloat(x);
    const yi: i32 = @intFromFloat(y);

    // Run in background with delay to let overlay hide
    var cmd_buf: [512]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf,
        "(sleep 0.2; /usr/bin/osascript -e 'tell application \"System Events\" to set frontmost of (first process whose unix id is {d}) to true'; sleep 0.1; /opt/homebrew/bin/cliclick c:{d},{d}) &",
        .{ target_pid, xi, yi }
    ) catch return;

    if (cmd.len < cmd_buf.len) {
        cmd_buf[cmd.len] = 0;
        _ = c.system(&cmd_buf);
    }

    std.debug.print("Clicked at ({d}, {d})\n", .{ xi, yi });
}

pub fn performRightClick(x: f32, y: f32) void {
    // Activate target app first
    activateTargetApp();
    std.Thread.sleep(200 * std.time.ns_per_ms);

    const point = c.CGPoint{
        .x = @floatCast(x),
        .y = @floatCast(y),
    };

    const mouse_down = c.CGEventCreateMouseEvent(
        null,
        c.kCGEventRightMouseDown,
        point,
        c.kCGMouseButtonRight,
    );
    defer if (mouse_down) |e| c.CFRelease(e);

    const mouse_up = c.CGEventCreateMouseEvent(
        null,
        c.kCGEventRightMouseUp,
        point,
        c.kCGMouseButtonRight,
    );
    defer if (mouse_up) |e| c.CFRelease(e);

    if (mouse_down) |down| {
        c.CGEventPost(c.kCGHIDEventTap, down);
    }

    std.Thread.sleep(10 * std.time.ns_per_ms);

    if (mouse_up) |up| {
        c.CGEventPost(c.kCGHIDEventTap, up);
    }
}

// Scroll at current mouse position (based on robotgo implementation)
pub fn performScroll(dx: i32, dy: i32) void {
    std.debug.print("Scrolling: dx={d}, dy={d}\n", .{ dx, dy });

    const source = c.CGEventSourceCreate(c.kCGEventSourceStateHIDSystemState);
    defer if (source) |s| c.CFRelease(s);

    // Use pixel-based scrolling with 2 axes (like robotgo)
    // y is vertical (positive = up), x is horizontal (positive = left)
    const scroll_event = c.CGEventCreateScrollWheelEvent(
        source,
        c.kCGScrollEventUnitPixel,
        2, // 2 axes
        dy * 50, // vertical scroll (multiply for more movement)
        dx * 50, // horizontal scroll
    );

    if (scroll_event) |ev| {
        defer c.CFRelease(ev);
        c.CGEventPost(c.kCGHIDEventTap, ev);
    }
}

pub fn performMiddleClick(x: f32, y: f32) void {
    // Activate target app first
    activateTargetApp();
    std.Thread.sleep(200 * std.time.ns_per_ms);

    const point = c.CGPoint{
        .x = @floatCast(x),
        .y = @floatCast(y),
    };

    const mouse_down = c.CGEventCreateMouseEvent(
        null,
        c.kCGEventOtherMouseDown,
        point,
        c.kCGMouseButtonCenter,
    );
    defer if (mouse_down) |e| c.CFRelease(e);

    const mouse_up = c.CGEventCreateMouseEvent(
        null,
        c.kCGEventOtherMouseUp,
        point,
        c.kCGMouseButtonCenter,
    );
    defer if (mouse_up) |e| c.CFRelease(e);

    if (mouse_down) |down| {
        c.CGEventPost(c.kCGHIDEventTap, down);
    }

    std.Thread.sleep(10 * std.time.ns_per_ms);

    if (mouse_up) |up| {
        c.CGEventPost(c.kCGHIDEventTap, up);
    }
}

pub fn performDoubleClick(x: f32, y: f32) void {
    // Activate target app first
    activateTargetApp();
    std.Thread.sleep(200 * std.time.ns_per_ms);

    const point = c.CGPoint{
        .x = @floatCast(x),
        .y = @floatCast(y),
    };

    // First click
    const down1 = c.CGEventCreateMouseEvent(null, c.kCGEventLeftMouseDown, point, c.kCGMouseButtonLeft);
    const up1 = c.CGEventCreateMouseEvent(null, c.kCGEventLeftMouseUp, point, c.kCGMouseButtonLeft);
    defer if (down1) |e| c.CFRelease(e);
    defer if (up1) |e| c.CFRelease(e);

    // Set click count to 1
    if (down1) |d| c.CGEventSetIntegerValueField(d, c.kCGMouseEventClickState, 1);
    if (up1) |u| c.CGEventSetIntegerValueField(u, c.kCGMouseEventClickState, 1);

    // Second click
    const down2 = c.CGEventCreateMouseEvent(null, c.kCGEventLeftMouseDown, point, c.kCGMouseButtonLeft);
    const up2 = c.CGEventCreateMouseEvent(null, c.kCGEventLeftMouseUp, point, c.kCGMouseButtonLeft);
    defer if (down2) |e| c.CFRelease(e);
    defer if (up2) |e| c.CFRelease(e);

    // Set click count to 2
    if (down2) |d| c.CGEventSetIntegerValueField(d, c.kCGMouseEventClickState, 2);
    if (up2) |u| c.CGEventSetIntegerValueField(u, c.kCGMouseEventClickState, 2);

    // Post all events
    if (down1) |d| c.CGEventPost(c.kCGHIDEventTap, d);
    if (up1) |u| c.CGEventPost(c.kCGHIDEventTap, u);
    if (down2) |d| c.CGEventPost(c.kCGHIDEventTap, d);
    if (up2) |u| c.CGEventPost(c.kCGHIDEventTap, u);
}
