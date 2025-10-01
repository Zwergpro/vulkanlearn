const std = @import("std");
const glfw = @import("glfw");

const inst = @import("vulkan/instance.zig");
const dev = @import("vulkan/devices.zig");
const c = @import("vulkan/clibs.zig");
const queues = @import("vulkan/queues.zig");
const swapchain = @import("vulkan/swapchain.zig");
const surfaces = @import("vulkan/surfaces.zig");
const image_view = @import("vulkan/image_view.zig");

pub const Engine = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,
    instance: *inst.Instance,
    surface: *surfaces.Surface,
    physical_device: *dev.PhysicalDevice,
    device: *dev.Device,
    swap_chain: *swapchain.SwapChain,
    image_views: *image_view.ImageViews,

    pub fn init(alloc: std.mem.Allocator, window: *glfw.Window) !Self {
        const alloc_cbs: ?*c.vk.AllocationCallbacks = null;
        const instance = try createInstance(alloc, alloc_cbs);
        const surface = try surfaces.createSurface(alloc, instance, window, alloc_cbs);
        const physical_device = try dev.pickPhysicalDevice(alloc, instance.handle, surface);
        const device = try dev.Device.create(alloc, physical_device, alloc_cbs);
        const swap_chain = try swapchain.createSwapChain(
            alloc,
            device,
            physical_device,
            surface,
            window,
            alloc_cbs,
        );
        const image_views = try image_view.createImageViews(alloc, device, swap_chain);

        return .{
            .alloc = alloc,
            .alloc_cbs = alloc_cbs,
            .instance = instance,
            .surface = surface,
            .physical_device = physical_device,
            .device = device,
            .swap_chain = swap_chain,
            .image_views = image_views,
        };
    }

    pub fn deinit(self: *Self) void {
        self.image_views.deinit();
        self.alloc.destroy(self.image_views);

        self.swap_chain.deinit();
        self.alloc.destroy(self.swap_chain);

        self.device.destroy();

        self.physical_device.destroy();

        self.surface.deinit();
        self.alloc.destroy(self.surface);

        self.instance.destroy();
    }
};

fn createInstance(alloc: std.mem.Allocator, alloc_cbs: ?*c.vk.AllocationCallbacks) !*inst.Instance {
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

    const instance = try inst.Instance.create(alloc, opts);
    return instance;
}
