const std = @import("std");
const lunaro = @import("lunaro");

const expect = std.testing.expect;

pub fn main() !void {
    const L = try lunaro.State.init();
    defer L.close();

    L.checkversion();
    L.openlibs();

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
}
