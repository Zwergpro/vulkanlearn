const std = @import("std");
const glfw = @import("glfw");

const c = @import("vulkan/clibs.zig");
const engine = @import("engine.zig");

pub const Application = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    window: *glfw.Window,
    engine: engine.Engine,
    vk_alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .alloc = allocator,
            .window = undefined,
            .engine = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.engine.deinit();

        glfw.destroyWindow(self.window);
        glfw.terminate();
    }

    pub fn run(self: *Self) !void {
        try self.initWindow();

        try self.initEngine();

        try self.mainLoop();
    }

    fn initEngine(self: *Self) !void {
        self.engine = try engine.Engine.init(self.alloc, self.window);
    }

    fn mainLoop(self: *Self) !void {
        while (!glfw.windowShouldClose(self.window)) {
            if (glfw.getKey(self.window, glfw.KeyEscape) == glfw.Press) {
                glfw.setWindowShouldClose(self.window, true);
            }

            glfw.pollEvents();
        }
    }

    fn initWindow(self: *Self) !void {
        var major: i32 = 0;
        var minor: i32 = 0;
        var rev: i32 = 0;

        glfw.getVersion(&major, &minor, &rev);
        std.debug.print("GLFW {}.{}.{}\n", .{ major, minor, rev });

        try glfw.init();
        std.debug.print("GLFW Init Succeeded.\n", .{});

        glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);
        glfw.windowHint(glfw.Resizable, 0);

        self.window = try glfw.createWindow(800, 640, "App", null, null);
    }
};
