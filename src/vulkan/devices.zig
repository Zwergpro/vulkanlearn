const std = @import("std");
const c = @import("./clibs.zig");

const checkVk = @import("./errors.zig").checkVk;
const queues = @import("./queues.zig");

pub const PhysicalDevice = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    handle: c.vk.PhysicalDevice = null,
    properties: c.vk.PhysicalDeviceProperties = undefined,
    features: c.vk.PhysicalDeviceFeatures = undefined,
    extensions: []c.vk.ExtensionProperties = undefined,

    pub fn deinit(self: Self) void {
        self.alloc.free(self.extensions);
    }
};

pub fn pickPhysicalDevice(alloc: std.mem.Allocator, instance: c.vk.Instance) !PhysicalDevice {
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
        const physical_device = try createPhysicalDevice(alloc, device);
        if (try isDeviceSuitable(alloc, physical_device)) {
            return physical_device;
        }
    }

    std.log.err("Failed to find a suitable GPU!", .{});
    return error.physical_device_not_found;
}

fn createPhysicalDevice(alloc: std.mem.Allocator, device: c.vk.PhysicalDevice) !PhysicalDevice {
    var physical_device = PhysicalDevice{
        .alloc = alloc,
        .handle = device,
    };
    c.vk.GetPhysicalDeviceProperties(device, &physical_device.properties);
    c.vk.GetPhysicalDeviceFeatures(device, &physical_device.features);

    var properties_count: u32 = 0;
    try checkVk(c.vk.EnumerateDeviceExtensionProperties(physical_device.handle, null, &properties_count, null));

    physical_device.extensions = try alloc.alloc(c.vk.ExtensionProperties, properties_count);

    try checkVk(c.vk.EnumerateDeviceExtensionProperties(physical_device.handle, null, &properties_count, physical_device.extensions.ptr));

    return physical_device;
}

fn isDeviceSuitable(alloc: std.mem.Allocator, device: PhysicalDevice) !bool {
    // Add support for VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    const device_type = switch (device.properties.deviceType) {
        c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_CPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        else => "PHYSICAL_DEVICE_TYPE_OTHER",
    };

    std.log.info("Physical device {s} type:{s}", .{ device.properties.deviceName, device_type });

    var indices = try queues.findQueueFamilies(alloc, device.handle);

    return device.properties.deviceType == c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU and indices.isComplete();
}

pub const Device = struct {
    const Self = @This();

    handle: c.vk.Device = null,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,
    graphics_queue: c.vk.Queue = null,
    // present_queue: c.vk.Queue = null,
    // compute_queue: c.vk.Queue = null,
    // transfer_queue: c.vk.Queue = null,

    pub fn deinit(self: Self) void {
        c.vk.DestroyDevice(self.handle, self.alloc_cbs);
    }
};

pub fn createLogicalDevice(alloc: std.mem.Allocator, physical_device: *PhysicalDevice, queue_indices: *queues.QueueFamilyIndices, alloc_cbs: ?*c.vk.AllocationCallbacks) !Device {
    var queue_priority: f32 = 1.0;
    var queue_create_info = std.mem.zeroInit(c.vk.DeviceQueueCreateInfo, .{
        .sType = c.vk.STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_indices.graphic_family.?,
        .pQueuePriorities = &queue_priority,
        .queueCount = 1,
    });

    var enabled_extensions = std.ArrayListUnmanaged([*]const u8){};
    defer enabled_extensions.deinit(alloc);

    // VK_KHR_portability_subset must be enabled because physical device VkPhysicalDevice supports it
    const VK_KHR_portability_subset: [*c]const u8 = "VK_KHR_portability_subset";
    for (physical_device.extensions) |ext| {
        const ext_name: [*c]const u8 = @ptrCast(ext.extensionName[0..]);
        if (std.mem.eql(u8, std.mem.span(ext_name), std.mem.span(VK_KHR_portability_subset))) {
            try enabled_extensions.append(alloc, VK_KHR_portability_subset);
        }
    }

    var create_info = std.mem.zeroInit(c.vk.DeviceCreateInfo, .{
        .sType = c.vk.STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = &physical_device.features,
        .enabledExtensionCount = @as(u32, @intCast(enabled_extensions.items.len)),
        .ppEnabledExtensionNames = enabled_extensions.items.ptr,
        .enabledLayerCount = 0,
    });

    var device: c.vk.Device = null;
    try checkVk(c.vk.CreateDevice(physical_device.handle, &create_info, alloc_cbs, &device));

    var graphics_queue: c.vk.Queue = null;
    c.vk.GetDeviceQueue(device, queue_indices.graphic_family.?, 0, &graphics_queue);

    return .{
        .handle = device,
        .alloc_cbs = alloc_cbs,
        .graphics_queue = graphics_queue,
    };
}
