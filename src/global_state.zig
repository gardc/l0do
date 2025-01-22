const std = @import("std");
const ziglua = @import("ziglua");
pub const GlobalState = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,
    routes: std.StringHashMap(i32),
    lua: *ziglua.Lua,

    pub fn init() !GlobalState {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        const routes = std.StringHashMap(i32).init(allocator);
        const lua = try ziglua.Lua.init(allocator);
        errdefer lua.deinit();

        lua.openBase();

        return GlobalState{
            .gpa = gpa,
            .allocator = allocator,
            .routes = routes,
            .lua = lua,
        };
    }

    pub fn deinit(self: *GlobalState) void {
        self.routes.deinit();
        self.lua.deinit();

        _ = self.gpa.deinit();
    }
};
