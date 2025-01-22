const std = @import("std");
const ziglua = @import("ziglua");
const httpz = @import("httpz");
const globalState = @import("global_state.zig");

const Lua = ziglua.Lua;

var state: globalState.GlobalState = undefined;

pub fn main() !void {
    state.init() catch |err| {
        std.debug.print("Error initializing state: {}\n", .{err});
        return;
    };
    defer state.deinit();
    // args
    var args = std.process.argsWithAllocator(state.allocator) catch |err| {
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

    var lua = Lua.init(state.allocator) catch |err| {
        std.debug.print("Error initializing Lua: {}\n", .{err});
        return;
    };
    defer lua.deinit();

    // load file
    lua.doFile(file_name) catch |err| {
        std.debug.print("Error loading luafile: {}\n", .{err});
    };

    // // get hello
    // _ = try lua.getGlobal("hello");
    // std.debug.print("hello {s}\n", .{try lua.toString(-1)});

    // webserver testing
    var server = try httpz.Server().init(state.allocator, .{ .port = 5555 });
    defer server.deinit();

    var router = server.router();
    router.get("/*", handle_root);

    try server.listen();
}

fn handle_root(req: *httpz.Request, res: *httpz.Response) !void {
    const resText = try std.fmt.allocPrint(state.allocator, "Hello, World! You are at {s}", .{req.url.path});
    res.body = resText;
}
