const std = @import("std");


pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vulkanlearn",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    const env_map = try std.process.getEnvMap(b.allocator);
    if (env_map.get("VULKAN_SDK")) |path| {
        exe.addLibraryPath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/lib", .{ path }) catch @panic("OOM") });
        exe.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/include", .{ path }) catch @panic("OOM") });
    }
    exe.root_module.linkSystemLibrary("vulkan", .{});


    const glfw_zig = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(glfw_zig.artifact("glfw"));

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("glfw", zglfw.module("glfw"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
