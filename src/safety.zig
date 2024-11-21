const std = @import("std");
const lunaro = @import("lunaro.zig");

const State = lunaro.State;
const Index = lunaro.Index;

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
                const symbol_info: std.debug.Symbol = module.getSymbolAtAddress(debug_info.allocator, address) catch break :debuginfo;
                defer symbol_info.deinit(debug_info.allocator);

                if (symbol_info.source_location) |info| {
                    L.raise("stack check failed in %s at %s:%d (expected %d items but %d were pushed)", .{ symbol_info.name, info.file_name, info.line, pushed, new_top - self.top });
                }

                L.raise("stack check failed in %s (expected %d items but %d were pushed)", .{ symbol_info.name, pushed, new_top - self.top });
            }

            L.raise("stack check failed (expected %d items but %d were pushed)", .{ pushed, new_top - self.top });
        }

        return pushed;
    }
};

comptime {
    if (@import("builtin").is_test)
        std.testing.refAllDecls(StackCheck);
}
