
const std = @import("std");


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
