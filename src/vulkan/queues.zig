const c = @import("./clibs.zig");
const std = @import("std");
const checkVk = @import("./errors.zig").checkVk;
const vk_surface = @import("./surfaces.zig");

pub const QueueFamilyIndices = struct {
    const Self = @This();

    graphic_family: ?u32 = null,
    present_family: ?u32 = null,

    pub fn isComplete(self: *Self) bool {
        return self.graphic_family != null and self.present_family != null;
    }
};

pub fn findQueueFamilies(alloc: std.mem.Allocator, device: c.vk.PhysicalDevice, surface: *vk_surface.Surface) !QueueFamilyIndices {
    var indices = QueueFamilyIndices{};

    var queue_family_count: u32 = 0;
    c.vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try alloc.alloc(c.vk.QueueFamilyProperties, queue_family_count);
    defer alloc.free(queue_families);

    c.vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    var i: u32 = 0;
    for (queue_families) |q_family| {
        if (q_family.queueFlags & c.vk.QUEUE_GRAPHICS_BIT == c.vk.QUEUE_GRAPHICS_BIT) {
            indices.graphic_family = i;
        }

        var present_support: c.vk.Bool32 = 0;
        try checkVk(c.vk.GetPhysicalDeviceSurfaceSupportKHR(device, i, surface.handle, &present_support));

        if (present_support != c.vk.FALSE) {
            indices.present_family = i;
        }

        i += 1;
    }

    return indices;
}
