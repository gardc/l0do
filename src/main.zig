const std = @import("std");
const ziglua = @import("ziglua");
const httpz = @import("httpz");
const globalState = @import("global_state.zig");
const Lua = ziglua.Lua;
const platform_api = @import("platform/api.zig");
const routing = @import("routing.zig");

pub fn main() !void {
    // setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // setup global state
    std.debug.print("Initializing global state...\n", .{});
    globalState.gs = try globalState.GlobalState.init(allocator);
    defer globalState.gs.deinit();

    // register all platform specific APIs
    platform_api.registerAll(globalState.gs.lua);

    // register the route function
    const wrapped_route = ziglua.wrap(routing.route);
    globalState.gs.lua.pushFunction(wrapped_route);
    globalState.gs.lua.setGlobal("route");
    std.debug.print("Lua global route function set...\n", .{});

    // check & get filename arg
    std.debug.print("Loading Lua file...\n", .{});
    var args = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("Error getting args: {}\n", .{err});
        return;
    };
    defer args.deinit();
    _ = args.skip(); // skips the first arg (program name)
    const lua_file = args.next() orelse {
        std.debug.print("Please provide 1 argument with the lua file to load! Usage: ludo <lua_file>\n", .{});
        return;
    };
    // make sure the file exists by trying to find the file
    std.fs.cwd().access(lua_file, .{}) catch {
        std.debug.print("File not found: {s}\n", .{lua_file});
        return;
    };

    // load the lua file in the interpreter
    globalState.gs.lua.doFile(lua_file) catch |err| {
        std.debug.print("Error loading luafile: {}\n", .{err});
        return;
    };

    // setup http server
    std.debug.print("Setting up http server...\n", .{});
    var server = try httpz.Server().init(globalState.gs.allocator, .{ .port = 5555 });
    defer server.deinit();

    var internal_router = server.router();
    internal_router.all("/*", routing.handleLuaRoute);

    std.debug.print("Starting server on port 5555...\n", .{});

    // Setup ctrl-c handler
    const sigaction = std.posix.Sigaction{
        .handler = .{ .handler = (struct {
            fn handler(sig: c_int) callconv(.C) void {
                _ = sig;
                std.debug.print("\nReceived SIGINT, shutting down...\n", .{});
                std.process.exit(0);
            }
        }).handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.INT, &sigaction, null);

    try server.listen();
}

// -----
// tests
// -----

test "basic Lua initialization" {
    std.debug.print("\n=== Testing standalone Lua initialization ===\n", .{});
    const allocator = std.testing.allocator;
    var lua = try Lua.init(allocator);
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

    const wrapped_route = ziglua.wrap(routing.route);
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
