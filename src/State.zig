const std = @import("std");
const lunaro = @import("lunaro.zig");

const arithmetic = @import("arithmetic.zig");

const c = lunaro.c;
const lua_version = lunaro.lua_version;

const Number = lunaro.Number;
const Integer = lunaro.Integer;
const Index = lunaro.Index;
const Size = lunaro.Size;

const CFn = lunaro.CFn;
const ReaderFn = lunaro.ReaderFn;
const WriterFn = lunaro.WriterFn;
const AllocFn = lunaro.AllocFn;
const HookFn = lunaro.HookFn;

const REGISTRYINDEX = lunaro.REGISTRYINDEX;

const DebugInfo = lunaro.DebugInfo;
const ThreadStatus = lunaro.ThreadStatus;
const Type = lunaro.Type;
const ArithOp = lunaro.ArithOp;
const CompareOp = lunaro.CompareOp;
const LoadMode = lunaro.LoadMode;

const Value = lunaro.Value;
const Table = lunaro.Table;
const Buffer = lunaro.Buffer;
const Function = lunaro.Function;

const safety = lunaro.safety;

const assert = std.debug.assert;

fn literal(comptime str: []const u8) [:0]const u8 {
    return (str ++ "\x00")[0..str.len :0];
}

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
    pub inline fn to(ptr: *State) *c.lua_State {
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
        return c.lua_atpanic(to(L), lunaro.wrapAnyFn(panicf));
    }

    // basic stack manipulation

    /// [-0, +0, -] Returns the pseudo-index that represents the i-th upvalue of the running function.
    pub fn upvalueindex(index: Index) Index {
        return c.lua_upvalueindex(index);
    }

    /// [-0, +0, -] Converts the acceptable index `index` into an absolute index (that is, one that does not depend
    /// on the stack top).
    pub fn absindex(L: *State, index: Index) Index {
        if (lua_version >= 502) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
            return L.rotate(index, 1);
        }

        return c.lua_insert(to(L), index);
    }

    /// [-1, +0, -] Moves the top element into the given valid index without shifting any element (therefore
    /// replacing the value at that given index),
    /// and then pops the top element.
    pub fn replace(L: *State, index: Index) void {
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 503) {
            return c.lua_isinteger(to(L), index) != 0;
        }

        if (!L.isnumber(index)) return false;

        const value = L.tonumber(index);
        return @floor(value) == value;
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
        if (lua_version >= 502) {
            var isnum: c_int = 0;
            const value = c.lua_tonumberx(to(L), index, &isnum);

            if (isnum == 0) return 0;
            return value;
        }

        return c.lua_tonumber(to(L), index);
    }

    /// [-0, +0, -] Converts the Lua value at the given index to `Integer`. The Lua value must be an integer or a
    /// number or string convertible to an integer; otherwise, returns 0.
    pub fn tointeger(L: *State, index: Index) Integer {
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
            if (@intFromEnum(op) >= 0) {
                return c.lua_arith(to(L), @intFromEnum(op));
            }
        }

        switch (op) {
            inline else => |value| if (@intFromEnum(value) < 0)
                return @field(arithmetic, @tagName(value))(L),
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
        if (lua_version >= 502) {
            return c.lua_compare(to(L), a, b, @intFromEnum(op)) != 0;
        }

        switch (op) {
            .eq => return c.lua_equal(L.to(), a, b) != 0,
            .lt => return c.lua_lessthan(L.to(), a, b) != 0,
            .le => return arithmetic.le(L, a, b),
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
        if (lua_version >= 502) {
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
        return c.lua_pushcclosure(to(L), lunaro.wrapAnyFn(func), n);
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
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
            return @enumFromInt(c.lua_gettable(to(L), index));
        }

        c.lua_gettable(to(L), index);
        return L.typeof(-1);
    }

    /// [-0, +1, e] Pushes onto the stack the value t[k], where t is the value at the given index.
    ///
    /// As in Lua, this function may trigger a metamethod for the "index" event.
    pub fn getfield(L: *State, index: Index, name: [:0]const u8) Type {
        if (lua_version >= 503) {
            return @enumFromInt(c.lua_getfield(to(L), index, name.ptr));
        }

        c.lua_getfield(to(L), index, name.ptr);
        return L.typeof(-1);
    }

    /// [-0, +1, e] Pushes onto the stack the value t[n], where t is the value at the given index.
    ///
    /// As in Lua, this function may trigger a metamethod for the "index" event.
    pub fn geti(L: *State, index: Index, n: Integer) Type {
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
            return @enumFromInt(c.lua_rawget(to(L), index));
        }

        c.lua_rawget(to(L), index);
        return L.typeof(-1);
    }

    /// [-0, +1, -] Pushes onto the stack the value t[n], where t is the value at the given index.
    ///
    /// The access is raw; that is, it does not invoke metamethods.
    pub fn rawgeti(L: *State, index: Index, n: Integer) Type {
        if (lua_version >= 503) {
            return @enumFromInt(c.lua_rawgeti(to(L), index, n));
        }

        // lua_rawgeti takes a c_int pre-5.3, so handle the edge case where n is too large or small
        if (n > std.math.maxInt(c_int) or n < std.math.minInt(c_int)) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 504) {
            return @alignCast(c.lua_newuserdatauv(to(L), size, 1).?);
        }

        return @alignCast(c.lua_newuserdata(to(L), size).?);
    }

    /// [-0, +(0|1), -] If the value at the given index has a metatable, the function pushes that metatable onto the
    /// stack and returns true.
    /// Otherwise, the function returns false and pushes nothing on the stack.
    pub fn getmetatable(L: *State, index: Index) bool {
        if (lua_version >= 504) {
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
        if (lua_version >= 502) {
            _ = L.rawgeti(REGISTRYINDEX, c.LUA_RIDX_GLOBALS);
            return;
        }

        return c.lua_pushvalue(to(L), c.LUA_GLOBALSINDEX);
    }

    /// [-0, +1, -] Pushes onto the stack the Lua value associated with the full userdata at the given index.
    ///
    /// Returns the type of the pushed value.
    pub fn getuservalue(L: *State, index: Index) Type {
        if (lua_version >= 503) {
            return @enumFromInt(c.lua_getuservalue(to(L), index));
        }

        if (lua_version >= 502) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
            _ = c.lua_setuservalue(to(L), index);
            return;
        }

        if (lua_version >= 502) {
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

        if (lua_version >= 502) {
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

        if (lua_version >= 502) {
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

        if (lua_version >= 502) {
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

        if (lua_version >= 503) {
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
        if (lua_version >= 503) {
            _ = c.lua_yieldk(to(L), nresults, 0, null);
            unreachable;
        }

        // before 5.3, lua_yield returns a magic value that MUST be returned to Lua's core
        if (lua_version >= 502) {
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
        if (lua_version >= 504) {
            var res: c_int = 0;
            return @enumFromInt(c.lua_resume(to(L), null, nargs, &res));
        }

        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 503) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
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
        if (lua_version >= 502) {
            c.luaL_traceback(to(L), to(target), if (msg) |m| m.ptr else null, level);
        }

        var ar: DebugInfo = undefined;
        var buffer: Buffer = undefined;
        buffer.init(L);

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

        buffer.final();
    }

    /// [-0, +1, e] If `module` is not already present in package.loaded, calls function openf with string `module`
    /// as an argument and sets the call result in package.loaded[module], as if that function has been called
    /// through require.
    ///
    /// If `global` is true, also stores the module into global `module`.
    ///
    /// Leaves a copy of the module on the stack.
    pub fn requiref(L: *State, module: [:0]const u8, openf: CFn, global: bool) void {
        if (lua_version >= 503) {
            c.luaL_requiref(to(L), module, openf, @intFromBool(global));
        }

        const scheck = safety.StackCheck.init(L);
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
    /// Strings and null terminated byte arrays are pushed as strings.
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

                switch (T) {
                    [*c]const u8, [*c]u8, [*:0]const u8, [*:0]u8 => c.lua_pushstring(to(L), value),
                    else => switch (info.size) {
                        .One, .Many, .C => L.pushlightuserdata(value),
                        .Slice => {
                            L.createtable(@intCast(value.len), 0);

                            for (value, 0..) |item, i| {
                                const idx = i + 1;
                                L.push(item);
                                L.rawseti(-2, @intCast(idx));
                            }
                        },
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
            .Fn => L.pushclosure_unwrapped(lunaro.helpers.wrapAnyFn(value), 0),
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
        const tname = if (@hasDecl(T, "lunaro_typename"))
            literal(T.lunaro_typename)
        else
            literal(@typeName(T));

        if (L.getmetatablefor(tname) != .table) {
            L.pop(1);

            if (metatable) |mt| {
                L.push(mt);
            } else {
                L.createtable(0, 1);
            }

            if (metatable == null or metatable != null and !@hasDecl(metatable.?, "__name")) {
                L.push(tname);
                L.setfield(-2, "__name");
            }

            if (lua_version <= 503 and (metatable == null or metatable != null and !@hasDecl(metatable.?, "__tostring"))) {
                L.pushvalue(-1);
                L.pushclosure_unwrapped(lunaro.wrapCFn(resource__tostring), 1);
                L.setfield(-2, "__tostring");
            }

            L.pushvalue(-1);
            L.setfield(c.LUA_REGISTRYINDEX, tname);
        }

        L.pop(1);
    }

    /// [-0, +1, m] Creates a new resource of the given type.
    ///
    /// `registerResource` must be called (with this type) before this function.
    pub fn resource(L: *State, comptime T: type) *align(@alignOf(usize)) T {
        const tname = if (@hasDecl(T, "lunaro_typename"))
            literal(T.lunaro_typename)
        else
            literal(@typeName(T));

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

    const CheckTraceback = struct {
        stack: [3][]const u8,
        extra: usize,
        len: u8,

        pub fn push(tb: *CheckTraceback, label: []const u8) void {
            if (tb.len < tb.stack.len) {
                tb.stack[tb.len] = label;
                tb.len += 1;
            } else {
                tb.extra += 1;
            }
        }

        pub fn pop(tb: *CheckTraceback) void {
            if (tb.extra > 0) {
                tb.extra -= 1;
            } else if (tb.len > 0) {
                tb.len -= 1;
            }
        }

        pub fn print(tb: *const CheckTraceback, writer: anytype) !void {
            for (tb.stack[0..tb.len]) |label| {
                try writer.writeAll(label);
            }

            if (tb.extra > 0) {
                try writer.print("...({d} more)", .{tb.extra});
            }
        }
    };

    pub const CheckOptions = struct {
        /// The allocator that will be used to allocate any non-const strings and slices.
        allocator: ?std.mem.Allocator = null,

        /// The source location that will be used to print the source of the error.
        source: ?std.builtin.SourceLocation = null,

        /// The label that will be used to identify where on the stack the error occurred.
        label_name: []const u8 = "argument",

        /// The numeric label that will be used to identify where on the stack the error occurred.
        ///
        /// A value of 0 means use the index of the original argument.
        label: c_int = 0,
    };

    fn check_throw(L: *State, options: CheckOptions, tb: ?*const CheckTraceback, comptime fmt: []const u8, args: anytype) noreturn {
        var buffer: Buffer = undefined;
        buffer.init(L);

        var buffered = std.io.bufferedWriter(buffer.writer());
        const writer = buffered.writer();

        if (options.source) |srcinfo| {
            writer.print("{s}:{d}:{d}: in {s}: ", .{ srcinfo.file, srcinfo.line, srcinfo.column, srcinfo.fn_name }) catch unreachable;
        } else {
            writer.writeAll("?:?:?: in ?: ") catch unreachable;
        }

        if (options.label > 0) {
            writer.print("({s} #{d}) ", .{ options.label_name, options.label }) catch unreachable;
        }

        if (tb) |trace| {
            trace.print(writer) catch unreachable;
        }

        writer.writeByte(' ') catch unreachable;
        writer.print(fmt, args) catch unreachable;

        buffered.flush() catch unreachable;
        buffer.final();

        L.throw();
    }

    fn checkInternal(L: *State, comptime T: type, idx: Index, options: CheckOptions, tb: *CheckTraceback) T {
        switch (@typeInfo(T)) {
            .Bool => {
                if (!L.isboolean(idx))
                    check_throw(L, options, tb, "expected boolean, got {s}", .{L.typenameof(idx)});

                return L.toboolean(idx);
            },
            .Int => {
                if (!L.isinteger(idx))
                    check_throw(L, options, tb, "expected integer, got {s}", .{L.typenameof(idx)});

                const num = L.tointeger(idx);
                return std.math.cast(T, num) orelse
                    check_throw(L, options, tb, "expected number in range [{d}, {d}], got {d}", .{ std.math.minInt(T), std.math.maxInt(T), num });
            },
            .Float => {
                if (!L.isnumber(idx))
                    check_throw(L, options, tb, "expected number, got {s}", .{L.typenameof(idx)});

                return @floatCast(L.tonumber(idx));
            },
            .Array => |info| {
                if (info.child == u8 and L.isstring(idx)) {
                    const str = L.tostring(idx).?;
                    if (str.len != info.len)
                        check_throw(L, options, tb, "expected table of length {d}, got {d}", .{ info.len, str.len });

                    return str[0..info.len].*;
                }

                if (!L.istable(idx))
                    check_throw(L, options, tb, "expected table, got {s}", .{L.typenameof(idx)});

                const tlen = L.lenof(idx);
                if (tlen != info.len)
                    check_throw(L, options, tb, "expected table of length {d}, got {d}", .{ info.len, tlen });

                var res: T = undefined;

                for (res[0..], 0..) |*slot, i| {
                    _ = L.rawgeti(idx, @as(Integer, @intCast(i)) + 1);

                    tb.push("[]");
                    slot.* = L.checkInternal(info.child, -1, options, tb);
                    tb.pop();
                }

                L.pop(info.len);
                return res;
            },
            .Struct => |info| {
                if (!L.istable(idx))
                    check_throw(L, options, tb, "expected table, got {s}", .{L.typenameof(idx)});

                var res: T = undefined;

                inline for (info.fields) |field| {
                    _ = L.getfield(idx, literal(field.name));

                    tb.push("." ++ field.name);
                    @field(res, field.name) = L.checkInternal(field.type, -1, options, tb);
                    tb.pop();
                }

                L.pop(info.fields.len);
                return res;
            },
            .Pointer => |info| {
                if (comptime isZigString(T)) {
                    if (!L.isstring(idx))
                        check_throw(L, options, tb, "expected string, got {s}", .{L.typenameof(idx)});

                    if (!info.is_const) {
                        if (options.allocator == null)
                            check_throw(L, options, tb, "cannot allocate non-const string, missing allocator", .{L.typenameof(idx)});

                        const str = L.tostring(idx) orelse unreachable;
                        return options.allocator.dupe(str) catch
                            L.raise("out of memory", .{});
                    }

                    return L.tostring(idx) orelse unreachable;
                }

                switch (T) {
                    [*c]const u8, [*:0]const u8 => {
                        if (!L.isstring(idx))
                            check_throw(L, options, tb, "expected string, got {s}", .{L.typenameof(idx)});

                        return c.lua_tolstring(to(L), idx, null).?;
                    },
                    else => switch (info.size) {
                        .One, .Many, .C => {
                            if (!L.isuserdata(idx))
                                check_throw(L, options, tb, "expected userdata, got {s}", .{L.typenameof(idx)});

                            return @ptrCast(L.touserdata(anyopaque, idx).?);
                        },
                        .Slice => {
                            if (!L.istable(idx))
                                check_throw(L, options, tb, "expected table, got {s}", .{L.typenameof(idx)});

                            if (options.allocator == null)
                                check_throw(L, options, tb, "cannot allocate slice, missing allocator", .{L.typenameof(idx)});

                            const sentinel = if (info.sentinel) |ptr| @as(*const info.child, @ptrCast(ptr)).* else null;

                            const slen = L.lenof(idx);
                            const ptr = options.allocator.allocWithOptions(info.child, slen, info.alignment, sentinel) catch
                                L.raise("out of memory", .{});

                            for (ptr[0..], 0..) |*slot, i| {
                                _ = L.rawgeti(idx, @as(Integer, @intCast(i)) + 1);

                                tb.push("[]");
                                slot.* = L.checkInternal(info.child, -1, options, tb);
                                tb.pop();
                            }

                            L.pop(slen);
                            return ptr;
                        },
                    },
                }
            },
            .Optional => |info| {
                if (L.isnoneornil(idx)) return null;

                tb.push(".?");
                defer tb.pop();

                return L.checkInternal(info.child, idx, options, tb);
            },
            .Enum => |info| {
                if (L.isnumber(idx)) {
                    const value = @as(info.tag_type, @intCast(L.tointeger(idx)));

                    return std.meta.intToEnum(T, value) catch
                        check_throw(L, options, tb, "invalid enum value '{d}' for {s}", .{ value, @typeName(T) });
                } else if (L.isstring(idx)) {
                    const value = L.tostring(idx) orelse unreachable;

                    return std.meta.stringToEnum(T, value) orelse
                        check_throw(L, options, tb, "invalid enum value '{s}' for {s}", .{ value, @typeName(T) });
                } else {
                    check_throw(L, options, tb, "expected number or string, got {s}", .{L.typenameof(idx)});
                }
            },
            else => @compileError("check not implemented for " ++ @typeName(T)),
        }
    }

    /// [-0, +0, v] Checks that the value at the given index is of the given type. Returns the value.
    pub fn check(L: *State, comptime T: type, idx: Index, options: CheckOptions) T {
        var tb = CheckTraceback{
            .stack = undefined,
            .extra = 0,
            .len = 0,
        };
        defer assert(tb.len == 0);

        if (options.label == 0) {
            var new_options = options;
            new_options.label = idx;

            return L.checkInternal(T, idx, new_options, &tb);
        } else {
            return L.checkInternal(T, idx, options, &tb);
        }
    }

    /// [-0, +0, v] Checks that the value at the given index is of the given resource type. Returns a pointer to the
    /// resource.
    ///
    /// If the resource type has a `lunaro_typename` field, it will be used as the resource name. Otherwise, the
    /// type name will be used.
    ///
    /// If the resource type has a `lunaro_raw` field and it is true, the resource will be treated as a raw resource
    /// and the metatable will not be checked.
    pub fn checkResource(L: *State, comptime T: type, idx: Index, options: CheckOptions) *align(@alignOf(usize)) T {
        const resource_name = if (@hasDecl(T, "lunaro_typename"))
            literal(T.lunaro_typename)
        else
            literal(@typeName(T));

        const resource_is_raw = @hasDecl(T, "lunaro_raw") and T.lunaro_raw;

        var new_options = options;
        if (options.label == 0)
            new_options.label = idx;

        if (!L.isuserdata(idx))
            check_throw(L, new_options, null, "expected resource '{s}', got {s}", .{ resource_name, L.typenameof(idx) });

        if (resource_is_raw)
            return L.touserdata(T, idx).?;

        if (!L.getmetatable(idx) or L.typeof(-1) != .table)
            check_throw(L, new_options, null, "expected resource '{s}', got userdata", .{resource_name});

        if (L.getmetatablefor(resource_name) != .table)
            check_throw(L, new_options, null, "attempt to check non-existent resource: '{s}'", .{resource_name});

        if (!L.rawequal(-1, -2)) {
            if (L.getfield(-2, "__name") == .string) {
                check_throw(L, new_options, null, "expected resource '{s}', got '{s}'", .{ resource_name, L.tostring(-1).? });
            } else {
                check_throw(L, new_options, null, "expected resource '{s}', got userdata", .{resource_name});
            }
        }

        L.pop(2);
        return L.touserdata(T, idx).?;
    }

    // [-0, +0, e] Checks that the value at the given index is a function or callable table
    pub fn checkCallable(L: *State, idx: Index, options: CheckOptions) void {
        const typ = L.typeof(idx);

        switch (typ) {
            .function => return,
            .table, .userdata => if (L.getmetatable(idx) and L.typeof(-1) == .table) {
                defer L.pop(2);

                if (L.getfield(-1, "__call") == .function) return;
            },
            else => {},
        }

        var new_options = options;
        if (options.label == 0)
            new_options.label = idx;

        check_throw(L, new_options, null, "expected function, got {s}", .{L.typenameof(idx)});
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
