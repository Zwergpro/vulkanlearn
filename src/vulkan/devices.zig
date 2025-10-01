//! Vulkan Device Management Module
//!
//! This module handles both physical and logical Vulkan device management:
//! - Physical device enumeration and selection based on capabilities
//! - Extension support verification
//! - Queue family configuration
//! - Logical device creation with appropriate queues and extensions

const std = @import("std");
const c = @import("./clibs.zig");
const builtin = @import("builtin");

const glfw = @import("glfw");

const checkVk = @import("./errors.zig").checkVk;
const queues = @import("./queues.zig");
const swapchain = @import("./swapchain.zig");
const vk_surface = @import("./surfaces.zig");

/// Represents a physical GPU device with its properties and capabilities.
/// This struct wraps a Vulkan physical device handle and caches information
/// about the device's properties, features, supported extensions, and available queue families.
pub const PhysicalDevice = struct {
    const Self = @This();

    /// Allocator used for dynamic memory allocation
    alloc: std.mem.Allocator,

    /// Vulkan physical device handle
    handle: c.vk.PhysicalDevice = null,

    /// Device properties (name, type, limits, etc.)
    properties: c.vk.PhysicalDeviceProperties = undefined,

    /// Device features (geometry shaders, tessellation, etc.)
    features: c.vk.PhysicalDeviceFeatures = undefined,

    /// List of extensions supported by this device
    extensions: []c.vk.ExtensionProperties = undefined,

    /// Queue family indices (graphics, present, compute, transfer)
    queue_indices: *queues.QueueFamilyIndices = undefined,

    /// Initialize a PhysicalDevice by querying its properties, features, extensions, and queue families.
    pub fn init(alloc: std.mem.Allocator, device: c.vk.PhysicalDevice, surface: *vk_surface.Surface) !Self {
        var physical_device = PhysicalDevice{
            .alloc = alloc,
            .handle = device,
        };

        // Query device properties (name, vendor, device type, limits)
        c.vk.GetPhysicalDeviceProperties(device, &physical_device.properties);

        // Query device features (supported capabilities like geometry shaders, tessellation)
        c.vk.GetPhysicalDeviceFeatures(device, &physical_device.features);

        // Enumerate supported extensions - first get count
        var extension_count: u32 = 0;
        try checkVk(c.vk.EnumerateDeviceExtensionProperties(physical_device.handle, null, &extension_count, null));

        // Allocate memory for extensions list
        physical_device.extensions = try alloc.alloc(c.vk.ExtensionProperties, extension_count);

        // Retrieve the actual extension properties
        try checkVk(c.vk.EnumerateDeviceExtensionProperties(physical_device.handle, null, &extension_count, physical_device.extensions.ptr));

        // Find and store queue family indices for graphics and presentation
        physical_device.queue_indices = try alloc.create(queues.QueueFamilyIndices);
        physical_device.queue_indices.* = try queues.findQueueFamilies(alloc, device, surface);

        // Platform-specific adjustments
        switch (builtin.os.tag) {
            // Metal (Apple's graphics API) doesn't support robust buffer access
            // Disable this feature on Apple platforms to ensure compatibility
            .ios, .macos, .tvos, .watchos => {
                physical_device.features.robustBufferAccess = c.vk.FALSE;
            },
            else => {},
        }

        return physical_device;
    }

    /// Create a PhysicalDevice on the heap.
    pub fn create(alloc: std.mem.Allocator, device: c.vk.PhysicalDevice, surface: *vk_surface.Surface) !*Self {
        const self = try alloc.create(PhysicalDevice);
        errdefer alloc.destroy(self);

        self.* = try PhysicalDevice.init(alloc, device, surface);
        return self;
    }

    /// Free dynamically allocated resources (queue_indices and extensions).
    pub fn deinit(self: *Self) void {
        self.alloc.destroy(self.queue_indices);
        self.alloc.free(self.extensions);
    }

    /// Cleanup and free the PhysicalDevice struct itself.
    pub fn destroy(self: *Self) void {
        const allocator = self.alloc;
        self.deinit();
        allocator.destroy(self);
    }
};

/// Enumerate all available physical devices and select the first suitable one.
pub fn pickPhysicalDevice(alloc: std.mem.Allocator, instance: c.vk.Instance, surface: *vk_surface.Surface) !*PhysicalDevice {
    var device_count: u32 = 0;
    try checkVk(c.vk.EnumeratePhysicalDevices(instance, &device_count, null));

    if (device_count == 0) {
        std.log.err("Failed to find GPUs with Vulkan support!", .{});
        return error.physical_device_not_found;
    }

    const physical_devices = try alloc.alloc(c.vk.PhysicalDevice, device_count);
    defer alloc.free(physical_devices);

    try checkVk(c.vk.EnumeratePhysicalDevices(instance, &device_count, physical_devices.ptr));

    // Iterate through devices and select the first suitable one
    for (physical_devices) |device| {
        var physical_device = try PhysicalDevice.create(alloc, device, surface);
        if (try isDeviceSuitable(alloc, physical_device, surface)) {
            return physical_device;
        }
        physical_device.destroy();
    }

    std.log.err("Failed to find a suitable GPU!", .{});
    return error.physical_device_not_found;
}

/// Check if a physical device meets all requirements for our application.
fn isDeviceSuitable(alloc: std.mem.Allocator, device: *PhysicalDevice, surface: *vk_surface.Surface) !bool {
    const device_type = switch (device.properties.deviceType) {
        c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_CPU => "PHYSICAL_DEVICE_TYPE_CPU",
        else => "PHYSICAL_DEVICE_TYPE_OTHER",
    };

    std.log.info("Physical device {s} type:{s}", .{ device.properties.deviceName, device_type });

    // We prefer integrated or discrete GPUs over CPU-based or virtual implementations
    const is_preferred_type = (device.properties.deviceType == c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU or
        device.properties.deviceType == c.vk.PHYSICAL_DEVICE_TYPE_DISCRETE_GPU);

    // Check if all required extensions (like swapchain) are supported
    const is_extension_supported = try checkDeviceExtensionSupport(device);

    // Verify swapchain support only if extensions are available
    var swap_chain_adequate = false;
    if (is_extension_supported) {
        var swap_chain_support = try swapchain.SwapchainSupportInfo.init(alloc, device, surface);
        defer swap_chain_support.deinit();

        // Swapchain is adequate if at least one format and one present mode are available
        swap_chain_adequate = swap_chain_support.formats.len > 0 and swap_chain_support.present_modes.len > 0;
    }

    return (is_preferred_type and device.queue_indices.isComplete() and is_extension_supported and swap_chain_adequate);
}

/// Verify that the physical device supports all required extensions.
///
/// This function checks if the device supports essential extensions like VK_KHR_swapchain,
/// which is required for presenting rendered images to the screen.
fn checkDeviceExtensionSupport(device: *PhysicalDevice) !bool {
    const required_extensions = [_][*c]const u8{
        "VK_KHR_swapchain", // Required for presenting images to the window surface
    };

    for (required_extensions) |req_ext| {
        var is_found = false;

        for (device.extensions) |ext| {
            const ext_name: [*c]const u8 = @ptrCast(ext.extensionName[0..]);
            if (std.mem.eql(u8, std.mem.span(ext_name), std.mem.span(req_ext))) {
                is_found = true;
                break;
            }
        }

        // If any required extension is missing, log error and return false
        if (!is_found) {
            std.log.err("Device extension not found: {s}", .{req_ext});
            return false;
        }
    }

    // All required extensions are supported
    return true;
}

/// Represents a logical Vulkan device with associated queues.
///
/// A logical device is the primary interface for interacting with a physical device.
/// It manages queues for submitting commands (graphics, present, compute, transfer).
/// Note: graphics and present queues might reference the same underlying queue family.
pub const Device = struct {
    const Self = @This();

    /// Allocator used for dynamic memory allocation
    alloc: std.mem.Allocator,

    /// Vulkan logical device handle
    handle: c.vk.Device,

    /// Optional allocation callbacks for Vulkan API calls
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    /// Queue for graphics operations (rendering, compute, etc.)
    graphics_queue: c.vk.Queue = null,

    /// Queue for presenting rendered images to the window surface
    present_queue: c.vk.Queue = null,

    // Future extension: additional specialized queues
    // compute_queue: c.vk.Queue = null,
    // transfer_queue: c.vk.Queue = null,

    /// Initialize a logical device from a physical device.
    /// Note on extensions:
    /// - VK_KHR_swapchain: Always required for rendering to window
    /// - VK_KHR_portability_subset: Required on macOS/MoltenVK (Vulkan over Metal)
    pub fn init(
        alloc: std.mem.Allocator,
        physical_device: *PhysicalDevice,
        alloc_cbs: ?*c.vk.AllocationCallbacks,
    ) !Self {
        // Step 1: Collect unique queue families
        // Graphics and present families might be the same, so we use a hash map to deduplicate.
        // The hash map key is the family index, value is void (we only care about uniqueness).
        var unique_queue_families = std.AutoHashMap(u32, void).init(alloc);
        defer unique_queue_families.deinit();

        try unique_queue_families.put(physical_device.queue_indices.graphic_family.?, {});
        try unique_queue_families.put(physical_device.queue_indices.present_family.?, {});

        // Step 2: Build queue create info structures
        // We create one queue from each unique family with maximum priority (1.0).
        var queue_create_infos = std.ArrayList(c.vk.DeviceQueueCreateInfo){};
        defer queue_create_infos.deinit(alloc);

        const queue_priority: f32 = 1.0; // Maximum priority for our queue

        var it = unique_queue_families.keyIterator();
        while (it.next()) |family_idx_ptr| {
            const info = std.mem.zeroInit(c.vk.DeviceQueueCreateInfo, .{
                .sType = c.vk.STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = family_idx_ptr.*,
                .pQueuePriorities = &queue_priority,
                .queueCount = 1, // Create one queue from this family
            });
            try queue_create_infos.append(alloc, info);
        }

        // Step 3: Prepare list of required extensions
        var enabled_extensions = std.ArrayList([*]const u8){};
        defer enabled_extensions.deinit(alloc);

        // Swapchain extension is mandatory and was verified during device selection
        try enabled_extensions.append(alloc, "VK_KHR_swapchain");

        // Check if VK_KHR_portability_subset is supported and enable it if available.
        // This extension is REQUIRED on macOS when using MoltenVK (Vulkan over Metal).
        // Without it, device creation will fail on Apple platforms.
        const portability_ext_name: [*c]const u8 = "VK_KHR_portability_subset";
        for (physical_device.extensions) |ext| {
            const ext_name: [*c]const u8 = @ptrCast(ext.extensionName[0..]);
            if (std.mem.eql(u8, std.mem.span(ext_name), std.mem.span(portability_ext_name))) {
                try enabled_extensions.append(alloc, ext_name);
                break; // Extension found and added, no need to continue searching
            }
        }

        // Step 4: Create the logical device
        var create_info = std.mem.zeroInit(c.vk.DeviceCreateInfo, .{
            .sType = c.vk.STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pQueueCreateInfos = queue_create_infos.items.ptr,
            .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.items.len)),
            .pEnabledFeatures = &physical_device.features,
            .enabledExtensionCount = @as(u32, @intCast(enabled_extensions.items.len)),
            .ppEnabledExtensionNames = enabled_extensions.items.ptr,
            .enabledLayerCount = 0, // Validation layers are enabled at instance level
        });

        var device: c.vk.Device = null;
        try checkVk(c.vk.CreateDevice(physical_device.handle, &create_info, alloc_cbs, &device));

        // Step 5: Retrieve queue handles
        // Get the graphics queue handle (index 0 from the graphics family)
        var graphics_queue: c.vk.Queue = null;
        c.vk.GetDeviceQueue(device, physical_device.queue_indices.graphic_family.?, 0, &graphics_queue);

        // Get the present queue handle (index 0 from the present family)
        // Note: This might be the same queue as graphics_queue if both families are identical
        var present_queue: c.vk.Queue = null;
        c.vk.GetDeviceQueue(device, physical_device.queue_indices.present_family.?, 0, &present_queue);

        return .{
            .alloc = alloc,
            .handle = device,
            .alloc_cbs = alloc_cbs,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
        };
    }

    /// Create a Device on the heap.
    pub fn create(
        alloc: std.mem.Allocator,
        physical_device: *PhysicalDevice,
        alloc_cbs: ?*c.vk.AllocationCallbacks,
    ) !*Self {
        const self = try alloc.create(Device);
        errdefer alloc.destroy(self);

        self.* = try Device.init(alloc, physical_device, alloc_cbs);
        return self;
    }

    /// Destroy the logical device and release all associated Vulkan resources.
    pub fn deinit(self: *Self) void {
        c.vk.DestroyDevice(self.handle, self.alloc_cbs);
    }

    /// Cleanup and free the Device struct itself.
    pub fn destroy(self: *Self) void {
        const allocator = self.alloc;
        self.deinit();
        allocator.destroy(self);
    }
};
