const std = @import("std");
const lunaro = @import("lunaro");

const expect = std.testing.expect;

pub fn main() !void {
    const L = try lunaro.State.init();
    defer L.close();

    L.checkversion();
    L.openlibs();

    L.push(testfn);

    try expect(L.getglobal("print") == .function);
    const print = try L.functionAt(-1);

    L.push("Hello, ");
    L.push("World!");
    L.concat(2);

    L.pushvalue(-1);
    L.insert(-3);

    L.call(1, 0);

    const value = try L.valueAt(-1);
    try expect(value == .string);
    try expect(std.mem.eql(u8, value.string, "Hello, World!"));

    print.call(.{"This is a print() call!"}, .none);

    L.call(1, 1);

    const value1 = try L.valueAt(-1);
    try expect(value1 == .boolean and value1.boolean == true);

    print.push(L);
    L.push(does_error);
    try expect(L.pcall(0, 1, 0) != .ok);

    L.call(1, 0);
}

pub fn testfn(L: *lunaro.State) bool {
    const value = L.check([]const u8, 1, .{ .source = @src() });

    expect(std.mem.eql(u8, value, "Hello, World!")) catch return false;

    return true;
}

pub fn does_error(L: *lunaro.State) bool {
    const value = L.check(bool, 1, .{ .source = @src() });
    return value;
}
