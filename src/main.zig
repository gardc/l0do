const std = @import("std");
const ziglua = @import("ziglua");
const httpz = @import("httpz");
const globalState = @import("global_state.zig");
const Lua = ziglua.Lua;

var gs: globalState.GlobalState = undefined;

fn route(lua: *Lua) i32 {
    if (lua.getTop() < 2) return 0;
    if (!lua.isString(1)) return 0;
    if (!lua.isFunction(2)) return 0;

    const path = lua.toString(1) catch return 0;

    // Store the function reference in the registry
    lua.pushValue(2);
    const ref = lua.ref(ziglua.registry_index) catch return 0;

    // Store path and function reference in routes
    const path_copy = gs.allocator.dupe(u8, path) catch return 0;

    gs.routes.put(path_copy, ref) catch {
        std.debug.print("Error storing route\n", .{});
        gs.allocator.free(path_copy);
        return 0;
    };

    return 1;
}

fn handleLuaRoute(req: *httpz.Request, res: *httpz.Response) !void {
    if (gs.routes.get(req.url.path)) |fnRef| {
        // Get the function from registry using the stored reference
        _ = gs.lua.rawGetIndex(ziglua.registry_index, fnRef);

        // Create request table
        gs.lua.createTable(0, 1);
        _ = gs.lua.pushString(req.url.path);
        gs.lua.setField(-2, "path");

        // Create response table
        gs.lua.createTable(0, 0);

        // Call the function with 2 arguments (req, res), expecting 1 return value
        try gs.lua.protectedCall(.{ .args = 2, .results = 1 });

        // Get the return value as the response
        const response = try gs.lua.toString(-1);
        res.body = try gs.allocator.dupe(u8, response);
    } else {
        res.body = "404 Not Found";
        res.status = 404;
    }
}

// -----
// tests
// -----

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    std.debug.print("Initializing global state...\n", .{});
    gs = try globalState.GlobalState.init(allocator);
    defer gs.deinit();

    std.debug.print("Opening Lua libraries...\n", .{});

    std.debug.print("Registering route function...\n", .{});
    const wrapped_route = ziglua.wrap(route);
    std.debug.print("Function wrapped...\n", .{});

    gs.lua.pushFunction(wrapped_route);
    std.debug.print("Function pushed...\n", .{});

    gs.lua.setGlobal("route");
    std.debug.print("Global set successfully\n", .{});

    std.debug.print("Loading Lua file...\n", .{});
    // Then load file
    gs.lua.doFile("test.lua") catch |err| {
        std.debug.print("Error loading luafile: {}\n", .{err});
        return;
    };

    std.debug.print("Setting up web server...\n", .{});
    // webserver testing
    var server = try httpz.Server().init(gs.allocator, .{ .port = 5555 });
    defer server.deinit();

    var internal_router = server.router();
    internal_router.get("/*", handleLuaRoute);

    std.debug.print("Starting server...\n", .{});
    try server.listen();
}

test "basic Lua initialization" {
    std.debug.print("\n=== Testing standalone Lua initialization ===\n", .{});
    var lua = try Lua.init(std.heap.page_allocator);
    defer lua.deinit();

    std.debug.print("Opening libraries...\n", .{});
    lua.openLibs();
    std.debug.print("Libraries opened successfully\n", .{});
}

test "route function registration" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Testing route function registration ===\n", .{});
    var testgs = try globalState.GlobalState.init(allocator);
    defer testgs.deinit();

    std.debug.print("created testgs...\n", .{});

    const wrapped_route = ziglua.wrap(route);
    std.debug.print("wrapped route is {any}...\n", .{wrapped_route});

    testgs.lua.pushFunction(wrapped_route);
    std.debug.print("pushed function...\n", .{});

    testgs.lua.setGlobal("route");
    std.debug.print("set global route...\n", .{});

    testgs.lua.openBase();

    // Test if we can retrieve the function
    const lua_type = try testgs.lua.getGlobal("route");
    std.debug.print("Lua type: {}\n", .{lua_type});
    try std.testing.expect(testgs.lua.isFunction(-1));
}
