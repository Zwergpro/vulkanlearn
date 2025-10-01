const std = @import("std");
const c = @import("./clibs.zig");
const buildin = @import("builtin");

const glfw = @import("glfw");

const checkVk = @import("./errors.zig").checkVk;
const queues = @import("./queues.zig");
const devices = @import("./devices.zig");
const swapchain = @import("./swapchain.zig");
const vk_surface = @import("./surfaces.zig");

pub const ImageViews = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    handle: std.ArrayList(c.vk.ImageView),
    device: *devices.Device,

    pub fn init(alloc: std.mem.Allocator, device: *devices.Device, swap_chain: *swapchain.SwapChain) !Self {
        const image_views_list = try std.ArrayList(c.vk.ImageView).initCapacity(alloc, swap_chain.images.items.len);
        std.log.info("Swapchain images count: {any}", .{swap_chain.images.items.len});
        std.log.info("ImageView count: {any}", .{image_views_list.items.len});

        for (swap_chain.images.items, 0..) |image, idx| {
            var create_info = std.mem.zeroInit(c.vk.ImageViewCreateInfo, .{
                .sType = c.vk.STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.vk.IMAGE_VIEW_TYPE_2D,
                .format = swap_chain.image_format,
            });

            create_info.components.r = c.vk.COMPONENT_SWIZZLE_IDENTITY;
            create_info.components.g = c.vk.COMPONENT_SWIZZLE_IDENTITY;
            create_info.components.b = c.vk.COMPONENT_SWIZZLE_IDENTITY;
            create_info.components.a = c.vk.COMPONENT_SWIZZLE_IDENTITY;

            create_info.subresourceRange.aspectMask = c.vk.IMAGE_ASPECT_COLOR_BIT;
            create_info.subresourceRange.baseMipLevel = 0;
            create_info.subresourceRange.levelCount = 1;
            create_info.subresourceRange.baseArrayLayer = 0;
            create_info.subresourceRange.layerCount = 1;

            try checkVk(c.vk.CreateImageView(device.handle, &create_info, null, &image_views_list.items[idx]));
        }

        return .{
            .alloc = alloc,
            .handle = image_views_list,
            .device = device,
        };
    }

    pub fn create(alloc: std.mem.Allocator, device: *devices.Device, swap_chain: *swapchain.SwapChain) !*Self {
        const self = try alloc.create(ImageViews);
        errdefer alloc.destroy(self);

        self.* = try ImageViews.init(alloc, device, swap_chain);
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.handle.items) |image| {
            c.vk.DestroyImageView(self.device.handle, image, null);
        }
        self.handle.deinit(self.alloc);
    }

    pub fn destroy(self: *Self) void {
        const allocator = self.alloc;
        self.deinit();
        allocator.destroy(self);
    }
};
