const std = @import("std");
const c = @cImport(@cInclude("./rocksdb/c.h"));

fn rocksdbBool(value: bool) u1 {
    return if (value) 1 else 0;
}

fn handleRocksError(error_string: ?[*:0]u8) !noreturn {
    try checkRocksError(error_string);
    return error.RocksDbNonDescribedError;
}

fn checkRocksError(error_string: ?[*:0]u8) !void {
    const msg = error_string orelse return;
    std.log.err("RocksDB: {s}", .{msg});
    return error.RocksDb;
}

fn unwrapSlice(T: type, slice: []?*T) ![]*T {
    for (slice) |item| if (item == null) return error.SliceUnwrap;
    return @ptrCast(slice);
}

const RocksErr = ?[*:0]u8;

pub const Options = struct {
    ptr: *c.rocksdb_options_t,

    pub fn init() !@This() {
        return .{ .ptr = c.rocksdb_options_create() orelse return error.RocksCreate };
    }

    pub fn deinit(self: @This()) void {
        c.rocksdb_options_destroy(self.ptr);
    }

    pub fn increaseParallelism(self: @This(), count: usize) @This() {
        c.rocksdb_options_increase_parallelism(self.ptr, @intCast(count));
        return self;
    }

    pub fn optimizeLevelStyleCompaction(self: @This(), value: bool) @This() {
        c.rocksdb_options_optimize_level_style_compaction(self.ptr, rocksdbBool(value));
        return self;
    }

    pub fn createIfMissing(self: @This(), value: bool) @This() {
        c.rocksdb_options_set_create_if_missing(self.ptr, rocksdbBool(value));
        return self;
    }

    pub fn createMissingColumnFamilies(self: @This(), value: bool) @This() {
        c.rocksdb_options_set_create_missing_column_families(self.ptr, rocksdbBool(value));
        return self;
    }

    // TODO fill up api functions

    pub fn intoVoid(_: @This()) void {}
};

pub const WriteOptions = struct {
    ptr: *c.rocksdb_writeoptions_t,

    pub fn init() !@This() {
        return .{ .ptr = c.rocksdb_writeoptions_create() orelse return error.RocksCreate };
    }

    pub fn deinit(self: @This()) void {
        c.rocksdb_writeoptions_destroy(self.ptr);
    }

    // TODO fill up api functions
};

pub const Db = struct {
    allocator: std.mem.Allocator,
    ptr: *c.rocksdb_t,
    cfs: []*c.rocksdb_column_family_handle_t,
    err: RocksErr,

    pub fn openColumnFamilies(
        allocator: std.mem.Allocator,
        db_opt: Options,
        db_path: []const u8,
        names: []const []const u8,
        cf_opts: []const Options,
    ) !@This() {
        var stack_fb = std.heap.stackFallback(0x4000, allocator);
        const stack_layer = stack_fb.get();
        var arena = std.heap.ArenaAllocator.init(stack_layer);
        defer arena.deinit();

        var c_names_z = try std.ArrayList([*:0]const u8).initCapacity(arena.allocator(), names.len);
        for (names) |name| c_names_z.appendAssumeCapacity(try arena.allocator().dupeZ(u8, name));

        var c_cf_opts = try std.ArrayList(*c.rocksdb_options_t).initCapacity(arena.allocator(), cf_opts.len);
        for (cf_opts) |cf_opt| c_cf_opts.appendAssumeCapacity(cf_opt.ptr);

        const db_path_z = try arena.allocator().dupeZ(u8, db_path);
        const cfs = try allocator.alloc(?*c.rocksdb_column_family_handle_t, names.len);

        var err: RocksErr = null;

        return .{
            .ptr = c.rocksdb_open_column_families(db_opt.ptr, db_path_z, @intCast(names.len), c_names_z.items.ptr, c_cf_opts.items.ptr, cfs.ptr, &err) orelse {
                try handleRocksError(err);
            },
            .allocator = allocator,
            .cfs = try unwrapSlice(c.rocksdb_column_family_handle_t, cfs),
            .err = err,
        };
    }

    pub fn close(self: @This()) void {
        c.rocksdb_close(self.ptr);
        self.allocator.free(self.cfs);
    }

    pub fn putCf(self: *@This(), w_opt: WriteOptions, cf: *c.rocksdb_column_family_handle_t, key: []const u8, value: []const u8) !*@This() {
        c.rocksdb_put_cf(self.ptr, w_opt.ptr, cf, key.ptr, key.len, value.ptr, value.len, &self.err);
        try checkRocksError(self.err);
        return self;
    }

    pub fn intoVoid(_: @This()) void {}
};

pub const Batch = struct {
    ptr: *c.rocksdb_writebatch_t,

    pub fn init() !@This() {
        return .{ .ptr = c.rocksdb_writebatch_create() orelse return error.RocksCreate };
    }

    pub fn deinit(self: @This()) void {
        c.rocksdb_writebatch_destroy(self.ptr);
    }

    pub fn put(self: @This(), key: []const u8, value: []const u8) @This() {
        c.rocksdb_writebatch_put(self.ptr, key.ptr, key.len, value.ptr, value.len);
        return self;
    }

    pub fn putCf(self: @This(), cf: *c.rocksdb_column_family_handle_t, key: []const u8, value: []const u8) @This() {
        c.rocksdb_writebatch_put_cf(self.ptr, cf, key.ptr, key.len, value.ptr, value.len);
        return self;
    }

    pub fn write(self: @This(), db: *Db, w_opt: WriteOptions) !void {
        c.rocksdb_write(db.ptr, w_opt.ptr, self.ptr, &db.err);
        try checkRocksError(db.err);
    }

    pub fn intoVoid(_: @This()) void {}
};
