const std = @import("std");
const temp = @import("temp");

const c = @cImport(@cInclude("rocksdb/c.h"));

const rdb = @import("rocksdb");

pub fn main() !void {
    try mainRawC();
    try mainZigWrapper();
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

fn mainRawC() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var buf_stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer buf_stdout.flush() catch {};
    const stdout = buf_stdout.writer();

    const db_path_z = try std.fmt.allocPrintZ(arena.allocator(), "{s}{c}{s}", .{
        try temp.system_dir_path_alloc(arena.allocator()),
        std.fs.path.sep,
        "mainRawC.kv",
    });

    std.fs.deleteFileAbsolute(db_path_z) catch {};

    var err: ?[*:0]u8 = null;

    const db_opt = c.rocksdb_options_create() orelse return error.RocksDb;
    defer c.rocksdb_options_destroy(db_opt);

    c.rocksdb_options_increase_parallelism(db_opt, @intCast(std.Thread.getCpuCount() catch 1));
    c.rocksdb_options_optimize_level_style_compaction(db_opt, 0);
    c.rocksdb_options_set_create_if_missing(db_opt, 1);
    c.rocksdb_options_set_create_missing_column_families(db_opt, 1);

    const cf_opt = c.rocksdb_options_create() orelse return error.RocksDb;
    defer c.rocksdb_options_destroy(cf_opt);

    const write_opt = c.rocksdb_writeoptions_create() orelse return error.RocksDb;
    defer c.rocksdb_writeoptions_destroy(write_opt);

    var cfHandles: [3]?*c.rocksdb_column_family_handle_t = .{null} ** 3;

    const db = brk: {
        const cf_names: []const [*:0]const u8 = &.{ "default", "apples", "oranges" };
        const cf_opts = [_]*c.rocksdb_options_t{ cf_opt, cf_opt, cf_opt };
        break :brk c.rocksdb_open_column_families(db_opt, db_path_z, cf_names.len, cf_names.ptr, &cf_opts, &cfHandles, &err) orelse try handleRocksError(err);
    };
    defer c.rocksdb_close(db);

    const cf_default = cfHandles[0] orelse return error.MissingColumnFamily;
    const cf_apples = cfHandles[1] orelse return error.MissingColumnFamily;
    const cf_oranges = cfHandles[2] orelse return error.MissingColumnFamily;

    {
        const key = "key";
        const value = "value";

        c.rocksdb_put_cf(db, write_opt, cf_default, key, key.len, value, value.len, &err);
        try checkRocksError(err);
    }
    {
        const batch = c.rocksdb_writebatch_create();
        defer c.rocksdb_writebatch_destroy(batch);
        {
            const key = "batchk1";
            const value = "batchvalue1";
            c.rocksdb_writebatch_put(batch, key, key.len, value, value.len);
        }
        {
            const key = "batchk2";
            const value = "batchvalue2";
            c.rocksdb_writebatch_put(batch, key, key.len, value, value.len);
        }
        {
            const key = "apple1";
            const value = "super juicy";
            c.rocksdb_writebatch_put_cf(batch, cf_apples, key, key.len, value, value.len);
        }
        {
            const key = "apple2";
            const value = "less juicy";
            c.rocksdb_writebatch_put_cf(batch, cf_apples, key, key.len, value, value.len);
        }
        {
            const key = "orange1";
            const value = "very juicy";
            c.rocksdb_writebatch_put_cf(batch, cf_oranges, key, key.len, value, value.len);
        }
        {
            const key = "orange2";
            const value = "mini juicy";
            c.rocksdb_writebatch_put_cf(batch, cf_oranges, key, key.len, value, value.len);
        }
        c.rocksdb_write(db, write_opt, batch, &err);
        try checkRocksError(err);
    }

    try stdout.print("{s} finished successfully!\n", .{@src().fn_name});
}

fn mainZigWrapper() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var buf_stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer buf_stdout.flush() catch {};
    const stdout = buf_stdout.writer();

    const db_path_z = try std.fmt.allocPrintZ(arena.allocator(), "{s}{c}{s}", .{
        try temp.system_dir_path_alloc(arena.allocator()),
        std.fs.path.sep,
        "mainZigWrapperC.kv",
    });

    std.fs.deleteFileAbsolute(db_path_z) catch {};

    const db_opt =
        (try rdb.Options.init())
        .increaseParallelism(std.Thread.getCpuCount() catch 1)
        .optimizeLevelStyleCompaction(false)
        .createIfMissing(true)
        .createMissingColumnFamilies(true);
    defer db_opt.deinit();

    const cf_opt = try rdb.Options.init();
    defer cf_opt.deinit();

    const write_opt = try rdb.WriteOptions.init();
    defer write_opt.deinit();

    var db = try rdb.Db.openColumnFamilies(
        gpa.allocator(),
        db_opt,
        db_path_z,
        &.{ "default", "apples", "oranges" },
        &.{ cf_opt, cf_opt, cf_opt },
    );
    defer db.close();

    const cfs = .{
        .default = db.cfs[0],
        .apples = db.cfs[1],
        .oranges = db.cfs[2],
    };

    (try db.putCf(write_opt, cfs.default, "key", "value")).intoVoid();

    const batch = try rdb.Batch.init();
    defer batch.deinit();

    try batch
        .put("batchk1", "batchvalue1")
        .put("batchk2", "batchvalue2")
        .putCf(cfs.apples, "apple1", "super juicy")
        .putCf(cfs.apples, "apple2", "less juicy")
        .putCf(cfs.oranges, "orange1", "very juicy")
        .putCf(cfs.oranges, "orange2", "mini juicy")
        .write(&db, write_opt);

    try stdout.print("{s} finished successfully!\n", .{@src().fn_name});
}
