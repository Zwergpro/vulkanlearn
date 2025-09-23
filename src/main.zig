const std = @import("std");
const app = @import("app.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    const allocator = gpa.allocator();

    var main_app = try allocator.create(app.Application);
    defer allocator.destroy(main_app);

    main_app.* = app.Application.init(allocator);
    defer main_app.deinit();

    try main_app.run();
}
