const std = @import("std");
const lunaro = @import("lunaro.zig");

const State = lunaro.State;
const Value = lunaro.Value;
const Function = @This();

const assert = std.debug.assert;

state: *State,
ref: c_int,

/// [-0, +0, -] Initializes a function from the value at the given index. This stores a reference to the function.
///
/// Asserts that the value at the given index is a function.
pub fn init(L: *State, index: lunaro.Index) Function {
    assert(L.typeof(index) == .function);

    L.pushvalue(index);
    return .{ .ref = L.ref(lunaro.REGISTRYINDEX), .state = L };
}

/// [-0, +0, -] Deinitializes this representation and dereferences the function.
pub fn deinit(func: Function) void {
    func.state.unref(lunaro.REGISTRYINDEX, func.ref);
}

/// [-0, +1, m] Pushes this function onto the stack of `to`. The `to` thread must be in the same state as this function.
pub fn push(func: Function, to: *State) void {
    assert(func.state.geti(lunaro.REGISTRYINDEX, func.ref) == .function);

    func.state.xmove(to, 1);
}

pub const ReturnType = union(enum) {
    /// Drop all return values.
    none,

    /// Return a single Value of the first return.
    /// The value is left on the stack.
    value,

    /// Return the number of return values left on the stack.
    all,

    /// Return a tuple of the given types.
    /// The values are left on the stack.
    many: []const type,
};

fn MakeCallReturn(comptime ret: ReturnType) type {
    switch (ret) {
        .none => return void,
        .value => return Value,
        .all => return lunaro.Size,
        .many => |v| return std.meta.Tuple(v),
    }
}

/// [-0, +nargs, e] Calls this function with the given arguments and returns the result.
pub fn call(func: Function, args: anytype, comptime returns: ReturnType) MakeCallReturn(returns) {
    const prev_top = func.state.gettop();

    assert(func.state.geti(lunaro.REGISTRYINDEX, func.ref) == .function);

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
        .value => return Value.init(func.state, -1),
        .all => return @intCast(func.state.gettop() - prev_top),
        .many => {
            inline for (returns.many, 0..) |T, i| {
                ret[i] = func.state.check(T, prev_top + i + 1, .{
                    .source = @src(),
                    .label_name = "return",
                    .label = i,
                });
            }

            return ret;
        },
    }
}

comptime {
    if (@import("builtin").is_test)
        std.testing.refAllDecls(Function);
}
