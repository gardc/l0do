const std = @import("std");
const builtin = @import("builtin");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

pub fn registerAll(lua: *Lua) void {
    if (builtin.target.os.tag == .macos) {
        const battery = @import("macos/battery.zig");
        battery.register(lua);
    }
}
