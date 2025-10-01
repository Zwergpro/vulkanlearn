const std = @import("std");

const c = @import("./clibs.zig");
const glfw = @import("glfw");
const vk_instance = @import("./instance.zig");
const checkVk = @import("./errors.zig").checkVk;

pub const Surface = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    handle: c.vk.SurfaceKHR = null,
    instance: *vk_instance.Instance,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    pub fn init(alloc: std.mem.Allocator, instance: *vk_instance.Instance, window: *glfw.Window, alloc_cbs: ?*c.vk.AllocationCallbacks) !Self {
        const glfw_alloc: ?*const glfw.VkAllocationCallbacks = if (alloc_cbs) |p| @ptrCast(p) else null;

        var glfw_surface: glfw.VkSurfaceKHR = 0;
        const res = glfw.createWindowSurface(@intFromPtr(instance.handle.?), window, glfw_alloc, &glfw_surface);
        if (res != glfw.VkResult.success) {
            std.log.err("Surface creating error: {d}", .{res});
            return error.surface_creation_failed;
        }

        // Convert GLFW's handle type to your c.vk type
        const handle: c.vk.SurfaceKHR = @ptrFromInt(glfw_surface);

        return .{
            .alloc = alloc,
            .handle = handle,
            .instance = instance,
            .alloc_cbs = alloc_cbs,
        };
    }

    pub fn create(alloc: std.mem.Allocator, instance: *vk_instance.Instance, window: *glfw.Window, alloc_cbs: ?*c.vk.AllocationCallbacks) !*Self {
        const self = try alloc.create(Surface);
        errdefer alloc.destroy(self);

        self.* = try Surface.init(alloc, instance, window, alloc_cbs);
        return self;
    }

    pub fn deinit(self: *Self) void {
        c.vk.DestroySurfaceKHR(self.instance.handle, self.handle, self.alloc_cbs);
    }

    pub fn destroy(self: *Self) void {
        const allocator = self.alloc;
        self.deinit();
        allocator.destroy(self);
    }
};
