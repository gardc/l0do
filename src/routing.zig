const std = @import("std");
const ziglua = @import("ziglua");
const globalState = @import("global_state.zig");
const httpz = @import("httpz");
const Lua = ziglua.Lua;

/// route is the Zig function that's called when the Lua "route" function is called.
/// It registers a Lua function as a route handler.
pub fn route(lua: *Lua) i32 {
    if (lua.getTop() < 2) { // check if there are at least 2 arguments
        std.debug.print("Error: route() requires 2 arguments\n", .{});
        globalState.gs.lua.raiseErrorStr("route() requires 2 arguments", .{}) catch return 0;
        return 0;
    }
    if (!lua.isString(1)) { // check if the first argument is a string
        std.debug.print("Error: First argument must be a string\n", .{});
        globalState.gs.lua.raiseErrorStr("First argument must be a string", .{}) catch return 0;
        return 0;
    }
    if (!lua.isFunction(2)) { // check if the second argument is a function
        std.debug.print("Error: Second argument must be a function\n", .{});
        globalState.gs.lua.raiseErrorStr("Second argument must be a function", .{}) catch return 0;
        return 0;
    }

    const path = lua.toString(1) catch return 0;

    // Store the function reference in the registry
    globalState.gs.lua.pushValue(2);
    const ref = globalState.gs.lua.ref(ziglua.registry_index) catch return 0;

    // Store path and function reference in routes
    const path_copy = globalState.gs.allocator.dupe(u8, path) catch return 0;

    globalState.gs.routes.put(path_copy, ref) catch {
        std.debug.print("Error storing route\n", .{});
        globalState.gs.allocator.free(path_copy);
        return 0;
    };

    return 1;
}

/// handleLuaRoute is the function that gets called when we receive a request.
/// It then calls the anonymous Lua function that was registered with the route as the second argument to route().
/// It gives the Lua function access to the request and response objects
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
pub fn handleLuaRoute(req: *httpz.Request, res: *httpz.Response) !void {
    if (globalState.gs.routes.get(req.url.path)) |fnRef| {
        const initial_top = globalState.gs.lua.getTop();
        defer {
            globalState.gs.lua.setTop(initial_top);
        }

        // Get the function from registry
        _ = globalState.gs.lua.rawGetIndex(ziglua.registry_index, fnRef);

        // Create request table
        globalState.gs.lua.createTable(0, 4);
        _ = globalState.gs.lua.pushString(req.url.path);
        globalState.gs.lua.setField(-2, "path");

        if (req.body_buffer) |buffer| {
            const body_str = try globalState.gs.allocator.dupe(u8, buffer.data);
            _ = globalState.gs.lua.pushString(body_str);
        } else {
            _ = globalState.gs.lua.pushString("");
        }
        globalState.gs.lua.setField(-2, "body");

        _ = globalState.gs.lua.pushString(@tagName(req.method));
        globalState.gs.lua.setField(-2, "method");

        _ = globalState.gs.lua.pushString(@tagName(req.protocol));
        globalState.gs.lua.setField(-2, "protocol");

        // Create response table
        globalState.gs.lua.createTable(0, 1);
        _ = globalState.gs.lua.pushInteger(200);
        globalState.gs.lua.setField(-2, "status");

        // Save response table reference before call
        const response_ref = globalState.gs.lua.ref(ziglua.registry_index) catch return;
        defer globalState.gs.lua.unref(ziglua.registry_index, response_ref);

        // Get response table back on stack
        _ = globalState.gs.lua.rawGetIndex(ziglua.registry_index, response_ref);

        // Call function with request table and response table
        try globalState.gs.lua.protectedCall(.{ .args = 2, .results = 1 });

        // Handle return value (response body)
        const response = try globalState.gs.lua.toString(-1);
        res.body = try globalState.gs.allocator.dupe(u8, response);
        globalState.gs.lua.pop(1);

        // Get response table back again
        _ = globalState.gs.lua.rawGetIndex(ziglua.registry_index, response_ref);

        // Get status
        if (globalState.gs.lua.getField(-1, "status") == .number) {
            const status = try globalState.gs.lua.toInteger(-1);
            res.status = @intCast(status);
        }
    } else {
        res.body = "404 Not Found";
        res.status = 404;
    }
}
