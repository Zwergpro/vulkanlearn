const std = @import("std");

const c = @import("./clibs.zig");
const glfw = @import("glfw");
const vk_instance = @import("./instance.zig");
const checkVk = @import("./errors.zig").checkVk;

pub const Surface = struct {
    const Self = @This();

    handle: c.vk.SurfaceKHR = null,
    instance: *vk_instance.Instance,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    pub fn deinit(self: Self) void {
        c.vk.DestroySurfaceKHR(self.instance.handle, self.handle, self.alloc_cbs);
    }
};

pub fn createSurface(alloc: std.mem.Allocator, instance: *vk_instance.Instance, window: *glfw.Window, alloc_cbs: ?*c.vk.AllocationCallbacks) !*Surface {
    var surface = try alloc.create(Surface);
    surface.* = Surface{ .alloc_cbs = alloc_cbs, .instance = instance };

    const glfw_alloc: ?*const glfw.VkAllocationCallbacks = if (alloc_cbs) |p| @ptrCast(p) else null;

    var glfw_surface: glfw.VkSurfaceKHR = 0;
    const res = glfw.createWindowSurface(@intFromPtr(instance.handle.?), window, glfw_alloc, &glfw_surface);
    if (res != glfw.VkResult.success) {
        std.log.err("Surface creating error: {d}", .{res});
        return error.surface_creation_failed;
    }

    // Convert GLFW's handle type to your c.vk type
    surface.handle = @ptrFromInt(glfw_surface);

    return surface;
}
