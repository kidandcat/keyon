const std = @import("std");
const UIElement = @import("ui_element.zig").UIElement;

// macOS Accessibility API bindings
const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

// Define string constants manually since CFSTR macro can't be translated
extern fn CFStringCreateWithCString(alloc: c.CFAllocatorRef, cStr: [*:0]const u8, encoding: c.CFStringEncoding) c.CFStringRef;

fn makeCFString(str: [*:0]const u8) c.CFStringRef {
    return CFStringCreateWithCString(null, str, c.kCFStringEncodingUTF8);
}

pub fn isTrusted() bool {
    return c.AXIsProcessTrusted() != 0;
}

pub fn requestPermissions() void {
    // Create options dictionary with prompt
    const key = c.kAXTrustedCheckOptionPrompt;
    const value: c.CFBooleanRef = c.kCFBooleanTrue;

    var keys = [_]?*const anyopaque{@ptrCast(key)};
    var values = [_]?*const anyopaque{@ptrCast(value)};

    const options = c.CFDictionaryCreate(
        null,
        @ptrCast(&keys),
        @ptrCast(&values),
        1,
        &c.kCFTypeDictionaryKeyCallBacks,
        &c.kCFTypeDictionaryValueCallBacks,
    );
    defer if (options) |o| c.CFRelease(o);

    _ = c.AXIsProcessTrustedWithOptions(options);
}

pub fn getFrontmostPid() ?c.pid_t {
    return getFrontmostAppPid();
}

pub fn scanFrontmostApp(allocator: std.mem.Allocator) ![]UIElement {
    const pid = getFrontmostAppPid() orelse {
        std.debug.print("Could not get frontmost app PID\n", .{});
        return error.NoFrontmostApp;
    };
    return scanApp(pid, allocator);
}

// Scan timeout in milliseconds
const SCAN_TIMEOUT_MS: i64 = 500;
var scan_start_time: i64 = 0;
var scan_timed_out: bool = false;

pub fn scanApp(pid: c.pid_t, allocator: std.mem.Allocator) ![]UIElement {
    // Reset string buffer and timeout state
    string_offset = 0;
    scan_start_time = std.time.milliTimestamp();
    scan_timed_out = false;


    // Create AXUIElement for the application
    const app_element = c.AXUIElementCreateApplication(pid);
    defer c.CFRelease(app_element);

    // Scan all clickable elements
    var elements = std.ArrayListUnmanaged(UIElement){};
    errdefer elements.deinit(allocator);

    scanElement(app_element, &elements, allocator, 0, 10) catch |err| {
        if (err != error.ScanTimeout) {
            return err;
        }
    };

    return elements.toOwnedSlice(allocator);
}

fn getFrontmostAppPid() ?c.pid_t {
    // Use CGWindowListCopyWindowInfo to get the frontmost window's owner
    const window_list = c.CGWindowListCopyWindowInfo(
        c.kCGWindowListOptionOnScreenOnly | c.kCGWindowListExcludeDesktopElements,
        c.kCGNullWindowID,
    );

    if (window_list == null) return null;
    defer c.CFRelease(window_list);

    const count = c.CFArrayGetCount(window_list);
    if (count == 0) return null;

    // The first window in the list is typically the frontmost
    // Skip our own windows and system UI windows
    const our_pid = std.c.getpid();

    const pid_key = makeCFString("kCGWindowOwnerPID");
    defer c.CFRelease(pid_key);
    const name_key = makeCFString("kCGWindowOwnerName");
    defer c.CFRelease(name_key);
    const layer_key = makeCFString("kCGWindowLayer");
    defer c.CFRelease(layer_key);

    // System UI apps to skip
    const system_apps = [_][]const u8{
        "Control Center",
        "SystemUIServer",
        "Notification Center",
        "Spotlight",
        "WindowManager",
        "Window Server",
        "Dock",
    };

    var i: c.CFIndex = 0;
    while (i < count) : (i += 1) {
        const window_info = c.CFArrayGetValueAtIndex(window_list, i);
        if (window_info == null) continue;

        const dict: c.CFDictionaryRef = @ptrCast(window_info);

        // Check window layer - only consider normal windows (layer 0)
        var layer_ref: ?*const anyopaque = null;
        if (c.CFDictionaryGetValueIfPresent(dict, @ptrCast(layer_key), &layer_ref) != 0) {
            if (layer_ref) |l| {
                var layer: c_int = 0;
                if (c.CFNumberGetValue(@ptrCast(l), c.kCFNumberIntType, &layer) != 0) {
                    if (layer != 0) continue; // Skip non-normal windows (menu bars, etc.)
                }
            }
        }

        // Get window owner name to filter system apps
        var name_ref: ?*const anyopaque = null;
        if (c.CFDictionaryGetValueIfPresent(dict, @ptrCast(name_key), &name_ref) != 0) {
            if (name_ref) |n| {
                const app_name = cfStringToSlice(@ptrCast(n));

                // Skip system UI apps
                var is_system = false;
                for (system_apps) |sys_app| {
                    if (std.mem.eql(u8, app_name, sys_app)) {
                        is_system = true;
                        break;
                    }
                }
                if (is_system) continue;

            }
        }

        var pid_ref: ?*const anyopaque = null;
        if (c.CFDictionaryGetValueIfPresent(dict, @ptrCast(pid_key), &pid_ref) != 0) {
            if (pid_ref) |p| {
                var pid: c_int = 0;
                if (c.CFNumberGetValue(@ptrCast(p), c.kCFNumberIntType, &pid) != 0) {
                    // Skip our own process
                    if (pid != our_pid) {
                        return @intCast(pid);
                    }
                }
            }
        }
    }

    return null;
}

fn scanElement(element: c.AXUIElementRef, elements: *std.ArrayListUnmanaged(UIElement), allocator: std.mem.Allocator, depth: usize, max_depth: usize) !void {
    // Check timeout
    const elapsed = std.time.milliTimestamp() - scan_start_time;
    if (elapsed > SCAN_TIMEOUT_MS) {
        scan_timed_out = true;
        return error.ScanTimeout;
    }

    if (depth > max_depth) return;

    // Attribute strings
    const role_attr = makeCFString("AXRole");
    defer c.CFRelease(role_attr);
    const title_attr = makeCFString("AXTitle");
    defer c.CFRelease(title_attr);
    const desc_attr = makeCFString("AXDescription");
    defer c.CFRelease(desc_attr);
    const pos_attr = makeCFString("AXPosition");
    defer c.CFRelease(pos_attr);
    const size_attr = makeCFString("AXSize");
    defer c.CFRelease(size_attr);
    const enabled_attr = makeCFString("AXEnabled");
    defer c.CFRelease(enabled_attr);
    const children_attr = makeCFString("AXChildren");
    defer c.CFRelease(children_attr);

    // Get role
    var role_ref: c.CFTypeRef = null;
    _ = c.AXUIElementCopyAttributeValue(element, role_attr, &role_ref);
    defer if (role_ref) |r| c.CFRelease(r);

    // Get title
    var title_ref: c.CFTypeRef = null;
    _ = c.AXUIElementCopyAttributeValue(element, title_attr, &title_ref);
    defer if (title_ref) |t| c.CFRelease(t);

    // Get description if no title
    var desc_ref: c.CFTypeRef = null;
    if (title_ref == null) {
        _ = c.AXUIElementCopyAttributeValue(element, desc_attr, &desc_ref);
    }
    defer if (desc_ref) |d| c.CFRelease(d);

    // Get position
    var pos_ref: c.CFTypeRef = null;
    _ = c.AXUIElementCopyAttributeValue(element, pos_attr, &pos_ref);
    defer if (pos_ref) |p| c.CFRelease(p);

    // Get size
    var size_ref: c.CFTypeRef = null;
    _ = c.AXUIElementCopyAttributeValue(element, size_attr, &size_ref);
    defer if (size_ref) |s| c.CFRelease(s);

    // Get enabled state
    var enabled_ref: c.CFTypeRef = null;
    _ = c.AXUIElementCopyAttributeValue(element, enabled_attr, &enabled_ref);
    defer if (enabled_ref) |e| c.CFRelease(e);

    // Check if element should be added
    if (role_ref != null) {
        const role_str = cfStringToSlice(@ptrCast(role_ref));
        const title_str = if (title_ref) |t| cfStringToSlice(@ptrCast(t)) else if (desc_ref) |d| cfStringToSlice(@ptrCast(d)) else "";


        var position = c.CGPoint{ .x = 0, .y = 0 };
        if (pos_ref) |p| {
            _ = c.AXValueGetValue(@ptrCast(p), c.kAXValueCGPointType, &position);
        }

        var size = c.CGSize{ .width = 0, .height = 0 };
        if (size_ref) |s| {
            _ = c.AXValueGetValue(@ptrCast(s), c.kAXValueCGSizeType, &size);
        }

        // Check if enabled (default to true if not specified)
        var is_enabled = true;
        if (enabled_ref) |e| {
            is_enabled = c.CFBooleanGetValue(@ptrCast(e)) != 0;
        }

        // Create UIElement
        var ui_elem = UIElement.init();
        ui_elem.setRole(role_str);
        ui_elem.setTitle(title_str);
        ui_elem.x = @floatCast(position.x);
        ui_elem.y = @floatCast(position.y);
        ui_elem.width = @floatCast(size.width);
        ui_elem.height = @floatCast(size.height);

        // Add clickable elements (even without titles, use role as fallback)
        // Limit to 500 elements to prevent slowdowns
        if (is_enabled and ui_elem.isClickable() and elements.items.len < 500) {
            // Skip elements that are off-screen or too small
            if (position.x >= 0 and position.y >= 0 and size.width > 5 and size.height > 5) {
                // Store AXUIElementRef for direct action clicking
                ui_elem.setAXElement(@ptrCast(@constCast(element)));
                try elements.append(allocator, ui_elem);
            }
        }
    }

    // Recurse into children
    var children_ref: c.CFTypeRef = null;
    const children_result = c.AXUIElementCopyAttributeValue(element, children_attr, &children_ref);

    if (children_result == c.kAXErrorSuccess and children_ref != null) {
        defer c.CFRelease(children_ref);

        const children: c.CFArrayRef = @ptrCast(children_ref);
        const count = c.CFArrayGetCount(children);

        var i: c.CFIndex = 0;
        while (i < count) : (i += 1) {
            // Check timeout before each child
            if (std.time.milliTimestamp() - scan_start_time > SCAN_TIMEOUT_MS) {
                scan_timed_out = true;
                return error.ScanTimeout;
            }

            const child = c.CFArrayGetValueAtIndex(children, i);
            if (child) |ch| {
                scanElement(@ptrCast(ch), elements, allocator, depth + 1, max_depth) catch |err| {
                    if (err == error.ScanTimeout) return err;
                    // Ignore other errors and continue
                };
            }
        }
    }
}

// Global buffer for string extraction (simple approach)
var string_buffer: [4096]u8 = undefined;
var string_offset: usize = 0;

fn cfStringToSlice(cf_string: c.CFStringRef) []const u8 {
    if (cf_string == null) return "";

    const length = c.CFStringGetLength(cf_string);
    if (length == 0) return "";

    // Try to get direct pointer first
    const c_str = c.CFStringGetCStringPtr(cf_string, c.kCFStringEncodingUTF8);
    if (c_str) |s| {
        return std.mem.span(s);
    }

    // Fallback: copy to buffer
    const max_size = c.CFStringGetMaximumSizeForEncoding(length, c.kCFStringEncodingUTF8) + 1;
    if (max_size <= 0) return "";

    const size: usize = @intCast(max_size);
    if (string_offset + size > string_buffer.len) {
        string_offset = 0; // Reset buffer
    }

    const start = string_offset;
    const success = c.CFStringGetCString(
        cf_string,
        @ptrCast(&string_buffer[start]),
        @intCast(string_buffer.len - start),
        c.kCFStringEncodingUTF8,
    );

    if (success != 0) {
        const slice = std.mem.sliceTo(string_buffer[start..], 0);
        string_offset += slice.len + 1;
        return slice;
    }

    return "";
}
