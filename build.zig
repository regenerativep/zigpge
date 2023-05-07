const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const pge_mod = b.createModule(.{ .source_file = .{ .path = "pge/pge.zig" } });
    try b.modules.put(b.dupe("pge"), pge_mod);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zigpge",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("pge", pge_mod);

    exe.linkLibC();
    exe.linkSystemLibrary("X11");
    exe.addIncludePath("/usr/include/X11");
    exe.linkSystemLibrary("GL");
    exe.addIncludePath("/usr/include/GL");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
