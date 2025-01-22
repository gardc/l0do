const std = @import("std");
const ziglua = @import("ziglua");
const httpz = @import("httpz");
const globalState = @import("global_state.zig");
const Lua = ziglua.Lua;
const platform_api = @import("platform/api.zig");

var gs: globalState.GlobalState = undefined;

fn route(lua: *Lua) i32 {
    if (lua.getTop() < 2) { // check if there are at least 2 arguments
        std.debug.print("Error: route() requires 2 arguments\n", .{});
        lua.raiseErrorStr("route() requires 2 arguments", .{}) catch return 0;
        return 0;
    }
    if (!lua.isString(1)) { // check if the first argument is a string
        std.debug.print("Error: First argument must be a string\n", .{});
        lua.raiseErrorStr("First argument must be a string", .{}) catch return 0;
        return 0;
    }
    if (!lua.isFunction(2)) { // check if the second argument is a function
        std.debug.print("Error: Second argument must be a function\n", .{});
        lua.raiseErrorStr("Second argument must be a function", .{}) catch return 0;
        return 0;
    }

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

/// handleLuaRoute is the function that handles the Lua routes.
/// Currently it gives the Lua function access to the request and response objects
/// like so:
///
/// route("/", function(req, res)
///     return "hello, " .. req.path
/// end)
///
/// The Lua function can then access the request and response objects like so:
///
/// local path = req.path
/// local body = req.body
/// local method = req.method
/// local protocol = req.protocol
/// local body = req.body
///
/// res.status = 200
///
/// return "hello, " .. req.path
/// end)
///
fn handleLuaRoute(req: *httpz.Request, res: *httpz.Response) !void {
    if (gs.routes.get(req.url.path)) |fnRef| {
        const initial_top = gs.lua.getTop();
        defer {
            gs.lua.setTop(initial_top);
        }

        // Get the function from registry
        _ = gs.lua.rawGetIndex(ziglua.registry_index, fnRef);

        // Create request table
        gs.lua.createTable(0, 4);
        _ = gs.lua.pushString(req.url.path);
        gs.lua.setField(-2, "path");

        if (req.body_buffer) |buffer| {
            const body_str = try gs.allocator.dupe(u8, buffer.data);
            _ = gs.lua.pushString(body_str);
        } else {
            _ = gs.lua.pushString("");
        }
        gs.lua.setField(-2, "body");

        _ = gs.lua.pushString(@tagName(req.method));
        gs.lua.setField(-2, "method");

        _ = gs.lua.pushString(@tagName(req.protocol));
        gs.lua.setField(-2, "protocol");

        // Create response table
        gs.lua.createTable(0, 1);
        _ = gs.lua.pushInteger(200);
        gs.lua.setField(-2, "status");

        // Save response table reference before call
        const response_ref = gs.lua.ref(ziglua.registry_index) catch return;
        defer gs.lua.unref(ziglua.registry_index, response_ref);

        // Get response table back on stack
        _ = gs.lua.rawGetIndex(ziglua.registry_index, response_ref);

        // Call function with request table and response table
        try gs.lua.protectedCall(.{ .args = 2, .results = 1 });

        // Handle return value (response body)
        const response = try gs.lua.toString(-1);
        res.body = try gs.allocator.dupe(u8, response);
        gs.lua.pop(1);

        // Get response table back again
        _ = gs.lua.rawGetIndex(ziglua.registry_index, response_ref);

        // Get status
        if (gs.lua.getField(-1, "status") == .number) {
            const status = try gs.lua.toInteger(-1);
            res.status = @intCast(status);
        }
    } else {
        res.body = "404 Not Found";
        res.status = 404;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    std.debug.print("Initializing global state...\n", .{});
    gs = try globalState.GlobalState.init(allocator);
    defer gs.deinit();

    // register all platform specific APIs
    platform_api.registerAll(gs.lua);

    const wrapped_route = ziglua.wrap(route);
    gs.lua.pushFunction(wrapped_route);
    gs.lua.setGlobal("route");
    std.debug.print("Lua global route function set...\n", .{});

    std.debug.print("Loading Lua file...\n", .{});

    // Then load file
    var args = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("Error getting args: {}\n", .{err});
        return;
    };
    defer args.deinit();
    _ = args.skip(); // skips the first arg (program name)
    const lua_file = args.next() orelse {
        std.debug.print("Wrong usage! Usage: l0do <lua_file>\n", .{});
        return;
    };
    // make sure the file exists by trying to find the file
    std.fs.cwd().access(lua_file, .{}) catch {
        std.debug.print("File not found: {s}\n", .{lua_file});
        return;
    };

    gs.lua.doFile(lua_file) catch |err| {
        std.debug.print("Error loading luafile: {}\n", .{err});
        return;
    };

    std.debug.print("Setting up web server...\n", .{});
    // webserver testing
    var server = try httpz.Server().init(gs.allocator, .{ .port = 5555 });
    defer server.deinit();

    var internal_router = server.router();
    internal_router.all("/*", handleLuaRoute);

    std.debug.print("Starting server...\n", .{});
    try server.listen();
}

// -----
// tests
// -----

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
