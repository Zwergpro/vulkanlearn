const std = @import("std");

const inst = @import("vulkan/instance.zig");
const c = @import("vulkan/clibs.zig");
const glfw = @import("glfw");


pub const Engine = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,
    instance: inst.Instance,

    pub fn init(alloc: std.mem.Allocator) !Self {
        const alloc_cbs: ?*c.vk.AllocationCallbacks = null;
        const instance = try createInstance(alloc, alloc_cbs);

        return .{
            .alloc = alloc,
            .alloc_cbs = alloc_cbs,
            .instance = instance,
        };
    }
};


fn createInstance(alloc: std.mem.Allocator, alloc_cbs: ?*c.vk.AllocationCallbacks) !inst.Instance {
    const required_extensions = [_][*]const u8{
        c.vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME, // For macOS
        };

    var glfw_extension_count: u32 = 0;
    var glfw_extensions = glfw.getRequiredInstanceExtensions(&glfw_extension_count).?;

    const all_exts = try alloc.alloc([*]const u8, glfw_extension_count + required_extensions.len);
    defer alloc.free(all_exts);

    std.mem.copyForwards([*]const u8, all_exts[0..glfw_extension_count], glfw_extensions[0..glfw_extension_count]);
    std.mem.copyForwards([*]const u8, all_exts[glfw_extension_count..], required_extensions[0..]);

    const opts = inst.VkInstanceOpts{
        .application_name = "VkGuide",
        .application_version = c.vk.MAKE_VERSION(0, 1, 0),
        .engine_name = "VkGuide",
        .engine_version = c.vk.MAKE_VERSION(0, 1, 0),
        .api_version = c.vk.MAKE_VERSION(1, 1, 0),
        .debug = true,
        .alloc_cbs = alloc_cbs,
        .required_extensions = all_exts,
    };
    return try inst.Instance.init(alloc, opts);
}
