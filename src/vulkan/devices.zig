const std = @import("std");
const c = @import("./clibs.zig");
const buildin = @import("builtin");

const checkVk = @import("./errors.zig").checkVk;
const queues = @import("./queues.zig");
const vk_surface = @import("./surfaces.zig");

pub const PhysicalDevice = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    handle: c.vk.PhysicalDevice = null,
    properties: c.vk.PhysicalDeviceProperties = undefined,
    features: c.vk.PhysicalDeviceFeatures = undefined,
    extensions: []c.vk.ExtensionProperties = undefined,
    queue_indices: *queues.QueueFamilyIndices = undefined,

    pub fn deinit(self: Self) void {
        self.alloc.destroy(self.queue_indices);
        self.alloc.free(self.extensions);
    }
};

pub fn pickPhysicalDevice(alloc: std.mem.Allocator, instance: c.vk.Instance, surface: *vk_surface.Surface) !PhysicalDevice {
    var device_count: u32 = 0;
    try checkVk(c.vk.EnumeratePhysicalDevices(instance, &device_count, null));

    if (device_count == 0) {
        std.log.err("Failed to find GPUs with Vulkan support!", .{});
        return error.physical_device_not_found;
    }

    const physical_devices = try alloc.alloc(c.vk.PhysicalDevice, device_count);
    defer alloc.free(physical_devices);

    try checkVk(c.vk.EnumeratePhysicalDevices(instance, &device_count, physical_devices.ptr));

    for (physical_devices) |device| {
        var physical_device = try createPhysicalDevice(alloc, device, surface);
        if (try isDeviceSuitable(alloc, &physical_device, surface)) {
            return physical_device;
        }
        // Not suitable; free resources before checking next device
        physical_device.deinit();
    }

    std.log.err("Failed to find a suitable GPU!", .{});
    return error.physical_device_not_found;
}

fn createPhysicalDevice(alloc: std.mem.Allocator, device: c.vk.PhysicalDevice, surface: *vk_surface.Surface) !PhysicalDevice {
    var physical_device = PhysicalDevice{
        .alloc = alloc,
        .handle = device,
    };
    c.vk.GetPhysicalDeviceProperties(device, &physical_device.properties);
    c.vk.GetPhysicalDeviceFeatures(device, &physical_device.features);

    var extension_count: u32 = 0;
    try checkVk(c.vk.EnumerateDeviceExtensionProperties(physical_device.handle, null, &extension_count, null));

    physical_device.extensions = try alloc.alloc(c.vk.ExtensionProperties, extension_count);

    try checkVk(c.vk.EnumerateDeviceExtensionProperties(physical_device.handle, null, &extension_count, physical_device.extensions.ptr));

    physical_device.queue_indices = try alloc.create(queues.QueueFamilyIndices);
    physical_device.queue_indices.* = try queues.findQueueFamilies(alloc, device, surface);

    switch (buildin.os.tag) {
        // Do not enable any optional features by default; Metal doesn't support robust buffer access
        .ios, .macos, .tvos, .watchos => {
            physical_device.features.robustBufferAccess = c.vk.FALSE;
        },
        else => {},
    }

    return physical_device;
}

fn isDeviceSuitable(alloc: std.mem.Allocator, device: *PhysicalDevice, surface: *vk_surface.Surface) !bool {
    // Accept both integrated and discrete GPUs; log accurate type
    const device_type = switch (device.properties.deviceType) {
        c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_CPU => "PHYSICAL_DEVICE_TYPE_CPU",
        else => "PHYSICAL_DEVICE_TYPE_OTHER",
    };

    std.log.info("Physical device {s} type:{s}", .{ device.properties.deviceName, device_type });

    const is_preferred_type = (device.properties.deviceType == c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU or
        device.properties.deviceType == c.vk.PHYSICAL_DEVICE_TYPE_DISCRETE_GPU);
    const is_extensionn_supported = try checkDeviceExtensionSupport(device);

    var swap_chain_adequate = false;
    if (is_extensionn_supported) {
        var swap_chain_support = try SwapchainSupportInfo.init(alloc, device, surface);
        defer swap_chain_support.deinit();

        swap_chain_adequate = swap_chain_support.formats.len > 0 and swap_chain_support.present_modes.len > 0;
    }

    return (is_preferred_type and device.queue_indices.isComplete() and is_extensionn_supported and swap_chain_adequate);
}

fn checkDeviceExtensionSupport(device: *PhysicalDevice) !bool {
    const required_extensions = [_][*c]const u8{
        "VK_KHR_swapchain",
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

        if (!is_found) {
            std.log.err("Device extension not found: {s}", .{req_ext});
            return false;
        }
    }

    return true;
}

pub const Device = struct {
    const Self = @This();

    handle: c.vk.Device = null,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,
    graphics_queue: c.vk.Queue = null,
    present_queue: c.vk.Queue = null,
    // compute_queue: c.vk.Queue = null,
    // transfer_queue: c.vk.Queue = null,

    pub fn deinit(self: Self) void {
        c.vk.DestroyDevice(self.handle, self.alloc_cbs);
    }
};

pub fn createLogicalDevice(
    alloc: std.mem.Allocator,
    physical_device: *PhysicalDevice,
    alloc_cbs: ?*c.vk.AllocationCallbacks,
) !Device {
    // Collect unique queue families
    var unique_queue_families = std.AutoHashMap(u32, void).init(alloc);
    defer unique_queue_families.deinit();

    try unique_queue_families.put(physical_device.queue_indices.graphic_family.?, {});
    try unique_queue_families.put(physical_device.queue_indices.present_family.?, {});

    // Build queue create infos
    var queue_create_infos = std.ArrayList(c.vk.DeviceQueueCreateInfo){};
    defer queue_create_infos.deinit(alloc);

    const queue_priority: f32 = 1.0;

    var it = unique_queue_families.keyIterator();
    while (it.next()) |family_idx_ptr| {
        const info = std.mem.zeroInit(c.vk.DeviceQueueCreateInfo, .{
            .sType = c.vk.STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = family_idx_ptr.*,
            .pQueuePriorities = &queue_priority,
            .queueCount = 1,
        });
        try queue_create_infos.append(alloc, info);
    }

    // Enable required extensions (e.g., VK_KHR_portability_subset if supported)
    var enabled_extensions = std.ArrayList([*]const u8){};
    defer enabled_extensions.deinit(alloc);

    // TODO: refactor
    try enabled_extensions.append(alloc, "VK_KHR_swapchain"); // we checked supports previously

    const portability_ext_name: [*c]const u8 = "VK_KHR_portability_subset";
    for (physical_device.extensions) |ext| {
        const ext_name: [*c]const u8 = @ptrCast(ext.extensionName[0..]);
        if (std.mem.eql(u8, std.mem.span(ext_name), std.mem.span(portability_ext_name))) {
            // Append the zero-terminated name coming from Vulkan props
            try enabled_extensions.append(alloc, ext_name);
            break; // only need to add once
        }
    }

    var create_info = std.mem.zeroInit(c.vk.DeviceCreateInfo, .{
        .sType = c.vk.STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.items.len)),
        .pEnabledFeatures = &physical_device.features,
        .enabledExtensionCount = @as(u32, @intCast(enabled_extensions.items.len)),
        .ppEnabledExtensionNames = enabled_extensions.items.ptr,
        .enabledLayerCount = 0,
    });

    var device: c.vk.Device = null;
    try checkVk(c.vk.CreateDevice(physical_device.handle, &create_info, alloc_cbs, &device));

    var graphics_queue: c.vk.Queue = null;
    c.vk.GetDeviceQueue(device, physical_device.queue_indices.graphic_family.?, 0, &graphics_queue);

    var present_queue: c.vk.Queue = null;
    c.vk.GetDeviceQueue(device, physical_device.queue_indices.present_family.?, 0, &present_queue);

    return .{
        .handle = device,
        .alloc_cbs = alloc_cbs,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
    };
}

const SwapchainSupportInfo = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    capabilities: c.vk.SurfaceCapabilitiesKHR = undefined,
    formats: []c.vk.SurfaceFormatKHR = &.{},
    present_modes: []c.vk.PresentModeKHR = &.{},

    fn init(alloc: std.mem.Allocator, device: *PhysicalDevice, surface: *vk_surface.Surface) !Self {
        var capabilities: c.vk.SurfaceCapabilitiesKHR = undefined;
        try checkVk(c.vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device.handle, surface.handle, &capabilities));

        var format_count: u32 = undefined;
        try checkVk(c.vk.GetPhysicalDeviceSurfaceFormatsKHR(device.handle, surface.handle, &format_count, null));
        const formats = try alloc.alloc(c.vk.SurfaceFormatKHR, format_count);
        try checkVk(c.vk.GetPhysicalDeviceSurfaceFormatsKHR(device.handle, surface.handle, &format_count, formats.ptr));

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

    fn deinit(self: Self) void {
        self.alloc.free(self.formats);
        self.alloc.free(self.present_modes);
    }
};
