const std = @import("std");
const ziglua = @import("ziglua");

pub const GlobalState = struct {
    allocator: std.mem.Allocator,
    routes: std.StringHashMap(i32),
    lua: *ziglua.Lua,

    pub fn init(allocator: std.mem.Allocator) !GlobalState {
        const routes = std.StringHashMap(i32).init(allocator);
        var lua = try ziglua.Lua.init(allocator);
        errdefer lua.deinit();

        // lua.openLibs();
        // lua.openBase();

        return GlobalState{
            .allocator = allocator,
            .routes = routes,
            .lua = lua,
        };
    }

    pub fn deinit(self: *GlobalState) void {
        self.routes.deinit();
        self.lua.deinit();
    }
};

test "GlobalState - basic initialization" {
    std.debug.print("\n=== Testing basic GlobalState initialization ===\n", .{});

    const allocator = std.testing.allocator;

    var gs = try GlobalState.init(allocator);
    defer gs.deinit();
    std.debug.print("Basic initialization successful\n", .{});
}

test "GlobalState - Lua initialization with libs" {
    std.debug.print("\n=== Testing Lua initialization with libraries ===\n", .{});

    const allocator = std.testing.allocator;

    var gs = try GlobalState.init(allocator);
    defer gs.deinit();

    std.debug.print("Opening Lua libraries...\n", .{});
    gs.lua.openLibs();
    std.debug.print("Libraries opened successfully\n", .{});
}

test "GlobalState - Lua basic operations" {
    std.debug.print("\n=== Testing basic Lua operations ===\n", .{});

    const allocator = std.testing.allocator;

    var gs = try GlobalState.init(allocator);
    defer gs.deinit();

    gs.lua.openLibs();

    // Try pushing and retrieving a string
    std.debug.print("Testing string operations...\n", .{});
    _ = gs.lua.pushString("test");
    try std.testing.expect(gs.lua.isString(-1));

    // Try running a simple Lua chunk
    std.debug.print("Testing Lua execution...\n", .{});
    try gs.lua.doString("a = 1 + 1");
}
