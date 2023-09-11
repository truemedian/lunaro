const std = @import("std");

pub fn build(b: *std.Build) void {
    const module = b.addModule("lunaro", .{
        .source_file = .{ .path = "src/lunaro.zig" },
    });
    _ = module;

    const test_step = b.step("test", "Run tests");

    inline for (.{ "lua51", "lua52", "lua53", "lua54", "luajit" }) |lua| {
        const test_exe = b.addTest(.{
            .root_source_file = .{ .path = "src/lunaro.zig" },
        });

        test_exe.linkLibC();
        test_exe.linkSystemLibrary(lua);

        const test_this_step = b.step("test-" ++ lua, "Run tests for " ++ lua);
        test_this_step.dependOn(&test_exe.step);
        test_step.dependOn(test_this_step);
    }

    const autodoc_test = b.addTest(.{
        .root_source_file = .{ .path = "src/lunaro.zig" },
    });

    autodoc_test.linkLibC();
    autodoc_test.linkSystemLibrary("lua");

    const install_docs = b.addInstallDirectory(.{
        .source_dir = autodoc_test.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const autodoc_step = b.step("autodoc", "Generate documentation");
    autodoc_step.dependOn(&install_docs.step);
}
