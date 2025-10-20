const std = @import("std");

const c = @import("clibs.zig");
const devices = @import("devices.zig");
const checkVk = @import("errors.zig").checkVk;

pub fn loadCode(alloc: std.mem.Allocator, file_path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(file_path, .{});
    defer file.close();

    // Get the file size by seeking to the end
    const file_size = try file.getEndPos();

    // Allocate a buffer to hold the entire file
    const buffer = try alloc.alloc(u8, file_size);
    errdefer alloc.free(buffer);

    // Read all bytes from the file
    const bytes_read = try file.readAll(buffer);

    // Verify we read the entire file
    if (bytes_read != file_size) {
        alloc.free(buffer);
        return error.UnexpectedEndOfFile;
    }

    return buffer;
}

pub const ShaderModule = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    handle: c.vk.ShaderModule,
    device: c.vk.Device,
    alloc_cbs: ?*c.vk.AllocationCallbacks = null,

    pub fn init(alloc: std.mem.Allocator, device: *devices.Device, alloc_cbs: ?*c.vk.AllocationCallbacks, code: []const u8) !Self {
        if (!std.mem.isAligned(@intFromPtr(code.ptr), 4)) return error.BadAlignment;

        const create_info = std.mem.zeroInit(c.vk.ShaderModuleCreateInfo, .{
            .sType = c.vk.STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = code.len,
            .pCode = @as([*c]const u32, @ptrCast(@alignCast(code.ptr))),
        });

        var module: c.vk.ShaderModule = undefined;
        try checkVk(c.vk.CreateShaderModule(device.handle, &create_info, alloc_cbs, &module));

        return .{
            .alloc = alloc,
            .handle = module,
            .device = device.handle,
            .alloc_cbs = alloc_cbs,
        };
    }

    pub fn create(alloc: std.mem.Allocator, device: *devices.Device, alloc_cbs: ?*c.vk.AllocationCallbacks, code: []const u8) !*Self {
        const self = try alloc.create(ShaderModule);
        errdefer alloc.destroy(self);

        self.* = try ShaderModule.init(alloc, device, alloc_cbs, code);
        return self;
    }

    pub fn deinit(self: *Self) void {
        c.vk.DestroyShaderModule(self.device, self.handle, self.alloc_cbs);
    }

    pub fn destroy(self: *Self) void {
        const allocator = self.alloc;
        self.deinit();
        allocator.destroy(self);
    }
};
