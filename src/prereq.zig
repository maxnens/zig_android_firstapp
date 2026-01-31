const std = @import("std");

/// Minimum supported versions
pub const MIN_API_LEVEL: u8 = 26;
pub const MIN_NDK_MAJOR: u8 = 25;
pub const MIN_BUILD_TOOLS_MAJOR: u8 = 30;

/// Prerequisite check result
pub const CheckResult = struct {
    ok: bool,
    message: []const u8,
    suggestion: []const u8,
};

/// Parse version string like "35.0.0" into major version
pub fn parseMajorVersion(version_str: []const u8) ?u8 {
    const dot_idx = std.mem.indexOf(u8, version_str, ".");
    const major_str = if (dot_idx) |idx| version_str[0..idx] else version_str;
    return std.fmt.parseInt(u8, major_str, 10) catch null;
}

/// Parse NDK version from source.properties content (e.g., "27.0.12077973")
pub fn parseNdkVersion(properties_content: []const u8) ?u8 {
    var lines = std.mem.splitScalar(u8, properties_content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "Pkg.Revision")) {
            // Find the = sign and get the value after it
            const eq_idx = std.mem.indexOf(u8, line, "=") orelse continue;
            const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t\r");
            return parseMajorVersion(value);
        }
    }
    return null;
}

/// Parse API level from directory name like "android-35"
pub fn parseApiLevel(dir_name: []const u8) ?u8 {
    if (std.mem.startsWith(u8, dir_name, "android-")) {
        return std.fmt.parseInt(u8, dir_name[8..], 10) catch null;
    }
    return null;
}

/// Find highest available version in a directory
pub fn findHighestVersion(allocator: std.mem.Allocator, dir_path: []const u8, comptime parser: fn ([]const u8) ?u8) !?u8 {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound, error.NotDir => return null,
            else => return err,
        }
    };
    defer dir.close();

    var highest: ?u8 = null;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const name = try allocator.dupe(u8, entry.name);
            defer allocator.free(name);
            if (parser(name)) |version| {
                if (highest == null or version > highest.?) {
                    highest = version;
                }
            }
        }
    }
    return highest;
}

/// Find highest build-tools version directory name
pub fn findHighestBuildTools(allocator: std.mem.Allocator, sdk_path: []const u8) !?[]const u8 {
    const build_tools_path = try std.fmt.allocPrint(allocator, "{s}/build-tools", .{sdk_path});
    defer allocator.free(build_tools_path);

    var dir = std.fs.openDirAbsolute(build_tools_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound, error.NotDir => return null,
            else => return err,
        }
    };
    defer dir.close();

    var highest_name: ?[]const u8 = null;
    var highest_version: ?u8 = null;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            if (parseMajorVersion(entry.name)) |version| {
                if (highest_version == null or version > highest_version.?) {
                    if (highest_name) |old| allocator.free(old);
                    highest_name = try allocator.dupe(u8, entry.name);
                    highest_version = version;
                }
            }
        }
    }
    return highest_name;
}

/// Check if a path exists (handles empty or relative paths gracefully)
pub fn pathExists(path: []const u8) bool {
    if (path.len == 0) return false;
    if (!std.fs.path.isAbsolute(path)) return false;
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

/// Check if a file exists (handles empty or relative paths gracefully)
pub fn fileExists(path: []const u8) bool {
    if (path.len == 0) return false;
    if (!std.fs.path.isAbsolute(path)) return false;
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

// ============================================================================
// Validation Results
// ============================================================================

pub const ValidationError = struct {
    component: []const u8,
    message: []const u8,
    suggestion: []const u8,
};

pub const ValidationResult = struct {
    sdk_path: []const u8,
    ndk_path: []const u8,
    build_tools_version: []const u8,
    api_level: u8,
    errors: []ValidationError,

    pub fn hasErrors(self: ValidationResult) bool {
        return self.errors.len > 0;
    }
};

/// Format an error message for display
pub fn formatError(allocator: std.mem.Allocator, err: ValidationError) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\
        \\ERROR: {s}
        \\  {s}
        \\
        \\  Suggestion: {s}
        \\
    , .{ err.component, err.message, err.suggestion });
}

/// Read NDK version from source.properties file
pub fn readNdkVersion(allocator: std.mem.Allocator, ndk_path: []const u8) !?u8 {
    const props_path = try std.fmt.allocPrint(allocator, "{s}/source.properties", .{ndk_path});
    defer allocator.free(props_path);

    const file = std.fs.openFileAbsolute(props_path, .{}) catch return null;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(content);

    return parseNdkVersion(content);
}

/// Find highest available API level in SDK platforms
pub fn findHighestApiLevel(allocator: std.mem.Allocator, sdk_path: []const u8) !?u8 {
    const platforms_path = try std.fmt.allocPrint(allocator, "{s}/platforms", .{sdk_path});
    defer allocator.free(platforms_path);

    return findHighestVersion(allocator, platforms_path, parseApiLevel);
}

/// Find highest API level supported by NDK (aarch64 libraries)
pub fn findHighestNdkApiLevel(allocator: std.mem.Allocator, ndk_path: []const u8) !?u8 {
    const lib_path = try std.fmt.allocPrint(allocator, "{s}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android", .{ndk_path});
    defer allocator.free(lib_path);

    return findHighestVersion(allocator, lib_path, parseMajorVersion);
}

/// Information about a discovered NDK
pub const NdkInfo = struct {
    path: []const u8,
    version: ?u8,
    max_api: ?u8,
};

/// Scan SDK_ROOT for installed NDKs
pub fn discoverNdks(allocator: std.mem.Allocator, sdk_path: []const u8) ![]NdkInfo {
    var ndks: std.ArrayListUnmanaged(NdkInfo) = .{};

    // Check $SDK_ROOT/ndk/ directory for versioned NDKs
    const ndk_dir_path = try std.fmt.allocPrint(allocator, "{s}/ndk", .{sdk_path});
    defer allocator.free(ndk_dir_path);

    if (pathExists(ndk_dir_path)) {
        var dir = std.fs.openDirAbsolute(ndk_dir_path, .{ .iterate = true }) catch null;
        if (dir) |*d| {
            defer d.close();
            var iter = d.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .directory) {
                    const ndk_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ ndk_dir_path, entry.name });
                    const version = try readNdkVersion(allocator, ndk_path);
                    const max_api = try findHighestNdkApiLevel(allocator, ndk_path);
                    try ndks.append(allocator, .{
                        .path = ndk_path,
                        .version = version,
                        .max_api = max_api,
                    });
                }
            }
        }
    }

    // Check $SDK_ROOT/ndk-bundle (legacy location)
    const ndk_bundle_path = try std.fmt.allocPrint(allocator, "{s}/ndk-bundle", .{sdk_path});
    if (pathExists(ndk_bundle_path)) {
        const version = try readNdkVersion(allocator, ndk_bundle_path);
        const max_api = try findHighestNdkApiLevel(allocator, ndk_bundle_path);
        try ndks.append(allocator, .{
            .path = ndk_bundle_path,
            .version = version,
            .max_api = max_api,
        });
    } else {
        allocator.free(ndk_bundle_path);
    }

    return ndks.toOwnedSlice(allocator);
}

/// Format NDK info for display
pub fn formatNdkInfo(allocator: std.mem.Allocator, ndk: NdkInfo) ![]const u8 {
    const version_str = if (ndk.version) |v| try std.fmt.allocPrint(allocator, "r{d}", .{v}) else try allocator.dupe(u8, "unknown");
    defer allocator.free(version_str);

    const api_str = if (ndk.max_api) |a| try std.fmt.allocPrint(allocator, "API {d}", .{a}) else try allocator.dupe(u8, "no aarch64 libs");
    defer allocator.free(api_str);

    return std.fmt.allocPrint(allocator, "  {s} (version {s}, max {s})", .{ ndk.path, version_str, api_str });
}

/// Check if required build tools exist
pub fn checkBuildTools(allocator: std.mem.Allocator, sdk_path: []const u8, version: []const u8) !bool {
    const tools = [_][]const u8{ "aapt2", "d8", "zipalign", "apksigner" };

    for (tools) |tool| {
        const tool_path = try std.fmt.allocPrint(allocator, "{s}/build-tools/{s}/{s}", .{ sdk_path, version, tool });
        defer allocator.free(tool_path);

        if (!fileExists(tool_path)) {
            return false;
        }
    }
    return true;
}

/// Check if NDK has required components for aarch64
pub fn checkNdkComponents(allocator: std.mem.Allocator, ndk_path: []const u8, api_level: u8) !bool {
    // Check JNI headers
    const jni_path = try std.fmt.allocPrint(allocator, "{s}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/jni.h", .{ndk_path});
    defer allocator.free(jni_path);

    if (!fileExists(jni_path)) return false;

    // Check aarch64 libraries for the API level
    const lib_path = try std.fmt.allocPrint(allocator, "{s}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/{d}", .{ ndk_path, api_level });
    defer allocator.free(lib_path);

    return pathExists(lib_path);
}

// ============================================================================
// TESTS - Written FIRST per Claude.md methodology
// ============================================================================

test "parseMajorVersion parses standard version strings" {
    try std.testing.expectEqual(@as(?u8, 35), parseMajorVersion("35.0.0"));
    try std.testing.expectEqual(@as(?u8, 34), parseMajorVersion("34.0.0"));
    try std.testing.expectEqual(@as(?u8, 30), parseMajorVersion("30.0.3"));
    try std.testing.expectEqual(@as(?u8, 27), parseMajorVersion("27"));
}

test "parseMajorVersion returns null for invalid input" {
    try std.testing.expectEqual(@as(?u8, null), parseMajorVersion(""));
    try std.testing.expectEqual(@as(?u8, null), parseMajorVersion("abc"));
    try std.testing.expectEqual(@as(?u8, null), parseMajorVersion(".0.0"));
}

test "parseNdkVersion extracts version from properties content" {
    const content =
        \\Pkg.Desc = Android NDK
        \\Pkg.Revision = 27.0.12077973
    ;
    try std.testing.expectEqual(@as(?u8, 27), parseNdkVersion(content));
}

test "parseNdkVersion handles different formats" {
    const content1 = "Pkg.Revision = 25.2.9519653";
    try std.testing.expectEqual(@as(?u8, 25), parseNdkVersion(content1));

    const content2 = "Pkg.Revision=26.1.10909125";
    try std.testing.expectEqual(@as(?u8, 26), parseNdkVersion(content2));
}

test "parseNdkVersion returns null for missing revision" {
    const content = "Pkg.Desc = Android NDK";
    try std.testing.expectEqual(@as(?u8, null), parseNdkVersion(content));
}

test "parseApiLevel parses android platform directories" {
    try std.testing.expectEqual(@as(?u8, 35), parseApiLevel("android-35"));
    try std.testing.expectEqual(@as(?u8, 26), parseApiLevel("android-26"));
    try std.testing.expectEqual(@as(?u8, 11), parseApiLevel("android-11"));
}

test "parseApiLevel returns null for invalid format" {
    try std.testing.expectEqual(@as(?u8, null), parseApiLevel("platform-30"));
    try std.testing.expectEqual(@as(?u8, null), parseApiLevel("android-"));
    try std.testing.expectEqual(@as(?u8, null), parseApiLevel(""));
}

test "pathExists returns false for non-existent paths" {
    try std.testing.expect(!pathExists("/this/path/does/not/exist/12345"));
}

test "pathExists handles empty and relative paths" {
    try std.testing.expect(!pathExists(""));
    try std.testing.expect(!pathExists("relative/path"));
}

test "fileExists returns false for non-existent files" {
    try std.testing.expect(!fileExists("/this/file/does/not/exist/12345.txt"));
}

test "fileExists handles empty and relative paths" {
    try std.testing.expect(!fileExists(""));
    try std.testing.expect(!fileExists("relative/file.txt"));
}

test "minimum version constants are reasonable" {
    // These tests document our minimum requirements
    try std.testing.expect(MIN_API_LEVEL >= 21); // Android 5.0 Lollipop minimum
    try std.testing.expect(MIN_API_LEVEL <= 30); // Not too restrictive
    try std.testing.expect(MIN_NDK_MAJOR >= 21); // NDK r21 minimum (LTS)
    try std.testing.expect(MIN_BUILD_TOOLS_MAJOR >= 28); // Reasonable minimum
}

test "ValidationResult.hasErrors returns correct state" {
    const no_errors = ValidationResult{
        .sdk_path = "/sdk",
        .ndk_path = "/ndk",
        .build_tools_version = "35.0.0",
        .api_level = 35,
        .errors = &[_]ValidationError{},
    };
    try std.testing.expect(!no_errors.hasErrors());

    var errors = [_]ValidationError{.{
        .component = "SDK",
        .message = "Not found",
        .suggestion = "Install it",
    }};
    const with_errors = ValidationResult{
        .sdk_path = "",
        .ndk_path = "",
        .build_tools_version = "",
        .api_level = 0,
        .errors = &errors,
    };
    try std.testing.expect(with_errors.hasErrors());
}

test "formatError produces readable output" {
    const allocator = std.testing.allocator;
    const err = ValidationError{
        .component = "Android SDK",
        .message = "Not found at /opt/android-sdk",
        .suggestion = "Set ANDROID_SDK_ROOT environment variable",
    };

    const output = try formatError(allocator, err);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Android SDK") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ANDROID_SDK_ROOT") != null);
}

test "checkBuildTools returns false for non-existent path" {
    const allocator = std.testing.allocator;
    const result = try checkBuildTools(allocator, "/nonexistent/sdk", "35.0.0");
    try std.testing.expect(!result);
}

test "checkNdkComponents returns false for non-existent path" {
    const allocator = std.testing.allocator;
    const result = try checkNdkComponents(allocator, "/nonexistent/ndk", 35);
    try std.testing.expect(!result);
}

test "findHighestNdkApiLevel returns null for non-existent path" {
    const allocator = std.testing.allocator;
    const result = try findHighestNdkApiLevel(allocator, "/nonexistent/ndk");
    try std.testing.expectEqual(@as(?u8, null), result);
}

test "discoverNdks returns empty for non-existent SDK" {
    const allocator = std.testing.allocator;
    const result = try discoverNdks(allocator, "/nonexistent/sdk");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}
