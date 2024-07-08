const std = @import("std");
const lunaro = @import("lunaro.zig");

const State = lunaro.State;
const Index = lunaro.Index;

const Value = lunaro.Value;
const Table = @This();

const assert = std.debug.assert;
state: *State,
ref: Index,

/// [-0, +0, -] Initializes a table from the value at the given index. This stores a reference to the table.
///
/// Asserts that the value at the given index is a table.
pub fn init(L: *State, index: Index) Table {
    assert(L.typeof(index) == .table);

    L.pushvalue(index);
    return .{ .ref = L.ref(lunaro.REGISTRYINDEX), .state = L };
}

/// [-0, +0, -] Deinitializes this representation and dereferences the table.
pub fn deinit(table: Table) void {
    table.state.unref(lunaro.REGISTRYINDEX, table.ref);
}

/// [-0, +1, m] Pushes this table onto the stack of `to`. The `to` thread must be in the same state as this table.
pub fn push(table: Table, to: *State) void {
    assert(table.state.geti(lunaro.REGISTRYINDEX, table.ref) == .table);

    if (to != table.state)
        table.state.xmove(to, 1);
}

/// [-0, +1, e] Gets the value at the given key in this table and pushes it onto the stack.
pub fn get(table: Table, key: anytype) void {
    assert(table.state.geti(lunaro.REGISTRYINDEX, table.ref) == .table);
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
    assert(table.state.geti(lunaro.REGISTRYINDEX, table.ref) == .table);
    table.state.push(key);
    table.state.pushvalue(-3);
    table.state.settable(-3);
    table.state.pop(2);
}

/// [-0, +0, e] Sets the value at the given key in this table.
pub fn setValue(table: Table, key: anytype, value: anytype) void {
    assert(table.state.geti(lunaro.REGISTRYINDEX, table.ref) == .table);
    table.state.push(key);
    table.state.push(value);
    table.state.settable(-3);
    table.state.pop(1);
}

comptime {
    if (@import("builtin").is_test)
        std.testing.refAllDecls(Table);
}
