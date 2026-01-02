const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "keyon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add Objective-C status bar code
    exe.addCSourceFile(.{
        .file = b.path("src/statusbar.m"),
        .flags = &.{"-fobjc-arc"},
    });
    exe.root_module.addIncludePath(b.path("src"));

    // Link system raylib (installed via Homebrew)
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    exe.root_module.linkSystemLibrary("raylib", .{});

    // Link macOS frameworks for accessibility, hotkeys, and click simulation
    exe.root_module.linkFramework("ApplicationServices", .{});
    exe.root_module.linkFramework("CoreGraphics", .{});
    exe.root_module.linkFramework("Carbon", .{});
    exe.root_module.linkFramework("CoreFoundation", .{});
    exe.root_module.linkFramework("AppKit", .{});
    exe.root_module.linkFramework("IOKit", .{});
    exe.root_module.linkFramework("Cocoa", .{});
    exe.root_module.linkFramework("OpenGL", .{});

    // System libraries
    exe.linkLibC();

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run KeyOn");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_step = b.step("test", "Run unit tests");

    // Test search.zig (no special dependencies)
    const search_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/search.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(search_tests).step);

    // Test ui_element.zig (needs ApplicationServices)
    const ui_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ui_element.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ui_tests.root_module.linkFramework("ApplicationServices", .{});
    ui_tests.linkLibC();
    test_step.dependOn(&b.addRunArtifact(ui_tests).step);

    // Test hotkey.zig (needs CoreGraphics, CoreFoundation)
    const hotkey_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/hotkey.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hotkey_tests.root_module.addIncludePath(b.path("src"));
    hotkey_tests.root_module.linkFramework("CoreGraphics", .{});
    hotkey_tests.root_module.linkFramework("CoreFoundation", .{});
    hotkey_tests.linkLibC();
    test_step.dependOn(&b.addRunArtifact(hotkey_tests).step);
}
