const std = @import("std");
const lunaro = @import("lunaro.zig");

const State = lunaro.State;

/// A union of the possible Lua types, mostly used for debugging.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    number: lunaro.Number,
    integer: lunaro.Integer,
    string: [:0]const u8,
    table: lunaro.Table,
    function: lunaro.Function,
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
    pub fn init(L: *State, index: lunaro.Index) !Value {
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
            .table => return .{ .table = lunaro.Table.init(L, index) },
            .function => return .{ .function = lunaro.Function.init(L, index) },
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
