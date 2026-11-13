# Build and test

Use the standard Godot 4.7.2 editor and open `project.godot`, or follow the
command-line steps in the README. Godot imports assets into `.godot/`, which is
generated locally and ignored by Git.

To validate without a display, run the editor import and
`Tests/smoke_test.gd` as shown in the README. CI does the same and also starts
the project headlessly. These checks do not replace testing an exported build
on the target device.

A C++ toolchain is not needed yet. It will be required, and documented here,
when the GDExtension is added.

## Android

The `Android` preset builds an APK for arm64 phones (Android 7.0 and later)
without a custom Gradle build. Choices made to keep it light:

- Only `arm64-v8a` is exported. Dropping 32-bit ARM and x86 roughly halves
  the APK; every phone sold since about 2017 is arm64. Enable
  `architectures/armeabi-v7a` only if a target device needs it.
- The renderer is GL Compatibility (OpenGL ES 3.0), which runs on low-end
  GPUs. Textures import with ETC2/ASTC compression
  (`rendering/textures/vram_compression/import_etc2_astc`), which Android
  export requires and which keeps GPU memory low.
- The screen follows the sensor in landscape, uses immersive mode, and
  stretches with `aspect="expand"` so tall phone screens show more of the
  scene instead of black bars.
- The `INTERNET` permission is on for online play and the TTS service.

A debug export from the empty project is about 28 MB and a release export
about 26 MB; almost all of it is the engine library. A custom engine build
with unused modules disabled can shrink it further when that matters.

### Export locally

1. Install the Android SDK (platform-tools, build-tools) and JDK 17, then set
   their paths in **Editor > Editor Settings > Export > Android**. The
   `ANDROID_HOME` and `JAVA_HOME` environment variables work too.
2. Install the 4.7.2 export templates.
3. Export from the editor (**Project > Export > Android**), or from a shell:

```sh
"$GODOT" --headless --path . --export-debug "Android" build/android/Falemag.apk
```

Godot signs debug builds with the debug keystore from Editor Settings, or the
one named by `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `_USER` and `_PASSWORD`. A
release build needs your own keystore through the matching
`GODOT_ANDROID_KEYSTORE_RELEASE_*` variables; never commit a keystore.

CI exports a debug APK on every push and uploads it as the
`falemag-android-debug` artifact, kept for seven days. It proves the preset
exports; it does not run the game. Install the APK on a real low-end phone
(`adb install -r Falemag.apk`) to check performance.

### Native libraries

When the GDExtension is added, its `.gdextension` file needs an
`android.debug.arm64` and `android.release.arm64` entry pointing at the
`.so` built with the Android NDK. The preset packages those libraries into the
APK without a Gradle build, so no preset change is needed.
