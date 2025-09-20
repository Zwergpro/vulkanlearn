const std = @import("std");
const c = @import("vulkan/clibs.zig");

const checkVk = @import("errors.zig").checkVk;



pub fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: *c.vk.Instance) !c.vk.PhysicalDevice {
    var device_count: u32 = 0;
    try checkVk(c.vk.EnumeratePhysicalDevices(instance.handle, &device_count, null));

    if (device_count == 0) {
        std.log.err("Failed to find GPUs with Vulkan support!", .{});
        return error.physical_device_not_found;
    }

    const physical_devices = try allocator.alloc(c.vk.PhysicalDevice, device_count);
    try checkVk(c.vk.EnumeratePhysicalDevices(instance.handle, &device_count, physical_devices.ptr));

    const physical_device: c.vk.PhysicalDevice = null;
    for (physical_devices) |device| {
        if (isDeviceSuitable(device)) {
            physical_device = device;
            break;
        }
    }

    return physical_devices;
}


fn isDeviceSuitable(device: c.vk.PhysicalDevice) bool {
    return true;
}
