const std = @import("std");
const lunaro = @import("lunaro.zig");

const State = lunaro.State;

const lua_version = lunaro.lua_version;

pub fn le(L: *State, A: lunaro.Index, B: lunaro.Index) bool {
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

    if (L.getmetafield(absA, "__le") != .nil or L.getmetafield(absB, "__le") != .nil) {
        L.pushvalue(absA);
        L.pushvalue(absB);
        L.call(2, 1);

        const res = L.toboolean(-1);
        L.pop(1);
        return res;
    }

    if (L.getmetafield(absA, "__lt") != .nil or L.getmetafield(absB, "__lt") != .nil) {
        L.pushvalue(absB);
        L.pushvalue(absA);
        L.call(2, 1);

        const res = L.toboolean(-1);
        L.pop(1);
        return !res;
    }

    L.raise("attempt to compare %s with %s", .{ L.typenameof(absA), L.typenameof(absB) });
}

pub fn add(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        if (lua_version >= 503) {
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

    if (L.getmetafield(-2, "__add") != .nil or L.getmetafield(-1, "__add") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn sub(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        if (lua_version >= 503) {
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

    if (L.getmetafield(-2, "__sub") != .nil or L.getmetafield(-1, "__sub") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn mul(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        if (lua_version >= 503) {
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

    if (L.getmetafield(-2, "__mul") != .nil or L.getmetafield(-1, "__mul") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn div(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        if (lua_version >= 503) {
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

    if (L.getmetafield(-2, "__div") != .nil or L.getmetafield(-1, "__div") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn idiv(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        const a = L.tonumber(-2);
        const b = L.tonumber(-1);
        L.pop(2);

        return L.push(@divFloor(a, b));
    }

    if (L.getmetafield(-2, "__idiv") != .nil or L.getmetafield(-1, "__idiv") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn mod(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        if (lua_version >= 503) {
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

    if (L.getmetafield(-2, "__mod") != .nil or L.getmetafield(-1, "__mod") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn pow(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        if (lua_version >= 503) {
            if (L.isinteger(-2) and L.isinteger(-1)) {
                const a = L.tointeger(-2);
                const b = L.tointeger(-1);
                L.pop(2);

                return L.push(std.math.pow(@TypeOf(a, b), a, b));
            }
        }

        const a = L.tonumber(-2);
        const b = L.tonumber(-1);
        L.pop(2);

        return L.push(std.math.pow(@TypeOf(a, b), a, b));
    }

    if (L.getmetafield(-2, "__pow") != .nil or L.getmetafield(-1, "__pow") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn unm(L: *State) void {
    if (L.isnumber(-1)) {
        if (lua_version >= 503) {
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

    if (L.getmetafield(-1, "__unm") != .nil) {
        L.pushvalue(-1);
        L.call(1, 1);
        return;
    }

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn bnot(L: *State) void {
    if (L.isnumber(-1)) {
        const a = L.tointeger(-1);
        L.pop(1);

        return L.push(~a);
    }

    if (L.getmetafield(-1, "__bnot") != .nil) {
        L.pushvalue(-1);
        L.call(1, 1);
        return;
    }

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn band(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        const a = L.tointeger(-2);
        const b = L.tointeger(-1);
        L.pop(2);

        return L.push(a & b);
    }

    if (L.getmetafield(-2, "__band") != .nil or L.getmetafield(-1, "__band") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

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

    if (L.getmetafield(-2, "__bor") != .nil or L.getmetafield(-1, "__bor") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

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

    if (L.getmetafield(-2, "__bxor") != .nil or L.getmetafield(-1, "__bxor") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn shl(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        const a = L.tointeger(-2);
        const amt = L.tointeger(-1);
        L.pop(2);

        if (amt >= @bitSizeOf(@TypeOf(a))) return L.push(0);
        return L.push(a << @intCast(amt));
    }

    if (L.getmetafield(-2, "__shl") != .nil or L.getmetafield(-1, "__shl") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}

pub fn shr(L: *State) void {
    if (L.isnumber(-2) and L.isnumber(-1)) {
        const a = L.tointeger(-2);
        const amt = L.tointeger(-1);
        L.pop(2);

        if (amt >= @bitSizeOf(@TypeOf(a))) return L.push(0);
        return L.push(a >> @intCast(amt));
    }

    if (L.getmetafield(-2, "__shr") != .nil or L.getmetafield(-1, "__shr") != .nil) {
        L.pushvalue(-2);
        L.pushvalue(-1);
        L.call(2, 1);
        return;
    }

    if (!L.isnumber(-2))
        L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-2)});

    L.raise("attempt to perform arithmetic on a %s value", .{L.typenameof(-1)});
}
