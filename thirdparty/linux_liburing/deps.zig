const std = @import("std");

pub fn lib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const dep_uring = b.dependency("linux_liburing", .{});
    const lib_linux_uring = b.addStaticLibrary(.{
        .name = "linux_liburing",
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });

    const config_header = b.addConfigHeader(.{
        .include_guard_override = "LIBURING_VERSION_H",
    }, .{
        .IO_URING_VERSION_MAJOR = 2,
        .IO_URING_VERSION_MINOR = 8,
    });

    config_header.include_path = "liburing/io_uring_version.h";
    lib_linux_uring.step.dependOn(&config_header.step);

    lib_linux_uring.addIncludePath(config_header.getOutput().path(b, "../.."));
    lib_linux_uring.addIncludePath(dep_uring.path("src/include"));

    lib_linux_uring.addCSourceFiles(.{
        .files = &lib_srcs,
        .root = dep_uring.path(""),
        .flags = &cflags,
    });

    return lib_linux_uring;
}

const cflags = [_][]const u8{
    "-DCONFIG_NOLIBC",
    "-DCONFIG_HAVE_KERNEL_RWF_T",
    "-DCONFIG_HAVE_KERNEL_TIMESPEC",
    "-DCONFIG_HAVE_OPEN_HOW",
    "-DCONFIG_HAVE_STATX",
    "-DCONFIG_HAVE_GLIBC_STATX",
    "-DCONFIG_HAVE_CXX",
    "-DCONFIG_HAVE_UCONTEXT",
    "-DCONFIG_HAVE_STRINGOP_OVERFLOW",
    "-DCONFIG_HAVE_ARRAY_BOUNDS",
    "-DCONFIG_HAVE_NVME_URING",
    "-DCONFIG_HAVE_FANOTIFY",
    "-DCONFIG_HAVE_FUTEXV",
    "-DCONFIG_HAVE_UBLK_HEADER",
    "-D_GNU_SOURCE",
    "-D_LARGEFILE_SOURCE",
    "-D_FILE_OFFSET_BITS=64",
    "-DLIBURING_INTERNAL",
    "-fno-stack-protector",
    "-ffreestanding",
    "-fno-builtin",
};

const lib_srcs = [_][]const u8{
    "src/setup.c",
    "src/queue.c",
    "src/register.c",
    "src/syscall.c",
    "src/version.c",
    "src/nolibc.c",
};
