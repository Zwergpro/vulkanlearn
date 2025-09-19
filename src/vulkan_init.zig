const std = @import("std");
pub const c = @import("clibs.zig");

pub const VkInstanceOpts = struct {
    application_name: [:0]const u8 = "vki",
    application_version: u32 = c.vk.MAKE_VERSION(1, 0, 0),
    engine_name: ?[:0]const u8 = null,
    engine_version: u32 = c.vk.MAKE_VERSION(1, 0, 0),
    api_version: u32 = c.vk.MAKE_VERSION(1, 0, 0),
    debug: bool = false,
    debug_callback: c.vk.PFN_DebugUtilsMessengerCallbackEXT = null,
    required_extensions: []const [*c]const u8 = &.{},
    alloc_cb: ?*c.vk.AllocationCallbacks = null,
};

pub const Instance = struct {
    handle: c.vk.Instance = null,
};

pub fn create_instance(alloc: std.mem.Allocator, opts: VkInstanceOpts) !Instance {
    if (opts.api_version > c.vk.MAKE_VERSION(1, 0, 0)) {
        var api_requested = opts.api_version;
        try check_vk(c.vk.EnumerateInstanceVersion(@ptrCast(&api_requested)));
    }

    var enable_validation = opts.debug;

    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Get supported layers and extensions
    var layer_count: u32 = undefined;
    try check_vk(c.vk.EnumerateInstanceLayerProperties(&layer_count, null));
    const layer_props = try arena.alloc(c.vk.LayerProperties, layer_count);
    try check_vk(c.vk.EnumerateInstanceLayerProperties(&layer_count, layer_props.ptr));

    var extension_count: u32 = undefined;
    try check_vk(c.vk.EnumerateInstanceExtensionProperties(null, &extension_count, null));
    const extension_props = try arena.alloc(c.vk.ExtensionProperties, extension_count);
    try check_vk(c.vk.EnumerateInstanceExtensionProperties(null, &extension_count, extension_props.ptr));

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
    try check_vk(c.vk.CreateInstance(&instance_info, opts.alloc_cb, &instance));
    std.log.info("Create vulkan instance.", .{});

    return .{ .handle = instance };
}

pub fn check_vk(result: c.vk.Result) !void {
    return switch (result) {
        c.vk.SUCCESS => {},
        c.vk.NOT_READY => error.vk_not_ready,
        c.vk.TIMEOUT => error.vk_timeout,
        c.vk.EVENT_SET => error.vk_event_set,
        c.vk.EVENT_RESET => error.vk_event_reset,
        c.vk.INCOMPLETE => error.vk_incomplete,
        c.vk.ERROR_OUT_OF_HOST_MEMORY => error.vk_error_out_of_host_memory,
        c.vk.ERROR_OUT_OF_DEVICE_MEMORY => error.vk_error_out_of_device_memory,
        c.vk.ERROR_INITIALIZATION_FAILED => error.vk_error_initialization_failed,
        c.vk.ERROR_DEVICE_LOST => error.vk_error_device_lost,
        c.vk.ERROR_MEMORY_MAP_FAILED => error.vk_error_memory_map_failed,
        c.vk.ERROR_LAYER_NOT_PRESENT => error.vk_error_layer_not_present,
        c.vk.ERROR_EXTENSION_NOT_PRESENT => error.vk_error_extension_not_present,
        c.vk.ERROR_FEATURE_NOT_PRESENT => error.vk_error_feature_not_present,
        c.vk.ERROR_INCOMPATIBLE_DRIVER => error.vk_error_incompatible_driver,
        c.vk.ERROR_TOO_MANY_OBJECTS => error.vk_error_too_many_objects,
        c.vk.ERROR_FORMAT_NOT_SUPPORTED => error.vk_error_format_not_supported,
        c.vk.ERROR_FRAGMENTED_POOL => error.vk_error_fragmented_pool,
        c.vk.ERROR_UNKNOWN => error.vk_error_unknown,
        c.vk.ERROR_OUT_OF_POOL_MEMORY => error.vk_error_out_of_pool_memory,
        c.vk.ERROR_INVALID_EXTERNAL_HANDLE => error.vk_error_invalid_external_handle,
        c.vk.ERROR_FRAGMENTATION => error.vk_error_fragmentation,
        c.vk.ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => error.vk_error_invalid_opaque_capture_address,
        c.vk.PIPELINE_COMPILE_REQUIRED => error.vk_pipeline_compile_required,
        c.vk.ERROR_SURFACE_LOST_KHR => error.vk_error_surface_lost_khr,
        c.vk.ERROR_NATIVE_WINDOW_IN_USE_KHR => error.vk_error_native_window_in_use_khr,
        c.vk.SUBOPTIMAL_KHR => error.vk_suboptimal_khr,
        c.vk.ERROR_OUT_OF_DATE_KHR => error.vk_error_out_of_date_khr,
        c.vk.ERROR_INCOMPATIBLE_DISPLAY_KHR => error.vk_error_incompatible_display_khr,
        c.vk.ERROR_VALIDATION_FAILED_EXT => error.vk_error_validation_failed_ext,
        c.vk.ERROR_INVALID_SHADER_NV => error.vk_error_invalid_shader_nv,
        c.vk.ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => error.vk_error_image_usage_not_supported_khr,
        c.vk.ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => error.vk_error_video_picture_layout_not_supported_khr,
        c.vk.ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => error.vk_error_video_profile_operation_not_supported_khr,
        c.vk.ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => error.vk_error_video_profile_format_not_supported_khr,
        c.vk.ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => error.vk_error_video_profile_codec_not_supported_khr,
        c.vk.ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => error.vk_error_video_std_version_not_supported_khr,
        c.vk.ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.vk_error_invalid_drm_format_modifier_plane_layout_ext,
        c.vk.ERROR_NOT_PERMITTED_KHR => error.vk_error_not_permitted_khr,
        c.vk.ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.vk_error_full_screen_exclusive_mode_lost_ext,
        c.vk.THREAD_IDLE_KHR => error.vk_thread_idle_khr,
        c.vk.THREAD_DONE_KHR => error.vk_thread_done_khr,
        c.vk.OPERATION_DEFERRED_KHR => error.vk_operation_deferred_khr,
        c.vk.OPERATION_NOT_DEFERRED_KHR => error.vk_operation_not_deferred_khr,
        c.vk.ERROR_COMPRESSION_EXHAUSTED_EXT => error.vk_error_compression_exhausted_ext,
        c.vk.ERROR_INCOMPATIBLE_SHADER_BINARY_EXT => error.vk_error_incompatible_shader_binary_ext,
        else => error.vk_errror_unknown,
    };
}
