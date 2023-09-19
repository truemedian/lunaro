const std = @import("std");

const LuaVersion = enum {
    lua51,
    lua52,
    lua53,
    lua54,
    luajit,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const debug = b.option(bool, "debug", "Create a debug build of lua") orelse true;
    const strip = b.option(bool, "strip", "Strip debug information from static lua builds") orelse true;
    const requested_lua = b.option(LuaVersion, "lua", "Version of lua to build against");

    const compat52 = b.option(bool, "compat52", "Luajit only. Enable Lua 5.2 compat") orelse true;
    const disable_ffi = b.option(bool, "disable-ffi", "Luajit only. Disable FFI") orelse false;
    const disable_jit = b.option(bool, "disable-jit", "Luajit only. Disable JIT") orelse false;
    const disable_gc64 = b.option(bool, "disable-gc64", "Luajit only. Disable GC64") orelse false;

    const module = b.addModule("lunaro", .{
        .source_file = .{ .path = "src/lunaro.zig" },
    });

    const optimize: std.builtin.OptimizeMode = if (debug) .Debug else .ReleaseSafe;
    if (requested_lua) |req_lua| {
        const test_step = b.step("test", "Run tests");

        const lua_library = switch (req_lua) {
            .luajit => makeLuajit(b, target, optimize, .{
                .compat52 = compat52,
                .disable_ffi = disable_ffi,
                .disable_jit = disable_jit,
                .disable_gc64 = disable_gc64,
            }),
            inline else => |t| makeLua(b, @tagName(t), target, optimize),
        };

        lua_library.strip = strip;

        const test_static_exe = b.addTest(.{
            .root_source_file = .{ .path = "src/lunaro.zig" },
            .optimize = optimize,
        });

        test_static_exe.linkLibrary(lua_library);

        const example_static_exe = b.addExecutable(.{
            .name = "example-static",
            .root_source_file = .{ .path = "pkg/test.zig" },
            .optimize = optimize,
        });

        example_static_exe.linkLibrary(lua_library);
        example_static_exe.addModule("lunaro", module);

        const example_static_run = b.addRunArtifact(example_static_exe);
        example_static_run.expectExitCode(0);

        const test_static_step = b.step("test-static", "Run tests for static lua");
        test_static_step.dependOn(&test_static_exe.step);
        test_static_step.dependOn(&example_static_run.step);

        test_step.dependOn(test_static_step);

        const test_shared_exe = b.addTest(.{
            .root_source_file = .{ .path = "src/lunaro.zig" },
            .optimize = optimize,
        });

        test_shared_exe.linkLibC();
        test_shared_exe.linkSystemLibrary(@tagName(req_lua));

        const example_shared_exe = b.addExecutable(.{
            .name = "example-shared",
            .root_source_file = .{ .path = "pkg/test.zig" },
            .optimize = optimize,
        });

        example_shared_exe.linkLibC();
        example_shared_exe.linkSystemLibrary(@tagName(req_lua));
        example_shared_exe.addModule("lunaro", module);

        const example_shared_run = b.addRunArtifact(example_shared_exe);
        example_shared_run.expectExitCode(0);

        const test_shared_step = b.step("test-shared", "Run tests for shared lua");
        test_shared_step.dependOn(&test_shared_exe.step);
        test_shared_step.dependOn(&example_shared_run.step);

        test_step.dependOn(test_shared_step);
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

fn makeLua(b: *std.Build, comptime lua: []const u8, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lua_library = b.addStaticLibrary(.{
        .name = "lua",
        .target = target,
        .optimize = optimize,
    });

    lua_library.linkLibC();

    lua_library.installHeader("pkg/" ++ lua ++ "/lua.h", "lua.h");
    lua_library.installHeader("pkg/" ++ lua ++ "/luaconf.h", "luaconf.h");
    lua_library.installHeader("pkg/" ++ lua ++ "/lualib.h", "lualib.h");
    lua_library.installHeader("pkg/" ++ lua ++ "/lauxlib.h", "lauxlib.h");

    if (target.isFreeBSD() or target.isNetBSD() or target.isOpenBSD() or target.isFreeBSD() or target.isDragonFlyBSD() or target.isLinux()) {
        lua_library.defineCMacro("LUA_USE_LINUX", null);
    } else if (target.isDarwin()) {
        lua_library.defineCMacro("LUA_USE_MACOSX", null);
    } else if (target.isWindows()) {
        lua_library.defineCMacro("LUA_USE_WINDOWS", null);
    } else {
        lua_library.defineCMacro("LUA_USE_POSIX", null);
    }

    inline for (@field(files, lua)) |file| {
        lua_library.addCSourceFile(.{
            .file = .{ .path = "pkg/" ++ lua ++ "/" ++ file },
            .flags = &.{},
        });
    }

    b.installArtifact(lua_library);

    return lua_library;
}

const LuajitOptions = struct {
    compat52: bool,
    disable_ffi: bool,
    disable_jit: bool,
    disable_gc64: bool,
};

fn makeLuajit(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, options: LuajitOptions) *std.Build.Step.Compile {
    const minilua = b.addExecutable(.{
        .name = "minilua",
        .optimize = .ReleaseSafe,
    });

    minilua.linkLibC();
    minilua.disable_sanitize_c = true;

    inline for (files.luajit.minilua) |file| {
        minilua.addCSourceFile(.{
            .file = .{ .path = "pkg/luajit/src/" ++ file },
            .flags = &.{},
        });
    }

    // Run DASM to generate buildvm_arch.h

    const dasm_run = b.addRunArtifact(minilua);
    dasm_run.addFileArg(.{ .path = "pkg/luajit/dynasm/dynasm.lua" });

    if (target.getCpuArch().endian() == .Little) {
        dasm_run.addArgs(&.{ "-D", "LE" });
    } else {
        dasm_run.addArgs(&.{ "-D", "BE" });
    }

    if (target.toTarget().ptrBitWidth() == 64) {
        dasm_run.addArgs(&.{ "-D", "P64" });
    }

    dasm_run.addArgs(&.{ "-D", "JIT" });
    dasm_run.addArgs(&.{ "-D", "FFI" });

    if (target.toTarget().getFloatAbi() != .hard) {
        dasm_run.addArgs(&.{ "-D", "FPU" });
    } else {
        dasm_run.addArgs(&.{ "-D", "HFABI" });
    }

    if (target.isWindows()) {
        dasm_run.addArgs(&.{ "-D", "WIN" });
    }

    dasm_run.addArg("-o");
    const buildvm_arch_header = dasm_run.addOutputFileArg("buildvm_arch.h");

    switch (target.getCpuArch()) {
        .x86 => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_x86.dasc" }),
        .x86_64 => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_x64.dasc" }),
        .arm, .armeb => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_arm.dasc" }),
        .aarch64, .aarch64_be => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_arm64.dasc" }),
        .powerpc, .powerpcle => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_ppc.dasc" }),
        .mips, .mipsel => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_mips.dasc" }),
        .mips64, .mips64el => dasm_run.addFileArg(.{ .path = "pkg/luajit/src/vm_mips64.dasc" }),
        else => @panic("unhandled architechture"),
    }

    // Generate versioned luajit.h

    const luajit_h_run = b.addRunArtifact(minilua);
    luajit_h_run.addFileArg(.{ .path = "pkg/luajit/src/host/genversion.lua" });
    luajit_h_run.addFileArg(.{ .path = "pkg/luajit/src/luajit_rolling.h" });
    luajit_h_run.addFileArg(.{ .path = "pkg/luajit_relver.txt" });
    const luajit_h = luajit_h_run.addOutputFileArg("luajit.h");

    // Create buildvm to generate necessary files

    const buildvm_exe = b.addExecutable(.{
        .name = "buildvm",
        .optimize = .ReleaseSafe,
    });
    buildvm_exe.disable_sanitize_c = true;

    buildvm_exe.step.dependOn(&dasm_run.step);

    buildvm_exe.linkLibC();
    buildvm_exe.addIncludePath(FixIncludePath.init(b, luajit_h));
    buildvm_exe.addIncludePath(FixIncludePath.init(b, buildvm_arch_header));
    buildvm_exe.addIncludePath(.{ .path = "pkg/luajit/src" });

    if (options.compat52)
        buildvm_exe.defineCMacro("LUAJIT_ENABLE_LUA52COMPAT", null);

    if (options.disable_ffi)
        buildvm_exe.defineCMacro("LUAJIT_DISABLE_FFI", null);

    if (options.disable_jit)
        buildvm_exe.defineCMacro("LUAJIT_DISABLE_JIT", null);

    if (options.disable_gc64)
        buildvm_exe.defineCMacro("LUAJIT_DISABLE_GC64", null);

    if (target.isWindows()) {
        buildvm_exe.defineCMacro("LUAJIT_OS", "LUAJIT_OS_WINDOWS");
    } else if (target.isLinux()) {
        buildvm_exe.defineCMacro("LUAJIT_OS", "LUAJIT_OS_LINUX");
    } else if (target.isDarwin()) {
        buildvm_exe.defineCMacro("LUAJIT_OS", "LUAJIT_OS_OSX");
    } else if (target.isNetBSD() or target.isFreeBSD() or target.isOpenBSD() or target.isDragonFlyBSD()) {
        buildvm_exe.defineCMacro("LUAJIT_OS", "LUAJIT_OS_BSD");
    } else {
        buildvm_exe.defineCMacro("LUAJIT_OS", "LUAJIT_OS_OTHER");
    }

    if (target.getCpuArch() == .aarch64_be) {
        buildvm_exe.defineCMacro("__AARCH64EB__", "1");
    } else if (target.getCpuArch().isPPC() or target.getCpuArch().isPPC64()) {
        if (target.getCpuArch().endian() == .Little) {
            buildvm_exe.defineCMacro("LJ_ARCH_ENDIAN", "LUAJIT_LE");
        } else {
            buildvm_exe.defineCMacro("LJ_ARCH_ENDIAN", "LUAJIT_BE");
        }
    } else if (target.getCpuArch().isMIPS()) {
        if (target.getCpuArch().endian() == .Little) {
            buildvm_exe.defineCMacro("__MIPSEL__", "1");
        }
    }

    switch (target.getCpuArch()) {
        .x86 => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_x86"),
        .x86_64 => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_x64"),
        .arm, .armeb => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_arm"),
        .aarch64, .aarch64_be => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_arm64"),
        .powerpc, .powerpcle => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_ppc"),
        .mips, .mipsel => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_mips"),
        .mips64, .mips64el => buildvm_exe.defineCMacro("LUAJIT_CPU", "LUAJIT_ARCH_mips64"),
        else => @panic("unhandled architechture"),
    }

    if (target.toTarget().getFloatAbi() != .hard) {
        buildvm_exe.defineCMacro("LJ_ARCH_HASFPU", "1");
        buildvm_exe.defineCMacro("LJ_ARCH_SOFTFP", "0");
    } else {
        buildvm_exe.defineCMacro("LJ_ARCH_HASFPU", "0");
        buildvm_exe.defineCMacro("LJ_ARCH_SOFTFP", "1");
    }

    inline for (files.luajit.buildvm) |file| {
        buildvm_exe.addCSourceFile(.{
            .file = .{ .path = "pkg/luajit/src/" ++ file },
            .flags = &.{},
        });
    }

    // Run buildvm to generate necessary files

    const buildvm_bcdef = b.addRunArtifact(buildvm_exe);
    buildvm_bcdef.addArgs(&.{ "-m", "bcdef", "-o" });
    const bcdef_header = buildvm_bcdef.addOutputFileArg("lj_bcdef.h");
    inline for (files.luajit.lib) |file| {
        buildvm_bcdef.addFileArg(.{ .path = "pkg/luajit/src/" ++ file });
    }

    const buildvm_ffdef = b.addRunArtifact(buildvm_exe);
    buildvm_ffdef.addArgs(&.{ "-m", "ffdef", "-o" });
    const ffdef_header = buildvm_ffdef.addOutputFileArg("lj_ffdef.h");
    inline for (files.luajit.lib) |file| {
        buildvm_ffdef.addFileArg(.{ .path = "pkg/luajit/src/" ++ file });
    }

    const buildvm_libdef = b.addRunArtifact(buildvm_exe);
    buildvm_libdef.addArgs(&.{ "-m", "libdef", "-o" });
    const libdef_header = buildvm_libdef.addOutputFileArg("lj_libdef.h");
    inline for (files.luajit.lib) |file| {
        buildvm_libdef.addFileArg(.{ .path = "pkg/luajit/src/" ++ file });
    }

    const buildvm_recdef = b.addRunArtifact(buildvm_exe);
    buildvm_recdef.addArgs(&.{ "-m", "recdef", "-o" });
    const recdef_header = buildvm_recdef.addOutputFileArg("lj_recdef.h");
    inline for (files.luajit.lib) |file| {
        buildvm_recdef.addFileArg(.{ .path = "pkg/luajit/src/" ++ file });
    }

    const buildvm_vmdef = b.addRunArtifact(buildvm_exe);
    buildvm_vmdef.addArgs(&.{ "-m", "vmdef", "-o" });
    const vmdef_lua = buildvm_vmdef.addOutputFileArg("vmdef.lua");
    inline for (files.luajit.lib) |file| {
        buildvm_recdef.addFileArg(.{ .path = "pkg/luajit/src/" ++ file });
    }

    const buildvm_folddef = b.addRunArtifact(buildvm_exe);
    buildvm_folddef.addArgs(&.{ "-m", "folddef", "-o" });
    const folddef_header = buildvm_folddef.addOutputFileArg("lj_folddef.h");
    buildvm_folddef.addFileArg(.{ .path = "pkg/luajit/src/lj_opt_fold.c" });

    // Create luajit library

    const real_optimize = if (optimize == .Debug) .ReleaseSafe else optimize;
    const luajit_library = b.addStaticLibrary(.{
        .name = "lua",
        .target = target,
        .optimize = real_optimize,
    });

    luajit_library.disable_sanitize_c = true;
    luajit_library.stack_protector = false;
    luajit_library.omit_frame_pointer = true;
    luajit_library.defineCMacro("LUAJIT_UNWIND_EXTERNAL", null);
    luajit_library.linkSystemLibrary("unwind");

    luajit_library.step.dependOn(&buildvm_bcdef.step);
    luajit_library.step.dependOn(&buildvm_ffdef.step);
    luajit_library.step.dependOn(&buildvm_libdef.step);
    luajit_library.step.dependOn(&buildvm_recdef.step);
    luajit_library.step.dependOn(&buildvm_folddef.step);

    luajit_library.linkLibC();
    luajit_library.addIncludePath(FixIncludePath.init(b, luajit_h));
    luajit_library.addIncludePath(FixIncludePath.init(b, bcdef_header));
    luajit_library.addIncludePath(FixIncludePath.init(b, ffdef_header));
    luajit_library.addIncludePath(FixIncludePath.init(b, libdef_header));
    luajit_library.addIncludePath(FixIncludePath.init(b, recdef_header));
    luajit_library.addIncludePath(FixIncludePath.init(b, folddef_header));
    luajit_library.addIncludePath(.{ .path = "pkg/luajit/src" });

    luajit_library.installHeader("pkg/luajit/src/lua.h", "lua.h");
    luajit_library.installHeader("pkg/luajit/src/luaconf.h", "luaconf.h");
    luajit_library.installHeader("pkg/luajit/src/lualib.h", "lualib.h");
    luajit_library.installHeader("pkg/luajit/src/lauxlib.h", "lauxlib.h");

    const install_luajit_h = b.addInstallFileWithDir(luajit_h, .header, "luajit.h");
    luajit_library.step.dependOn(&install_luajit_h.step);

    inline for (files.luajit.core) |file| {
        luajit_library.addCSourceFile(.{
            .file = .{ .path = "pkg/luajit/src/" ++ file },
            .flags = &.{},
        });
    }

    inline for (files.luajit.lib) |file| {
        luajit_library.addCSourceFile(.{
            .file = .{ .path = "pkg/luajit/src/" ++ file },
            .flags = &.{},
        });
    }

    if (options.compat52)
        luajit_library.defineCMacro("LUAJIT_ENABLE_LUA52COMPAT", null);

    if (options.disable_ffi)
        luajit_library.defineCMacro("LUAJIT_DISABLE_FFI", null);

    if (options.disable_jit)
        luajit_library.defineCMacro("LUAJIT_DISABLE_JIT", null);

    if (options.disable_gc64)
        luajit_library.defineCMacro("LUAJIT_DISABLE_GC64", null);

    b.installArtifact(luajit_library);

    // Final buildvm run to generate lj_vm.o

    const buildvm_ljvm = b.addRunArtifact(buildvm_exe);
    buildvm_ljvm.addArg("-m");

    if (target.isWindows()) {
        buildvm_ljvm.addArg("peobj");
    } else if (target.isDarwin()) {
        buildvm_ljvm.addArg("machasm");
    } else {
        buildvm_ljvm.addArg("elfasm");
    }

    buildvm_ljvm.addArg("-o");

    if (target.isWindows()) {
        const ljvm_obj_output = buildvm_ljvm.addOutputFileArg("lj_vm.o");

        luajit_library.addObjectFile(ljvm_obj_output);
    } else {
        const ljvm_asm_output = buildvm_ljvm.addOutputFileArg("lj_vm.S");

        luajit_library.addAssemblyFile(ljvm_asm_output);
    }

    // install jit/*.lua files

    const install_jit = b.addInstallDirectory(.{
        .source_dir = .{ .path = "pkg/luajit/src/jit" },
        .install_dir = .prefix,
        .install_subdir = "jit",
        .exclude_extensions = &.{".gitignore"},
    });

    const install_vmdef = b.addInstallFileWithDir(vmdef_lua, .{ .custom = "jit" }, "vmdef.lua");

    luajit_library.step.dependOn(&install_vmdef.step);
    luajit_library.step.dependOn(&install_jit.step);

    return luajit_library;
}

const FixIncludePath = struct {
    step: std.Build.Step,

    output_gen: std.Build.GeneratedFile,
    input_path: std.Build.LazyPath,

    pub fn init(b: *std.Build, path: std.Build.LazyPath) std.Build.LazyPath {
        const self = b.allocator.create(FixIncludePath) catch unreachable;

        self.step = std.Build.Step.init(.{
            .id = .custom,
            .name = "include-fix",
            .owner = b,
            .makeFn = make,
        });

        self.input_path = path;

        self.output_gen.step = &self.step;
        self.output_gen.path = null;

        path.addStepDependencies(&self.step);

        return .{ .generated = &self.output_gen };
    }

    pub fn make(step: *std.Build.Step, prog_node: *std.Progress.Node) anyerror!void {
        _ = prog_node;

        const self = @fieldParentPtr(FixIncludePath, "step", step);
        self.output_gen.path = std.fs.path.dirname(self.input_path.getPath(step.owner)) orelse unreachable;

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
