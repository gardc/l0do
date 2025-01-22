const std = @import("std");

pub const GlobalState = struct {
    gpa: *std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,
    routes: std.StringHashMap(i32),

    pub fn init() !GlobalState {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        const routes = std.StringHashMap(i32).init(allocator);

        return GlobalState{
            .gpa = gpa,
            .allocator = allocator,
            .routes = routes,
        };
    }

    pub fn deinit(self: *GlobalState) void {
        self.routes.deinit();
        _ = self.gpa.deinit();
    }
};
