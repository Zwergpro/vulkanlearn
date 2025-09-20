const std = @import("std");

const glfw = @import("glfw");

const c = @import("clibs.zig");

const checkVk = @import("errors.zig").checkVk;

pub const VkInstanceOpts = struct {
    application_name: [:0]const u8 = "vki",
    application_version: u32 = c.vk.MAKE_VERSION(1, 0, 0),
    engine_name: ?[:0]const u8 = null,
    engine_version: u32 = c.vk.MAKE_VERSION(1, 0, 0),
    api_version: u32 = c.vk.MAKE_VERSION(1, 0, 0),
    debug: bool = false,
    debug_callback: c.vk.PFN_DebugUtilsMessengerCallbackEXT = null,
    required_extensions: []const [*c]const u8 = &.{},
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,
};

pub const Instance = struct {
    const Self = @This();

    handle: c.vk.Instance = null,
    debug_messenger: c.vk.DebugUtilsMessengerEXT = null,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    pub fn init(alloc: std.mem.Allocator, opts: VkInstanceOpts) !Self {
        return try create_instance(alloc, opts);
    }

    pub fn deinit(self: *Self) void {
        if (self.debug_messenger != null) {
            const destroy_fn_opt = getVulkanInstanceFunc(
                c.vk.PFN_DestroyDebugUtilsMessengerEXT,
                self.handle,
                "vkDestroyDebugUtilsMessengerEXT",
            );
            if (destroy_fn_opt) |destroy_fn| {
                destroy_fn(self.handle, self.debug_messenger, self.alloc_cbs);
            } else {
                std.log.warn("Can not load vkDestroyDebugUtilsMessengerEXT", .{});
            }
        }

        c.vk.DestroyInstance(self.handle, self.alloc_cbs);
    }
};

fn create_instance(alloc: std.mem.Allocator, opts: VkInstanceOpts) !Instance {
    if (opts.api_version > c.vk.MAKE_VERSION(1, 0, 0)) {
        var api_requested = opts.api_version;
        try checkVk(c.vk.EnumerateInstanceVersion(@ptrCast(&api_requested)));
    }

    var enable_validation = opts.debug;

    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Get supported layers and extensions
    var layer_count: u32 = undefined;
    try checkVk(c.vk.EnumerateInstanceLayerProperties(&layer_count, null));
    const layer_props = try arena.alloc(c.vk.LayerProperties, layer_count);
    try checkVk(c.vk.EnumerateInstanceLayerProperties(&layer_count, layer_props.ptr));

    var extension_count: u32 = undefined;
    try checkVk(c.vk.EnumerateInstanceExtensionProperties(null, &extension_count, null));
    const extension_props = try arena.alloc(c.vk.ExtensionProperties, extension_count);
    try checkVk(c.vk.EnumerateInstanceExtensionProperties(null, &extension_count, extension_props.ptr));

    // Check if the validation layer is supported
    var layers = std.ArrayListUnmanaged([*]const u8){};
    const validation_layer_name: [*c]const u8 = "VK_LAYER_KHRONOS_validation";
    if (enable_validation) {
        enable_validation = blk: for (layer_props) |layer_prop| {
            const layer_name: [*c]const u8 = @ptrCast(layer_prop.layerName[0..]);
            if (std.mem.eql(u8, std.mem.span(validation_layer_name), std.mem.span(layer_name))) {
                try layers.append(arena, validation_layer_name);
                break :blk true;
            }
        } else false;
    }

    // Check if the required extensions are supported
    var extensions = std.ArrayListUnmanaged([*c]const u8){};

    const ExtensionFinder = struct {
        fn find(name: [*c]const u8, props: []c.vk.ExtensionProperties) bool {
            for (props) |prop| {
                const prop_name: [*c]const u8 = @ptrCast(prop.extensionName[0..]);
                if (std.mem.eql(u8, std.mem.span(name), std.mem.span(prop_name))) {
                    return true;
                }
            }
            return false;
        }
    };

    // Start ensuring all SDL required extensions are supported
    for (opts.required_extensions) |required_ext| {
        if (ExtensionFinder.find(required_ext, extension_props)) {
            try extensions.append(arena, required_ext);
        } else {
            std.log.err("Required vulkan extension not suppoorted: {s}", .{required_ext});
        }
    }

    // If we need validation, also add the debug utils extension
    if (enable_validation and ExtensionFinder.find("VK_EXT_debug_utils", extension_props)) {
        try extensions.append(arena, "VK_EXT_debug_utils");
    } else {
        enable_validation = false;
    }

    const app_info = std.mem.zeroInit(c.vk.ApplicationInfo, .{
        .sType = c.vk.STRUCTURE_TYPE_APPLICATION_INFO,
        .apiVersion = opts.api_version,
        .pApplicationName = opts.application_name,
        .pEngineName = opts.engine_name orelse opts.application_name,
    });

    const instance_info = std.mem.zeroInit(c.vk.InstanceCreateInfo, .{
        .sType = c.vk.STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .flags = c.vk.INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .enabledLayerCount = @as(u32, @intCast(layers.items.len)),
        .ppEnabledLayerNames = layers.items.ptr,
        .enabledExtensionCount = @as(u32, @intCast(extensions.items.len)),
        .ppEnabledExtensionNames = extensions.items.ptr,
    });

    var instance: c.vk.Instance = undefined;
    try checkVk(c.vk.CreateInstance(&instance_info, opts.alloc_cbs, &instance));
    std.log.info("Create vulkan instance.", .{});

    const debug_messenger = if (enable_validation)
        try createDebugCallback(instance, opts)
    else
        null;

    return .{
        .handle = instance,
        .debug_messenger = debug_messenger,
        .alloc_cbs = opts.alloc_cbs,
    };
}

fn createDebugCallback(instance: c.vk.Instance, opts: VkInstanceOpts) !c.vk.DebugUtilsMessengerEXT {
    const create_fn_opt = getVulkanInstanceFunc(
        c.vk.PFN_CreateDebugUtilsMessengerEXT,
        instance,
        "vkCreateDebugUtilsMessengerEXT",
    );

    if (create_fn_opt) |create_fn| {
        const create_info = std.mem.zeroInit(c.vk.DebugUtilsMessengerCreateInfoEXT, .{
            .sType = c.vk.STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
                c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = c.vk.DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                c.vk.DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                c.vk.DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = opts.debug_callback orelse defaultDebugCallback,
            .pUserData = null,
        });
        var debug_messenger: c.vk.DebugUtilsMessengerEXT = undefined;
        try checkVk(create_fn(instance, &create_info, opts.alloc_cbs, &debug_messenger));
        std.log.info("Created vulkan debug messenger.", .{});
        return debug_messenger;
    }
    return null;
}

fn defaultDebugCallback(
    severity: c.vk.DebugUtilsMessageSeverityFlagBitsEXT,
    msg_type: c.vk.DebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const c.vk.DebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) c.vk.Bool32 {
    _ = user_data;
    const severity_str = switch (severity) {
        c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => "verbose",
        c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => "info",
        c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => "warning",
        c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => "error",
        else => "unknown",
    };

    const type_str = switch (msg_type) {
        c.vk.DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT => "general",
        c.vk.DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT => "validation",
        c.vk.DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT => "performance",
        else => "unknown",
    };

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.pMessage else "NO MESSAGE!";
    std.log.err("[{s}][{s}]. Message:\n  {s}", .{ severity_str, type_str, message });

    if (severity >= c.vk.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        @panic("Unrecoverable vulkan error.");
    }

    return c.vk.FALSE;
}

fn getVulkanInstanceFunc(comptime Fn: type, instance: c.vk.Instance, name: [*c]const u8) Fn {
    if (glfw.getInstanceProcAddress(@intFromPtr(instance), name)) |proc| {
        return @ptrCast(proc);
    }
    std.log.err("Failed to resolve Vulkan proc: {s}", .{name});
    @panic("Vulkan proc address is null");
}
