const std = @import("std");
const c = @import("clibs.zig");

const checkVk = @import("errors.zig").checkVk;

pub fn pickPhysicalDevice(alloc: std.mem.Allocator, instance: c.vk.Instance) !c.vk.PhysicalDevice {
    var device_count: u32 = 0;
    try checkVk(c.vk.EnumeratePhysicalDevices(instance, &device_count, null));

    if (device_count == 0) {
        std.log.err("Failed to find GPUs with Vulkan support!", .{});
        return error.physical_device_not_found;
    }

    const physical_devices = try alloc.alloc(c.vk.PhysicalDevice, device_count);
    defer alloc.free(physical_devices);

    try checkVk(c.vk.EnumeratePhysicalDevices(instance, &device_count, physical_devices.ptr));

    var selected_physical_device: c.vk.PhysicalDevice = null;
    for (physical_devices) |device| {
        if (isDeviceSuitable(device)) {
            selected_physical_device = device;
            break;
        }
    }

    if (selected_physical_device == null) {
        std.log.err("Failed to find a suitable GPU!", .{});
        return error.physical_device_not_found;
    }

    return selected_physical_device;
}

fn isDeviceSuitable(device: c.vk.PhysicalDevice) bool {
    var device_pros: c.vk.PhysicalDeviceProperties = undefined;
    var device_features: c.vk.PhysicalDeviceFeatures = undefined;

    c.vk.GetPhysicalDeviceProperties(device, &device_pros);
    c.vk.GetPhysicalDeviceFeatures(device, &device_features);

    // Add support for VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
    const device_type = switch (device_pros.deviceType) {
        c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        c.vk.PHYSICAL_DEVICE_TYPE_CPU => "PHYSICAL_DEVICE_TYPE_DISCRETE_GPU",
        else => "PHYSICAL_DEVICE_TYPE_OTHER",
    };

    std.log.info("Physical device {s} type:{s}", .{ device_pros.deviceName, device_type });
    return device_pros.deviceType == c.vk.PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
}
