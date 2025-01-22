const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

extern "c" fn getBatteryLevel() f64;

fn getBatteryLevelLua(lua: *Lua) i32 {
    const level = getBatteryLevel();
    if (level < 0) {
        lua.pushNil();
        _ = lua.pushString("Unable to get battery level");
        return 2;
    }
    lua.pushNumber(level);
    return 1;
}

pub fn register(lua: *Lua) void {
    lua.pushFunction(ziglua.wrap(getBatteryLevelLua));
    lua.setGlobal("getBatteryLevel");
}
