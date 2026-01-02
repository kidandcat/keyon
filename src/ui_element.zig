const std = @import("std");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

pub const UIElement = struct {
    role: [64]u8,
    role_len: usize,
    title: [256]u8,
    title_len: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    ax_element: ?*anyopaque, // AXUIElementRef

    pub fn init() UIElement {
        return .{
            .role = [_]u8{0} ** 64,
            .role_len = 0,
            .title = [_]u8{0} ** 256,
            .title_len = 0,
            .x = 0,
            .y = 0,
            .width = 0,
            .height = 0,
            .ax_element = null,
        };
    }

    pub fn setAXElement(self: *UIElement, element: ?*anyopaque) void {
        if (element) |el| {
            // Retain the element
            _ = c.CFRetain(el);
            self.ax_element = el;
        }
    }

    pub fn performPress(self: *const UIElement) bool {
        if (self.ax_element) |el| {
            const role = self.getRole();

            // Text fields need focus, not press
            if (std.mem.eql(u8, role, "AXTextField") or
                std.mem.eql(u8, role, "AXTextArea") or
                std.mem.eql(u8, role, "AXComboBox")) {
                // Try to set focus attribute
                const focused_attr = c.CFStringCreateWithCString(null, "AXFocused", c.kCFStringEncodingUTF8);
                if (focused_attr) |attr| {
                    defer c.CFRelease(attr);
                    const result = c.AXUIElementSetAttributeValue(@ptrCast(el), attr, @ptrCast(c.kCFBooleanTrue));
                    if (result == 0) return true;
                }
                // Fallback: try AXFocus action
                const focus_action = c.CFStringCreateWithCString(null, "AXFocus", c.kCFStringEncodingUTF8);
                if (focus_action) |act| {
                    defer c.CFRelease(act);
                    const result = c.AXUIElementPerformAction(@ptrCast(el), act);
                    if (result == 0) return true;
                }
            }

            // Default: try AXPress
            const action = c.CFStringCreateWithCString(null, "AXPress", c.kCFStringEncodingUTF8);
            if (action) |act| {
                defer c.CFRelease(act);
                const result = c.AXUIElementPerformAction(@ptrCast(el), act);
                return result == 0; // kAXErrorSuccess
            }
        }
        return false;
    }

    pub fn deinit(self: *UIElement) void {
        if (self.ax_element) |el| {
            c.CFRelease(el);
            self.ax_element = null;
        }
    }

    pub fn setRole(self: *UIElement, role: []const u8) void {
        const len = @min(role.len, 63);
        @memcpy(self.role[0..len], role[0..len]);
        self.role_len = len;
    }

    pub fn setTitle(self: *UIElement, title: []const u8) void {
        const len = @min(title.len, 255);
        @memcpy(self.title[0..len], title[0..len]);
        self.title_len = len;
    }

    pub fn getRole(self: *const UIElement) []const u8 {
        return self.role[0..self.role_len];
    }

    pub fn getTitle(self: *const UIElement) []const u8 {
        return self.title[0..self.title_len];
    }

    pub fn getDisplayName(self: *const UIElement) []const u8 {
        if (self.title_len > 0) {
            return self.title[0..self.title_len];
        }
        return self.role[0..self.role_len];
    }

    pub fn getCenterX(self: *const UIElement) f32 {
        return self.x + self.width / 2.0;
    }

    pub fn getCenterY(self: *const UIElement) f32 {
        return self.y + self.height / 2.0;
    }

    // Clickable roles (excluding AXMenuItem - they're in menus, not visible)
    const clickable_roles = [_][]const u8{
        "AXButton",
        "AXLink",
        "AXMenuBarItem", // Top-level menu bar items only
        "AXPopUpButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXTab",
        "AXToolbarButton",
        "AXCell",
        "AXRow",
        "AXDisclosureTriangle",
        "AXIncrementor",
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSlider",
        "AXColorWell",
        "AXOutlineRow",
    };

    pub fn isClickable(self: *const UIElement) bool {
        const role = self.getRole();
        for (clickable_roles) |clickable| {
            if (std.mem.eql(u8, role, clickable)) {
                return true;
            }
        }
        return false;
    }
};

// Tests
test "UIElement init" {
    const elem = UIElement.init();
    try std.testing.expectEqual(@as(usize, 0), elem.role_len);
    try std.testing.expectEqual(@as(usize, 0), elem.title_len);
    try std.testing.expectEqual(@as(f32, 0), elem.x);
    try std.testing.expectEqual(@as(f32, 0), elem.y);
    try std.testing.expectEqual(@as(f32, 0), elem.width);
    try std.testing.expectEqual(@as(f32, 0), elem.height);
    try std.testing.expect(elem.ax_element == null);
}

test "UIElement setRole and getRole" {
    var elem = UIElement.init();
    elem.setRole("AXButton");
    try std.testing.expectEqualStrings("AXButton", elem.getRole());
}

test "UIElement setRole truncates long roles" {
    var elem = UIElement.init();
    const long_role = "A" ** 100; // 100 characters
    elem.setRole(long_role);
    try std.testing.expectEqual(@as(usize, 63), elem.role_len);
}

test "UIElement setTitle and getTitle" {
    var elem = UIElement.init();
    elem.setTitle("Submit Button");
    try std.testing.expectEqualStrings("Submit Button", elem.getTitle());
}

test "UIElement setTitle truncates long titles" {
    var elem = UIElement.init();
    const long_title = "B" ** 300; // 300 characters
    elem.setTitle(long_title);
    try std.testing.expectEqual(@as(usize, 255), elem.title_len);
}

test "UIElement getDisplayName returns title when set" {
    var elem = UIElement.init();
    elem.setRole("AXButton");
    elem.setTitle("OK");
    try std.testing.expectEqualStrings("OK", elem.getDisplayName());
}

test "UIElement getDisplayName returns role when no title" {
    var elem = UIElement.init();
    elem.setRole("AXButton");
    try std.testing.expectEqualStrings("AXButton", elem.getDisplayName());
}

test "UIElement getCenterX and getCenterY" {
    var elem = UIElement.init();
    elem.x = 100;
    elem.y = 200;
    elem.width = 50;
    elem.height = 30;
    try std.testing.expectEqual(@as(f32, 125), elem.getCenterX());
    try std.testing.expectEqual(@as(f32, 215), elem.getCenterY());
}

test "UIElement isClickable for buttons" {
    var elem = UIElement.init();
    elem.setRole("AXButton");
    try std.testing.expect(elem.isClickable());
}

test "UIElement isClickable for links" {
    var elem = UIElement.init();
    elem.setRole("AXLink");
    try std.testing.expect(elem.isClickable());
}

test "UIElement isClickable for text fields" {
    var elem = UIElement.init();
    elem.setRole("AXTextField");
    try std.testing.expect(elem.isClickable());
}

test "UIElement isClickable for checkboxes" {
    var elem = UIElement.init();
    elem.setRole("AXCheckBox");
    try std.testing.expect(elem.isClickable());
}

test "UIElement not clickable for groups" {
    var elem = UIElement.init();
    elem.setRole("AXGroup");
    try std.testing.expect(!elem.isClickable());
}

test "UIElement not clickable for windows" {
    var elem = UIElement.init();
    elem.setRole("AXWindow");
    try std.testing.expect(!elem.isClickable());
}

test "UIElement not clickable for static text" {
    var elem = UIElement.init();
    elem.setRole("AXStaticText");
    try std.testing.expect(!elem.isClickable());
}
