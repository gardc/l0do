const std = @import("std");
const ziglua = @import("ziglua");
const httpz = @import("httpz");
const globalState = @import("global_state.zig");
const Lua = ziglua.Lua;

var gs: globalState.GlobalState = undefined;

pub fn main() !void {
    std.debug.print("Initializing global state...\n", .{});
    gs = try globalState.GlobalState.init();
    defer gs.deinit();

    // args
    var args = std.process.argsWithAllocator(gs.allocator) catch |err| {
        std.debug.print("Error getting args: {}\n", .{err});
        return;
    };
    defer args.deinit();
    _ = args.skip();

    const file_name = args.next() orelse {
        std.debug.print("Usage: l0do <file>\n", .{});
        return;
    };

    std.debug.print("file_name: {s}\n", .{file_name});

    std.debug.print("Registering route function...\n", .{});
    // Register the route function first
    try registerRouteFn(gs.lua);

    std.debug.print("Loading Lua file...\n", .{});
    // Then load file
    gs.lua.doFile(file_name) catch |err| {
        std.debug.print("Error loading luafile: {}\n", .{err});
        return;
    };

    std.debug.print("Setting up web server...\n", .{});
    // webserver testing
    var server = try httpz.Server().init(gs.allocator, .{ .port = 5555 });
    defer server.deinit();

    var router = server.router();
    router.get("/*", handleLuaRoute);

    // std.debug.print("Opening Lua libraries...\n", .{});
    // // Open all standard libraries
    // gs.lua.openLibs();

    std.debug.print("Starting server...\n", .{});
    try server.listen();
}

fn registerRouteFn(lua: *Lua) !void {
    std.debug.print("Pushing route function...\n", .{});
    lua.pushFunction(ziglua.wrap(inner));
    std.debug.print("Setting global 'route'...\n", .{});
    lua.setGlobal("route"); // This gets trace trap error for some reason
    std.debug.print("Route function registered\n", .{});
}

fn inner(l: *Lua) i32 {
    std.debug.print("Route function called\n", .{});

    if (l.getTop() < 2) {
        std.debug.print("Error: route requires 2 arguments\n", .{});
        return l.raiseErrorStr("route requires 2 arguments (path, function)", .{});
    }

    if (!l.isString(1)) {
        std.debug.print("Error: first argument must be string\n", .{});
        return l.raiseErrorStr("first argument must be string", .{});
    }

    if (!l.isFunction(2)) {
        std.debug.print("Error: second argument must be function\n", .{});
        return l.raiseErrorStr("second argument must be function", .{});
    }

    const path = l.toString(1) catch |err| {
        std.debug.print("Error getting path string: {}\n", .{err});
        return l.raiseErrorStr("failed to get path string", .{});
    };

    std.debug.print("Registering route for path: {s}\n", .{path});

    // Store the function reference in the registry
    l.pushValue(2);
    const ref = l.ref(ziglua.registry_index) catch |err| {
        std.debug.print("Error storing function reference: {}\n", .{err});
        return l.raiseErrorStr("failed to store function reference", .{});
    };

    // Store path and function reference in routes
    const path_copy = gs.allocator.dupe(u8, path) catch |err| {
        std.debug.print("Error duplicating path: {}\n", .{err});
        return l.raiseErrorStr("failed to store path", .{});
    };

    gs.routes.put(path_copy, ref) catch |err| {
        std.debug.print("Error storing route: {}\n", .{err});
        gs.allocator.free(path_copy);
        return l.raiseErrorStr("failed to store route", .{});
    };

    std.debug.print("Successfully registered route\n", .{});
    return 0;
}

// fn handle_root(req: *httpz.Request, res: *httpz.Response) !void {
//     const resText = try std.fmt.allocPrint(gs.allocator, "Hello, World! You are at {s}", .{req.url.path});
//     res.body = resText;
// }

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
