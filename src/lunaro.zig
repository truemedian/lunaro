const std = @import("std");

const assert = std.debug.assert;
const comptimePrint = std.fmt.comptimePrint;

const luaconf = @cImport({
    @cDefine("luajit_c", "1");
    @cInclude("luaconf.h");
});

pub const is_luajit = @hasDecl(luaconf, "LUA_PROGNAME") and std.mem.eql(u8, luaconf.LUA_PROGNAME, "luajit");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");

    if (is_luajit)
        @cInclude("luajit.h");
});

fn literal(comptime str: []const u8) [:0]const u8 {
    return (str ++ "\x00")[0..str.len :0];
}

fn lookup(comptime field: []const u8, comptime default: anytype) @TypeOf(default) {
    if (@hasDecl(c, field)) return @field(c, field);
    return default;
}

const arith_functions = struct {
    fn mtcall(L: *State, index: Index, field: [:0]const u8, args: Size) bool {
        const t = L.getmetafield(index, field);
        if (t != .nil) {
            L.insert(-@as(Index, args) - 1);
            L.call(args, 1);

            return true;
        }

        return false;
    }

    pub const stack_alt = struct {
        pub const add = 2;
        pub const sub = 2;
        pub const mul = 2;
        pub const div = 2;
        pub const idiv = 2;
        pub const mod = 2;
        pub const pow = 2;
        pub const unm = 1;
        pub const bnot = 1;
        pub const band = 2;
        pub const bor = 2;
        pub const bxor = 2;
        pub const shl = 2;
        pub const shr = 2;
    };

    pub fn le(L: *State, A: Index, B: Index) bool {
        const Ta = L.typeof(A);
        const Tb = L.typeof(B);

        if (Ta == .number and Tb == .number) {
            const a = L.tonumber(A);
            const b = L.tonumber(B);

            return a <= b;
        } else if (Ta == .string and Tb == .string) {
            const a = L.tostring(A).?;
            const b = L.tostring(B).?;

            return std.mem.order(u8, a, b) != .gt;
        }

        const absA = L.absindex(A);
        const absB = L.absindex(B);

        L.pushvalue(absA);
        L.pushvalue(absB);
        if (mtcall(L, -2, "__le", 2) or mtcall(L, -1, "__le", 2)) {
            const res = L.toboolean(-1);
            L.pop(1);
            return res;
        }

        L.rotate(-2, 1);
        if (mtcall(L, -1, "__lt", 2) or mtcall(L, -2, "__lt", 2)) {
            const res = L.toboolean(-1);
            L.pop(1);
            return !res;
        }

        L.raise("attempt to compare %s with %s", .{ L.typenameof(absA), L.typenameof(absB) });
    }

    pub fn add(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-2) and L.isinteger(-1)) {
                    const a = L.tointeger(-2);
                    const b = L.tointeger(-1);
                    L.pop(2);

                    return L.push(a +% b);
                }
            }

            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(a + b);
        }

        if (mtcall(L, -2, "__add", 2) or mtcall(L, -1, "__add", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn sub(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-2) and L.isinteger(-1)) {
                    const a = L.tointeger(-2);
                    const b = L.tointeger(-1);
                    L.pop(2);

                    return L.push(a -% b);
                }
            }

            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(a - b);
        }

        if (mtcall(L, -2, "__sub", 2) or mtcall(L, -1, "__sub", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn mul(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-2) and L.isinteger(-1)) {
                    const a = L.tointeger(-2);
                    const b = L.tointeger(-1);
                    L.pop(2);

                    return L.push(a *% b);
                }
            }

            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(a * b);
        }

        if (mtcall(L, -2, "__mul", 2) or mtcall(L, -1, "__mul", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn div(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-2) and L.isinteger(-1)) {
                    const a = L.tointeger(-2);
                    const b = L.tointeger(-1);
                    L.pop(2);

                    return L.push(@divTrunc(a, b));
                }
            }

            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(a / b);
        }

        if (mtcall(L, -2, "__div", 2) or mtcall(L, -1, "__div", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn idiv(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(@divTrunc(a, b));
        }

        if (mtcall(L, -2, "__idiv", 2) or mtcall(L, -1, "__idiv", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn mod(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-2) and L.isinteger(-1)) {
                    const a = L.tointeger(-2);
                    const b = L.tointeger(-1);
                    L.pop(2);

                    return L.push(std.zig.c_translation.signedRemainder(a, b));
                }
            }

            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(@mod(a, b));
        }

        if (mtcall(L, -2, "__mod", 2) or mtcall(L, -1, "__mod", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn pow(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-2) and L.isinteger(-1)) {
                    const a = L.tointeger(-2);
                    const b = L.tointeger(-1);
                    L.pop(2);

                    return L.push(std.math.pow(Integer, a, b));
                }
            }

            const a = L.tonumber(-2);
            const b = L.tonumber(-1);
            L.pop(2);

            return L.push(std.math.pow(Number, a, b));
        }

        if (mtcall(L, -2, "__pow", 2) or mtcall(L, -1, "__pow", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn unm(L: *State) void {
        if (L.isnumber(-1)) {
            if (c.LUA_VERSION_NUM >= 503) {
                if (L.isinteger(-1)) {
                    const a = L.tointeger(-1);
                    L.pop(1);

                    return L.push(-a);
                }
            }

            const a = L.tonumber(-1);
            L.pop(1);

            return L.push(-a);
        }

        if (mtcall(L, -1, "__unm", 1)) return;

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn bnot(L: *State) void {
        if (L.isnumber(-1)) {
            const a = L.tointeger(-1);
            L.pop(1);

            return L.push(~a);
        }

        if (mtcall(L, -1, "__bnot", 1)) return;

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn band(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            const a = L.tointeger(-2);
            const b = L.tointeger(-1);
            L.pop(2);

            return L.push(a & b);
        }

        if (mtcall(L, -2, "__band", 2) and mtcall(L, -1, "__band", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn bor(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            const a = L.tointeger(-2);
            const b = L.tointeger(-1);
            L.pop(2);

            return L.push(a | b);
        }

        if (mtcall(L, -2, "__bor", 2) or mtcall(L, -1, "__bor", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn bxor(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            const a = L.tointeger(-2);
            const b = L.tointeger(-1);
            L.pop(2);

            return L.push(a ^ b);
        }

        if (mtcall(L, -2, "__bxor", 2) or mtcall(L, -1, "__bxor", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn shl(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            const a = L.tointeger(-2);
            const amt = L.tointeger(-1);
            L.pop(2);

            if (amt >= @bitSizeOf(Integer)) return L.push(0);
            return L.push(a << @intCast(amt));
        }

        if (mtcall(L, -2, "__shl", 2) or mtcall(L, -1, "__shl", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }

    pub fn shr(L: *State) void {
        if (L.isnumber(-2) and L.isnumber(-1)) {
            const a = L.tointeger(-2);
            const amt = L.tointeger(-1);
            L.pop(2);

            if (amt >= @bitSizeOf(Integer)) return L.push(0);
            return L.push(a >> @intCast(amt));
        }

        if (mtcall(L, -2, "__shr", 2) or mtcall(L, -1, "__shr", 2)) return;

        if (!L.isnumber(-2))
            L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
    }
};

/// The type of floating point numbers in Lua. By default this is `f64`.
/// In Lua 5.1 and 5.2, it is possible that this may instead be an integer.
pub const Number = c.lua_Number;

/// The type of integers in Lua. By default this is `i64`.
pub const Integer = c.lua_Integer;

/// The type of unsigned integers in Lua. By default this is the unsigned variant of `Integer`.
pub const Unsigned = lookup("lua_Unsigned", std.meta.Int(.unsigned, @bitSizeOf(Integer)));

/// The type of indexes into the Lua stack. By default this is `i32`.
pub const Index = c_int;

/// The type of absolute indexes (eg. not pseudo indexes) into the Lua stack. This is the same as `Size`.
pub const AbsIndex = Size;

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

/// The structure used to hold debug information. Some fields may not exist in some versions of Lua.
pub const DebugInfo = c.lua_Debug;

/// The type of debug hook functions used by Lua.
pub const HookFn = c.lua_Hook;

/// The pseudo-index used to refer to the registry.
pub const REGISTRYINDEX = c.LUA_REGISTRYINDEX;

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

/// An opaque type representing a Lua thread. This is the only way to access or manipulate the Lua state.
///
/// Stack Documentation follows the Lua format: [-o, +p, x]
/// - The first field, o, is how many elements the function pops from the stack.
/// - The second field, p, is how many elements the function pushes onto the stack.
/// - Any function always pushes its results after popping its arguments.
///   - A field in the form x|y means the function can push (or pop) x or y elements, depending on the situation
///   - an interrogation mark '?' means that we cannot know how many elements the function pops/pushes by looking
///     only at its arguments (e.g., they may depend on what is on the stack).
/// - The third field, x, tells whether the function may raise errors:
///   - '-' means the function never raises any error
///   - 'm' means the function may raise out-of-memory errors and errors running a __gc metamethod
///   - 'e' means the function may raise any errors (it can run arbitrary Lua code, either directly or through
///     metamethods)
///   - 'v' means the function may raise an error on purpose.
pub const State = opaque {
    fn to(ptr: *State) *c.lua_State {
        return @ptrCast(ptr);
    }

    // state manipulation

    /// [-0, +0, -] Creates a new Lua state. Allows for custom allocation functions.
    ///
    /// This function **WILL NOT** work on Luajit on a 64 bit target.
    pub fn initWithAlloc(f: AllocFn, ud: ?*anyopaque) !*State {
        const ret = c.lua_newstate(f, ud);
        if (ret == null) return error.OutOfMemory;
        return @ptrCast(ret.?);
    }

    /// [-0, +0, -] Destroys all objects in the given state and frees all dynamic memory used by this state.
    pub fn close(L: *State) void {
        return c.lua_close(to(L));
    }

    /// [-0, +1, m] Creates a new Lua thread, pushes it onto the stack, and returns a pointer to it. This thread
    /// shares its global environment with the given thread.
    /// There is no explicit function to close or to destroy a thread. Threads are subject to garbage collection,
    /// like any Lua object.
    pub fn createcoroutine(L: *State) !*State {
        const ptr = c.lua_newthread(to(L));
        if (ptr == null) return error.OutOfMemory;
        return @ptrCast(ptr.?);
    }

    /// [-0, +0, -] Sets a new panic function and returns the old one.
    pub fn atpanic(L: *State, panicf: anytype) CFn {
        return c.lua_atpanic(to(L), wrapAnyFn(panicf));
    }

    // basic stack manipulation

    /// [-0, +0, -] Returns the pseudo-index that represents the i-th upvalue of the running function.
    pub fn upvalueindex(index: Index) Index {
        return c.lua_upvalueindex(index);
    }

    /// [-0, +0, -] Converts the acceptable index `index` into an absolute index (that is, one that does not depend
    /// on the stack top).
    pub fn absindex(L: *State, index: Index) Index {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_absindex(to(L), index);
        }

        if (index < 0 and index > REGISTRYINDEX)
            return L.gettop() + 1 + index;
        return index;
    }

    /// [-0, +0, -] Returns the index of the top element in the stack. This also represents the number of elements
    /// in the stack.
    pub fn gettop(L: *State) Index {
        return c.lua_gettop(to(L));
    }

    /// [-?, +?, -] Sets the stack top to the given index. If the new top is larger than the old one, then the new
    /// elements are filled with nil.
    pub fn settop(L: *State, index: Index) void {
        return c.lua_settop(to(L), index);
    }

    /// [-0, +1, -] Pushes a copy of the element at the given index onto the stack.
    pub fn pushvalue(L: *State, index: Index) void {
        return c.lua_pushvalue(to(L), index);
    }

    /// [-1, +0, -] Removes the element at the given valid index, shifting down the elements above this index to
    /// fill the gap.
    ///
    /// Cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    pub fn remove(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            L.rotate(index, -1);
            return L.pop(1);
        }

        return c.lua_remove(to(L), index);
    }

    /// [-1, +1, -] Moves the top element into the given valid index, shifting up the elements above this index to
    /// open space.
    ///
    /// This function cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    pub fn insert(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return L.rotate(index, 1);
        }

        return c.lua_insert(to(L), index);
    }

    /// [-1, +0, -] Moves the top element into the given valid index without shifting any element (therefore
    /// replacing the value at that given index),
    /// and then pops the top element.
    pub fn replace(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            L.copy(-1, index);
            return L.pop(1);
        }

        return c.lua_replace(to(L), index);
    }

    fn rotate_reverse(L: *State, start: Index, end: Index) void {
        var a = start;
        var b = end;

        while (a < b) : ({
            a += 1;
            b -= 1;
        }) {
            L.pushvalue(a);
            L.pushvalue(b);
            L.replace(a);
            L.replace(b);
        }
    }

    /// [-0, +0, -] Rotates the stack elements between the valid index idx and the top of the stack.
    ///
    /// The elements are rotated n positions in the direction of the top, for a positive n, or -n positions in the
    /// direction of the bottom, for a negative n.
    /// The absolute value of n must not be greater than the size of the slice being rotated.
    ///
    /// This function cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    pub fn rotate(L: *State, index: Index, amount: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_rotate(to(L), index, amount);
        } else {
            const idx = L.absindex(index);
            const elems = L.gettop() - idx + 1;
            var n = amount;
            if (n < 0) n += elems;

            if (n > 0 and n < elems) {
                L.ensurestack(2, "not enough stack slots available");
                n = elems - n;
                rotate_reverse(L, idx, idx + n - 1);
                rotate_reverse(L, idx + n, idx + elems - 1);
                rotate_reverse(L, idx, idx + elems - 1);
            }
        }
    }

    /// [-0, +0, -] Copies the element at index `src` into the valid index `dest`, replacing the value at that
    /// position. Values at other positions are not affected.
    pub fn copy(L: *State, src: Index, dest: Index) void {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_copy(to(L), src, dest);
        }

        const abs_dest = L.absindex(dest);
        L.ensurestack(1, "not enough stack slots");
        L.pushvalue(src);
        return L.replace(abs_dest);
    }

    /// [-0, +0, -] Ensures that the stack has space for at least n extra slots (that is, that you can safely push
    /// up to n values into it).
    /// It returns false if it cannot fulfill the request, either because it would cause the stack to be larger than
    /// a fixed maximum size(typically at least several thousand elements) or because it cannot allocate memory for
    /// the extra space.
    ///
    /// This function never shrinks the stack; if the stack already has space for the extra slots, it is left
    /// unchanged.
    pub fn checkstack(L: *State, extra: Size) bool {
        return c.lua_checkstack(to(L), extra) == 0;
    }

    /// [-?, +?, -] Exchange values between different threads of the same state.
    ///
    /// This function pops `n` values from the stack `src`, and pushes them onto the stack `dest`.
    pub fn xmove(src: *State, dest: *State, n: Size) void {
        return c.lua_xmove(to(src), to(dest), n);
    }

    /// [-n, +0, -] Pops n elements from the stack.
    pub fn pop(L: *State, n: Size) void {
        return c.lua_settop(to(L), -@as(Index, n) - 1);
    }

    // access functions (stack -> zig)

    /// [-0, +0, -] Returns true if the value at the given index is a number or a string convertible to a number.
    pub fn isnumber(L: *State, index: Index) bool {
        return c.lua_isnumber(to(L), index) != 0;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a string or a number (which is always
    /// convertible to a string).
    pub fn isstring(L: *State, index: Index) bool {
        return c.lua_isstring(to(L), index) != 0;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a C function.
    pub fn iscfunction(L: *State, index: Index) bool {
        return c.lua_iscfunction(to(L), index) != 0;
    }

    /// [-0, +0, -] Returns true if the value at the given index is an integer (that is, the value is a number and
    /// is represented as an integer).
    pub fn isinteger(L: *State, index: Index) bool {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_isinteger(to(L), index) != 0;
        }

        if (!L.isnumber(index)) return false;

        return @as(Integer, @intFromFloat(L.tonumber(index))) == L.tointeger(index);
    }

    /// [-0, +0, -] Returns true if the value at the given index is a userdata (either full or light).
    pub fn isuserdata(L: *State, index: Index) bool {
        return c.lua_isuserdata(to(L), index) != 0;
    }

    /// [-0, +0, -] Returns the type of the value in the given valid index.
    pub fn typeof(L: *State, index: Index) Type {
        return @enumFromInt(c.lua_type(to(L), index));
    }

    /// [-0, +0, -] Converts the Lua value at the given index to `Number`. The Lua value must be a number or a
    /// string convertible to a number; otherwise, returns 0.
    pub fn tonumber(L: *State, index: Index) Number {
        if (c.LUA_VERSION_NUM >= 502) {
            var isnum: c_int = 0;
            const value = c.lua_tonumberx(to(L), index, &isnum);

            if (isnum == 0) return 0;
            return value;
        }

        return c.lua_tonumber(to(L), index);
    }

    /// [-0, +0, -] Converts the Lua value at the given index to `Number`. The Lua value must be an integer or a
    /// number or string convertible to an integer; otherwise, returns 0.
    pub fn tointeger(L: *State, index: Index) Integer {
        if (c.LUA_VERSION_NUM >= 502) {
            var isnum: c_int = 0;
            const value = c.lua_tointegerx(to(L), index, &isnum);

            if (isnum == 0) return 0;
            return value;
        }

        return c.lua_tointeger(to(L), index);
    }

    /// [-0, +0, -] Converts the Lua value at the given index to `bool`.
    ///
    /// If the value is not `false` or `nil`, returns `true`; otherwise, returns `false`.
    pub fn toboolean(L: *State, index: Index) bool {
        return c.lua_toboolean(to(L), index) != 0;
    }

    /// [-0, +0, m] Converts the Lua value at the given index to a string. If the value is a number, then tostring
    /// also changes the actual value in the stack to a string (which will confuse `next`).
    pub fn tostring(L: *State, index: Index) ?[:0]const u8 {
        var ptr_len: usize = undefined;
        const ptr = c.lua_tolstring(to(L), index, &ptr_len);
        if (ptr == null) return null;

        return ptr[0..ptr_len :0];
    }

    /// [-0, +0, -] Returns the raw "length" of the value at the given index.
    ///
    /// For strings, this is the string length.
    /// For tables, this is the result of the length operator ('#') with no metamethods.
    /// For userdata, this is the size of the block of memory allocated for the userdata.
    /// For other values, it is 0.
    pub fn rawlen(L: *State, index: Index) usize {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_rawlen(to(L), index);
        }

        return c.lua_objlen(to(L), index);
    }

    /// [-0, +0, -] Converts the Lua value at the given index to a C function (or null).
    pub fn tocfunction(L: *State, index: Index) CFn {
        return c.lua_tocfunction(to(L), index);
    }

    /// [-0, +0, -] If the value at the given index is a full userdata, returns its block address. If the value is a
    /// light userdata, returns its pointer.
    pub fn touserdata(L: *State, comptime T: type, index: Index) ?*align(@alignOf(usize)) T {
        return @ptrCast(@alignCast(c.lua_touserdata(to(L), index)));
    }

    /// [-0, +0, -] Converts the value at the given index to a Lua thread (represented as `State`) or null.
    pub fn tothread(L: *State, index: Index) ?*State {
        return @ptrCast(c.lua_tothread(to(L), index));
    }

    /// [-0, +0, -] Converts the value at the given index to a pointer or null. Different objects give different
    /// pointers.
    ///
    /// There is no way to convert the pointer back to its original value.
    pub fn topointer(L: *State, index: Index) ?*const anyopaque {
        return c.lua_topointer(to(L), index);
    }

    /// [-(2|1), +1, e] Performs an arithmetic or bitwise operation over the two values (or one, in the case of
    /// negations) at the top of the stack. The function pops these values, performs the operation, and pushes the
    /// result back onto the stack.
    ///
    /// This function follows the semantics of the corresponding Lua operator (that is, it may call metamethods).
    pub fn arith(L: *State, op: ArithOp) void {
        if (c.LUA_VERSION_NUM >= 502) {
            if (c.LUA_VERSION_NUM >= 503 or @intFromEnum(op) >= 0) {
                return c.lua_arith(to(L), @intFromEnum(op));
            }
        }

        inline for (comptime std.enums.values(ArithOp)) |value| {
            if (@intFromEnum(value) < 0) {
                if (op == value) {
                    const func = @field(arith_functions, @tagName(value));

                    var scheck = StackCheck.init(L);
                    defer _ = scheck.check(func, L, -@field(arith_functions.stack_alt, @tagName(value)) + 1);

                    return func(L);
                }
            }
        }
    }

    /// [-0, +0, -] Returns true if the values at indices `a` and `b` are primitively equal (that is, without
    /// calling metamethods).
    pub fn rawequal(L: *State, a: Index, b: Index) bool {
        return c.lua_rawequal(to(L), a, b) != 0;
    }

    /// [-0, +0, e] Compares two Lua values. Returns true if the value at index `a` satisfies op when compared with
    /// the value at index `b`, following the semantics of the corresponding Lua operator (that is, it may call
    /// metamethods).
    pub fn compare(L: *State, a: Index, b: Index, op: CompareOp) bool {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_compare(to(L), a, b, @intFromEnum(op)) != 0;
        }

        switch (op) {
            .eq => return c.lua_equal(L.to(), a, b) != 0,
            .lt => return c.lua_lessthan(L.to(), a, b) != 0,
            .le => {
                const scheck = StackCheck.init(L);
                defer _ = scheck.check(arith_functions.le, L, 0);

                return arith_functions.le(L, a, b);
            },
        }
    }

    /// [-0, +0, -] Returns true if the value at the given index is a function (either C or Lua).
    pub fn isfunction(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TFUNCTION;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a table.
    pub fn istable(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TTABLE;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a full userdata.
    pub fn isfulluserdata(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TUSERDATA;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a light userdata.
    pub fn islightuserdata(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TLIGHTUSERDATA;
    }

    /// [-0, +0, -] Returns true if the value at the given index is nil.
    pub fn isnil(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TNIL;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a boolean.
    pub fn isboolean(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TBOOLEAN;
    }

    /// [-0, +0, -] Returns true if the value at the given index is a thread.
    pub fn isthread(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TTHREAD;
    }

    /// [-0, +0, -] Returns true if the value at the given index is not valid.
    pub fn isnone(L: *State, index: Index) bool {
        return c.lua_type(to(L), index) == c.LUA_TNONE;
    }

    /// [-0, +0, -] Returns true if the value at the given index is nil or not valid.
    pub fn isnoneornil(L: *State, index: Index) bool {
        const t = c.lua_type(to(L), index);
        return t == c.LUA_TNONE or t == c.LUA_TNIL;
    }

    // push functions (zig -> stack)

    /// [-0, +1, -] Pushes a nil value onto the stack.
    pub fn pushnil(L: *State) void {
        return c.lua_pushnil(to(L));
    }

    /// [-0, +1, -] Pushes a float with value `value` onto the stack.
    pub fn pushnumber(L: *State, value: Number) void {
        return c.lua_pushnumber(to(L), value);
    }

    /// [-0, +1, -] Pushes an integer with value `value` onto the stack.
    pub fn pushinteger(L: *State, value: Integer) void {
        return c.lua_pushinteger(to(L), value);
    }

    /// [-0, +1, m] Pushes a copy of the string `value` onto the stack.
    pub fn pushstring(L: *State, value: []const u8) void {
        _ = c.lua_pushlstring(to(L), value.ptr, value.len);
    }

    /// [-0, +1, m] Pushes a copy of the string `value` onto the stack. Returns a pointer to the internal copy, but
    /// does NOT reference it.
    pub fn pushstringExtra(L: *State, value: []const u8) [*:0]const u8 {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_pushlstring(to(L), value.ptr, value.len)[0..value.len :0];
        }

        c.lua_pushlstring(to(L), value.ptr, value.len);
        return L.tostring(-1).?;
    }

    /// [-0, +1, e] Pushes onto the stack a formatted string and returns a pointer to this string.
    ///
    /// It is similar to the C function sprintf, but the conversion specifiers are quite restricted:
    /// - There are no flags, widths, or precisions, and only the following conversion specifiers are allowed:
    /// - '%%' (inserts the character '%')
    /// - '%s' (inserts a zero-terminated string, with no size restrictions)
    /// - '%f' (inserts a Number)
    /// - '%I' (inserts a Integer)
    /// - '%p' (inserts a pointer as a hexadecimal numeral)
    /// - '%d' (inserts an c_int)
    /// - '%c' (inserts an c_int as a one-byte character)
    /// - '%U' (inserts a long int as a UTF-8 byte sequence) [Lua 5.3+]
    pub fn pushfstring(L: *State, fmt: [:0]const u8, args: anytype) [:0]const u8 {
        const ptr = @call(.auto, c.lua_pushfstring, .{ to(L), fmt.ptr } ++ args);
        return std.mem.sliceTo(ptr, 0);
    }

    /// [-n, +1, m] Pushes a new C closure onto the stack. Pops `n` values from the stack and sets the new closure's
    /// upvalues from the popped values.
    ///
    /// Does not wrap zig functions, only accepts CFn.
    pub fn pushclosure_unwrapped(L: *State, func: CFn, n: Size) void {
        return c.lua_pushcclosure(to(L), func, n);
    }

    /// [-n, +1, m] Pushes a new C closure onto the stack. Pops `n` values from the stack and sets the new closure's
    /// upvalues from the popped values.
    pub fn pushclosure(L: *State, comptime func: anytype, n: Size) void {
        return c.lua_pushcclosure(to(L), wrapAnyFn(func), n);
    }

    /// [-0, +1, -] Pushes a boolean value with value `value` onto the stack.
    pub fn pushboolean(L: *State, value: bool) void {
        return c.lua_pushboolean(to(L), @intFromBool(value));
    }

    /// [-0, +1, -] Pushes a light userdata onto the stack.
    pub fn pushlightuserdata(L: *State, ptr: anytype) void {
        return c.lua_pushlightuserdata(to(L), @ptrCast(@constCast(ptr)));
    }

    /// [-0, +1, -] Pushes the thread represented by `L` onto the stack.
    pub fn pushthread(L: *State) bool {
        return c.lua_pushthread(to(L)) != 0;
    }

    // get functions (Lua -> stack)

    /// [-0, +1, e] Pushes onto the stack the value of the global `name`. Returns the type of that value.
    pub fn getglobal(L: *State, name: [:0]const u8) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_getglobal(to(L), name.ptr));
        }

        c.lua_getglobal(to(L), name.ptr);
        return L.typeof(-1);
    }

    /// [-1, +1, e] Pushes onto the stack the value t[k], where t is the value at the given index and k is the value
    /// at the top of the stack. Returns the type of the pushed value.
    ///
    /// This function pops the key from the stack (putting the resulting value in its place). As in Lua, this
    /// function may trigger a metamethod for the "index" event.
    pub fn gettable(L: *State, index: Index) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_gettable(to(L), index));
        }

        c.lua_gettable(to(L), index);
        return L.typeof(-1);
    }

    /// [-0, +1, e] Pushes onto the stack the value t[k], where t is the value at the given index.
    ///
    /// As in Lua, this function may trigger a metamethod for the "index" event.
    pub fn getfield(L: *State, index: Index, name: [:0]const u8) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_getfield(to(L), index, name.ptr));
        }

        c.lua_getfield(to(L), index, name.ptr);
        return L.typeof(-1);
    }

    /// [-0, +1, e] Pushes onto the stack the value t[n], where t is the value at the given index.
    ///
    /// As in Lua, this function may trigger a metamethod for the "index" event.
    pub fn geti(L: *State, index: Index, n: Integer) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_geti(to(L), index, n));
        }

        const abs = L.absindex(index);
        L.pushinteger(n);
        return L.gettable(abs);
    }

    /// [-1, +1, -] Pushes onto the stack the value t[i], where t is the value at the given index and i is the value
    /// at the top of the stack.
    ///
    /// This function pops the key from the stack (putting the resulting value in its place). This access is "raw"
    /// and does not invoke metamethods.
    pub fn rawget(L: *State, index: Index) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_rawget(to(L), index));
        }

        c.lua_rawget(to(L), index);
        return L.typeof(-1);
    }

    /// [-0, +1, -] Pushes onto the stack the value t[n], where t is the value at the given index.
    ///
    /// The access is raw; that is, it does not invoke metamethods.
    pub fn rawgeti(L: *State, index: Index, n: Integer) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_rawgeti(to(L), index, n));
        }

        if (n > std.math.maxInt(c_int)) {
            L.pushinteger(n);
            return L.rawget(index);
        } else {
            c.lua_rawgeti(to(L), index, @as(c_int, @intCast(n)));
            return L.typeof(-1);
        }
    }

    /// [-0, +1, -] Pushes onto the stack the value t[p], where t is the value at the given index and p is any
    /// pointer.
    ///
    /// The access is raw; that is, it does not invoke metamethods.
    pub fn rawgetp(L: *State, index: Index, ptr: anytype) Type {
        assert(@typeInfo(@TypeOf(ptr)) == .Pointer);
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_rawgetp(to(L), index, @ptrCast(ptr)));
        }

        const abs = L.absindex(index);
        L.pushlightuserdata(ptr);
        return L.rawget(abs);
    }

    /// [-0, +1, m] Creates a new empty table and pushes it onto the stack. Parameter `narr` is a hint for how many
    /// elements the table will have as a sequence; parameter `nrec` is a hint for how many other elements the table
    /// will have.
    ///
    /// Lua may use these hints to preallocate memory for the new table. This preallocation is useful for
    /// performance when you know in advance how many elements the table will have.
    pub fn createtable(L: *State, narr: Size, nrec: Size) void {
        return c.lua_createtable(to(L), narr, nrec);
    }

    /// [-0, +1, m] This function allocates a new block of memory with the given size, pushes onto the stack a new
    /// full userdata with the block address, and returns this address.
    ///
    /// The host program can freely use this memory.
    pub fn newuserdata(L: *State, size: Size) *align(@alignOf(usize)) anyopaque {
        if (c.LUA_VERSION_NUM >= 504) {
            return @alignCast(c.lua_newuserdatauv(to(L), size, 1).?);
        }

        return @alignCast(c.lua_newuserdata(to(L), size).?);
    }

    /// [-0, +(0|1), -] If the value at the given index has a metatable, the function pushes that metatable onto the
    /// stack and returns true.
    /// Otherwise, the function returns false and pushes nothing on the stack.
    pub fn getmetatable(L: *State, index: Index) bool {
        if (c.LUA_VERSION_NUM >= 504) {
            return c.lua_getmetatable(to(L), index) != 0;
        }

        return c.lua_getmetatable(to(L), index) != 0;
    }

    /// [-0, +1, m] Creates a new empty table and pushes it onto the stack.
    pub fn newtable(L: *State) void {
        return c.lua_newtable(to(L));
    }

    /// [-0, +1, -] Pushes onto the stack the global environment.
    pub fn pushglobaltable(L: *State) void {
        if (c.LUA_VERSION_NUM >= 502) {
            _ = L.rawgeti(REGISTRYINDEX, c.LUA_RIDX_GLOBALS);
            return;
        }

        return c.lua_pushvalue(to(L), c.LUA_GLOBALSINDEX);
    }

    /// [-0, +1, -] Pushes onto the stack the Lua value associated with the full userdata at the given index.
    ///
    /// Returns the type of the pushed value.
    pub fn getuservalue(L: *State, index: Index) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_getuservalue(to(L), index));
        }

        if (c.LUA_VERSION_NUM >= 502) {
            c.lua_getuservalue(to(L), index);

            if (L.istable(-1)) {
                const typ = L.rawgeti(-1, 1);
                L.remove(-2);

                return typ;
            }

            return .nil;
        }

        if (!L.isfulluserdata(index))
            L.raise("full userdata expected", .{});

        const ptr = L.topointer(index).?;
        return L.rawgetp(REGISTRYINDEX, ptr);
    }

    // set functions (stack -> Lua)

    /// [-1, +0, e] Pops a value from the stack and sets it as the new value of global name.
    pub fn setglobal(L: *State, name: [:0]const u8) void {
        return c.lua_setglobal(to(L), name.ptr);
    }

    /// [-2, +0, e] Does the equivalent to t[k] = v, where t is the value at the given index, v is the value at the
    /// top of the stack, and k is the value just below the top.
    ///
    /// This function pops both the key and the value from the stack. As in Lua, this function may trigger a
    /// metamethod for the "newindex" event.
    pub fn settable(L: *State, index: Index) void {
        return c.lua_settable(to(L), index);
    }

    /// [-1, +0, e] Does the equivalent to t[k] = v, where t is the value at the given index and v is the value at
    /// the top of the stack.
    ///
    /// This function pops the value from the stack. As in Lua, this function may trigger a metamethod for the
    /// "newindex" event.
    pub fn setfield(L: *State, index: Index, name: [:0]const u8) void {
        return c.lua_setfield(to(L), index, name.ptr);
    }

    /// [-1, +0, e] Does the equivalent to t[n] = v, where t is the value at the given index and v is the value at
    /// the top of the stack.
    ///
    /// This function pops the value from the stack. As in Lua, this function may trigger a metamethod for the
    /// "newindex" event.
    pub fn seti(L: *State, index: Index, n: Integer) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_seti(to(L), index, n);
        }

        const abs = L.absindex(index);
        L.pushinteger(n);
        return L.settable(abs);
    }

    /// [-2, +0, m] Does the equivalent to t[k] = v, where t is the value at the given index, v is the value at the
    /// top of the stack, and k is the value just below the top.
    ///
    /// This function pops the both the key and value from the stack. The assignment is raw; that is, it does not
    /// invoke metamethods.
    pub fn rawset(L: *State, index: Index) void {
        return c.lua_rawset(to(L), index);
    }

    /// [-1, +0, m] Does the equivalent of t[n] = v, where t is the value at the given index and v is the value at
    /// the top of the stack.
    ///
    /// This function pops the value from the stack. The assignment is raw; that is, it does not invoke metamethods.
    pub fn rawseti(L: *State, index: Index, n: Size) void {
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_rawseti(to(L), index, n);
        }

        return c.lua_rawseti(to(L), index, n);
    }

    /// [-1, +0, m] Does the equivalent of t[p] = v, where t is the value at the given index, v is the value at the
    /// top of the stack, and p is any pointer (which will become lightuserdata).
    ///
    /// The assignment is raw; that is, it does not invoke metamethods.
    pub fn rawsetp(L: *State, index: Index, ptr: anytype) void {
        assert(@typeInfo(@TypeOf(ptr)) == .Pointer);
        if (c.LUA_VERSION_NUM >= 503) {
            return c.lua_rawsetp(to(L), index, @ptrCast(ptr));
        }

        const abs = L.absindex(index);
        L.pushlightuserdata(ptr);
        L.insert(-2);
        return L.rawset(abs);
    }

    /// [-1, +0, -] Pops a table from the stack and sets it as the new metatable for the value at the given index.
    pub fn setmetatable(L: *State, index: Index) void {
        _ = c.lua_setmetatable(to(L), index);
        return;
    }

    /// [-1, +0, -] Pops a value from the stack and sets it as the new value associated to the full userdata at the
    /// given index.
    pub fn setuservalue(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 503) {
            _ = c.lua_setuservalue(to(L), index);
            return;
        }

        if (c.LUA_VERSION_NUM >= 502) {
            c.lua_getuservalue(to(L), index);
            if (!L.istable(-1)) {
                L.pop(1);
                L.newtable();
            }

            L.insert(-2);
            L.rawseti(-2, 1);
            return c.lua_setuservalue(to(L), index);
        }

        if (!L.isfulluserdata(index))
            L.raise("full userdata expected", .{});

        const ptr = L.topointer(index).?;
        return L.rawsetp(REGISTRYINDEX, ptr);
    }

    // load and call functions

    /// [-(nargs+1), +nresults, e] Calls a function. The following protocol must be followed:
    ///
    /// - The function to be called is pushed onto the stack.
    /// - The arguments are pushed in direct order (the first argument is pushed first).
    /// - Then call `State.call`, the function and all arguments are popped from the stack, and the function's
    /// results are pushed onto the stack.
    /// - The number of results is adjusted to `nresults`, unless `nresults` is `null` (indicating you want all
    /// returned values).
    /// - The function results are pushed in direct order (the first result is pushed first), such that the last
    /// result is on the top of the stack.
    pub fn call(L: *State, nargs: Size, nresults: ?Size) void {
        const nres: Index = nresults orelse c.LUA_MULTRET;

        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_callk(to(L), nargs, nres, 0, null);
        }

        return c.lua_call(to(L), nargs, nres);
    }

    /// [-(nargs + 1), +(nresults|1), -] Calls a function in protected mode. Both `nargs` and `nresults` have the
    /// same meaning as in `call`. And like `call`, the function and all arguments are popped from the stack when
    /// the function is called.
    ///
    /// If there are no errors during the call, `State.pcall` behaves exactly like `State.call`. However, if there
    /// is any error, `State.pcall` catches it, pushes a single value on the stack (the error message), and returns
    /// an error code.
    ///
    /// If `handler_index` is zero, the error object on the stack is exactly the original error object. Otherwise
    /// `handler_index` is the stack index of a message handler. In case of runtime errors, this function will be
    /// called with the error object and its return value will be the object pushed on the stack by `State.pcall`.
    pub fn pcall(L: *State, nargs: Size, nresults: ?Size, handler_index: Index) ThreadStatus {
        const nres: Index = nresults orelse c.LUA_MULTRET;

        if (c.LUA_VERSION_NUM >= 502) {
            return @enumFromInt(c.lua_pcallk(to(L), nargs, nres, handler_index, 0, null));
        }

        return @enumFromInt(c.lua_pcall(to(L), nargs, nres, handler_index));
    }

    /// [-0, +1, -] Loads a Lua chunk without running it. If there are no errors, `load` pushes the compiled chunk
    /// as a Lua function on top of the stack. Otherwise, it pushes an error message.
    ///
    /// `load` uses the stack internally, so the reader function must always leave the stack unmodified when
    /// returning.
    ///
    /// If the resulting function has upvalues, its first upvalue is set to the value of the global environment.
    /// When loading main chunks, this upvalue will be the _ENV variable. Other upvalues are initialized with nil.
    pub fn load(L: *State, reader: anytype, chunkname: [:0]const u8, mode: LoadMode) ThreadStatus {
        const read = @typeInfo(@TypeOf(reader)).Pointer.child.read;

        if (c.LUA_VERSION_NUM >= 502) {
            return @enumFromInt(c.lua_load(
                to(L),
                read,
                reader,
                chunkname,
                switch (mode) {
                    .binary => "b",
                    .text => "t",
                    .either => null,
                },
            ));
        }

        if (reader.mode == .binary and mode == .text)
            L.raise("attempt to load a binary chunk (mode is 'text')", .{});

        if (reader.mode == .text and mode == .binary)
            L.raise("attempt to load a text chunk (mode is 'binary')", .{});

        return @enumFromInt(c.lua_load(to(L), read, reader, chunkname));
    }

    /// [-0, +0, -] Dumps a function as a binary chunk. Receives a Lua function on the top of the stack and produces
    /// a binary chunk that, if loaded again, results in a function equivalent to the one dumped.
    ///
    /// If `strip` is true, the binary representation may not include all debug information about the function, to
    /// save space. The value returned is the error code returned by the last call to the writer; `ok` means no
    /// errors. This function does not pop the Lua function from the stack.
    pub fn dump(L: *State, writer: anytype, strip: bool) ThreadStatus {
        if (@typeInfo(@TypeOf(writer)) != .Pointer)
            @compileError("expected *LuaWriter, got " ++ @typeName(@TypeOf(writer)));
        const write = @typeInfo(@TypeOf(writer)).Pointer.child.write;

        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.lua_dump(to(L), write, writer, @intFromBool(strip)));
        }

        return @enumFromInt(c.lua_dump(to(L), write, writer));
    }

    // coroutine functions

    /// [-?, +?, -] Yields a coroutine. This function MUST only be used as a tailcall.
    ///
    /// The running coroutine suspends it's execution and the call to `State.resume` that started this coroutine
    /// returns. The parameter `nresults` is the number of values from the stack that are passed as results to
    /// `State.resume`.
    pub fn yield(L: *State, nresults: Size) c_int {
        if (c.LUA_VERSION_NUM >= 503) {
            _ = c.lua_yieldk(to(L), nresults, 0, null);
            unreachable;
        }

        // before 5.3, lua_yield returns a magic value that MUST be returned to Lua's core
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_yieldk(to(L), nresults, 0, null);
        }

        return c.lua_yield(to(L), nresults);
    }

    /// [-?, +?, -] Starts or resumes a coroutine in the given thread.
    ///
    /// This call returns when the coroutine suspends or finishes its execution. When it returns, the stack contains
    /// all values passed to `yield`, or all values returned by the body function. This function returns `.yield` if
    /// the coroutine yields, `.ok` if the coroutine finishes its execution without errors, or an error code in case
    /// of errors (see `ThreadStatus`).
    ///
    /// In case of errors, the stack is not unwound, so you can use the debug API over it. The error object is on the top of the stack.
    ///
    /// To resume a coroutine, you remove any results from the last `yield`, put on its stack only the values to be passed as results from yield, and then call `resume.
    pub fn @"resume"(L: *State, nargs: Size) ThreadStatus {
        if (c.LUA_VERSION_NUM >= 504) {
            var res: c_int = 0;
            return @enumFromInt(c.lua_resume(to(L), null, nargs, &res));
        }

        if (c.LUA_VERSION_NUM >= 502) {
            return @enumFromInt(c.lua_resume(to(L), null, nargs));
        }

        return @enumFromInt(c.lua_resume(to(L), nargs));
    }

    /// [-0, +0, -] Returns the status of the thread `L`.
    ///
    /// You can only call functions in threads with status `.ok`.
    /// You can only resume threads with status `.ok` or `.yield`.
    pub fn status(L: *State) ThreadStatus {
        return @enumFromInt(c.lua_status(to(L)));
    }

    // isyieldable unimplementable in 5.2 and 5.1
    // setwarnf unimplementable in 5.3 and 5.2 and 5.1
    // warning unimplementable in 5.3 and 5.2 and 5.1

    // TODO: gc

    // miscellaneous functions

    /// [-1, +0, v] Generates a Lua error, using the value at the top of the stack as the error object.
    pub fn throw(L: *State) noreturn {
        _ = c.lua_error(to(L));
        unreachable;
    }

    /// [-1, +(2|0), e] Pops a key from the stack, and pushes a key–value pair from the table at the given index
    /// (the "next" pair after the given key). If there are no more elements in the table, then `next` returns 0 and
    /// pushes nothing.
    pub fn next(L: *State, index: Index) bool {
        return c.lua_next(to(L), index) != 0;
    }

    /// [-n, +1, e] Concatenates the `n` values at the top of the stack, pops them, and leaves the result at the top.
    ///
    /// Concatenation is performed following the usual semantics of Lua.
    pub fn concat(L: *State, items: Size) void {
        return c.lua_concat(to(L), items);
    }

    /// [-0, +1, -] Pushes the length of the value at the given index onto the stack. It is equivalent to the '#'
    /// operator in Lua.
    pub fn len(L: *State, index: Index) void {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.lua_len(to(L), index);
        }

        switch (L.typeof(index)) {
            .string => {
                return L.pushinteger(@intCast(c.lua_objlen(to(L), index)));
            },
            .table => if (!L.callmeta(index, "__len")) {
                return L.pushinteger(@intCast(c.lua_objlen(to(L), index)));
            },
            .userdata => if (!L.callmeta(index, "__len")) {
                L.raise("attempt to get length of a userdata value", .{});
            },
            else => L.raise("attempt to get length of a %s value", .{L.typenameof(index)}),
        }
    }

    // debug api

    /// [-0, +0, -] Gets information about the interpreter runtime stack.
    ///
    /// This function fills parts of a `DebugInfo` struct with an identification of the activation record of the
    /// function executing at a given level.
    ///
    /// Level 0 is the current running function, whereas level `n+1` is the function that has called level `n`.
    /// Returns false if the given level is greater than the current stack depth.
    pub fn getstack(L: *State, level: Size, ar: *DebugInfo) bool {
        return c.lua_getstack(to(L), level, ar) != 0;
    }

    /// [-(0|1), +(0|1|2), e] Gets information about a specific function or function invocation.
    ///
    /// To get information about a function invokation, `ar` must be a valid activation record that was filled by a
    /// previous call to `State.getstack` or given as argument to a hook.
    ///
    /// If the first character of `what` is `>`, the function is popped from the stack.
    ///
    /// The following values of `what` are valid:
    /// - 'n': fills in the field `name` and `namewhat`.
    /// - 'S': fills in the fields `source`, `short_src`, `linedefined`, `lastlinedefined`, and `what`.
    /// - 'l': fills in the field `currentline`.
    /// - 't': fills in the field `istailcall` [Lua 5.2+].
    /// - 'u': fills in the field `nups`, `nparams` [Lua 5.2+], and `isvararg` [Lua 5.2+].
    /// - 'f': pushes onto the stack the function that is running at the given level.
    /// - 'L': pushes onto the stack a table whose indices are the numbers of the lines that are valid on the
    ///        function. (A valid line is a line with some associated code, that is, a line where you can put a break
    ///        point. Non-valid lines include empty lines and comments.).
    ///
    /// If `f` and `L` are provided, the function is pushed first.`
    ///
    /// Returns `false` on error (such as an invalid option in `what`).
    pub fn getinfo(L: *State, what: [:0]const u8, ar: *DebugInfo) bool {
        return c.lua_getinfo(to(L), what.ptr, ar) != 0;
    }

    /// [-0, +(1|0), -] Gets information about a local variable of a given activation record.
    ///
    /// Pushes the value on the stack and return's it's name.
    ///
    /// The parameter `ar` must be a valid activation record that was filled by a previous call to `State.getstack`
    /// or given as argument to a hook. The index `n` selects which local variable to inspect (1 is the first parameter or active local variable).
    ///
    /// Returns null and pushes nothing if the index is greater than the number of active local variables.
    pub fn getlocal(L: *State, ar: *DebugInfo, n: Size) ?[:0]const u8 {
        const ptr = c.lua_getlocal(to(L), ar, n);
        if (ptr == null) return null;
        return std.mem.sliceTo(ptr, 0);
    }

    /// [-(1|0), +0, -] Sets the value of a local variable of a given activation record.
    ///
    /// Pops the value from the stack and sets it as the new value of the local variable.
    ///
    /// The parameter `ar` must be a valid activation record that was filled by a previous call to `State.getstack`
    /// or given as argument to a hook. The index `n` selects which local variable to inspect (1 is the first parameter or active local variable).
    ///
    /// Returns null and pops nothing if the index is greater than the number of active local variables.
    pub fn setlocal(L: *State, ar: *DebugInfo, n: Size) ?[:0]const u8 {
        const ptr = c.lua_setlocal(to(L), ar, n);
        if (ptr == null) return null;
        return std.mem.sliceTo(ptr, 0);
    }

    /// [-0, +(0|1), -] Gets information about the n-th upvalues of the closure at index `funcindex`. It pushes the
    /// upvalue's value onto the stack and returns its name. Returns null and pushes nothing if there is no upvalue with the given index.
    ///
    /// Upvalues are numbered in an arbitrary order. Upvalues for C closures all have a name of empty string `""`.
    pub fn getupvalue(L: *State, funcindex: Index, n: Size) ?[:0]const u8 {
        const ptr = c.lua_getupvalue(to(L), funcindex, n);
        if (ptr == null) return null;
        return std.mem.sliceTo(ptr, 0);
    }

    /// [-(0|1), +0, -] Sets the value of the n-th upvalue of the closure at index `funcindex`. It assigns the value
    /// at the top of the stack to the upvalue and returns its name. It also pops the value from the stack.
    ///
    /// Returns null and pops nothing if there is no upvalue with the given index.
    pub fn setupvalue(L: *State, funcindex: Index, n: Size) ?[:0]const u8 {
        const ptr = c.lua_setupvalue(to(L), funcindex, n);
        if (ptr == null) return null;
        return std.mem.sliceTo(ptr, 0);
    }

    // upvalueid unimplementable in 5.3 and 5.2 and 5.1
    // upvaluejoin unimplementable in 5.3 and 5.2 and 5.1

    // TODO: better binding for hook
    /// [-0, +0, -] Sets the debugging hook function. `func` is the function to be called. `mask` specifies on which
    /// events the hook will be called, and `count` is the only used with LUA_MASKCOUNT.
    ///
    /// Each event is described below:
    /// - call: called when the interpreter calls a functions, just after Lua enters the function, but before the
    ///   function gets it's arguments.
    /// - return: called when the interpreter returns from a function. The hook is called just before Lua leaves the
    ///   function. You have no access to the values to be returned by the function.
    /// - line: called when the interpreter is about to start the execution of a new line of code, or when it jumps
    ///   back in the code (even to the same line). (This event only happens while Lua is executing a Lua function.)
    /// - count: called after the interpreter executes every `count` instructions. (This event only happens while Lua
    ///   is executing a Lua function.)
    ///
    /// If `mask` is zero, the debug hook is disabled.
    pub fn sethook(L: *State, func: HookFn, mask: c_int, count: Size) void {
        _ = c.lua_sethook(to(L), func, mask, count);
    }

    /// [-0, +0, -] Returns the current hook function.
    pub fn gethook(L: *State) HookFn {
        return c.lua_gethook(to(L));
    }

    /// [-0, +0, -] Returns the current hook mask.
    pub fn gethookmask(L: *State) c_int {
        return c.lua_gethookmask(to(L));
    }

    /// [-0, +0, -] Returns the current hook count.
    pub fn gethookcount(L: *State) Size {
        return @intCast(c.lua_gethookcount(to(L)));
    }

    // auxiliary library

    /// [-0, +0, v] Checks whether the code making the call and the Lua library being called are using the same version
    /// of Lua and the same numeric types.
    pub fn checkversion(L: *State) void {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.luaL_checkversion(to(L));
        }

        if (L.loadstring("return _VERSION", "lunaro/checkversion", .either) != .ok or L.pcall(0, 1, 0) != .ok) {
            L.raise("lua core does not expose version information, cannot assume compatability", .{});
        }

        if (L.tostring(-1)) |core_version| {
            if (!std.mem.eql(u8, core_version, c.LUA_VERSION)) {
                L.raise("version mismatch: app needs %s, Lua core provides %s", .{ c.LUA_VERSION, core_version });
            }
        }

        L.pop(1);
    }

    /// [-0, +(0|1), m] Pushes onto the stack the field `event` from the metatable of the object at index `obj` and
    /// returns the type of the pushed value. If the object does not have a metatable, or if the metatable does not
    /// have this field, pushes nothing and returns `.nil`.
    pub fn getmetafield(L: *State, obj: Index, event: [:0]const u8) Type {
        if (c.LUA_VERSION_NUM >= 503) {
            return @enumFromInt(c.luaL_getmetafield(to(L), obj, event.ptr));
        }

        if (c.luaL_getmetafield(to(L), obj, event.ptr) == 0) {
            return .nil;
        }

        return L.typeof(-1);
    }

    /// [-0, +(0|1), e] Calls a metamethod. If the object at index `obj` has a metatable and this metatable has a
    /// field `event`, this function calls this field passing the object as its only argument. In this case this
    /// function returns true and pushes onto the stack the value returned by the call. If there is no metatable or
    /// no metamethod, this function returns false (without pushing any value on the stack).
    pub fn callmeta(L: *State, obj: Index, event: [:0]const u8) bool {
        return c.luaL_callmeta(to(L), obj, event.ptr) != 0;
    }

    // argerror replaced with check mechanism
    // typeerror replaced with check mechanism
    // checklstring replaced with check mechanism
    // optlstring replaced with check mechanism
    // checknumber replaced with check mechanism
    // optnumber replaced with check mechanism
    // checkinteger replaced with check mechanism
    // optinteger replaced with check mechanism
    // checktype replaced with check mechanism
    // checkany replaced with check mechanism

    /// [-0, +0, v] Checks whether the function argument `arg` has type `typ`.
    pub fn ensuretype(L: *State, arg: Size, typ: Type) void {
        c.luaL_checktype(to(L), arg, @intFromEnum(typ));
    }

    /// [-0, +0, v] Checks whether the function argument `arg` exists, even if it is nil.
    pub fn ensureexists(L: *State, arg: Size) void {
        c.luaL_checkany(to(L), arg);
    }

    /// [-0, +0, v] Grows the stack size to `top + sz` elements, raising an error if the stack cannot grow to that
    /// size. msg is an additional text to go into the error message.
    pub fn ensurestack(L: *State, sz: Size, msg: [:0]const u8) void {
        c.luaL_checkstack(to(L), sz, msg.ptr);
    }

    /// [-0, +1, m] If the registry already has the key `tname`, return false. Otherwise creates a new table to be
    /// used as a metatable for userdata, adds to this new table the pair `__name = tname`, adds the table to the
    /// registry under the key `tname` and returns true.
    ///
    /// In both cases pushes the final value associated with `tname` in the registry.
    pub fn newmetatablefor(L: *State, tname: [:0]const u8) bool {
        return c.luaL_newmetatable(to(L), tname.ptr) != 0;
    }

    /// [-0, +0, -] Sets the metatable of the object at the top of the stack as the metatable associated with name
    /// `tname` in the registry
    pub fn setmetatablefor(L: *State, tname: [:0]const u8) void {
        if (c.LUA_VERSION_NUM >= 502) {
            c.luaL_setmetatable(to(L), tname.ptr);
        }

        _ = L.getmetatablefor(tname);
        L.setmetatable(-2);
    }

    // testudata replaced with userdata mechanism
    // checkudata replaced with userdata mechanism

    /// [-0, +1, m] Pushes onto the stack a string identifying the current position of the control at level lvl in the call stack. Typically this string has the following format:
    ///
    ///    chunkname:currentline:
    ///
    /// Level 0 is the running function, level 1 is the function that called the running function, etc.
    /// This function is used to build a prefix for error messages.
    pub fn where(L: *State, lvl: Size) void {
        c.luaL_where(to(L), lvl);
    }

    /// [-0, +0, v] Raises an error. The error message format is given by fmt plus any extra arguments, following
    /// the same rules of `pushfstring`. It also adds at the beginning of the message the file name and the line
    /// number where the error occurred, if this information is available.
    pub fn raise(L: *State, msg: [:0]const u8, args: anytype) noreturn {
        if (args.len == 0) {
            L.where(1);
            L.pushstring(msg);
            L.concat(2);
            L.throw();
        } else {
            const ArgsTuple = std.meta.Tuple(blk: {
                var types: [args.len]type = undefined;

                inline for (@typeInfo(@TypeOf(args)).Struct.fields, 0..) |field, i| {
                    if (field.type == [:0]const u8 or field.type == []const u8) {
                        types[i] = [*:0]const u8;
                    } else {
                        types[i] = field.type;
                    }
                }

                break :blk types[0..];
            });

            var new_args: ArgsTuple = undefined;
            inline for (args, 0..) |arg, i| {
                if (@TypeOf(arg) == [:0]const u8) {
                    new_args[i] = arg.ptr;
                } else if (@TypeOf(arg) == []const u8) {
                    new_args[i] = L.pushstringExtra(arg);
                } else {
                    new_args[i] = arg;
                }
            }

            _ = @call(.auto, c.luaL_error, .{ to(L), msg.ptr } ++ new_args);
            unreachable;
        }
    }

    // checkoption replaced with check mechanism

    /// [-1, +0, m] Creates and returns a reference, in the table at index t, for the object at the top of the stack
    /// (and pops the object).
    ///
    /// A reference is a unique integer key. As long as you do not manually add integer keys into table t, `ref`
    /// ensures the uniqueness of the key it returns. You can retrieve an object referred by reference r by calling
    /// `L.rawgeti(t, r)`. Function `unref` frees a reference and its associated object.
    ///
    /// If the object at the top of the stack is nil, luaL_ref returns the constant `State.refnil`. The constant
    /// `State.noref` is guaranteed to be different from any reference returned by `ref`.
    pub fn ref(L: *State, t: Index) c_int {
        return c.luaL_ref(to(L), t);
    }

    /// [-0, +0, -] Releases reference refi from the table at index t (see `ref`). The entry is removed from the
    /// table, so that the referred object can be collected. The reference refi is also freed to be used again.
    pub fn unref(L: *State, t: Index, refi: c_int) void {
        c.luaL_unref(to(L), t, refi);
    }

    // TODO: loadfile

    /// [-0, +1, -] Loads a string as a Lua chunk. This function uses `load` to load the chunk, so all caveats about
    /// that function apply.
    pub fn loadstring(L: *State, str: []const u8, chunkname: [:0]const u8, mode: LoadMode) ThreadStatus {
        if (c.LUA_VERSION_NUM >= 502) {
            return @enumFromInt(c.luaL_loadbufferx(
                to(L),
                str.ptr,
                str.len,
                chunkname,
                switch (mode) {
                    .binary => "b",
                    .text => "t",
                    .either => null,
                },
            ));
        }

        return @enumFromInt(c.luaL_loadbuffer(to(L), str.ptr, str.len, chunkname));
    }

    /// [-0, +0, -] Creates a new Lua state with a default allocator function and panic function.
    pub fn init() !*State {
        const ret = c.luaL_newstate();
        if (ret == null) return error.OutOfMemory;
        return @ptrCast(ret.?);
    }

    /// [-0, +0, e] Returns the "length" of the value at the given index as a number; it is equivalent to the '#'
    /// operator in Lua. Raises an error if the result of the operation is not an integer. (This case only can
    /// happen through metamethods.)
    pub fn lenof(L: *State, obj: Index) Size {
        if (c.LUA_VERSION_NUM >= 502) {
            return @intCast(c.luaL_len(to(L), obj));
        }

        L.len(obj);
        const n = L.tointeger(-1);
        L.pop(1);
        return @intCast(n);
    }

    /// [-0, +1, m] Creates a copy of string `s` by replacing any occurrence of the string `p` with the string `r`.
    /// Pushes the resulting string on the stack and returns it.
    pub fn gsub(L: *State, s: [:0]const u8, p: [:0]const u8, r: [:0]const u8) [:0]const u8 {
        return std.mem.sliceTo(c.luaL_gsub(to(L), s.ptr, p.ptr, r.ptr), 0);
    }

    // TODO: setfuncs

    /// [-0, +1, e] Ensures that the value t[fname], where t is the value at index idx, is a table, and pushes that
    /// table onto the stack. Returns true if it finds a previous table there and false if it creates a new table.
    pub fn getsubtable(L: *State, t: Index, fname: [:0]const u8) bool {
        if (c.LUA_VERSION_NUM >= 502) {
            return c.luaL_getsubtable(to(L), t, fname.ptr) != 0;
        }

        if (L.getfield(t, fname) != .table) {
            L.pop(1);
            L.newtable();
            L.pushvalue(-1);
            L.setfield(t, fname);
            return false;
        }

        return true;
    }

    /// [-0, +1, m] Creates and pushes a traceback of the stack `target`. If msg is not null it is appended at the
    /// beginning of the traceback. The level parameter tells at which level to start the traceback.
    pub fn traceback(L: *State, target: *State, msg: ?[:0]const u8, level: Size) void {
        if (c.LUA_VERSION_NUM >= 502) {
            c.luaL_traceback(to(L), to(target), if (msg) |m| m.ptr else null, level);
        }

        var ar: DebugInfo = undefined;
        var buffer = Buffer.init(L);

        if (msg) |m| {
            buffer.addstring(m);
            buffer.addchar('\n');
        }

        buffer.addstring("stack traceback:");
        var this_level = level;
        while (target.getstack(this_level, &ar)) : (this_level += 1) {
            _ = target.getinfo("Slnt", &ar);
            if (ar.currentline <= 0) {
                _ = L.pushfstring("\n\t%s: in ", .{&ar.short_src});
            } else {
                _ = L.pushfstring("\n\t%s:%d: in ", .{ &ar.short_src, ar.currentline });
            }
            buffer.addvalue();

            if (ar.namewhat[0] != 0) {
                _ = L.pushfstring("%s '%s'", .{ ar.namewhat, ar.name });
            } else if (ar.what[0] == 'm') {
                L.pushstring("main chunk");
            } else if (ar.what[0] != 'C') {
                _ = L.pushfstring("function <%s:%d>", .{ &ar.short_src, ar.linedefined });
            } else {
                L.pushstring("?");
            }

            buffer.addvalue();
            if (@hasField(DebugInfo, "istailcall") and ar.istailcall != 0)
                buffer.addstring("\n\t(...tail calls...)");
        }
    }

    /// [-0, +1, e] If `module` is not already present in package.loaded, calls function openf with string `module`
    /// as an argument and sets the call result in package.loaded[module], as if that function has been called
    /// through require.
    ///
    /// If `global` is true, also stores the module into global `module`.
    ///
    /// Leaves a copy of the module on the stack.
    pub fn requiref(L: *State, module: [:0]const u8, openf: CFn, global: bool) void {
        if (c.LUA_VERSION_NUM >= 503) {
            c.luaL_requiref(to(L), module, openf, @intFromBool(global));
        }

        const scheck = StackCheck.init(L);
        defer _ = scheck.check(requiref, L, 1);

        if (L.getglobal("package") != .table) return;
        if (L.getfield(-1, "loaded") != .table) return;
        _ = L.getfield(-1, module);
        if (!L.toboolean(-1)) {
            L.pop(1);
            L.pushclosure_unwrapped(openf, 0);
            L.pushstring(module);
            L.call(1, 1);
            L.pushvalue(-1);
            L.setfield(-3, module);
        }

        if (global) {
            L.pushvalue(-1);
            L.setglobal(module);
        }

        L.insert(-3);
        L.pop(2);
    }

    /// [-0, +0, -] Returns the name of the type of the value at the given index.
    pub fn typenameof(L: *State, idx: Index) [:0]const u8 {
        return @tagName(L.typeof(idx));
    }

    /// [-0, +1, m] Pushes onto the stack the metatable associated with name tname in the registry (see
    /// `newmetatableFor`) or nil if there is no metatable associated with that name. Returns the type of the pushed
    /// value.
    pub fn getmetatablefor(L: *State, tname: [:0]const u8) Type {
        return L.getfield(REGISTRYINDEX, tname);
    }

    /// [-0, +0, e] Opens all standard Lua libraries into the given state.
    pub fn openlibs(L: *State) void {
        c.luaL_openlibs(to(L));
    }

    // convienience functions

    /// [-0, +1, m] Pushes the given value onto the stack.
    ///
    /// Slices, arrays, vectors and tuples are pushed as a sequence (a table with sequential integer keys).
    /// Packed structs are pushed as their integer backed value.
    /// Normal and extern structs are pushed as a table.
    /// Enums are pushed as their integer value.
    /// Errors and enum literals are pushed as their name as a string.
    /// Unions are pushed as a table with a single key-value pair.
    /// Functions are pushed as a closure.
    /// Enums and ErrorSet *types* are pushed as a sequence of their fields.
    /// Struct *types* are pushed as a table with their public declarations as key-value pairs.
    pub fn push(L: *State, value: anytype) void {
        const T = @TypeOf(value);
        if (T == Value)
            return value.push(L);

        switch (@typeInfo(T)) {
            .Void, .Null => L.pushnil(),
            .Bool => L.pushboolean(value),
            .Int, .ComptimeInt => L.pushinteger(@intCast(value)),
            .Float, .ComptimeFloat => L.pushnumber(@floatCast(value)),
            .Pointer => |info| {
                if (comptime isZigString(T)) {
                    return L.pushstring(value);
                }

                switch (info.size) {
                    .One, .Many, .C => L.pushlightuserdata(value),
                    .Slice => {
                        L.createtable(@intCast(value.len), 0);

                        for (value, 0..) |item, i| {
                            const idx = i + 1;
                            L.push(item);
                            L.rawseti(-2, @intCast(idx));
                        }
                    },
                }
            },
            .Array, .Vector => {
                L.createtable(@intCast(value.len), 0);

                for (value, 0..) |item, i| {
                    L.push(item);
                    L.rawseti(-2, i + 1);
                }
            },
            .Struct => |info| if (info.is_tuple) {
                L.createtable(@intCast(info.fields.len), 0);

                inline for (value, 0..) |item, i| {
                    L.push(item);
                    L.rawseti(-2, i + 1);
                }
            } else if (info.backing_integer) |int_t| {
                L.pushinteger(@intCast(@as(int_t, @bitCast(value))));
            } else {
                L.createtable(0, @intCast(info.fields.len));

                inline for (info.fields) |field| {
                    L.push(@field(value, field.name));
                    L.setfield(-2, literal(field.name));
                }
            },
            .Optional => if (value) |u_value| {
                L.push(u_value);
            } else {
                L.pushnil();
            },
            .ErrorSet => L.pushstring(@errorName(value)),
            .Enum => L.pushinteger(@intFromEnum(value)),
            .Union => {
                L.createtable(0, 1);

                switch (value) {
                    inline else => |u_value| {
                        L.push(u_value);
                        L.setfield(-2, @tagName(value));
                    },
                }
            },
            .Fn => L.pushclosure_unwrapped(wrapAnyFn(value), 0),
            .EnumLiteral => L.pushstring(@tagName(value)),
            .Type => switch (@typeInfo(value)) {
                .Struct => |info| {
                    L.createtable(0, @intCast(info.decls.len));

                    inline for (info.decls) |decl| {
                        if (decl.is_pub) {
                            L.push(@field(value, decl.name));
                            L.setfield(-2, literal(decl.name));
                        }
                    }
                },
                .Enum => |info| {
                    L.createtable(0, @intCast(info.fields.len));

                    inline for (info.fields) |field| {
                        L.push(field.value);
                        L.setfield(-2, literal(field.name));
                    }
                },
                .ErrorSet => |info| if (info) |fields| {
                    L.createtable(@intCast(fields.len), 0);

                    inline for (fields, 0..) |field, i| {
                        L.push(field.name);
                        L.rawseti(-2, i + 1);
                    }
                } else @compileError("cannot push anyerror"),
                else => @compileError("unable to push container '" ++ @typeName(value) ++ "'"),
            },
            else => @compileError("unable to push value '" ++ @typeName(T) ++ "'"),
        }
    }

    fn resource__tostring(L: *State) c_int {
        _ = L.getfield(upvalueindex(1), "__name");
        _ = L.pushfstring(": %p", .{L.topointer(1)});
        L.concat(2);

        return 1;
    }

    /// [-0, +1, m] Registers a resource type with the given metatable.
    pub fn registerResource(L: *State, comptime T: type, comptime metatable: ?type) void {
        const tname = literal(@typeName(T));

        if (L.getmetatablefor(tname) != .table) {
            L.pop(1);

            if (metatable) |mt| {
                L.push(mt);
            } else {
                L.createtable(0, 1);
            }

            L.push(tname);
            L.setfield(-2, "__name");

            if (c.LUA_VERSION_NUM <= 503 and (metatable == null or metatable != null and !@hasField(metatable.?, "__tostring"))) {
                L.pushvalue(-1);
                L.pushclosure_unwrapped(wrapCFn(resource__tostring), 1);
                L.setfield(-2, "__tostring");
            }

            L.pushvalue(-1);
            L.setfield(c.LUA_REGISTRYINDEX, tname);
        }

        L.pop(1);
    }

    /// [-0, +1, m] Creates a new resource of the given type.
    ///
    /// `registerResource` must be called ((with this type) before this function.
    pub fn resource(L: *State, comptime T: type) *align(@alignOf(usize)) T {
        const tname = literal(@typeName(T));

        const size = @sizeOf(T);
        const ptr = L.newuserdata(size);

        assert(L.getmetatablefor(tname) == .table);
        L.setmetatable(-2);

        return @ptrCast(@alignCast(ptr));
    }

    /// [-0, +2, m] Pushes a `nil, string` pair onto the stack representing the given zig error.
    pub fn pusherror(L: *State, err: anyerror) void {
        L.pushnil();
        L.pushstring(@errorName(err));
    }

    fn check_typeerror(L: *State, srcloc: ?std.builtin.SourceLocation, label: ?[]const u8, comptime source: []const u8, comptime expected: []const u8, index: Index) noreturn {
        var to_concat: u8 = 0;
        if (srcloc) |src| {
            _ = L.pushfstring("%s[%s]:%d:%d: ", .{ src.file, src.fn_name, src.line, src.column });
            to_concat += 1;
        }

        if (label) |lbl| {
            _ = L.pushfstring("(%s) ", .{lbl});
            to_concat += 1;
        }

        if (source.len > 0) {
            _ = L.pushfstring("%s: ", .{literal(source)});
            to_concat += 1;
        }

        _ = L.pushfstring("expected " ++ expected ++ ", got %s", .{L.typenameof(index).ptr});

        if (to_concat > 0)
            L.concat(to_concat + 1);

        L.throw();
    }

    fn check_strerror(L: *State, srcloc: ?std.builtin.SourceLocation, label: ?[]const u8, comptime source: []const u8, comptime expected: []const u8, str: [:0]const u8) noreturn {
        var to_concat: u8 = 0;
        if (srcloc) |src| {
            _ = L.pushfstring("%s[%s]:%d:%d: ", .{ src.file, src.fn_name, src.line, src.column });
            to_concat += 1;
        }

        if (label) |lbl| {
            _ = L.pushfstring("(%s) ", .{lbl});
            to_concat += 1;
        }

        if (source.len > 0) {
            _ = L.pushfstring("%s: ", .{literal(source)});
            to_concat += 1;
        }

        _ = L.pushfstring("expected " ++ expected ++ ", got %s", .{str.ptr});

        if (to_concat > 0)
            L.concat(to_concat + 1);

        L.throw();
    }

    fn check_numerror(L: *State, srcloc: ?std.builtin.SourceLocation, label: ?[]const u8, comptime source: []const u8, comptime expected: []const u8, num: Integer) noreturn {
        var to_concat: u8 = 0;
        if (srcloc) |src| {
            _ = L.pushfstring("%s[%s]:%d:%d: ", .{ src.file, src.fn_name, src.line, src.column });
            to_concat += 1;
        }

        if (label) |lbl| {
            _ = L.pushfstring("(%s) ", .{lbl});
            to_concat += 1;
        }

        if (source.len > 0) {
            _ = L.pushfstring("%s: ", .{literal(source)});
            to_concat += 1;
        }

        _ = L.pushfstring("expected " ++ expected ++ ", got %d", .{num});

        if (to_concat > 0)
            L.concat(to_concat + 1);

        L.throw();
    }

    fn checkInternal(L: *State, srcloc: ?std.builtin.SourceLocation, label: ?[]const u8, comptime name: []const u8, comptime T: type, idx: Index, allocator: anytype) T {
        switch (@typeInfo(T)) {
            .Bool => {
                if (!L.isboolean(idx))
                    L.check_typeerror(srcloc, label, name, "boolean", idx);

                return L.toboolean(idx);
            },
            .Int => {
                if (!L.isinteger(idx))
                    L.check_typeerror(srcloc, label, name, "integer", idx);

                const err_range = comptime comptimePrint("number in range [{d}, {d}]", .{ std.math.minInt(T), std.math.maxInt(T) });

                const num = L.tointeger(idx);
                return std.math.cast(T, num) orelse
                    L.check_numerror(srcloc, label, name, err_range, num);
            },
            .Float => {
                if (!L.isnumber(idx))
                    L.check_typeerror(srcloc, label, name, "number", idx);

                return @floatCast(L.tonumber(idx));
            },
            .Array => |info| {
                if (info.child == u8 and L.isstring(idx)) {
                    const err_len = comptime comptimePrint("string of length {d}", .{info.len});

                    const str = L.tostring(idx).?;
                    if (str.len != info.len)
                        L.check_numerror(srcloc, label, name, err_len, @intCast(str.len));

                    return str[0..info.len].*;
                }

                if (!L.istable(idx))
                    L.check_typeerror(srcloc, label, name, "table", idx);

                const err_len = comptime comptimePrint("table of length {d}", .{info.len});

                const tlen = L.lenof(idx);
                if (tlen != info.len)
                    L.check_numerror(srcloc, label, name, err_len, tlen);

                var res: T = undefined;

                for (res[0..], 0..) |*slot, i| {
                    _ = L.rawgeti(idx, @as(Integer, @intCast(i)) + 1);
                    slot.* = L.checkInternal(srcloc, label, name ++ "[]", info.child, -1, allocator);
                }

                L.pop(info.len);
                return res;
            },
            .Struct => |info| {
                if (!L.istable(idx))
                    L.check_typeerror(srcloc, label, name, "table", idx);

                var res: T = undefined;

                inline for (info.fields) |field| {
                    _ = L.getfield(idx, literal(field.name));
                    @field(res, field.name) = L.checkInternal(srcloc, label, name ++ "." ++ field.name, field.type, -1, allocator);
                }

                L.pop(info.fields.len);
                return res;
            },
            .Pointer => |info| {
                if (comptime std.meta.trait.isZigString(T)) {
                    if (!L.isstring(idx))
                        L.check_typeerror(srcloc, label, name, "string", idx);

                    if (!info.is_const) {
                        if (allocator == null) @compileError("cannot allocate non-const string, use checkAlloc instead");

                        const str = L.tostring(idx) orelse unreachable;
                        return allocator.dupe(str) catch
                            L.raise("out of memory", .{});
                    }

                    return L.tostring(idx) orelse unreachable;
                }

                switch (info.size) {
                    .One, .Many, .C => {
                        if (!L.isuserdata(idx))
                            L.check_typeerror(srcloc, label, name, "userdata", idx);

                        return @ptrCast(L.touserdata(idx).? orelse unreachable);
                    },
                    .Slice => {
                        if (!L.istable(idx))
                            L.check_typeerror(srcloc, label, name, "table", idx);

                        if (allocator == null) @compileError("cannot allocate slice, use checkAlloc instead");

                        const sentinel = if (info.sentinel) |ptr| @as(*const info.child, @ptrCast(ptr)).* else null;

                        const slen = L.lenof(idx);
                        const ptr = allocator.allocWithOptions(info.child, slen, info.alignment, sentinel) catch
                            L.raise("out of memory", .{});

                        for (ptr[0..], 0..) |*slot, i| {
                            _ = L.rawgeti(idx, @as(Integer, @intCast(i)) + 1);
                            slot.* = L.checkInternal(srcloc, label, name ++ "[]", info.child, -1, allocator);
                        }

                        L.pop(slen);
                        return ptr;
                    },
                }
            },
            .Optional => |info| {
                if (L.isnoneornil(idx)) return null;

                return L.checkInternal(srcloc, label, name ++ ".?", info.child, idx, allocator);
            },
            .Enum => |info| {
                if (L.isnumber(idx)) {
                    const value = @as(info.tag_type, @intCast(L.tointeger(idx)));
                    return @enumFromInt(value);
                } else if (L.isstring(idx)) {
                    const value = L.tostring(idx) orelse unreachable;

                    return std.meta.stringToEnum(T, value) orelse
                        L.check_strerror(srcloc, label, name, "member of " ++ @typeName(T), value);
                } else L.check_typeerror(srcloc, label, name, "number or string", idx);
            },
            else => @compileError("check not implemented for " ++ @typeName(T)),
        }
    }

    /// [-0, +0, v] Checks that the value at the given index is of the given type. Returns the value.
    ///
    /// Cannot be called on a non-const string type or any non-string slice type, as they require allocation.
    pub fn check(L: *State, comptime T: type, idx: Index) T {
        return L.checkInternal("", T, idx, null);
    }

    /// [-0, +0, v] Checks that the value at the given index is of the given type. Returns the value. Allows for
    /// types that require allocation.
    pub fn checkAlloc(L: *State, comptime T: type, idx: Index, allocator: Allocator) T {
        return L.checkInternal("", T, idx, allocator);
    }

    /// [-0, +0, v] Checks that the value at the given index is of the given resource type. Returns a pointer to the
    /// resource.
    pub fn checkResource(L: *State, comptime T: type, arg: Index) *align(@alignOf(usize)) T {
        const ptr = c.luaL_checkudata(to(L), arg, literal(@typeName(T))).?;
        return @ptrCast(@alignCast(ptr));
    }

    /// [-0, +0, -] Returns a value representation of the value at an index, and stores a reference to that value if necessary
    pub fn valueAt(L: *State, index: Index) !Value {
        return Value.init(L, index);
    }

    /// [-0, +0, -] Returns a table representation of the value at an index, and stores a reference to that value
    ///
    /// Throws an error if the value is not a table
    pub fn tableAt(L: *State, index: Index) !Table {
        return Table.init(L, index);
    }

    /// [-0, +0, -] Returns a function representation of the value at an index, and stores a reference to that value
    pub fn functionAt(L: *State, index: Index) !Function {
        return Function.init(L, index);
    }
};

/// Wraps any zig function to be used as a Lua C function.
///
/// Arguments will be checked using `State.check`. Follows the same rules as `wrapCFn`.
pub fn wrapAnyFn(func: anytype) CFn {
    if (@TypeOf(func) == CFn) return func;

    const I = @typeInfo(@TypeOf(func));
    const info = if (I == .Fn) I.Fn else @typeInfo(@typeInfo(@TypeOf(func)).Pointer.child).Fn;
    if (info.params.len == 1 and info.params[0].type.? == *State) {
        return wrapCFn(func);
    }

    if (info.is_generic) return null;

    return wrapCFn(struct {
        fn wrapped(L: *State) info.return_type.? {
            var args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;

            inline for (&args, 0..) |*slot, i| {
                slot.* = L.check(@TypeOf(slot), i + 1);
            }

            return @call(.always_inline, func, args);
        }
    }.wrapped);
}

/// Wraps a zig-like Lua function (with a `*State` as its first argument) to be used as a Lua C function.
///
/// If the function returns `c_int`, it will be returned unmodified.
/// Return values will be pushed using `State.push`.
pub fn wrapCFn(func: anytype) CFn {
    if (@TypeOf(func) == CFn) return func;

    const I = @typeInfo(@TypeOf(func));
    const info = if (I == .Fn) I.Fn else @typeInfo(@typeInfo(@TypeOf(func)).Pointer.child).Fn;
    return struct {
        fn wrapped(L_opt: ?*c.lua_State) callconv(.C) c_int {
            const L: *State = @ptrCast(L_opt.?);
            const T = info.return_type.?;

            const top = switch (@typeInfo(T)) {
                .ErrorUnion => L.gettop(),
                else => {},
            };

            const scheck = StackCheck.init(L);
            const result = @call(.always_inline, func, .{L});

            if (T == c_int)
                return scheck.check(func, L, result);

            switch (@typeInfo(T)) {
                .Void => return scheck.check(func, L, 0),
                .ErrorUnion => |err_info| {
                    const actual_result = result catch |err| {
                        L.settop(top);
                        L.pusherror(err);

                        return scheck.check(func, L, 2);
                    };

                    if (err_info.payload == c_int) return scheck.check(func, L, actual_result);

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

const Allocator = std.mem.Allocator;

/// Wraps a zig allocator to be used as a Lua allocator. This function should be used as the allocator function.
/// The zig allocation should be passed as the `ud` argument to `initWithAlloc`.
pub fn luaAlloc(ud: ?*anyopaque, ptr: ?*anyopaque, oldsize: usize, newsize: usize) callconv(.C) ?*anyopaque {
    assert(ud != null);

    const allocator: *Allocator = @ptrCast(@alignCast(ud.?));
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

/// The type of a wrapped std.io.Reader that can be passed as a Lua reader.
pub fn LuaReader(comptime Reader: anytype) type {
    return struct {
        const Self = @This();

        pub fn read(L_opt: ?*c.lua_State, ud: ?*anyopaque, size: ?*usize) callconv(.C) [*c]const u8 {
            assert(ud != null);
            assert(size != null);

            const L: *State = @ptrCast(L_opt.?);
            const wrapper: *Self = @ptrCast(@alignCast(ud.?));

            if (wrapper.has_byte) {
                wrapper.has_byte = false;

                size.?.* = 1;
                return wrapper.buf[0..1];
            }

            size.?.* = wrapper.reader.read(wrapper.buf[0..]) catch |err| {
                L.raise(@errorName(err), .{});
            };

            return &wrapper.buf;
        }

        reader: Reader,
        buf: [c.BUFSIZ]u8 = undefined,

        has_byte: bool = false,
        mode: LoadMode,
    };
}

/// Wraps a std.io.Reader to be used as a Lua reader function.
///
/// Should be used as follows:
/// ```zig
/// var lua_reader = try luaReader(reader);
/// L.load(lua_reader, "test.lua");
/// ```
pub fn luaReader(reader: anytype) !LuaReader(@TypeOf(reader)) {
    const byte = try reader.readByte();

    const mode: LoadMode = switch (byte) {
        c.LUA_SIGNATURE[0] => .binary,
        else => .text,
    };

    var wrapper = LuaReader(@TypeOf(reader)){ .reader = reader, .mode = mode };
    wrapper.buf[0] = byte;
    wrapper.has_byte = true;

    return wrapper;
}

/// The type of a wrapped std.io.Writer that can be passed as a Lua writer.
pub fn LuaWriter(comptime Writer: anytype) type {
    return struct {
        const Self = @This();

        pub fn write(L_opt: ?*c.lua_State, p: ?*const anyopaque, sz: usize, ud: ?*anyopaque) callconv(.C) c_int {
            assert(ud != null);
            assert(p != null);

            const L: *State = @ptrCast(L_opt.?);
            const wrapper: *Self = @ptrCast(@alignCast(ud.?));
            const ptr: [*]const u8 = @ptrCast(p.?);

            wrapper.writer.writeAll(ptr[0..sz]) catch |err| {
                L.raise(@errorName(err), .{});
            };

            return 0;
        }

        writer: Writer,
    };
}

/// Wraps a std.io.Writer to be used as a Lua writer function.
///
/// Should be used as follows:
/// ```zig
/// var lua_writer = LuaWriter(@TypeOf(writer)){ .writer = writer };
/// L.dump(lua_writer.write, &lua_writer);
/// ```
pub fn luaWriter(writer: anytype) LuaWriter(@TypeOf(writer)) {
    return LuaWriter(@TypeOf(writer)){ .writer = writer };
}

/// Export a zig function as the entry point of a Lua module. This wraps the function and exports it as
/// `luaopen_{name}`.
pub fn exportAs(comptime func: anytype, comptime name: []const u8) CFn {
    return struct {
        fn luaopen(L: ?*c.lua_State) callconv(.C) c_int {
            const fnc = comptime wrapCFn(func) orelse unreachable;

            return @call(.always_inline, fnc, .{L});
        }

        comptime {
            @export(luaopen, .{ .name = "luaopen_" ++ name });
        }
    }.luaopen;
}

/// A Lua string buffer
///
/// During its normal operation, a string buffer uses a variable number of stack slots. So, while using a buffer,
/// you cannot assume that you know where the top of the stack is. You can use the stack between successive calls to
/// buffer operations as long as that use is balanced; that is, when you call a buffer operation, the stack is at
/// the same level it was immediately after the previous buffer operation.
pub const Buffer = struct {
    state: *State,
    buf: c.luaL_Buffer,

    /// [-0, +0, -] Initializes a buffer B. This function does not allocate any space.
    pub fn init(L: *State) Buffer {
        var res: Buffer = undefined;
        res.state = L;
        res.buf = std.mem.zeroes(c.luaL_Buffer);

        c.luaL_buffinit(L.to(), &res.buf);

        return res;
    }

    /// [-?, +?, m] Returns a slice of memory of at *most* `max_size` bytes where you can copy a string to be added
    /// to the buffer (see `commit`).
    pub fn reserve(buffer: *Buffer, max_size: usize) []u8 {
        const ptr = if (c.LUA_VERSION_NUM >= 502)
            c.luaL_prepbuffsize(&buffer.buf, max_size)
        else
            c.luaL_prepbuffer(&buffer.buf);

        const clamped_len = if (c.LUA_VERSION_NUM >= 502)
            max_size
        else
            @min(max_size, c.LUAL_BUFFERSIZE);

        return ptr[0..clamped_len];
    }

    /// [-?, +?, -] Adds to the buffer a string of length `size` that had previously been copied into the buffer
    /// area provided by `reserve`.
    pub fn commit(buffer: *Buffer, size: usize) void {
        // TODO: translate-c bug: c.luaL_addsize(&buffer.buf, size);
        if (c.LUA_VERSION_NUM >= 502) {
            buffer.buf.n += size;
        } else {
            buffer.buf.p += size;
        }
    }

    /// [-?, +?, m] Adds the byte `char` to the buffer.
    pub fn addchar(buffer: *Buffer, char: u8) void {
        const str = buffer.reserve(1);
        str[0] = char;
        buffer.commit(1);
    }

    /// [-?, +?, m] Adds the string `str` to the buffer.
    pub fn addstring(buffer: *Buffer, str: []const u8) void {
        c.luaL_addlstring(&buffer.buf, str.ptr, str.len);
    }

    /// [-1, +?, m] Adds the value at the top of the stack to the buffer. Pops the value.
    pub fn addvalue(buffer: *Buffer) void {
        c.luaL_addvalue(&buffer.buf);
    }

    /// [-?, +1, m] Finishes the use of buffer B leaving the final string on the top of the stack.
    pub fn final(buffer: *Buffer) void {
        c.luaL_pushresult(&buffer.buf);
    }

    /// A Lua writer function that can be used to write to a string buffer.
    pub fn write(L_opt: ?*c.lua_State, p: ?[*]const u8, sz: usize, ud: ?*anyopaque) callconv(.C) c_int {
        _ = L_opt;
        assert(ud != null);
        assert(p != null);

        const buf: *Buffer = @ptrCast(@alignCast(ud.?));
        buf.addstring(p.?[0..sz]);

        return 0;
    }
};

/// A debug utility to ensure that the stack is in the expected state after a function call.
///
/// Does nothing when `std.debug.runtime_safety` is false.
pub const StackCheck = struct {
    top: if (std.debug.runtime_safety) Index else void,

    /// [-0, +0, -] Initializes a stack check. The top of the stack will be saved as the "base".
    pub fn init(L: *State) StackCheck {
        return .{ .top = if (std.debug.runtime_safety) L.gettop() else {} };
    }

    /// [-0, +0, v] Checks that the stack is in the expected state. If it is not, an error is thrown with debug
    /// information if available from the given function (by probing for debug info in the binary).
    ///
    /// A negative value for `pushed` means that `abs(pushed)` items have been popped.
    pub fn check(self: StackCheck, comptime func: anytype, L: *State, pushed: c_int) c_int {
        if (!std.debug.runtime_safety) return;

        const new_top = L.gettop();
        if (new_top != self.top + pushed) {
            debuginfo: {
                const address = @intFromPtr(&func);

                const debug_info = std.debug.getSelfDebugInfo() catch break :debuginfo;
                const module = debug_info.getModuleForAddress(address) catch break :debuginfo;
                const symbol_info: std.debug.SymbolInfo = module.getSymbolAtAddress(debug_info.allocator, address) catch break :debuginfo;
                defer symbol_info.deinit(debug_info.allocator);

                if (symbol_info.line_info) |info| {
                    L.raise("stack check failed in %s at %s:%d (expected %d items but %d were pushed)", .{ symbol_info.symbol_name, info.file_name, info.line, pushed, new_top - self.top });
                }

                L.raise("stack check failed in %s (expected %d items but %d were pushed)", .{ symbol_info.symbol_name, pushed, new_top - self.top });
            }

            L.raise("stack check failed (expected %d items but %d were pushed)", .{ pushed, new_top - self.top });
        }

        return pushed;
    }
};

// Extra Stuff

/// A union of the possible Lua types, mostly used for debugging.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    number: Number,
    integer: Integer,
    string: [:0]const u8,
    table: Table,
    function: Function,
    userdata: *anyopaque,
    lightuserdata: *anyopaque,

    pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;

        switch (value) {
            .nil => return std.fmt.formatBuf("nil", options, writer),
            .boolean => return std.fmt.format(writer, "{}", .{value.boolean}),
            .number, .integer => |num| return std.fmt.format(writer, "{d}", .{num}),
            .string => return std.fmt.format(writer, "'{'}'", .{std.zig.fmtEscapes(value.string)}),
            .function => return std.fmt.format(writer, "function: 0x{?x}", .{@intFromPtr(value.function)}),
            .table => return std.fmt.format(writer, "table: 0x{x}", .{@intFromPtr(value.table)}),
            .lightuserdata, .userdata => |ptr| return std.fmt.format(writer, "userdata: 0x{x}", .{@intFromPtr(ptr)}),
        }
    }

    /// [-0, +0, -] Returns a value representation of the current value, and stores a reference to that value if necessary
    pub fn init(L: *State, index: Index) !Value {
        const T = L.typeof(-1);

        switch (T) {
            .none, .nil => return .{ .nil = {} },
            .boolean => return .{ .boolean = L.toboolean(index) },
            .lightuserdata => return .{ .lightuserdata = L.touserdata(anyopaque, index).? },
            .number => if (L.isinteger(index))
                return .{ .integer = L.tointeger(index) }
            else
                return .{ .number = L.tonumber(index) },
            .string => return .{ .string = L.tostring(index).? },
            .table => return .{ .table = try Table.init(L, index) },
            .function => return .{ .function = try Function.init(L, index) },
            .userdata => return .{ .userdata = L.touserdata(anyopaque, index).? },
            .thread => return error.NotImplemented,
        }
    }

    /// [-0, +1, -] Pushes this value onto the stack.
    pub fn push(value: Value, L: *State) void {
        switch (value) {
            .nil => L.pushnil(),
            .boolean => |v| L.pushboolean(v),
            .number => |v| L.pushnumber(v),
            .integer => |v| L.pushinteger(v),
            .string => |v| L.pushstring(v),
            .table => |v| v.push(L),
            .function => |v| v.push(L),
            .userdata => |v| L.pushlightuserdata(v), // FIXME: should this copy the userdata?
            .lightuserdata => |v| L.pushlightuserdata(v),
        }
    }
};

pub const Table = struct {
    state: *State,
    ref: Index,

    /// [-0, +0, -] Initializes a table from the value at the given index. This stores a reference to the table.
    pub fn init(L: *State, index: Index) !Table {
        if (L.typeof(index) != .table)
            return error.NotATable;

        L.pushvalue(index);
        return .{ .ref = L.ref(REGISTRYINDEX), .state = L };
    }

    /// [-0, +0, -] Deinitializes this representation and dereferences the table.
    pub fn deinit(table: Table) void {
        table.state.unref(REGISTRYINDEX, table.ref);
    }

    /// [-0, +1, m] Pushes this table onto the stack of `to`. The `to` thread must be in the same state as this table.
    pub fn push(table: Table, to: *State) void {
        table.state.geti(REGISTRYINDEX, table.ref);

        if (to != table.state)
            table.state.xmove(to, 1);
    }

    /// [-0, +1, e] Gets the value at the given key in this table and pushes it onto the stack.
    pub fn get(table: Table, key: anytype) void {
        table.state.geti(REGISTRYINDEX, table.ref);
        table.state.push(key);
        table.state.gettable(-2);
        table.state.remove(-2);
    }

    /// [-0, +0, e] Gets the value at the given key in this table as a Value.
    pub fn getValue(table: Table, key: anytype) Value {
        table.get(key);
        defer table.state.pop(1);

        return Value.init(table.state, -1);
    }

    /// [-1, +0, e] Sets the value at the given key in this table with the value at the top of the stack.
    pub fn set(table: Table, key: anytype) void {
        table.state.geti(REGISTRYINDEX, table.ref);
        table.state.push(key);
        table.state.rotate(-3, -1);
        table.state.settable(-3);
        table.state.pop(1);
    }

    /// [-0, +0, e] Sets the value at the given key in this table.
    pub fn setValue(table: Table, key: anytype, value: anytype) void {
        table.state.geti(REGISTRYINDEX, table.ref);
        table.state.push(key);
        table.state.push(value);
        table.state.settable(-3);
        table.state.pop(1);
    }
};

pub const Function = struct {
    state: *State,
    ref: Index,

    /// [-0, +0, -] Initializes a function from the value at the given index. This stores a reference to the function.
    pub fn init(L: *State, index: Index) !Function {
        if (L.typeof(index) != .function)
            return error.NotAFunction;

        L.pushvalue(index);
        return .{ .ref = L.ref(REGISTRYINDEX), .state = L };
    }

    /// [-0, +0, -] Deinitializes this representation and dereferences the function.
    pub fn deinit(func: Function) void {
        func.state.unref(REGISTRYINDEX, func.ref);
    }

    /// [-0, +1, m] Pushes this function onto the stack of `to`. The `to` thread must be in the same state as this function.
    pub fn push(func: Function, to: *State) void {
        func.state.geti(REGISTRYINDEX, func.ref);

        if (to != func.state)
            func.state.xmove(to, 1);
    }

    pub const ReturnType = union(enum) {
        /// Drop all return values.
        none,

        /// Return a single Value of the first return.
        value,

        /// Return the number of return values left on the stack.
        all,

        /// Return a tuple of the given types.
        many: []const type,
    };

    fn MakeCallReturn(comptime ret: ReturnType) type {
        switch (ret) {
            .none => return void,
            .value => return Value,
            .all => return Index,
            .many => |v| return std.meta.Tuple(v),
        }
    }

    /// [-0, +0, e] Calls this function with the given arguments and returns the result.
    pub fn call(func: Function, args: anytype, comptime returns: ReturnType) MakeCallReturn(returns) {
        const prev_top = func.state.gettop();

        assert(func.state.geti(REGISTRYINDEX, func.ref) == .function);

        inline for (args) |arg| {
            func.state.push(arg);
        }

        var ret: MakeCallReturn(returns) = undefined;
        const num_returns = switch (returns) {
            .none => 0,
            .value => 1,
            .all => null,
            .many => returns.many.len,
        };

        func.state.call(args.len, num_returns);

        switch (returns) {
            .none => return,
            .value => {
                defer func.state.pop(1);

                return Value.init(func.state, -1);
            },
            .all => return func.state.gettop() - prev_top,
            .many => {
                defer func.state.pop(returns.many.len);

                inline for (returns.many, 0..) |T, i| {
                    ret[i] = func.state.check(T, prev_top + i + 1);
                }

                return ret;
            },
        }
    }
};

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(arith_functions);

    std.testing.refAllDecls(State);
    std.testing.refAllDecls(Buffer);
    std.testing.refAllDecls(StackCheck);

    std.testing.refAllDecls(LuaReader(std.fs.File.Reader));
    std.testing.refAllDecls(LuaWriter(std.fs.File.Writer));
}

/// Returns true if the passed type will coerce to []const u8.
/// Any of the following are considered strings:
/// ```
/// []const u8, [:S]const u8, *const [N]u8, *const [N:S]u8,
/// []u8, [:S]u8, *[:S]u8, *[N:S]u8.
/// ```
/// These types are not considered strings:
/// ```
/// u8, [N]u8, [*]const u8, [*:0]const u8,
/// [*]const [N]u8, []const u16, []const i8,
/// *const u8, ?[]const u8, ?*const [N]u8.
/// ```
inline fn isZigString(comptime T: type) bool {
    return blk: {
        // Only pointer types can be strings, no optionals
        const info = @typeInfo(T);
        if (info != .Pointer) break :blk false;

        const ptr = &info.Pointer;
        // Check for CV qualifiers that would prevent coerction to []const u8
        if (ptr.is_volatile or ptr.is_allowzero) break :blk false;

        // If it's already a slice, simple check.
        if (ptr.size == .Slice) {
            break :blk ptr.child == u8;
        }

        // Otherwise check if it's an array type that coerces to slice.
        if (ptr.size == .One) {
            const child = @typeInfo(ptr.child);
            if (child == .Array) {
                const arr = &child.Array;
                break :blk arr.child == u8;
            }
        }

        break :blk false;
    };
}

test isZigString {
    try std.testing.expect(isZigString([]const u8));
    try std.testing.expect(isZigString([]u8));
    try std.testing.expect(isZigString([:0]const u8));
    try std.testing.expect(isZigString([:0]u8));
    try std.testing.expect(isZigString([:5]const u8));
    try std.testing.expect(isZigString([:5]u8));
    try std.testing.expect(isZigString(*const [0]u8));
    try std.testing.expect(isZigString(*[0]u8));
    try std.testing.expect(isZigString(*const [0:0]u8));
    try std.testing.expect(isZigString(*[0:0]u8));
    try std.testing.expect(isZigString(*const [0:5]u8));
    try std.testing.expect(isZigString(*[0:5]u8));
    try std.testing.expect(isZigString(*const [10]u8));
    try std.testing.expect(isZigString(*[10]u8));
    try std.testing.expect(isZigString(*const [10:0]u8));
    try std.testing.expect(isZigString(*[10:0]u8));
    try std.testing.expect(isZigString(*const [10:5]u8));
    try std.testing.expect(isZigString(*[10:5]u8));

    try std.testing.expect(!isZigString(u8));
    try std.testing.expect(!isZigString([4]u8));
    try std.testing.expect(!isZigString([4:0]u8));
    try std.testing.expect(!isZigString([*]const u8));
    try std.testing.expect(!isZigString([*]const [4]u8));
    try std.testing.expect(!isZigString([*c]const u8));
    try std.testing.expect(!isZigString([*c]const [4]u8));
    try std.testing.expect(!isZigString([*:0]const u8));
    try std.testing.expect(!isZigString([*:0]const u8));
    try std.testing.expect(!isZigString(*[]const u8));
    try std.testing.expect(!isZigString(?[]const u8));
    try std.testing.expect(!isZigString(?*const [4]u8));
    try std.testing.expect(!isZigString([]allowzero u8));
    try std.testing.expect(!isZigString([]volatile u8));
    try std.testing.expect(!isZigString(*allowzero [4]u8));
    try std.testing.expect(!isZigString(*volatile [4]u8));
}
