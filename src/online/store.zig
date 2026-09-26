// SPDX-License-Identifier: GPL-2.0-or-later
//! SQLite owns durable control state. Callers serialize transactions under their mutex.
const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
pub const Store = struct {
    db: *c.sqlite3,
    pub fn open(path: [:0]const u8) !Store {
        var db: ?*c.sqlite3 = null;
        if (c.sqlite3_open_v2(path, &db, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, null) != c.SQLITE_OK) {
            if (db) |handle| _ = c.sqlite3_close(handle);
            return error.DatabaseOpen;
        }
        var self: Store = .{ .db = db.? };
        errdefer self.close();
        _ = c.sqlite3_busy_timeout(self.db, 5000);
        try self.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(kind,id)); PRAGMA user_version=1;");
        return self;
    }
    /// SQLite's online backup API includes committed WAL pages in one snapshot.
    /// The caller exclusively creates the private destination before opening it.
    pub fn backup(self: *Store, path: [:0]const u8) !void {
        var destination: ?*c.sqlite3 = null;
        if (c.sqlite3_open_v2(path, &destination, c.SQLITE_OPEN_READWRITE, null) != c.SQLITE_OK) {
            if (destination) |db| _ = c.sqlite3_close(db);
            return error.DatabaseOpen;
        }
        defer _ = c.sqlite3_close(destination.?);
        _ = c.sqlite3_busy_timeout(destination.?, 5000);
        const copy = c.sqlite3_backup_init(destination.?, "main", self.db, "main") orelse return error.Database;
        const status = c.sqlite3_backup_step(copy, -1);
        const finished = c.sqlite3_backup_finish(copy);
        if (status != c.SQLITE_DONE or finished != c.SQLITE_OK) return error.Database;
        // Force rollback-journal form so the delivered backup is a single file.
        if (c.sqlite3_exec(destination.?, "PRAGMA journal_mode=DELETE", null, null, null) != c.SQLITE_OK) return error.Database;
    }
    pub fn close(self: *Store) void {
        _ = c.sqlite3_close(self.db);
    }
    pub fn exec(self: *Store, sql: [:0]const u8) !void {
        if (c.sqlite3_exec(self.db, sql, null, null, null) != c.SQLITE_OK) return error.Database;
    }
    fn prepare(self: *Store, sql: [:0]const u8, values: []const []const u8) !*c.sqlite3_stmt {
        var statement: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &statement, null) != c.SQLITE_OK) return error.Database;
        const stmt = statement.?;
        errdefer _ = c.sqlite3_finalize(stmt);
        for (values, 1..) |value, i| {
            if (value.len > 1 << 20) return error.RecordTooLarge;
            // SQLITE_STATIC: the statement is finalized within the input lifetime.
            if (c.sqlite3_bind_text(stmt, @intCast(i), value.ptr, @intCast(value.len), null) != c.SQLITE_OK) return error.Database;
        }
        return stmt;
    }
    pub fn put(self: *Store, kind: []const u8, id: []const u8, data: []const u8) !void {
        const stmt = try self.prepare("INSERT INTO records(kind,id,data) VALUES(?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data", &.{ kind, id, data });
        defer _ = c.sqlite3_finalize(stmt);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.Database;
    }
    pub fn remove(self: *Store, kind: []const u8, id: []const u8) !void {
        const stmt = try self.prepare("DELETE FROM records WHERE kind=? AND id=?", &.{ kind, id });
        defer _ = c.sqlite3_finalize(stmt);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.Database;
    }
    pub fn get(self: *Store, allocator: std.mem.Allocator, kind: []const u8, id: []const u8) !?[]const u8 {
        const stmt = try self.prepare("SELECT data FROM records WHERE kind=? AND id=?", &.{ kind, id });
        defer _ = c.sqlite3_finalize(stmt);
        const status = c.sqlite3_step(stmt);
        if (status == c.SQLITE_DONE) return null;
        if (status != c.SQLITE_ROW) return error.Database;
        const data = c.sqlite3_column_text(stmt, 0);
        return try allocator.dupe(u8, data[0..@intCast(c.sqlite3_column_bytes(stmt, 0))]);
    }
    pub const Record = struct { id: []const u8, data: []const u8 };
    pub fn list(self: *Store, allocator: std.mem.Allocator, kind: []const u8) ![]Record {
        const stmt = try self.prepare("SELECT id,data FROM records WHERE kind=? ORDER BY id", &.{kind});
        defer _ = c.sqlite3_finalize(stmt);
        var records: std.ArrayList(Record) = .empty;
        while (true) {
            const status = c.sqlite3_step(stmt);
            if (status == c.SQLITE_DONE) break;
            if (status != c.SQLITE_ROW) return error.Database;
            if (records.items.len == 10000) return error.Capacity;
            const id = c.sqlite3_column_text(stmt, 0);
            const data = c.sqlite3_column_text(stmt, 1);
            try records.append(allocator, .{ .id = try allocator.dupe(u8, id[0..@intCast(c.sqlite3_column_bytes(stmt, 0))]), .data = try allocator.dupe(u8, data[0..@intCast(c.sqlite3_column_bytes(stmt, 1))]) });
        }
        return records.toOwnedSlice(allocator);
    }
};
