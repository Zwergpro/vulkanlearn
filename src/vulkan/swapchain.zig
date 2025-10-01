const std = @import("std");
const c = @import("./clibs.zig");
const buildin = @import("builtin");

const glfw = @import("glfw");

const checkVk = @import("./errors.zig").checkVk;
const queues = @import("./queues.zig");
const devices = @import("./devices.zig");
const vk_surface = @import("./surfaces.zig");

// Represents a Vulkan swapchain with associated images and configuration
pub const SwapChain = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    handle: c.vk.SwapchainKHR,
    images: std.ArrayList(c.vk.Image),
    device: *devices.Device,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    image_format: c.vk.Format,
    extent: c.vk.Extent2D,

    pub fn deinit(self: *Self) void {
        self.images.deinit(self.alloc);
        c.vk.DestroySwapchainKHR(self.device.handle, self.handle, self.alloc_cbs);
    }
};

pub fn createSwapChain(
    alloc: std.mem.Allocator,
    device: *devices.Device,
    physical_device: *devices.PhysicalDevice,
    surface: *vk_surface.Surface,
    window: *glfw.Window,
    alloc_cbs: ?*c.vk.AllocationCallbacks,
) !*SwapChain {
    // Query swapchain support details from the physical device
    var swap_chain_support = try SwapchainSupportInfo.init(alloc, physical_device, surface);
    defer swap_chain_support.deinit();

    // Select the best configuration options for the swapchain
    const surface_format = chooseSwapSurfaceFormat(&swap_chain_support);
    const present_mode = chooseSwapPresentMode(&swap_chain_support);
    const extent = chooseSwapExtent(&swap_chain_support, window);
    const image_count = calculateSwapChainImageCount(&swap_chain_support.capabilities);

    const create_info = createSwapChainCreateInfo(
        &swap_chain_support,
        surface,
        surface_format,
        present_mode,
        extent,
        image_count,
        physical_device,
    );

    var swap_chain_handle: c.vk.SwapchainKHR = undefined;
    try checkVk(c.vk.CreateSwapchainKHR(device.handle, &create_info, alloc_cbs, &swap_chain_handle));

    // Retrieve the images created by the swapchain
    const swap_chain_images = try retrieveSwapChainImages(alloc, device.handle, swap_chain_handle);

    const swap_chain_ptr = try alloc.create(SwapChain);
    swap_chain_ptr.* = .{
        .alloc = alloc,
        .handle = swap_chain_handle,
        .images = swap_chain_images,
        .device = device,
        .alloc_cbs = alloc_cbs,
        .image_format = surface_format.format,
        .extent = extent,
    };

    return swap_chain_ptr;
}

// Information about swapchain support capabilities for a physical device
pub const SwapchainSupportInfo = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    // Basic surface capabilities (image count, dimensions, etc.)
    capabilities: c.vk.SurfaceCapabilitiesKHR = undefined,
    // Available surface formats (pixel format and color space)
    formats: []c.vk.SurfaceFormatKHR = &.{},
    // Available presentation modes (FIFO, mailbox, etc.)
    present_modes: []c.vk.PresentModeKHR = &.{},

    pub fn init(alloc: std.mem.Allocator, device: *devices.PhysicalDevice, surface: *vk_surface.Surface) !Self {
        // Query surface capabilities
        var capabilities: c.vk.SurfaceCapabilitiesKHR = undefined;
        try checkVk(c.vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device.handle, surface.handle, &capabilities));

        // Query available surface formats
        var format_count: u32 = undefined;
        try checkVk(c.vk.GetPhysicalDeviceSurfaceFormatsKHR(device.handle, surface.handle, &format_count, null));
        const formats = try alloc.alloc(c.vk.SurfaceFormatKHR, format_count);
        try checkVk(c.vk.GetPhysicalDeviceSurfaceFormatsKHR(device.handle, surface.handle, &format_count, formats.ptr));

        // Query available present modes
        var present_mode_count: u32 = undefined;
        try checkVk(c.vk.GetPhysicalDeviceSurfacePresentModesKHR(device.handle, surface.handle, &present_mode_count, null));
        const present_modes = try alloc.alloc(c.vk.PresentModeKHR, present_mode_count);
        try checkVk(c.vk.GetPhysicalDeviceSurfacePresentModesKHR(device.handle, surface.handle, &present_mode_count, present_modes.ptr));

        return .{
            .alloc = alloc,
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }

    pub fn deinit(self: Self) void {
        self.alloc.free(self.formats);
        self.alloc.free(self.present_modes);
    }
};

// Selects the optimal surface format for the swapchain
// Prefers BGRA8_SRGB format with SRGB_NONLINEAR color space
// Falls back to the first available format if preferred format is not available
fn chooseSwapSurfaceFormat(swap_chain_support: *SwapchainSupportInfo) c.vk.SurfaceFormatKHR {
    for (swap_chain_support.formats) |format| {
        if (format.format == c.vk.FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.vk.COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return format;
        }
    }
    return swap_chain_support.formats[0];
}

// Selects the optimal present mode for the swapchain
// Prefers MAILBOX mode (triple buffering) for lower latency
// Falls back to FIFO mode (guaranteed to be available) if MAILBOX is not supported
fn chooseSwapPresentMode(swap_chain_support: *SwapchainSupportInfo) c.vk.PresentModeKHR {
    for (swap_chain_support.present_modes) |mod| {
        if (mod == c.vk.PRESENT_MODE_MAILBOX_KHR) {
            return mod;
        }
    }
    return c.vk.PRESENT_MODE_FIFO_KHR;
}

// Determines the resolution of the swapchain images
// Uses the current extent if it's set, otherwise queries the window size
// and clamps it within the supported min/max extent range
fn chooseSwapExtent(swap_chain_support: *SwapchainSupportInfo, window: *glfw.Window) c.vk.Extent2D {
    // If currentExtent is not maxInt(u32), it's already set by the platform
    if (swap_chain_support.capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return swap_chain_support.capabilities.currentExtent;
    }

    // Query the actual framebuffer size from the window
    var width_ci: c_int = 0;
    var height_ci: c_int = 0;
    glfw.getFramebufferSize(window, &width_ci, &height_ci);

    var extent = c.vk.Extent2D{
        .width = @as(u32, @intCast(width_ci)),
        .height = @as(u32, @intCast(height_ci)),
    };

    extent.width = @max(swap_chain_support.capabilities.minImageExtent.width, @min(swap_chain_support.capabilities.maxImageExtent.width, extent.width));
    extent.height = @max(swap_chain_support.capabilities.minImageExtent.height, @min(swap_chain_support.capabilities.maxImageExtent.height, extent.height));

    return extent;
}

// Calculates the optimal number of images in the swapchain
// Requests minImageCount + 1 for better performance, but respects maxImageCount
fn calculateSwapChainImageCount(capabilities: *const c.vk.SurfaceCapabilitiesKHR) u32 {
    var image_count = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 and image_count > capabilities.maxImageCount) {
        image_count = capabilities.maxImageCount;
    }
    return image_count;
}

// Constructs the SwapchainCreateInfoKHR structure with all necessary parameters
// Handles queue family index configuration for concurrent vs exclusive sharing modes
fn createSwapChainCreateInfo(
    swap_chain_support: *SwapchainSupportInfo,
    surface: *vk_surface.Surface,
    surface_format: c.vk.SurfaceFormatKHR,
    present_mode: c.vk.PresentModeKHR,
    extent: c.vk.Extent2D,
    image_count: u32,
    physical_device: *devices.PhysicalDevice,
) c.vk.SwapchainCreateInfoKHR {
    var create_info = std.mem.zeroInit(c.vk.SwapchainCreateInfoKHR, .{
        .sType = c.vk.STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface.handle,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1, // Always 1 unless stereoscopic 3D
        .imageUsage = c.vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = swap_chain_support.capabilities.currentTransform,
        .compositeAlpha = c.vk.COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.vk.TRUE, // Don't care about obscured pixels
        .oldSwapchain = null,
    });

    // Configure queue family sharing mode
    const queue_family_indices = [_]u32{
        physical_device.queue_indices.graphic_family.?,
        physical_device.queue_indices.present_family.?,
    };
    if (physical_device.queue_indices.graphic_family != physical_device.queue_indices.present_family) {
        // Graphics and present queues are in different families - use concurrent mode
        create_info.imageSharingMode = c.vk.SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = 2;
        create_info.pQueueFamilyIndices = &queue_family_indices;
    } else {
        // Graphics and present queues are in the same family - use exclusive mode
        create_info.imageSharingMode = c.vk.SHARING_MODE_EXCLUSIVE;
        create_info.queueFamilyIndexCount = 0;
        create_info.pQueueFamilyIndices = null;
    }

    return create_info;
}

// Retrieves the list of images created by the swapchain
// These images will be rendered to and presented to the screen
fn retrieveSwapChainImages(alloc: std.mem.Allocator, device_handle: c.vk.Device, swap_chain_handle: c.vk.SwapchainKHR) !std.ArrayList(c.vk.Image) {
    // Query the number of swapchain images
    var swapchain_image_count: u32 = 0;
    try checkVk(c.vk.GetSwapchainImagesKHR(device_handle, swap_chain_handle, &swapchain_image_count, null));

    const swap_chain_images = try std.ArrayList(c.vk.Image).initCapacity(alloc, swapchain_image_count);

    try checkVk(c.vk.GetSwapchainImagesKHR(device_handle, swap_chain_handle, &swapchain_image_count, swap_chain_images.items.ptr));

    return swap_chain_images;
}
