// SPDX-License-Identifier: GPL-2.0-or-later
//! HTTPS adapter using the engine's existing libcurl dependency. Zig 0.16's
//! Certificate.verifyHostName omits iPAddress SANs, so it cannot verify IP sites.
const std = @import("std");
const api = @import("api.zig");
const c = @cImport({
    @cDefine("CURL_DISABLE_TYPECHECK", "1");
    @cInclude("curl/curl.h");
});
const Curl = struct {
    library: std.DynLib,
    global_init: @TypeOf(&c.curl_global_init),
    global_cleanup: @TypeOf(&c.curl_global_cleanup),
    easy_init: @TypeOf(&c.curl_easy_init),
    easy_cleanup: @TypeOf(&c.curl_easy_cleanup),
    easy_setopt: @TypeOf(&c.curl_easy_setopt),
    easy_perform: @TypeOf(&c.curl_easy_perform),
    easy_getinfo: @TypeOf(&c.curl_easy_getinfo),
    slist_append: @TypeOf(&c.curl_slist_append),
    slist_free_all: @TypeOf(&c.curl_slist_free_all),
    version_info: @TypeOf(&c.curl_version_info),
    fn open() !Curl {
        var library = std.DynLib.open("libcurl.so.4") catch return error.LibcurlUnavailable;
        errdefer library.close();
        var result: Curl = undefined;
        result.library = library;
        inline for (std.meta.fields(Curl)) |field| {
            if (comptime !std.mem.eql(u8, field.name, "library")) @field(result, field.name) = library.lookup(field.type, "curl_" ++ field.name) orelse return error.LibcurlUnavailable;
        }
        const version = result.version_info(c.CURLVERSION_FIRST);
        if (version == null or version[0].version_num < 0x075500 or version[0].features & c.CURL_VERSION_THREADSAFE == 0) return error.LibcurlTooOld;
        if (result.global_init(c.CURL_GLOBAL_DEFAULT) != c.CURLE_OK) return error.LibcurlUnavailable;
        return result;
    }
    fn close(self: *Curl) void {
        self.global_cleanup();
        self.library.close();
    }
    fn set(self: *Curl, handle: *c.CURL, option: c.CURLoption, value: anytype) !void {
        if (self.easy_setopt(handle, option, value) != c.CURLE_OK) return error.HttpConfiguration;
    }
};
const Buffer = struct {
    writer: std.Io.Writer,
    overflow: bool = false,
    fn append(bytes: [*c]u8, size: usize, count: usize, context: ?*anyopaque) callconv(.c) usize {
        const self: *Buffer = @ptrCast(@alignCast(context.?));
        const length = std.math.mul(usize, size, count) catch return 0;
        self.writer.writeAll(bytes[0..length]) catch {
            self.overflow = true;
            return 0;
        };
        return length;
    }
};
pub const Client = struct {
    curl: Curl,
    transport: struct { io: std.Io },
    base: []const u8,
    token: []const u8,
    ca_file: ?[]const u8,
    pub fn init(_: std.mem.Allocator, io: std.Io, base: []const u8, token: []const u8, ca_file: ?[]const u8) !Client {
        const uri = try std.Uri.parse(base);
        const host = uri.host orelse return error.HttpsRequired;
        if (uri.user != null or uri.password != null or uri.query != null or uri.fragment != null) return error.InvalidCoordinator;
        if (!std.mem.eql(u8, uri.scheme, "https") and !(std.mem.eql(u8, uri.scheme, "http") and std.mem.eql(u8, host.percent_encoded, "127.0.0.1"))) return error.HttpsRequired;
        if (base.len > 1024 or std.mem.indexOfAny(u8, base, "\r\n") != null) return error.InvalidCoordinator;
        return .{ .curl = try Curl.open(), .transport = .{ .io = io }, .base = std.mem.trimEnd(u8, base, "/"), .token = token, .ca_file = ca_file };
    }
    pub fn deinit(self: *Client) void {
        self.curl.close();
    }
    pub fn call(self: *Client, a: std.mem.Allocator, comptime T: type, path: []const u8, value: anytype) !T {
        return self.request(a, T, path, try std.json.Stringify.valueAlloc(a, value, .{}));
    }
    pub fn get(self: *Client, a: std.mem.Allocator, comptime T: type, path: []const u8) !T {
        return self.request(a, T, path, null);
    }
    fn request(self: *Client, a: std.mem.Allocator, comptime T: type, path: []const u8, payload: ?[]const u8) !T {
        if (std.mem.indexOfAny(u8, self.token, "\r\n") != null) return error.InvalidToken;
        const curl = &self.curl;
        const handle = curl.easy_init() orelse return error.OutOfMemory;
        defer curl.easy_cleanup(handle);
        const url = try std.fmt.allocPrintSentinel(a, "{s}{s}", .{ self.base, path }, 0);
        try curl.set(handle, c.CURLOPT_URL, url.ptr);
        try curl.set(handle, c.CURLOPT_PROTOCOLS_STR, @as([*:0]const u8, "https,http"));
        try curl.set(handle, c.CURLOPT_PROXY, @as([*:0]const u8, ""));
        try curl.set(handle, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
        try curl.set(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));
        try curl.set(handle, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 0));
        try curl.set(handle, c.CURLOPT_NOSIGNAL, @as(c_long, 1));
        try curl.set(handle, c.CURLOPT_CONNECTTIMEOUT_MS, @as(c_long, 5000));
        try curl.set(handle, c.CURLOPT_TIMEOUT_MS, @as(c_long, 15000));
        try curl.set(handle, c.CURLOPT_USERAGENT, @as([*:0]const u8, "dk3-online/1"));
        if (self.ca_file) |file| try curl.set(handle, c.CURLOPT_CAINFO, (try a.dupeZ(u8, file)).ptr);
        var headers: [*c]c.curl_slist = null;
        defer curl.slist_free_all(headers);
        headers = curl.slist_append(headers, "Content-Type: application/json");
        if (headers == null) return error.OutOfMemory;
        const auth = try std.fmt.allocPrintSentinel(a, "Authorization: Bearer {s}", .{self.token}, 0);
        const with_auth = curl.slist_append(headers, auth.ptr);
        if (with_auth == null) return error.OutOfMemory;
        headers = with_auth;
        try curl.set(handle, c.CURLOPT_HTTPHEADER, headers);
        if (payload) |bytes| {
            try curl.set(handle, c.CURLOPT_POST, @as(c_long, 1));
            try curl.set(handle, c.CURLOPT_POSTFIELDSIZE_LARGE, @as(c.curl_off_t, @intCast(bytes.len)));
            try curl.set(handle, c.CURLOPT_POSTFIELDS, bytes.ptr);
        }
        const storage = try a.alloc(u8, 4 * 1024 * 1024);
        defer a.free(storage);
        var output: Buffer = .{ .writer = .fixed(storage) };
        try curl.set(handle, c.CURLOPT_WRITEFUNCTION, &Buffer.append);
        try curl.set(handle, c.CURLOPT_WRITEDATA, &output);
        const result = curl.easy_perform(handle);
        if (output.overflow) return error.ResponseTooLarge;
        if (result == c.CURLE_OPERATION_TIMEDOUT) return error.RequestTimedOut;
        if (result == c.CURLE_PEER_FAILED_VERIFICATION or result == c.CURLE_SSL_CACERT_BADFILE) return error.CertificateVerificationFailed;
        if (result != c.CURLE_OK) return error.HttpTransport;
        var status: c_long = 0;
        if (curl.easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status) != c.CURLE_OK) return error.HttpTransport;
        if (status != 200) {
            const failure = std.json.parseFromSlice(api.Failure, a, output.writer.buffered(), .{}) catch return error.RequestRejected;
            inline for (.{ "Unauthorized", "Expired", "Forbidden", "Banned", "NotFound", "Capacity", "RateLimited", "Conflict", "Incompatible", "NoWorker" }) |code| {
                if (std.mem.eql(u8, failure.value.code, code)) return @field(anyerror, code);
            }
            return error.RequestRejected;
        }
        return (try std.json.parseFromSlice(T, a, output.writer.buffered(), .{ .allocate = .alloc_always })).value;
    }
};
