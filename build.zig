const std = @import("std");

const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const debug = b.option(bool, "debug", "Create a debug build of lua") orelse true;
    const strip = b.option(bool, "strip", "Strip debug information from static lua builds") orelse true;
    const requested_lua = b.option(LuaVersion, "lua", "Version of lua to build against") orelse .lua54;

    const disable_compat52 = b.option(bool, "disable-compat52", "Luajit only. Disable Lua 5.2 compat") orelse false;
    const disable_ffi = b.option(bool, "disable-ffi", "Luajit only. Disable FFI") orelse false;
    const disable_jit = b.option(bool, "disable-jit", "Luajit only. Disable JIT") orelse false;
    const disable_gc64 = b.option(bool, "disable-gc64", "Luajit only. Disable GC64") orelse false;

    const optimize: std.builtin.OptimizeMode = if (debug) .Debug else .ReleaseSafe;
    // Lua Shared Library

    const lua_shared = b.addSharedLibrary(.{
        .name = "lua-shared",
        .optimize = optimize,
        .target = target,
    });

    lua_shared.root_module.strip = strip;

    configureLuaLibrary(b, target, lua_shared, requested_lua, .{
        .debug = debug,

        .compat52 = !disable_compat52,
        .disable_ffi = disable_ffi,
        .disable_jit = disable_jit,
        .disable_gc64 = disable_gc64,
    });

    const module_shared = b.addModule("lunaro-shared", .{
        .root_source_file = .{ .path = "src/lunaro.zig" },
    });

    module_shared.linkLibrary(lua_shared);

    // Lua Static Library

    const lua_static = b.addStaticLibrary(.{
        .name = "lua-static",
        .optimize = optimize,
        .target = target,
    });

    lua_static.root_module.strip = strip;

    configureLuaLibrary(b, target, lua_static, requested_lua, .{
        .debug = debug,

        .compat52 = !disable_compat52,
        .disable_ffi = disable_ffi,
        .disable_jit = disable_jit,
        .disable_gc64 = disable_gc64,
    });

    const module_static = b.addModule("lunaro-static", .{
        .root_source_file = .{ .path = "src/lunaro.zig" },
    });

    module_static.linkLibrary(lua_static);

    // Lua System Library

    const module_system = b.addModule("lunaro-system", .{
        .root_source_file = .{ .path = "src/lunaro.zig" },
        .target = target,
    });

    module_system.link_libc = true;
    module_system.linkSystemLibrary(@tagName(requested_lua), .{ .needed = true, .use_pkg_config = .force });

    // Lunaro Tests

    const test_step = b.step("test", "Run tests");

    {
        const test_shared_exe = b.addTest(.{
            .root_source_file = .{ .path = "src/lunaro.zig" },
            .optimize = optimize,
        });

        test_shared_exe.root_module.linkLibrary(lua_shared);

        const example_shared_exe = b.addExecutable(.{
            .target = b.host,
            .name = "example-shared",
            .root_source_file = .{ .path = "src/test.zig" },
            .optimize = optimize,
        });

        example_shared_exe.root_module.addImport("lunaro", module_shared);

        const example_shared_run = b.addRunArtifact(example_shared_exe);
        example_shared_run.expectExitCode(0);

        const install_example_shared = b.addInstallArtifact(example_shared_exe, .{});
        example_shared_run.step.dependOn(&install_example_shared.step);

        const test_shared_step = b.step("test-shared", "Run tests for shared lua");
        test_shared_step.dependOn(&test_shared_exe.step);
        test_shared_step.dependOn(&example_shared_run.step);

        test_step.dependOn(test_shared_step);
    }

    {
        const test_static_exe = b.addTest(.{
            .root_source_file = .{ .path = "src/lunaro.zig" },
            .optimize = optimize,
        });

        test_static_exe.root_module.linkLibrary(lua_static);

        const example_static_exe = b.addExecutable(.{
            .target = b.host,
            .name = "example-static",
            .root_source_file = .{ .path = "src/test.zig" },
            .optimize = optimize,
        });

        example_static_exe.root_module.addImport("lunaro", module_static);

        const example_static_run = b.addRunArtifact(example_static_exe);
        example_static_run.expectExitCode(0);

        const install_example_static = b.addInstallArtifact(example_static_exe, .{});
        example_static_run.step.dependOn(&install_example_static.step);

        const test_static_step = b.step("test-static", "Run tests for static lua");
        test_static_step.dependOn(&test_static_exe.step);
        test_static_step.dependOn(&example_static_run.step);

        test_step.dependOn(test_static_step);
    }

    {
        const test_system_exe = b.addTest(.{
            .root_source_file = .{ .path = "src/lunaro.zig" },
            .optimize = optimize,
        });

        test_system_exe.root_module.link_libc = true;
        test_system_exe.root_module.linkSystemLibrary(@tagName(requested_lua), .{});

        const example_system_exe = b.addExecutable(.{
            .target = b.host,
            .name = "example-system",
            .root_source_file = .{ .path = "src/test.zig" },
            .optimize = optimize,
        });

        example_system_exe.root_module.addImport("lunaro", module_system);

        const example_system_run = b.addRunArtifact(example_system_exe);
        example_system_run.expectExitCode(0);

        const install_example_system = b.addInstallArtifact(example_system_exe, .{});
        example_system_run.step.dependOn(&install_example_system.step);

        const test_system_step = b.step("test-system", "Run tests for system lua");
        test_system_step.dependOn(&test_system_exe.step);
        test_system_step.dependOn(&example_system_run.step);

        test_step.dependOn(test_system_step);
    }

    const autodoc_test = b.addTest(.{
        .root_source_file = .{ .path = "src/lunaro.zig" },
    });

    autodoc_test.linkLibC();
    autodoc_test.root_module.linkLibrary(lua_static);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = autodoc_test.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const autodoc_step = b.step("autodoc", "Generate documentation");
    autodoc_step.dependOn(&install_docs.step);
}

pub const ConfigureOptions = struct {
    debug: bool,

    // luajit only
    compat52: bool,
    disable_ffi: bool,
    disable_jit: bool,
    disable_gc64: bool,
};

const LuaVersion = enum {
    lua51,
    lua52,
    lua53,
    lua54,
    luajit,
};

pub fn configureLuaLibrary(b: *Build, target: Build.ResolvedTarget, compile: *Build.Step.Compile, version: LuaVersion, options: ConfigureOptions) void {
    const is_os_darwin = target.result.isDarwin();
    const is_os_windows = target.result.os.tag == .windows;
    const is_os_linux = target.result.os.tag == .linux;
    const is_os_bsd = switch (target.result.os.tag) {
        .netbsd, .freebsd, .openbsd, .dragonfly => true,
        else => false,
    };

    const is_endian_little = target.result.cpu.arch.endian() == .little;
    const is_arch_64bit = target.result.ptrBitWidth() == 64;
    const is_arch_fpu = switch (target.result.cpu.arch) {
        .arm, .armeb, .powerpc, .powerpcle, .powerpc64, .powerpc64le, .mips, .mipsel, .mips64, .mips64el => false,
        else => true,
    } or target.result.getFloatAbi() == .hard;

    const dep = b.lazyDependency(@tagName(version), .{}) orelse return;

    switch (version) {
        inline .lua51, .lua52, .lua53, .lua54 => |this_version| {
            compile.linkLibC();

            compile.installHeader(dep.path("src/lua.h"), "lua.h");
            compile.installHeader(dep.path("src/luaconf.h"), "luaconf.h");
            compile.installHeader(dep.path("src/lualib.h"), "lualib.h");
            compile.installHeader(dep.path("src/lauxlib.h"), "lauxlib.h");

            if (is_os_darwin) {
                compile.root_module.addCMacro("LUA_USE_MACOSX", "1");
            } else if (is_os_windows) {
                compile.root_module.addCMacro("LUA_USE_WINDOWS", "1");
            } else {
                compile.root_module.addCMacro("LUA_USE_POSIX", "1");
                compile.root_module.addCMacro("LUA_USE_DLOPEN", "1");
            }

            inline for (@field(files, @tagName(this_version))) |file| {
                compile.addCSourceFile(.{
                    .file = dep.path("src/" ++ file),
                    .flags = &.{},
                });
            }
        },
        inline .luajit => {
            const minilua = b.addExecutable(.{
                .target = b.host,
                .name = "minilua",
                .optimize = .ReleaseSafe,
            });

            minilua.root_module.link_libc = true;
            minilua.root_module.sanitize_c = false;

            inline for (files.luajit.minilua) |file| {
                minilua.addCSourceFile(.{
                    .file = dep.path("src/" ++ file),
                    .flags = &.{},
                });
            }

            // Run DASM to generate buildvm_arch.h

            const dasm_run = b.addRunArtifact(minilua);
            dasm_run.addFileArg(dep.path("dynasm/dynasm.lua"));

            if (is_endian_little) {
                dasm_run.addArgs(&.{ "-D", "ENDIAN_LE" });
            } else {
                dasm_run.addArgs(&.{ "-D", "ENDIAN_BE" });
            }

            if (is_arch_64bit) {
                dasm_run.addArgs(&.{ "-D", "P64" });
            }

            dasm_run.addArgs(&.{ "-D", "JIT" });
            dasm_run.addArgs(&.{ "-D", "FFI" });

            if (is_arch_fpu) {
                dasm_run.addArgs(&.{ "-D", "FPU" });
                dasm_run.addArgs(&.{ "-D", "HFABI" });
            }

            if (target.result.os.tag == .windows) {
                dasm_run.addArgs(&.{ "-D", "WIN" });
            }

            switch (target.result.cpu.arch) {
                .aarch64, .aarch64_be, .aarch64_32 => dasm_run.addArgs(&.{ "-D", "PAUTH" }),
                else => {},
            }

            dasm_run.addArg("-o");
            const buildvm_arch_header = dasm_run.addOutputFileArg("buildvm_arch.h");

            switch (target.result.cpu.arch) {
                .x86 => dasm_run.addFileArg(FixDynasmPath.init(b, dep.path("src/vm_x86.dasc"))),
                .x86_64 => dasm_run.addFileArg(FixDynasmPath.init(b, dep.path("src/vm_x64.dasc"))),
                .arm, .armeb => dasm_run.addFileArg(FixDynasmPath.init(b, dep.path("src/vm_arm.dasc"))),
                .aarch64, .aarch64_be => dasm_run.addFileArg(FixDynasmPath.init(b, dep.path("src/vm_arm64.dasc"))),
                // .powerpc, .powerpcle => dasm_run.addFileArg(dep.path("src/vm_ppc.dasc")),
                // .mips, .mipsel => dasm_run.addFileArg(dep.path("src/vm_mips.dasc")),
                // .mips64, .mips64el => dasm_run.addFileArg(dep.path("src/vm_mips64.dasc")),
                else => @panic("unhandled architecture"),
            }

            // Generate versioned luajit.h

            const luajit_relver = b.addWriteFile("luajit_relver.txt", "1694751058");

            const luajit_h_run = b.addRunArtifact(minilua);
            luajit_h_run.addFileArg(dep.path("src/host/genversion.lua"));
            luajit_h_run.addFileArg(dep.path("src/luajit_rolling.h"));
            luajit_h_run.addFileArg(luajit_relver.files.items[0].getPath());
            const luajit_h = luajit_h_run.addOutputFileArg("luajit.h");

            // Create buildvm to generate necessary files

            const buildvm_exe = b.addExecutable(.{
                .target = b.host,
                .name = "buildvm",
                .optimize = .ReleaseSafe,
            });

            buildvm_exe.root_module.sanitize_c = false;
            buildvm_exe.root_module.link_libc = true;

            buildvm_exe.root_module.addIncludePath(luajit_h.dirname());
            buildvm_exe.root_module.addIncludePath(buildvm_arch_header.dirname());
            buildvm_exe.root_module.addIncludePath(dep.path("src"));

            if (options.compat52)
                buildvm_exe.root_module.addCMacro("LUAJIT_ENABLE_LUA52COMPAT", "1");

            if (options.disable_ffi)
                buildvm_exe.root_module.addCMacro("LUAJIT_DISABLE_FFI", "1");

            if (options.disable_jit)
                buildvm_exe.root_module.addCMacro("LUAJIT_DISABLE_JIT", "1");

            if (options.disable_gc64)
                buildvm_exe.root_module.addCMacro("LUAJIT_DISABLE_GC64", "1");

            if (is_os_windows) {
                buildvm_exe.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_WINDOWS");
            } else if (is_os_linux) {
                buildvm_exe.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_LINUX");
            } else if (is_os_darwin) {
                buildvm_exe.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_OSX");
            } else if (is_os_bsd) {
                buildvm_exe.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_BSD");
            } else {
                buildvm_exe.root_module.addCMacro("LUAJIT_OS", "LUAJIT_OS_OTHER");
            }

            if (target.result.cpu.arch == .aarch64_be) {
                buildvm_exe.root_module.addCMacro("__AARCH64EB__", "1");
            } else if (target.result.cpu.arch.isPPC() or target.result.cpu.arch.isPPC64()) {
                if (is_endian_little) {
                    buildvm_exe.root_module.addCMacro("LJ_ARCH_ENDIAN", "LUAJIT_LE");
                } else {
                    buildvm_exe.root_module.addCMacro("LJ_ARCH_ENDIAN", "LUAJIT_BE");
                }
            } else if (target.result.cpu.arch.isMIPS()) {
                if (is_endian_little) {
                    buildvm_exe.root_module.addCMacro("__MIPSEL__", "1");
                }
            }

            switch (target.result.cpu.arch) {
                .aarch64, .aarch64_be, .aarch64_32 => buildvm_exe.root_module.addCMacro("LJ_ABI_PAUTH", "1"),
                else => {},
            }

            switch (target.result.cpu.arch) {
                .x86 => buildvm_exe.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_x86"),
                .x86_64 => buildvm_exe.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_x64"),
                .arm, .armeb => buildvm_exe.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_arm"),
                .aarch64, .aarch64_be => buildvm_exe.root_module.addCMacro("LUAJIT_TARGET", "LUAJIT_ARCH_arm64"),
                // .powerpc, .powerpcle => buildvm_exe.root_module.addCMacro("LUAJIT_CPU", "LUAJIT_ARCH_ppc"),
                // .mips, .mipsel => buildvm_exe.root_module.addCMacro("LUAJIT_CPU", "LUAJIT_ARCH_mips"),
                // .mips64, .mips64el => buildvm_exe.root_module.addCMacro("LUAJIT_CPU", "LUAJIT_ARCH_mips64"),
                else => @panic("unhandled architechture"),
            }

            if (is_arch_fpu) {
                buildvm_exe.root_module.addCMacro("LJ_ARCH_HASFPU", "1");
                buildvm_exe.root_module.addCMacro("LJ_ARCH_SOFTFP", "0");
            } else {
                buildvm_exe.root_module.addCMacro("LJ_ARCH_HASFPU", "0");
                buildvm_exe.root_module.addCMacro("LJ_ARCH_SOFTFP", "1");
            }

            inline for (files.luajit.buildvm) |file| {
                buildvm_exe.addCSourceFile(.{
                    .file = dep.path("src/" ++ file),
                    .flags = &.{},
                });
            }

            // Run buildvm to generate necessary files

            const buildvm_bcdef = b.addRunArtifact(buildvm_exe);
            buildvm_bcdef.addArgs(&.{ "-m", "bcdef", "-o" });
            const bcdef_header = buildvm_bcdef.addOutputFileArg("lj_bcdef.h");
            inline for (files.luajit.lib) |file| {
                buildvm_bcdef.addFileArg(dep.path("src/" ++ file));
            }

            const buildvm_ffdef = b.addRunArtifact(buildvm_exe);
            buildvm_ffdef.addArgs(&.{ "-m", "ffdef", "-o" });
            const ffdef_header = buildvm_ffdef.addOutputFileArg("lj_ffdef.h");
            inline for (files.luajit.lib) |file| {
                buildvm_ffdef.addFileArg(dep.path("src/" ++ file));
            }

            const buildvm_libdef = b.addRunArtifact(buildvm_exe);
            buildvm_libdef.addArgs(&.{ "-m", "libdef", "-o" });
            const libdef_header = buildvm_libdef.addOutputFileArg("lj_libdef.h");
            inline for (files.luajit.lib) |file| {
                buildvm_libdef.addFileArg(dep.path("src/" ++ file));
            }

            const buildvm_recdef = b.addRunArtifact(buildvm_exe);
            buildvm_recdef.addArgs(&.{ "-m", "recdef", "-o" });
            const recdef_header = buildvm_recdef.addOutputFileArg("lj_recdef.h");
            inline for (files.luajit.lib) |file| {
                buildvm_recdef.addFileArg(dep.path("src/" ++ file));
            }

            const buildvm_vmdef = b.addRunArtifact(buildvm_exe);
            buildvm_vmdef.addArgs(&.{ "-m", "vmdef", "-o" });
            const vmdef_lua = buildvm_vmdef.addOutputFileArg("vmdef.lua");
            inline for (files.luajit.lib) |file| {
                buildvm_recdef.addFileArg(dep.path("src/" ++ file));
            }

            const buildvm_folddef = b.addRunArtifact(buildvm_exe);
            buildvm_folddef.addArgs(&.{ "-m", "folddef", "-o" });
            const folddef_header = buildvm_folddef.addOutputFileArg("lj_folddef.h");
            buildvm_folddef.addFileArg(dep.path("src/lj_opt_fold.c"));

            // Create luajit library

            compile.root_module.sanitize_c = false;
            compile.root_module.stack_protector = false;
            compile.root_module.omit_frame_pointer = true;
            compile.root_module.addCMacro("LUAJIT_UNWIND_EXTERNAL", "1");
            compile.root_module.linkSystemLibrary("unwind", .{ .needed = true });
            compile.root_module.unwind_tables = true;

            compile.step.dependOn(&buildvm_bcdef.step);
            compile.step.dependOn(&buildvm_ffdef.step);
            compile.step.dependOn(&buildvm_libdef.step);
            compile.step.dependOn(&buildvm_recdef.step);
            compile.step.dependOn(&buildvm_folddef.step);

            compile.linkLibC();
            compile.addIncludePath(luajit_h.dirname());
            compile.addIncludePath(bcdef_header.dirname());
            compile.addIncludePath(ffdef_header.dirname());
            compile.addIncludePath(libdef_header.dirname());
            compile.addIncludePath(recdef_header.dirname());
            compile.addIncludePath(folddef_header.dirname());
            compile.addIncludePath(dep.path("src"));

            compile.installHeader(dep.path("src/lua.h"), "lua.h");
            compile.installHeader(dep.path("src/luaconf.h"), "luaconf.h");
            compile.installHeader(dep.path("src/lualib.h"), "lualib.h");
            compile.installHeader(dep.path("src/lauxlib.h"), "lauxlib.h");
            compile.installHeader(luajit_h, "luajit.h");

            inline for (files.luajit.core) |file| {
                compile.addCSourceFile(.{
                    .file = dep.path("src/" ++ file),
                    .flags = &.{},
                });
            }

            inline for (files.luajit.lib) |file| {
                compile.addCSourceFile(.{
                    .file = dep.path("src/" ++ file),
                    .flags = &.{},
                });
            }

            if (options.compat52)
                compile.root_module.addCMacro("LUAJIT_ENABLE_LUA52COMPAT", "1");

            if (options.disable_ffi)
                compile.root_module.addCMacro("LUAJIT_DISABLE_FFI", "1");

            if (options.disable_jit)
                compile.root_module.addCMacro("LUAJIT_DISABLE_JIT", "1");

            if (options.disable_gc64)
                compile.root_module.addCMacro("LUAJIT_DISABLE_GC64", "1");

            // Final buildvm run to generate lj_vm.o

            const buildvm_ljvm = b.addRunArtifact(buildvm_exe);
            buildvm_ljvm.addArg("-m");

            if (target.result.os.tag == .windows) {
                buildvm_ljvm.addArg("peobj");
            } else if (target.result.isDarwin()) {
                buildvm_ljvm.addArg("machasm");
            } else {
                buildvm_ljvm.addArg("elfasm");
            }

            buildvm_ljvm.addArg("-o");

            if (target.result.os.tag == .windows) {
                const ljvm_obj_output = buildvm_ljvm.addOutputFileArg("lj_vm.o");

                compile.addObjectFile(ljvm_obj_output);
            } else {
                const ljvm_asm_output = buildvm_ljvm.addOutputFileArg("lj_vm.S");

                compile.addAssemblyFile(ljvm_asm_output);
            }

            // install jit/*.lua files

            const install_jit = b.addInstallDirectory(.{
                .source_dir = dep.path("src/jit"),
                .install_dir = .prefix,
                .install_subdir = "jit",
                .exclude_extensions = &.{".gitignore"},
            });

            const install_vmdef = b.addInstallFileWithDir(vmdef_lua, .{ .custom = "jit" }, "vmdef.lua");

            compile.step.dependOn(&install_vmdef.step);
            compile.step.dependOn(&install_jit.step);
        },
    }
}

const FixDynasmPath = struct {
    step: Build.Step,

    output_gen: Build.GeneratedFile,
    input_path: Build.LazyPath,

    pub fn init(b: *Build, path: Build.LazyPath) Build.LazyPath {
        const self = b.allocator.create(FixDynasmPath) catch unreachable;

        self.step = Build.Step.init(.{
            .id = .custom,
            .name = "dynasm-fix",
            .owner = b,
            .makeFn = make,
        });

        self.input_path = path;

        self.output_gen.step = &self.step;
        self.output_gen.path = null;

        path.addStepDependencies(&self.step);

        return .{ .generated = &self.output_gen };
    }

    pub fn make(step: *Build.Step, prog_node: *std.Progress.Node) anyerror!void {
        _ = prog_node;

        const b = step.owner;
        const self: *FixDynasmPath = @fieldParentPtr("step", step);

        const in_path = b.allocator.dupe(u8, self.input_path.getPath(b)) catch unreachable;
        std.mem.replaceScalar(u8, in_path, '\\', '/');

        self.output_gen.path = in_path;

        var all_cached = true;

        for (step.dependencies.items) |dep| {
            all_cached = all_cached and dep.result_cached;
        }

        step.result_cached = all_cached;
    }
};

pub const files = struct {
    pub const lua51 = .{
        "lapi.c",
        "lcode.c",
        "ldebug.c",
        "ldo.c",
        "ldump.c",
        "lfunc.c",
        "lgc.c",
        "llex.c",
        "lmem.c",
        "lobject.c",
        "lopcodes.c",
        "lparser.c",
        "lstate.c",
        "lstring.c",
        "ltable.c",
        "ltm.c",
        "lundump.c",
        "lvm.c",
        "lzio.c",
        "lauxlib.c",
        "lbaselib.c",
        "ldblib.c",
        "linit.c",
        "liolib.c",
        "lmathlib.c",
        "loadlib.c",
        "loslib.c",
        "lstrlib.c",
        "ltablib.c",
    };

    pub const lua52 = .{
        "lapi.c",
        "lcode.c",
        "lctype.c",
        "ldebug.c",
        "ldo.c",
        "ldump.c",
        "lfunc.c",
        "lgc.c",
        "llex.c",
        "lmem.c",
        "lobject.c",
        "lopcodes.c",
        "lparser.c",
        "lstate.c",
        "lstring.c",
        "ltable.c",
        "ltm.c",
        "lundump.c",
        "lvm.c",
        "lzio.c",
        "lauxlib.c",
        "lbaselib.c",
        "lbitlib.c",
        "lcorolib.c",
        "ldblib.c",
        "linit.c",
        "liolib.c",
        "lmathlib.c",
        "loadlib.c",
        "loslib.c",
        "lstrlib.c",
        "ltablib.c",
    };

    pub const lua53 = .{
        "lapi.c",
        "lcode.c",
        "lctype.c",
        "ldebug.c",
        "ldo.c",
        "ldump.c",
        "lfunc.c",
        "lgc.c",
        "llex.c",
        "lmem.c",
        "lobject.c",
        "lopcodes.c",
        "lparser.c",
        "lstate.c",
        "lstring.c",
        "ltable.c",
        "ltm.c",
        "lundump.c",
        "lvm.c",
        "lzio.c",
        "lauxlib.c",
        "lbaselib.c",
        "lbitlib.c",
        "lcorolib.c",
        "ldblib.c",
        "linit.c",
        "liolib.c",
        "lmathlib.c",
        "loadlib.c",
        "loslib.c",
        "lstrlib.c",
        "ltablib.c",
        "lutf8lib.c",
    };

    pub const lua54 = .{
        "lapi.c",
        "lcode.c",
        "lctype.c",
        "ldebug.c",
        "ldo.c",
        "ldump.c",
        "lfunc.c",
        "lgc.c",
        "llex.c",
        "lmem.c",
        "lobject.c",
        "lopcodes.c",
        "lparser.c",
        "lstate.c",
        "lstring.c",
        "ltable.c",
        "ltm.c",
        "lundump.c",
        "lvm.c",
        "lzio.c",
        "lauxlib.c",
        "lbaselib.c",
        "lcorolib.c",
        "ldblib.c",
        "linit.c",
        "liolib.c",
        "lmathlib.c",
        "loadlib.c",
        "loslib.c",
        "lstrlib.c",
        "ltablib.c",
        "lutf8lib.c",
    };

    pub const luajit = struct {
        pub const minilua = .{
            "host/minilua.c",
        };

        pub const buildvm = .{
            "host/buildvm_asm.c",
            "host/buildvm_fold.c",
            "host/buildvm_lib.c",
            "host/buildvm_peobj.c",
            "host/buildvm.c",
        };

        pub const lib = .{
            "lib_base.c",
            "lib_math.c",
            "lib_bit.c",
            "lib_string.c",
            "lib_table.c",
            "lib_io.c",
            "lib_os.c",
            "lib_package.c",
            "lib_debug.c",
            "lib_jit.c",
            "lib_ffi.c",
            "lib_buffer.c",
        };

        pub const core = .{
            "lj_assert.c",
            "lj_gc.c",
            "lj_err.c",
            "lj_char.c",
            "lj_bc.c",
            "lj_obj.c",
            "lj_buf.c",
            "lj_str.c",
            "lj_tab.c",
            "lj_func.c",
            "lj_udata.c",
            "lj_meta.c",
            "lj_debug.c",
            "lj_prng.c",
            "lj_state.c",
            "lj_dispatch.c",
            "lj_vmevent.c",
            "lj_vmmath.c",
            "lj_strscan.c",
            "lj_strfmt.c",
            "lj_strfmt_num.c",
            "lj_serialize.c",
            "lj_api.c",
            "lj_profile.c",
            "lj_lex.c",
            "lj_parse.c",
            "lj_bcread.c",
            "lj_bcwrite.c",
            "lj_load.c",
            "lj_ir.c",
            "lj_opt_mem.c",
            "lj_opt_fold.c",
            "lj_opt_narrow.c",
            "lj_opt_dce.c",
            "lj_opt_loop.c",
            "lj_opt_split.c",
            "lj_opt_sink.c",
            "lj_mcode.c",
            "lj_snap.c",
            "lj_record.c",
            "lj_crecord.c",
            "lj_ffrecord.c",
            "lj_asm.c",
            "lj_trace.c",
            "lj_gdbjit.c",
            "lj_ctype.c",
            "lj_cdata.c",
            "lj_cconv.c",
            "lj_ccall.c",
            "lj_ccallback.c",
            "lj_carith.c",
            "lj_clib.c",
            "lj_cparse.c",
            "lj_lib.c",
            "lj_alloc.c",
            "lib_aux.c",
            "lib_init.c",
        };
    };
};
