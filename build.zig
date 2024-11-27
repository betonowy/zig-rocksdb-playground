const std = @import("std");
const rocksdb = @import("thirdparty/rocksdb/deps.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_rocksdb = rocksdb.lib(b, target, optimize);
    const mod_temp = b.dependency("temp", .{}).module("temp");

    {
        const exe = b.addExecutable(.{
            .name = "zig-rocksdb-playground",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("rocksdb", &lib_rocksdb.root_module);
        exe.root_module.addImport("temp", mod_temp);
        exe.root_module.include_dirs.appendSlice(b.allocator, lib_rocksdb.root_module.include_dirs.items) catch @panic("OOM");

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
    {
        const exe = rocksdb.ldb(b, target, optimize, lib_rocksdb);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("ldb", "Run the ldb");
        run_step.dependOn(&run_cmd.step);
    }
}
