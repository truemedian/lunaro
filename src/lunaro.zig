const std = @import("std");

const assert = std.debug.assert;
const comptimePrint = std.fmt.comptimePrint;

const luaconf = @cImport({
    @cDefine("luajit_c", "1");
    @cInclude("luaconf.h");
});

pub const is_luajit = @hasDecl(luaconf, "LUA_PROGNAME") and std.mem.eql(u8, luaconf.LUA_PROGNAME, "luajit");

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");

    if (is_luajit)
        @cInclude("luajit.h");
});

pub const safety = @import("safety.zig");

pub const State = @import("State.zig").State;
pub const Value = @import("Value.zig").Value;
pub const Table = @import("Table.zig");
pub const Buffer = @import("Buffer.zig");
pub const Function = @import("Function.zig");

pub const lua_version = c.LUA_VERSION_NUM;

/// The type of floating point numbers in Lua. By default this is `f64`.
/// In Lua 5.1 and 5.2, it is possible that this may instead be an integer.
pub const Number = c.lua_Number;

/// The type of integers in Lua. By default this is `i64`.
pub const Integer = c.lua_Integer;

/// The type of indexes into the Lua stack. By default this is `i32`.
pub const Index = c_int;

/// The type of sizes used by Lua. By default this is `u31` and can be implicitly converted to `Index`.
pub const Size = std.meta.Int(.unsigned, @bitSizeOf(Index) - 1);

/// The type of external functions used by Lua.
pub const CFn = c.lua_CFunction;

/// The type of reader functions used by Lua.
pub const ReaderFn = c.lua_Reader;

/// The type of writer functions used by Lua.
pub const WriterFn = c.lua_Writer;

/// The type of allocation functions used by Lua.
pub const AllocFn = c.lua_Alloc;

/// The type of debug hook functions used by Lua.
pub const HookFn = c.lua_Hook;

/// The structure used to hold debug information. Some fields may not exist in some versions of Lua.
pub const DebugInfo = c.lua_Debug;

/// The pseudo-index used to refer to the registry.
pub const REGISTRYINDEX = c.LUA_REGISTRYINDEX;

fn lookup(comptime field: []const u8, comptime default: anytype) @TypeOf(default) {
    if (@hasDecl(c, field)) return @field(c, field);
    return default;
}

/// The enum used to represent the status of a thread.
pub const ThreadStatus = enum(c_int) {
    ok = lookup("LUA_OK", 0),
    yield = c.LUA_YIELD,
    err_runtime = c.LUA_ERRRUN,
    err_syntax = c.LUA_ERRSYNTAX,
    err_memory = c.LUA_ERRMEM,
    err_handler = c.LUA_ERRERR,
    err_file = c.LUA_ERRFILE,
};

/// The enum of different possible types of a Lua value.
pub const Type = enum(c_int) {
    none = c.LUA_TNONE,
    nil = c.LUA_TNIL,
    boolean = c.LUA_TBOOLEAN,
    lightuserdata = c.LUA_TLIGHTUSERDATA,
    number = c.LUA_TNUMBER,
    string = c.LUA_TSTRING,
    table = c.LUA_TTABLE,
    function = c.LUA_TFUNCTION,
    userdata = c.LUA_TUSERDATA,
    thread = c.LUA_TTHREAD,
};

/// The enum of different possible arithmetic operations to be passed to `State.arith`.
/// A negative value indicates that lunaro will be forced to polyfill the operation.
pub const ArithOp = enum(c_int) {
    add = lookup("LUA_OPADD", -1),
    sub = lookup("LUA_OPSUB", -2),
    mul = lookup("LUA_OPMUL", -3),
    div = lookup("LUA_OPDIV", -4),
    idiv = lookup("LUA_OPIDIV", -5),
    mod = lookup("LUA_OPMOD", -6),
    pow = lookup("LUA_OPPOW", -7),
    unm = lookup("LUA_OPUNM", -8),
    bnot = lookup("LUA_OPBNOT", -9),
    band = lookup("LUA_OPBAND", -10),
    bor = lookup("LUA_OPBOR", -11),
    bxor = lookup("LUA_OPBXOR", -12),
    shl = lookup("LUA_OPSHL", -13),
    shr = lookup("LUA_OPSHR", -14),
};

/// The enum of different possible comparison operations to be passed to `State.compare`.
pub const CompareOp = enum(c_int) {
    eq = lookup("LUA_OPEQ", -1),
    lt = lookup("LUA_OPLT", -2),
    le = lookup("LUA_OPLE", -3),
};

/// The different possible modes of loading a Lua chunk.
pub const LoadMode = enum {
    binary,
    text,
    either,
};

pub const helpers = struct {
    /// Wraps any zig function to be used as a Lua C function.
    ///
    /// Arguments will be checked using `State.check`. Follows the same rules as `wrapCFn`.
    pub fn wrapAnyFn(func: anytype) CFn {
        if (@TypeOf(func) == CFn) return func;

        const info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |info_Fn| info_Fn,
            .pointer => |info_Pointer| switch (@typeInfo(info_Pointer.child)) {
                .@"fn" => |info_Fn| info_Fn,
                else => @compileError("expected a `fn(X...) Y` or `*const fn(X...) Y`"),
            },
            else => @compileError("expected a `fn(X...) Y` or `*const fn(X...) Y`"),
        };

        if (info.params.len == 1 and info.params[0].type.? == *State) {
            return wrapCFn(func);
        }

        if (info.is_generic) @compileError("cannot wrap generic functions as Lua C functions");

        return wrapCFn(struct {
            fn wrapped(L: *State) info.return_type.? {
                var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;

                inline for (&args, 0..) |*slot, i| {
                    if (i == 0 and @TypeOf(slot) == *State) {
                        slot.* = L;
                    } else {
                        slot.* = L.check(@TypeOf(slot), i + 1, @src());
                    }
                }

                return @call(.auto, func, args);
            }
        }.wrapped);
    }

    /// Wraps a zig-like Lua function (with a `*State` as its first argument) to be used as a Lua C function.
    ///
    /// If the function returns `c_int`, it will be returned unmodified.
    /// Return values will be pushed using `State.push`.
    pub fn wrapCFn(func: anytype) CFn {
        if (@TypeOf(func) == CFn) return func;

        const info = switch (@typeInfo(@TypeOf(func))) {
            .@"fn" => |info_Fn| info_Fn,
            .pointer => |info_Pointer| switch (@typeInfo(info_Pointer.child)) {
                .@"fn" => |info_Fn| info_Fn,
                else => @compileError("expected a `fn(*State) X` or `*const fn(*State) X`"),
            },
            else => @compileError("expected a `fn(*State) X` or `*const fn(*State) X`"),
        };

        return struct {
            fn wrapped(L_opt: ?*c.lua_State) callconv(.C) c_int {
                const L: *State = @ptrCast(L_opt.?);
                const T = info.return_type.?;

                const top = switch (@typeInfo(T)) {
                    .error_union => L.gettop(),
                    else => {},
                };

                const scheck = safety.StackCheck.init(L);
                const result = @call(.auto, func, .{L});

                if (T == c_int)
                    return scheck.check(func, L, result);

                switch (@typeInfo(T)) {
                    .void => return scheck.check(func, L, 0),
                    .error_union => |err_info| {
                        const actual_result = result catch |err| {
                            L.settop(top);
                            L.pusherror(err);

                            return scheck.check(func, L, 2);
                        };

                        if (err_info.payload == c_int)
                            return scheck.check(func, L, actual_result);

                        L.push(actual_result);
                        return scheck.check(func, L, 1);
                    },
                    else => {
                        L.push(result);
                        return scheck.check(func, L, 1);
                    },
                }
            }
        }.wrapped;
    }

    /// Wraps a zig allocator to be used as a Lua allocator. This function should be used as the allocator function
    /// to `initWithAlloc`. The `std.mem.Allocator` should be passed as the `ud` argument to `initWithAlloc`.
    ///
    /// Usage: `L.initWithAlloc(helpers.alloc, allocator)`.
    pub fn alloc(ud: ?*anyopaque, ptr: ?*anyopaque, oldsize: usize, newsize: usize) callconv(.C) ?*anyopaque {
        assert(ud != null);

        const allocator: *std.mem.Allocator = @ptrCast(@alignCast(ud.?));
        const alignment = @alignOf(c.max_align_t);

        const ptr_aligned: ?[*]align(alignment) u8 = @ptrCast(@alignCast(ptr));

        if (ptr_aligned) |prev_ptr| {
            const prev_slice = prev_ptr[0..oldsize];

            if (newsize == 0) {
                allocator.free(prev_slice);
                return null;
            }

            if (newsize <= oldsize) {
                assert(allocator.resize(prev_slice, newsize));

                return prev_slice.ptr;
            }

            const new_slice = allocator.realloc(prev_slice, newsize) catch return null;
            return new_slice.ptr;
        }

        if (newsize == 0) return null;

        const new_ptr = allocator.alignedAlloc(u8, alignment, newsize) catch return null;
        return new_ptr.ptr;
    }

    pub const ReaderState = struct {
        reader: std.io.AnyReader,
        buffer: [1024]u8 = undefined,

        /// A `ReaderFn` that accepts a `helpers.ReaderState` as its user data. This provides a simple way
        /// to read from a `std.io.AnyReader` in a Lua chunk.
        ///
        /// This is the function that will be used when a `helpers.ReaderState` is passed to any function that requires
        /// a `ReaderFn`.
        pub fn read(L_opt: ?*c.lua_State, ud: ?*anyopaque, size: ?*usize) callconv(.C) [*c]const u8 {
            assert(L_opt != null);
            assert(ud != null);
            assert(size != null);

            const L: *State = @ptrCast(L_opt.?);
            const state: *ReaderState = @ptrCast(@alignCast(ud.?));

            size.?.* = state.reader.read(state.buffer[0..]) catch |err| {
                L.raise("wrapped lunaro reader returned an error: {s}", .{@errorName(err)});
            };

            return &state.buffer;
        }
    };

    pub const WriterState = struct {
        writer: std.io.AnyWriter,

        /// A `WriterFn` that accepts a `helpers.WriterState` as its user data. This provides a simple way
        /// to write to a `std.io.AnyWriter` in a Lua chunk.
        ///
        /// This is the function that will be used when a `helpers.WriterState` is passed to any function that requires
        /// a `WriterFn`.
        pub fn write(L_opt: ?*c.lua_State, p: ?*const anyopaque, sz: usize, ud: ?*anyopaque) callconv(.C) c_int {
            assert(L_opt != null);
            assert(ud != null);
            assert(p != null);

            const L: *State = @ptrCast(L_opt.?);
            const wrapper: *WriterState = @ptrCast(@alignCast(ud.?));
            const ptr: [*]const u8 = @ptrCast(p.?);

            wrapper.writer.writeAll(ptr[0..sz]) catch |err| {
                L.raise("wrapped lunaro writer returned an error: {s}", .{@errorName(err)});
            };

            return 0;
        }
    };
};

/// Export a zig function as the entry point of a Lua module. This wraps the function and exports it as
/// `luaopen_{name}`.
pub fn exportAs(comptime func: anytype, comptime name: []const u8) CFn {
    return struct {
        fn luaopen(L: ?*c.lua_State) callconv(.C) c_int {
            const fnc = comptime helpers.wrapCFn(func) orelse unreachable;

            return @call(.always_inline, fnc, .{L});
        }

        comptime {
            @export(luaopen, .{ .name = "luaopen_" ++ name });
        }
    }.luaopen;
}

test {
    std.testing.refAllDecls(@This());
}
