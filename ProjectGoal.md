# Project Goal

## Vision

A **fast, lightweight, and portable** Zig-based Android application template that serves as a starting point for developers who want to build performant Android apps using Zig while avoiding the bloat and complexity of traditional Android development tooling.

## Core Principles

1. **Zig-First**: All application logic written in Zig
2. **Minimal Java**: Java only as a thin passthrough layer where absolutely required by Android
3. **No Gradle**: Complete build pipeline in `build.zig`
4. **No Android Studio**: Command-line only workflow
5. **Portable**: Clone and build on any Linux machine

## Success Criteria

### Primary Goal

```bash
git clone <repo>
cd helloworld
zig build
```

**This must work on any Linux machine with Zig and Android SDK/NDK installed, with zero errors.**

### Requirements

| Requirement | Status |
|-------------|--------|
| `zig build` completes without errors | :white_check_mark: |
| `zig build deploy` installs working APK | :white_check_mark: |
| No Gradle dependency | :white_check_mark: |
| No Android Studio dependency | :white_check_mark: |
| Minimal Java (entry point only) | :white_check_mark: |
| All app logic in Zig | :white_check_mark: |
| Clear documentation for setup | Partial |
| Works on fresh Linux install | Needs testing |

## Target Audience

Developers who:
- Want to write Android apps in Zig
- Value performance and small binary size
- Prefer command-line workflows over IDEs
- Want to understand their build system
- Are frustrated with Gradle build times and complexity

## Non-Goals

- iOS support (Android only)
- GUI build tools
- Compatibility with Android Studio project structure
- Support for Kotlin
- Backwards compatibility with very old Android versions

## Current Status

**Phase: Stabilization**

The core functionality works:
- Cross-compilation to ARM64 Android
- JNI integration with Zig abstractions
- Dynamic UI creation from Zig
- APK packaging and signing
- Deployment to device

**Next Steps:**
- Ensure clean build on fresh clone
- Verify all prerequisites are documented
- Test on different Linux distributions
- Clean up any warnings or non-essential output

## Dependencies

### Required (User Must Install)

- **Zig**: Latest stable version
- **Android SDK**: API 35+ with Build Tools 35.0.0
- **Android NDK**: r25+
- **Java**: JDK 11+
- **ADB**: For device deployment (included in SDK platform-tools)

### Environment Variables

```bash
export ANDROID_SDK_ROOT=/path/to/android-sdk
export ANDROID_NDK_ROOT=/path/to/android-ndk
```

## Architecture Decisions

1. **Why no Gradle?** - Gradle adds massive complexity, slow build times, and obscures what's happening. `build.zig` is transparent and fast.

2. **Why minimal Java?** - Android requires a Java entry point (Activity), but all logic can be delegated to native code immediately.

3. **Why Zig?** - Memory safety without garbage collection, excellent cross-compilation, C interop for JNI, and fast compilation.

4. **Why API 35?** - Modern Android features, no compatibility hacks for ancient devices, matches current device ecosystem.

## Measuring Success

The project succeeds when a developer can:

1. Clone the repository
2. Set up Android SDK/NDK (documented)
3. Run `zig build`
4. Get a working APK
5. Modify Zig code to build their own app
6. Never touch Gradle or Android Studio
