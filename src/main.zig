const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});

const statusbar = @cImport({
    @cInclude("statusbar.h");
});

const accessibility = @import("accessibility.zig");
const hotkey = @import("hotkey.zig");
const click = @import("click.zig");
const overlay = @import("overlay.zig");
const search = @import("search.zig");
const UIElement = @import("ui_element.zig").UIElement;

pub fn main() !void {
    std.debug.print("KeyOn starting...\n", .{});

    // Setup menu bar icon first (so user can quit)
    statusbar.setupStatusBar(null);

    // Check accessibility permissions
    if (!accessibility.isTrusted()) {
        std.debug.print("Requesting accessibility permissions...\n", .{});
        accessibility.requestPermissions();

        // Wait for permissions to be granted
        std.debug.print("Waiting for accessibility permissions...\n", .{});
        while (!accessibility.isTrusted()) {
            statusbar.processCocoaEvents();
            std.Thread.sleep(500 * std.time.ns_per_ms);
        }
        std.debug.print("Accessibility permissions granted!\n", .{});
    }

    std.debug.print("Press Cmd+< to activate\n", .{});

    // Initialize the app
    var app = App.init(std.heap.page_allocator);
    defer app.deinit();

    // Register global hotkey (F13)
    try hotkey.register(&app);

    // Main run loop - check for toggle requests and show overlay
    while (true) {
        // Process events briefly
        hotkey.processEvents();
        statusbar.processCocoaEvents();

        // Check if we should show overlay
        if (app.should_show_overlay) {
            app.should_show_overlay = false;
            app.doShowOverlay();
        }

        // Small sleep to prevent busy-waiting
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
}

pub const App = struct {
    elements: std.ArrayListUnmanaged(UIElement),
    allocator: std.mem.Allocator,
    overlay_visible: bool,
    should_show_overlay: bool,
    target_pid: ?i32,
    search_text: [256]u8,
    search_len: usize,
    selected_index: usize,
    filtered_count: usize,

    pub fn init(allocator: std.mem.Allocator) App {
        return .{
            .elements = .{},
            .allocator = allocator,
            .overlay_visible = false,
            .should_show_overlay = false,
            .target_pid = null,
            .search_text = [_]u8{0} ** 256,
            .search_len = 0,
            .selected_index = 0,
            .filtered_count = 0,
        };
    }

    pub fn deinit(self: *App) void {
        // Release all AXUIElementRefs
        for (self.elements.items) |*elem| {
            elem.deinit();
        }
        self.elements.deinit(self.allocator);
    }

    pub fn toggleOverlay(self: *App) void {
        if (self.overlay_visible) {
            self.hideOverlay();
        } else {
            // Capture target PID now (before overlay window appears)
            self.target_pid = accessibility.getFrontmostPid();
            std.debug.print("Target PID captured: {?}\n", .{self.target_pid});
            self.should_show_overlay = true;
        }
    }

    pub fn doShowOverlay(self: *App) void {
        // Release old AXUIElementRefs and clear elements
        for (self.elements.items) |*elem| {
            elem.deinit();
        }
        self.elements.clearRetainingCapacity();

        std.debug.print("Showing overlay for PID: {?}\n", .{self.target_pid});

        if (self.target_pid) |pid| {
            // Set target PID for click/scroll operations
            click.setTargetPid(@intCast(pid));

            if (accessibility.scanApp(pid, self.allocator)) |elements| {
                self.elements.appendSlice(self.allocator, elements) catch {};
                self.allocator.free(elements);
            } else |_| {
                std.debug.print("Failed to scan UI elements\n", .{});
            }
        } else {
            std.debug.print("Could not get frontmost app\n", .{});
        }

        // Reset search state
        self.search_text = [_]u8{0} ** 256;
        self.search_len = 0;
        self.selected_index = 0;
        self.filtered_count = self.elements.items.len;

        self.overlay_visible = true;

        // Show the overlay window
        overlay.show(self);
    }

    pub fn showOverlay(self: *App) void {
        self.target_pid = accessibility.getFrontmostPid();
        self.should_show_overlay = true;
    }

    pub fn hideOverlay(self: *App) void {
        self.overlay_visible = false;
        overlay.hide();
    }

    pub fn clickSelected(self: *App) void {
        const filtered = self.getFilteredElements();
        if (self.selected_index < filtered.len) {
            const element = filtered[self.selected_index];
            self.hideOverlay();
            // Small delay before clicking
            std.Thread.sleep(50 * std.time.ns_per_ms);
            click.performClick(element.x, element.y);
        }
    }

    pub fn clickElement(self: *App, element: UIElement) void {
        // Set target PID for app activation
        if (self.target_pid) |pid| {
            click.setTargetPid(@intCast(pid));
        }

        // Always use low-level mouse click
        const center_x = element.x + element.width / 2.0;
        const center_y = element.y + element.height / 2.0;
        click.performClick(center_x, center_y);
    }

    pub fn rightClickElement(self: *App, element: UIElement) void {
        // Set target PID for app activation
        if (self.target_pid) |pid| {
            click.setTargetPid(@intCast(pid));
        }

        const center_x = element.x + element.width / 2.0;
        const center_y = element.y + element.height / 2.0;
        click.performRightClick(center_x, center_y);
    }

    pub fn getFilteredElements(self: *App) []const UIElement {
        if (self.search_len == 0) {
            return self.elements.items;
        }

        // Filter elements by search text
        var filtered = std.ArrayListUnmanaged(UIElement){};
        defer filtered.deinit(self.allocator);

        const query = self.search_text[0..self.search_len];
        for (self.elements.items) |elem| {
            if (search.fuzzyMatch(query, elem.getDisplayName())) {
                filtered.append(self.allocator, elem) catch {};
            }
        }

        // Return a copy
        return filtered.toOwnedSlice(self.allocator) catch self.elements.items;
    }

    pub fn moveSelectionUp(self: *App) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    pub fn moveSelectionDown(self: *App) void {
        const count = self.filtered_count;
        if (self.selected_index + 1 < count) {
            self.selected_index += 1;
        }
    }

    pub fn updateSearch(self: *App, char: u8) void {
        if (self.search_len < 255) {
            self.search_text[self.search_len] = char;
            self.search_len += 1;
            self.selected_index = 0;
            self.updateFilteredCount();
        }
    }

    pub fn deleteSearchChar(self: *App) void {
        if (self.search_len > 0) {
            self.search_len -= 1;
            self.search_text[self.search_len] = 0;
            self.selected_index = 0;
            self.updateFilteredCount();
        }
    }

    fn updateFilteredCount(self: *App) void {
        if (self.search_len == 0) {
            self.filtered_count = self.elements.items.len;
            return;
        }

        var count: usize = 0;
        const query = self.search_text[0..self.search_len];
        for (self.elements.items) |elem| {
            if (search.fuzzyMatch(query, elem.getDisplayName())) {
                count += 1;
            }
        }
        self.filtered_count = count;
    }
};
