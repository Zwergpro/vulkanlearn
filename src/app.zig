const std = @import("std");
const glfw = @import("glfw");
const c = @import("clibs.zig");
const vki = @import("vulkan_init.zig");

pub const Application = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *glfw.Window,
    vk_instance: *vki.Instance,
    vk_alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .window = undefined,
            .vk_instance = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        c.vk.DestroyInstance(self.vk_instance.handle, self.vk_alloc_cbs);
        self.vk_instance.handle = null;
        self.allocator.destroy(self.vk_instance);

        glfw.destroyWindow(self.window);
        glfw.terminate();
    }

    pub fn run(self: *Self) !void {
        try self.initWindow();

        try self.initEngine();

        try self.mainLoop();
    }

    fn initEngine(self: *Self) !void {
        const required_extensions = [_][*]const u8{
            c.vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
        };

        const vk_instance = try self.allocator.create(vki.Instance);
        self.vk_instance = vk_instance;

        vk_instance.* = try vki.create_instance(self.allocator, .{
            .application_name = "VkGuide",
            .application_version = c.vk.MAKE_VERSION(0, 1, 0),
            .engine_name = "VkGuide",
            .engine_version = c.vk.MAKE_VERSION(0, 1, 0),
            .api_version = c.vk.MAKE_VERSION(1, 1, 0),
            .debug = true,
            .alloc_cb = self.vk_alloc_cbs,
            .required_extensions = &required_extensions,
        });
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
