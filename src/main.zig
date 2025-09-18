const std = @import("std");
const c = @import("clibs.zig");

const glfw = @import("glfw");

const vulkan_init = @import("vulkan_init.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    var major: i32 = 0;
    var minor: i32 = 0;
    var rev: i32 = 0;

    glfw.getVersion(&major, &minor, &rev);
    std.debug.print("GLFW {}.{}.{}\n", .{ major, minor, rev });

    const allocator = gpa.allocator();

    const required_extensions = [_][*]const u8{
        c.vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME, // only required for Vulkan version 1.0.
        c.vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };

    const vk_alloc_cbs: ?*c.vk.AllocationCallbacks = null;
    const instance = try vulkan_init.create_instance(allocator, .{
        .application_name = "VkGuide",
        .application_version = c.vk.MAKE_VERSION(0, 1, 0),
        .engine_name = "VkGuide",
        .engine_version = c.vk.MAKE_VERSION(0, 1, 0),
        .api_version = c.vk.MAKE_VERSION(1, 1, 0),
        .debug = true,
        .alloc_cb = vk_alloc_cbs,
        .required_extensions = &required_extensions,
    });

    c.vk.DestroyInstance(instance.handle, vk_alloc_cbs);
}
