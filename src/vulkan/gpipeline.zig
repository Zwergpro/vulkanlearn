const std = @import("std");

const c = @import("clibs.zig");
const config = @import("config");
const shaders = @import("shaders.zig");
const devices = @import("devices.zig");


pub fn createGraphicsPipeline(
    alloc: std.mem.Allocator,
    device: *devices.Device,
    alloc_cbs: ?*c.vk.AllocationCallbacks,
) !void {
    var stack_fallback = std.heap.stackFallback(100 * @sizeOf(u8), alloc);
    const sfa_alloc = stack_fallback.get();

    const vert_path = try std.fs.path.join(sfa_alloc, &.{ config.shaders_path, "vert.spv" });
    defer sfa_alloc.free(vert_path);
    const vert_shader_code = try shaders.loadCode(alloc, vert_path);
    defer alloc.free(vert_shader_code);

    const vert_shader_module = try shaders.ShaderModule.create(alloc, device, alloc_cbs, vert_shader_code);
    defer vert_shader_module.destroy();

    const frag_path = try std.fs.path.join(sfa_alloc, &.{ config.shaders_path, "frag.spv" });
    defer sfa_alloc.free(frag_path);
    const frag_shader_code = try shaders.loadCode(alloc, frag_path);
    defer alloc.free(frag_shader_code);

    const frag_shader_module = try shaders.ShaderModule.create(alloc, device, alloc_cbs, frag_shader_code);
    defer frag_shader_module.destroy();
}
