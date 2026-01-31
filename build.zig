const std = @import("std");
const prereq = @import("src/prereq.zig");

const AndroidConfig = struct {
    sdk_path: []const u8,
    ndk_path: []const u8,
    build_tools_version: []const u8,
    api_level: u8,
    min_sdk: u8,
    target_sdk: u8,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // Generate build number
    const build_number_step = generateBuildNumber(b);

    // Resolve paths from options, environment, or defaults
    const sdk_path = b.option([]const u8, "android-sdk", "Android SDK path") orelse
        getEnvOrDefault(b.allocator, "ANDROID_SDK_ROOT", null) orelse
        getEnvOrDefault(b.allocator, "ANDROID_HOME", null) orelse
        "/opt/android-sdk";

    const ndk_path = b.option([]const u8, "android-ndk", "Android NDK path") orelse
        getEnvOrDefault(b.allocator, "ANDROID_NDK_ROOT", null) orelse
        b.fmt("{s}/ndk-bundle", .{sdk_path});

    // Get min SDK option once
    const min_sdk = b.option(u8, "min-sdk", "Minimum SDK version") orelse prereq.MIN_API_LEVEL;

    // Validate prerequisites and auto-detect versions
    const validation = validateAndConfigure(b.allocator, sdk_path, ndk_path, .{
        .build_tools = b.option([]const u8, "build-tools", "Build tools version (auto-detected if not specified)"),
        .api_level = b.option(u8, "api-level", "Target API level (auto-detected if not specified)"),
        .min_sdk = min_sdk,
    }) catch |err| {
        std.debug.print("Configuration error: {}\n", .{err});
        return;
    };

    if (validation.hasErrors()) {
        printValidationErrors(b.allocator, validation);
        return;
    }

    const android_config = AndroidConfig{
        .sdk_path = validation.sdk_path,
        .ndk_path = validation.ndk_path,
        .build_tools_version = validation.build_tools_version,
        .api_level = validation.api_level,
        .min_sdk = min_sdk,
        .target_sdk = validation.api_level,
    };

    // Prerequisite checks step (for explicit validation)
    const check_step = b.step("check", "Check prerequisites");
    const check_cmd = b.addSystemCommand(&.{"echo"});
    check_cmd.addArg(b.fmt("Prerequisites OK: SDK={s}, NDK={s}, build-tools={s}, API={d}", .{
        android_config.sdk_path,
        android_config.ndk_path,
        android_config.build_tools_version,
        android_config.api_level,
    }));
    check_step.dependOn(&check_cmd.step);

    // Native library
    const target_query = std.Target.Query{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .android,
        .cpu_features_add = std.Target.aarch64.featureSet(&.{.v8a}),
    };
    const resolved_target = b.resolveTargetQuery(target_query);

    const lib = b.addLibrary(.{
        .name = "helloworld",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = resolved_target,
            .optimize = optimize,
        }),
    });

    // Make sure build number is generated before library compilation
    lib.step.dependOn(&build_number_step.step);

    // Generate android-libc.conf dynamically based on detected configuration
    const libc_conf_path = generateLibcConfig(b, android_config) catch |err| {
        std.debug.print("\n", .{});
        std.debug.print("=" ** 70 ++ "\n", .{});
        std.debug.print("LIBC CONFIGURATION ERROR\n", .{});
        std.debug.print("=" ** 70 ++ "\n", .{});
        std.debug.print("Failed to generate android-libc.conf: {}\n", .{err});
        std.debug.print("\nThis usually means the NDK paths don't exist:\n", .{});
        std.debug.print("  NDK: {s}\n", .{android_config.ndk_path});
        std.debug.print("  API: {d}\n", .{android_config.api_level});
        std.debug.print("=" ** 70 ++ "\n\n", .{});
        return;
    };
    lib.setLibCFile(libc_conf_path);

    // Add Android NDK include directories for JNI headers
    const ndk_include = b.fmt("{s}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include", .{android_config.ndk_path});
    lib.addIncludePath(.{ .cwd_relative = ndk_include });

    // Add library search paths for Android libraries (use configured API level)
    const ndk_lib_path = b.fmt("{s}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/{d}", .{ android_config.ndk_path, android_config.api_level });
    lib.addLibraryPath(.{ .cwd_relative = ndk_lib_path });

    // Link system libraries
    lib.linkSystemLibrary("c");
    lib.linkSystemLibrary("android");
    lib.linkSystemLibrary("log");

    // Java compilation
    const java_step = b.step("java", "Compile Java sources");
    const java_compile = addJavaCompilation(b, android_config);
    java_step.dependOn(&java_compile.step);

    // Resources
    const res_step = b.step("resources", "Compile resources");
    const res_compile = addResourceCompilation(b, android_config);
    res_step.dependOn(&res_compile.step);

    // DEX compilation
    const dex_step = b.step("dex", "Compile to DEX");
    const dex_compile = addDexCompilation(b, android_config);
    dex_compile.step.dependOn(java_step);
    dex_step.dependOn(&dex_compile.step);

    // Install the library for APK packaging (must happen before APK build)
    const install_lib = b.addInstallArtifact(lib, .{});

    // APK packaging
    const apk_step = b.step("apk", "Build APK");
    const apk_build = addApkPackaging(b, android_config, res_compile, dex_compile, &install_lib.step);
    apk_step.dependOn(&apk_build.step);

    // APK signing
    const sign_step = b.step("sign", "Sign APK");
    const sign_apk = addApkSigning(b, android_config, apk_build);
    sign_step.dependOn(&sign_apk.step);

    // Success message after signing
    const success_msg = b.addSystemCommand(&.{ "sh", "-c",
        \\echo ""
        \\echo "=========================================="
        \\echo "BUILD SUCCESSFUL"
        \\echo "=========================================="
        \\echo "APK: build/helloworld.apk"
        \\echo ""
        \\echo "To install on connected device:"
        \\echo "  adb install -r build/helloworld.apk"
        \\echo ""
        \\echo "To install and launch:"
        \\echo "  zig build deploy"
        \\echo "  adb shell am start -n com.zig.helloworld/.MainActivity"
        \\echo "=========================================="
    });
    success_msg.step.dependOn(&sign_apk.step);

    // Health checks
    const test_step = b.step("test", "Run health checks");
    const health_checks = addHealthChecks(b, android_config);
    health_checks.step.dependOn(sign_step);
    test_step.dependOn(&health_checks.step);

    // Deploy
    const deploy_step = b.step("deploy", "Install APK to device");
    const install_apk = addApkInstall(b, android_config);
    install_apk.step.dependOn(sign_step);
    deploy_step.dependOn(&install_apk.step);

    // Library-only step for testing
    const lib_step = b.step("lib", "Build native library only");
    lib_step.dependOn(&lib.step);

    // Default build target
    b.default_step.dependOn(&success_msg.step);
}

fn getEnvOrDefault(allocator: std.mem.Allocator, env_var: []const u8, default: ?[]const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(allocator, env_var) catch return default;
}

fn generateLibcConfig(b: *std.Build, config: AndroidConfig) !std.Build.LazyPath {
    const ndk_sysroot = b.fmt("{s}/toolchains/llvm/prebuilt/linux-x86_64/sysroot", .{config.ndk_path});
    const include_dir = b.fmt("{s}/usr/include", .{ndk_sysroot});
    const crt_dir = b.fmt("{s}/usr/lib/aarch64-linux-android/{d}", .{ ndk_sysroot, config.api_level });

    // Validate paths exist
    if (!prereq.pathExists(include_dir)) {
        std.debug.print("ERROR: NDK include directory not found: {s}\n", .{include_dir});
        return error.NdkIncludeNotFound;
    }
    if (!prereq.pathExists(crt_dir)) {
        std.debug.print("ERROR: NDK CRT directory not found: {s}\n", .{crt_dir});
        std.debug.print("       This means NDK doesn't have libraries for API {d}\n", .{config.api_level});

        // Try to find what API levels are available
        const ndk_lib_base = b.fmt("{s}/usr/lib/aarch64-linux-android", .{ndk_sysroot});
        if (prereq.findHighestNdkApiLevel(b.allocator, config.ndk_path) catch null) |max_api| {
            std.debug.print("       NDK supports up to API {d}\n", .{max_api});
            std.debug.print("       Try: zig build -Dapi-level={d}\n", .{max_api});
        } else {
            std.debug.print("       NDK lib directory: {s}\n", .{ndk_lib_base});
        }
        return error.NdkCrtNotFound;
    }

    // Generate the config content
    const config_content = b.fmt(
        \\# Auto-generated Android NDK libc configuration
        \\# Target: aarch64-linux-android API {d}
        \\# NDK: {s}
        \\
        \\include_dir={s}
        \\sys_include_dir={s}
        \\crt_dir={s}
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\gcc_dir=
        \\
    , .{ config.api_level, config.ndk_path, include_dir, include_dir, crt_dir });

    // Write to build directory
    const wf = b.addWriteFiles();
    return wf.add("android-libc.conf", config_content);
}

const ConfigOptions = struct {
    build_tools: ?[]const u8,
    api_level: ?u8,
    min_sdk: u8,
};

fn validateAndConfigure(allocator: std.mem.Allocator, sdk_path: []const u8, ndk_path: []const u8, opts: ConfigOptions) !prereq.ValidationResult {
    var errors: std.ArrayListUnmanaged(prereq.ValidationError) = .{};

    // Validate SDK path exists
    if (!prereq.pathExists(sdk_path)) {
        try errors.append(allocator, .{
            .component = "Android SDK",
            .message = std.fmt.allocPrint(allocator, "Not found at: {s}", .{sdk_path}) catch "Not found",
            .suggestion = "Set ANDROID_SDK_ROOT or ANDROID_HOME environment variable, or use -Dandroid-sdk=<path>",
        });
        return .{
            .sdk_path = sdk_path,
            .ndk_path = ndk_path,
            .build_tools_version = "",
            .api_level = 0,
            .errors = try errors.toOwnedSlice(allocator),
        };
    }

    // Validate NDK path exists
    if (!prereq.pathExists(ndk_path)) {
        try errors.append(allocator, .{
            .component = "Android NDK",
            .message = std.fmt.allocPrint(allocator, "Not found at: {s}", .{ndk_path}) catch "Not found",
            .suggestion = "Set ANDROID_NDK_ROOT environment variable, or use -Dandroid-ndk=<path>\n         Install with: sdkmanager --install \"ndk;27.0.12077973\"",
        });
    }

    // Check NDK version if path exists
    if (prereq.pathExists(ndk_path)) {
        if (try prereq.readNdkVersion(allocator, ndk_path)) |ndk_version| {
            if (ndk_version < prereq.MIN_NDK_MAJOR) {
                try errors.append(allocator, .{
                    .component = "Android NDK Version",
                    .message = std.fmt.allocPrint(allocator, "Version {d} is below minimum required ({d})", .{ ndk_version, prereq.MIN_NDK_MAJOR }) catch "Version too old",
                    .suggestion = "Update NDK: sdkmanager --install \"ndk;27.0.12077973\"",
                });
            }
        }
    }

    // Auto-detect or validate build-tools version
    var build_tools_version: []const u8 = "";
    if (opts.build_tools) |bt| {
        // User specified version - validate it exists
        const bt_path = try std.fmt.allocPrint(allocator, "{s}/build-tools/{s}", .{ sdk_path, bt });
        defer allocator.free(bt_path);
        if (!prereq.pathExists(bt_path)) {
            try errors.append(allocator, .{
                .component = "Build Tools",
                .message = std.fmt.allocPrint(allocator, "Version {s} not found", .{bt}) catch "Not found",
                .suggestion = std.fmt.allocPrint(allocator, "Install with: sdkmanager --install \"build-tools;{s}\"", .{bt}) catch "Install required version",
            });
        } else {
            build_tools_version = bt;
        }
    } else {
        // Auto-detect highest available version
        if (try prereq.findHighestBuildTools(allocator, sdk_path)) |bt| {
            if (prereq.parseMajorVersion(bt)) |major| {
                if (major < prereq.MIN_BUILD_TOOLS_MAJOR) {
                    try errors.append(allocator, .{
                        .component = "Build Tools",
                        .message = std.fmt.allocPrint(allocator, "Highest available version ({s}) is below minimum ({d}.0.0)", .{ bt, prereq.MIN_BUILD_TOOLS_MAJOR }) catch "Version too old",
                        .suggestion = "Install newer build-tools: sdkmanager --install \"build-tools;35.0.0\"",
                    });
                }
            }
            build_tools_version = bt;
        } else {
            try errors.append(allocator, .{
                .component = "Build Tools",
                .message = "No build-tools found in SDK",
                .suggestion = "Install with: sdkmanager --install \"build-tools;35.0.0\"",
            });
        }
    }

    // Auto-detect or validate API level
    var api_level: u8 = opts.api_level orelse 0;
    if (opts.api_level) |level| {
        // User specified level - validate it exists
        const platform_path = try std.fmt.allocPrint(allocator, "{s}/platforms/android-{d}", .{ sdk_path, level });
        defer allocator.free(platform_path);
        if (!prereq.pathExists(platform_path)) {
            try errors.append(allocator, .{
                .component = "Android Platform",
                .message = std.fmt.allocPrint(allocator, "API level {d} not found", .{level}) catch "Not found",
                .suggestion = std.fmt.allocPrint(allocator, "Install with: sdkmanager --install \"platforms;android-{d}\"", .{level}) catch "Install required platform",
            });
        }
    } else {
        // Auto-detect API level considering both SDK platforms and NDK support
        const sdk_api = try prereq.findHighestApiLevel(allocator, sdk_path);
        const ndk_api = if (prereq.pathExists(ndk_path))
            try prereq.findHighestNdkApiLevel(allocator, ndk_path)
        else
            null;

        // Get NDK version for diagnostics
        const ndk_version = if (prereq.pathExists(ndk_path))
            try prereq.readNdkVersion(allocator, ndk_path)
        else
            null;

        if (sdk_api == null) {
            try errors.append(allocator, .{
                .component = "Android Platform",
                .message = "No platforms found in SDK",
                .suggestion = "Install with: sdkmanager --install \"platforms;android-35\"",
            });
        } else if (ndk_api == null and prereq.pathExists(ndk_path)) {
            // NDK exists but has no aarch64 libraries
            const version_info = if (ndk_version) |v|
                std.fmt.allocPrint(allocator, "NDK r{d}", .{v}) catch "NDK"
            else
                std.fmt.allocPrint(allocator, "NDK (version unknown)", .{}) catch "NDK";

            try errors.append(allocator, .{
                .component = "NDK aarch64 Libraries",
                .message = std.fmt.allocPrint(allocator, "{s} has no aarch64-linux-android libraries", .{version_info}) catch "No aarch64 libraries found",
                .suggestion = "The NDK may be incomplete or corrupted. Reinstall with:\n         sdkmanager --install \"ndk;27.2.12479018\"",
            });
            api_level = sdk_api.?; // Use SDK level for reporting
        } else if (ndk_api == null) {
            // NDK doesn't exist - already reported above
            api_level = sdk_api orelse 0;
        } else {
            // Both SDK and NDK have valid API levels
            const effective_level = @min(sdk_api.?, ndk_api.?);
            if (effective_level < opts.min_sdk) {
                try errors.append(allocator, .{
                    .component = "API Level",
                    .message = std.fmt.allocPrint(allocator, "Effective API level ({d}) is below minimum SDK ({d})", .{ effective_level, opts.min_sdk }) catch "API level too low",
                    .suggestion = std.fmt.allocPrint(allocator, "SDK highest: {d}, NDK highest: {d}. Update NDK or use -Dmin-sdk={d}", .{ sdk_api.?, ndk_api.?, effective_level }) catch "Update SDK and NDK, or lower minimum SDK requirement",
                });
            }
            api_level = effective_level;

            // Inform user if NDK limited the API level
            if (sdk_api.? > ndk_api.?) {
                std.debug.print("Note: SDK has API {d}, but NDK only supports up to API {d}. Using API {d}.\n", .{ sdk_api.?, ndk_api.?, effective_level });
            }
        }
    }

    // Verify NDK has required components for the selected API level (only if we have a valid NDK with libraries)
    if (prereq.pathExists(ndk_path) and api_level > 0) {
        const ndk_max_api = try prereq.findHighestNdkApiLevel(allocator, ndk_path);
        if (ndk_max_api != null and !try prereq.checkNdkComponents(allocator, ndk_path, api_level)) {
            try errors.append(allocator, .{
                .component = "NDK Components",
                .message = std.fmt.allocPrint(allocator, "NDK missing aarch64 libraries for API {d} (NDK supports up to API {d})", .{ api_level, ndk_max_api.? }) catch "Missing libraries",
                .suggestion = std.fmt.allocPrint(allocator, "Use -Dapi-level={d} or lower", .{ndk_max_api.?}) catch "Use a lower API level",
            });
        }
    }

    // Check build tools have required executables
    if (build_tools_version.len > 0) {
        if (!try prereq.checkBuildTools(allocator, sdk_path, build_tools_version)) {
            try errors.append(allocator, .{
                .component = "Build Tools",
                .message = std.fmt.allocPrint(allocator, "Missing required tools in {s}", .{build_tools_version}) catch "Missing tools",
                .suggestion = "Reinstall build-tools or try a different version",
            });
        }
    }

    return .{
        .sdk_path = sdk_path,
        .ndk_path = ndk_path,
        .build_tools_version = build_tools_version,
        .api_level = api_level,
        .errors = try errors.toOwnedSlice(allocator),
    };
}

fn printValidationErrors(allocator: std.mem.Allocator, validation: prereq.ValidationResult) void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("BUILD CONFIGURATION ERRORS\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});

    for (validation.errors) |err| {
        const formatted = prereq.formatError(allocator, err) catch {
            std.debug.print("Error: {s} - {s}\n", .{ err.component, err.message });
            continue;
        };
        std.debug.print("{s}", .{formatted});
    }

    std.debug.print("-" ** 70 ++ "\n", .{});
    std.debug.print("Detected configuration:\n", .{});
    std.debug.print("  SDK path: {s}\n", .{if (validation.sdk_path.len > 0) validation.sdk_path else "(not found)"});
    std.debug.print("  NDK path: {s}\n", .{if (validation.ndk_path.len > 0) validation.ndk_path else "(not found)"});
    std.debug.print("  Build tools: {s}\n", .{if (validation.build_tools_version.len > 0) validation.build_tools_version else "(not found)"});
    std.debug.print("  API level: {d}\n", .{validation.api_level});

    // Show environment variables
    std.debug.print("\nEnvironment variables:\n", .{});
    const env_sdk = std.process.getEnvVarOwned(allocator, "ANDROID_SDK_ROOT") catch null;
    const env_home = std.process.getEnvVarOwned(allocator, "ANDROID_HOME") catch null;
    const env_ndk = std.process.getEnvVarOwned(allocator, "ANDROID_NDK_ROOT") catch null;

    std.debug.print("  ANDROID_SDK_ROOT: {s}\n", .{env_sdk orelse "(not set)"});
    if (env_home) |h| {
        std.debug.print("  ANDROID_HOME: {s}\n", .{h});
        allocator.free(h);
    }
    std.debug.print("  ANDROID_NDK_ROOT: {s}\n", .{env_ndk orelse "(not set)"});

    if (env_sdk) |s| allocator.free(s);
    if (env_ndk) |n| allocator.free(n);

    // Discover and show NDKs installed under SDK_ROOT
    if (validation.sdk_path.len > 0 and prereq.pathExists(validation.sdk_path)) {
        std.debug.print("\nNDKs found in SDK:\n", .{});
        const discovered = prereq.discoverNdks(allocator, validation.sdk_path) catch &[_]prereq.NdkInfo{};

        if (discovered.len == 0) {
            std.debug.print("  (none found)\n", .{});
            std.debug.print("\n  Install an NDK with:\n", .{});
            std.debug.print("    sdkmanager --install \"ndk;27.2.12479018\"\n", .{});
        } else {
            for (discovered) |ndk| {
                const info = prereq.formatNdkInfo(allocator, ndk) catch "  (error formatting)";
                std.debug.print("{s}\n", .{info});
            }

            // Suggest setting NDK_ROOT if it's not pointing to one of the discovered NDKs
            const current_ndk = validation.ndk_path;
            var found_match = false;
            var best_ndk: ?prereq.NdkInfo = null;

            for (discovered) |ndk| {
                if (std.mem.eql(u8, ndk.path, current_ndk)) {
                    found_match = true;
                }
                // Track the best NDK (highest version with aarch64 libs)
                if (ndk.max_api != null) {
                    if (best_ndk == null or (ndk.version orelse 0) > (best_ndk.?.version orelse 0)) {
                        best_ndk = ndk;
                    }
                }
            }

            if (!found_match and best_ndk != null) {
                std.debug.print("\n  Suggestion: Set ANDROID_NDK_ROOT to use an installed NDK:\n", .{});
                std.debug.print("    export ANDROID_NDK_ROOT={s}\n", .{best_ndk.?.path});
            }
        }
    }

    std.debug.print("=" ** 70 ++ "\n\n", .{});
}

fn addJavaCompilation(b: *std.Build, config: AndroidConfig) *std.Build.Step.Run {
    const android_jar = b.fmt("{s}/platforms/android-{d}/android.jar", .{ config.sdk_path, config.api_level });
    
    const javac = b.addSystemCommand(&.{
        "javac",
        "-d", "build/classes",
        "-cp", android_jar,
        "-sourcepath", "android",
        "-Xlint:-options",
        "-source", "11",
        "-target", "11",
        "android/MainActivity.java"
    });
    
    const mkdir = b.addSystemCommand(&.{"mkdir", "-p", "build/classes"});
    javac.step.dependOn(&mkdir.step);
    
    return javac;
}

fn addResourceCompilation(b: *std.Build, config: AndroidConfig) *std.Build.Step.Run {
    const aapt2 = b.fmt("{s}/build-tools/{s}/aapt2", .{ config.sdk_path, config.build_tools_version });
    
    // Create resources directory structure
    const mkdir_res = b.addSystemCommand(&.{"mkdir", "-p", "build/res/layout", "build/res/values"});
    
    // Copy layout file
    const copy_layout = b.addSystemCommand(&.{"cp", "src/ui.xml", "build/res/layout/activity_main.xml"});
    copy_layout.step.dependOn(&mkdir_res.step);
    
    // Create strings.xml
    const strings_xml = b.addSystemCommand(&.{"sh", "-c", 
        \\echo '<?xml version="1.0" encoding="utf-8"?><resources><string name="app_name">Zig Hello World</string></resources>' > build/res/values/strings.xml
    });
    strings_xml.step.dependOn(&mkdir_res.step);
    
    // Compile resources
    const aapt_compile = b.addSystemCommand(&.{
        aapt2, "compile",
        "--dir", "build/res",
        "-o", "build/compiled_res.zip"
    });
    aapt_compile.step.dependOn(&copy_layout.step);
    aapt_compile.step.dependOn(&strings_xml.step);
    
    // Link resources
    const android_jar = b.fmt("{s}/platforms/android-{d}/android.jar", .{ config.sdk_path, config.api_level });
    const aapt_link = b.addSystemCommand(&.{
        aapt2, "link",
        "-I", android_jar,
        "-o", "build/resources.apk",
        "--manifest", "android/Manifest.xml",
        "--min-sdk-version", b.fmt("{d}", .{config.min_sdk}),
        "--target-sdk-version", b.fmt("{d}", .{config.target_sdk}),
        "build/compiled_res.zip"
    });
    aapt_link.step.dependOn(&aapt_compile.step);
    
    return aapt_link;
}

fn addDexCompilation(b: *std.Build, config: AndroidConfig) *std.Build.Step.Run {
    const d8 = b.fmt("{s}/build-tools/{s}/d8", .{ config.sdk_path, config.build_tools_version });
    const android_jar = b.fmt("{s}/platforms/android-{d}/android.jar", .{ config.sdk_path, config.api_level });

    const dex_cmd = b.addSystemCommand(&.{
        d8,
        "--lib", android_jar,
        "--output", "build/",
        "build/classes/com/zig/helloworld/MainActivity.class"
    });

    return dex_cmd;
}

fn addApkPackaging(b: *std.Build, config: AndroidConfig, res_step: *std.Build.Step.Run, dex_step: *std.Build.Step.Run, lib_install_step: *std.Build.Step) *std.Build.Step.Run {
    _ = config;

    // Create APK directory structure
    const mkdir = b.addSystemCommand(&.{"mkdir", "-p", "build/apk/lib/arm64-v8a"});

    // Copy native library (must wait for library to be installed)
    const copy_lib = b.addSystemCommand(&.{"cp", "zig-out/lib/libhelloworld.so", "build/apk/lib/arm64-v8a/"});
    copy_lib.step.dependOn(&mkdir.step);
    copy_lib.step.dependOn(lib_install_step);
    
    // Extract resources (depends on resources step)
    const extract_res = b.addSystemCommand(&.{"unzip", "-o", "build/resources.apk", "-d", "build/apk/"});
    extract_res.step.dependOn(&mkdir.step);
    extract_res.step.dependOn(&res_step.step);
    
    // Copy DEX (depends on dex step)
    const copy_dex = b.addSystemCommand(&.{"cp", "build/classes.dex", "build/apk/"});
    copy_dex.step.dependOn(&extract_res.step);
    copy_dex.step.dependOn(&dex_step.step);
    
    // Package APK with uncompressed resources.arsc for Android R+ compatibility
    const zip_apk = b.addSystemCommand(&.{"sh", "-c", "cd build/apk && zip -r ../helloworld-unsigned.apk . -0 resources.arsc"});
    zip_apk.step.dependOn(&copy_lib.step);
    zip_apk.step.dependOn(&copy_dex.step);
    
    return zip_apk;
}

fn addApkSigning(b: *std.Build, config: AndroidConfig, apk_step: *std.Build.Step.Run) *std.Build.Step.Run {
    const zipalign = b.fmt("{s}/build-tools/{s}/zipalign", .{ config.sdk_path, config.build_tools_version });
    const apksigner = b.fmt("{s}/build-tools/{s}/apksigner", .{ config.sdk_path, config.build_tools_version });
    const home_dir = getHomeDir(b.allocator);
    const keystore_path = b.fmt("{s}/.android/debug.keystore", .{home_dir});
    
    // Align APK (depends on APK packaging completing)
    const align_cmd = b.addSystemCommand(&.{
        zipalign, "-f", "4",
        "build/helloworld-unsigned.apk",
        "build/helloworld-aligned.apk"
    });
    align_cmd.step.dependOn(&apk_step.step);
    
    // Create keystore if it doesn't exist
    const create_keystore = b.addSystemCommand(&.{"sh", "-c"});
    create_keystore.addArg(b.fmt(
        \\test -f '{s}' || keytool -genkey -v -keystore '{s}' -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    , .{ keystore_path, keystore_path }));
    
    // Sign APK (debug key)
    const sign_cmd = b.addSystemCommand(&.{
        apksigner, "sign",
        "--ks-type", "jks",
        "--ks", keystore_path,
        "--ks-pass", "pass:android",
        "--key-pass", "pass:android",
        "--out", "build/helloworld.apk",
        "build/helloworld-aligned.apk"
    });
    sign_cmd.step.dependOn(&align_cmd.step);
    sign_cmd.step.dependOn(&create_keystore.step);
    
    return sign_cmd;
}

fn addHealthChecks(b: *std.Build, config: AndroidConfig) *std.Build.Step.Run {
    const aapt = b.fmt("{s}/build-tools/{s}/aapt", .{ config.sdk_path, config.build_tools_version });
    
    // Check APK exists
    const check_apk = b.addSystemCommand(&.{"sh", "-c"});
    check_apk.addArg("test -f build/helloworld.apk || (echo 'Error: Signed APK not found' >&2 && exit 1)");
    
    // Verify APK structure
    const verify_cmd = b.addSystemCommand(&.{
        aapt, "dump", "badging", "build/helloworld.apk"
    });
    verify_cmd.step.dependOn(&check_apk.step);
    
    // Check APK signature
    const verify_sig = b.addSystemCommand(&.{
        b.fmt("{s}/build-tools/{s}/apksigner", .{ config.sdk_path, config.build_tools_version }),
        "verify", "build/helloworld.apk"
    });
    verify_sig.step.dependOn(&verify_cmd.step);
    
    // Check APK contents
    const check_contents = b.addSystemCommand(&.{"sh", "-c"});
    check_contents.addArg("unzip -l build/helloworld.apk | grep -E '(classes.dex|libhelloworld.so|AndroidManifest.xml)' | wc -l | grep -q '^3$' || (echo 'Error: APK missing required components' >&2 && exit 1)");
    check_contents.step.dependOn(&verify_sig.step);
    
    return check_contents;
}

fn addApkInstall(b: *std.Build, config: AndroidConfig) *std.Build.Step.Run {
    const adb = b.fmt("{s}/platform-tools/adb", .{config.sdk_path});
    
    const install_cmd = b.addSystemCommand(&.{
        adb, "install", "-r", "build/helloworld.apk"
    });
    
    return install_cmd;
}

fn getHomeDir(allocator: std.mem.Allocator) []const u8 {
    return std.process.getEnvVarOwned(allocator, "HOME") catch "/home/user";
}

fn generateBuildNumber(b: *std.Build) *std.Build.Step.Run {
    // Import build_info functions
    const build_info = @import("src/build_info.zig");

    const build_number = build_info.readBuildNumber(b.allocator) catch 1;
    const new_build_number = build_number + 1;

    // Write the new build number back to file
    build_info.writeBuildNumber(b.allocator, new_build_number) catch {};

    // Get current timestamp and format it
    const timestamp = std.time.timestamp();
    const formatted_date = build_info.formatTimestamp(b.allocator, timestamp);

    // Create the build_number.zig file content directly in source directory
    const build_content = b.fmt(
        \\pub const build_number: u32 = {d};
        \\pub const build_date: []const u8 = "{s}";
        \\pub const build_timestamp: i64 = {d};
        \\
    , .{ new_build_number, formatted_date, timestamp });

    // Write directly to src/build_number.zig using Zig's file system
    const cwd = std.fs.cwd();
    const file = cwd.createFile("src/build_number.zig", .{}) catch |err| {
        std.debug.print("Failed to create build_number.zig: {}\n", .{err});
        return b.addSystemCommand(&.{"echo", "Build number generation failed"});
    };
    defer file.close();

    file.writeAll(build_content) catch |err| {
        std.debug.print("Failed to write to build_number.zig: {}\n", .{err});
    };

    // Return a no-op command since we've already written the file
    return b.addSystemCommand(&.{"echo", "Build number generated"});
}