//! A Lua string buffer
//!
//! During its normal operation, a string buffer uses a variable number of stack slots. So, while using a buffer,
//! you cannot assume that you know where the top of the stack is. You can use the stack between successive calls to
//! buffer operations as long as that use is balanced; that is, when you call a buffer operation, the stack is at
//! the same level it was immediately after the previous buffer operation.
//!
//! This struct must be pinned, it cannot be moved or copied after initialization.

const std = @import("std");
const lunaro = @import("lunaro.zig");

const State = lunaro.State;
const Buffer = @This();

const c = lunaro.c;
const lua_version = lunaro.lua_version;

const assert = std.debug.assert;

state: *State,
buf: c.luaL_Buffer,

pin_check: if (std.debug.runtime_safety) *const Buffer else void,

/// [-0, +0, -] Initializes a buffer B. This function does not allocate any space.
pub fn init(buffer: *Buffer, L: *State) void {
    buffer.state = L;
    if (std.debug.runtime_safety) buffer.pin_check = buffer;

    c.luaL_buffinit(L.to(), &buffer.buf);
}

/// [-?, +?, m] Returns a slice of memory of at *most* `max_size` bytes where you can copy a string to be added
/// to the buffer (see `commit`).
pub fn reserve(buffer: *Buffer, max_size: usize) []u8 {
    if (std.debug.runtime_safety) assert(buffer == buffer.pin_check);

    const ptr = if (lua_version >= 502)
        c.luaL_prepbuffsize(&buffer.buf, max_size)
    else
        c.luaL_prepbuffer(&buffer.buf);

    const clamped_len = if (lua_version >= 502)
        max_size
    else
        @min(max_size, c.LUAL_BUFFERSIZE);

    return ptr[0..clamped_len];
}

/// [-?, +?, -] Adds to the buffer a string of length `size` that had previously been copied into the buffer
/// area provided by `reserve`.
pub fn commit(buffer: *Buffer, size: usize) void {
    if (std.debug.runtime_safety) assert(buffer == buffer.pin_check);

    // TODO: translate-c bug: c.luaL_addsize(&buffer.buf, size);
    if (lua_version >= 502) {
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
    if (std.debug.runtime_safety) assert(buffer == buffer.pin_check);

    c.luaL_addlstring(&buffer.buf, str.ptr, str.len);
}

/// [-1, +?, m] Adds the value at the top of the stack to the buffer. Pops the value.
pub fn addvalue(buffer: *Buffer) void {
    if (std.debug.runtime_safety) assert(buffer == buffer.pin_check);

    c.luaL_addvalue(&buffer.buf);
}

/// [-?, +1, m] Finishes the use of buffer B leaving the final string on the top of the stack.
pub fn final(buffer: *Buffer) void {
    if (std.debug.runtime_safety) assert(buffer == buffer.pin_check);

    c.luaL_pushresult(&buffer.buf);
}

/// A Lua writer function that can be used to write to a string buffer.
pub fn luaWrite(L_opt: ?*c.lua_State, p: ?[*]const u8, sz: usize, ud: ?*anyopaque) callconv(.C) c_int {
    _ = L_opt;
    assert(ud != null);
    assert(p != null);

    const buf: *Buffer = @ptrCast(@alignCast(ud.?));
    buf.addstring(p.?[0..sz]);

    return 0;
}

pub fn write(buffer: *Buffer, bytes: []const u8) error{}!usize {
    buffer.addstring(bytes);
    return bytes.len;
}

pub const Writer = std.io.GenericWriter(*Buffer, error{}, write);

pub fn writer(buffer: *Buffer) Writer {
    return Writer{ .context = buffer };
}

comptime {
    if (@import("builtin").is_test)
        std.testing.refAllDecls(Buffer);
}
