const std = @import("std");
const config = @import("config");
const shaders = @import("shaders.zig");


pub fn createGraphicsPipeline(alloc: std.mem.Allocator) !void {
    var stack_fallback = std.heap.stackFallback(50 * @sizeOf(u8), alloc);
    const sfa_alloc = stack_fallback.get();

    const vert_path = try std.fs.path.join(sfa_alloc, &.{ config.shaders_path, "vert.spv" });
    defer sfa_alloc.free(vert_path);
    const vert_shader_code = try shaders.loadCode(alloc, vert_path);
    defer alloc.free(vert_shader_code);

    const frag_path = try std.fs.path.join(sfa_alloc, &.{ config.shaders_path, "vert.spv" });
    defer sfa_alloc.free(frag_path);
    const frag_shader_code = try shaders.loadCode(alloc, frag_path);
    defer alloc.free(frag_shader_code);
}
