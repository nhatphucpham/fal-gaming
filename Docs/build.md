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

## Web

The `Web` preset is the quickest way to try the game on a phone, including
iPhone, where APKs do not install. Choices:

- **No threads** (`variant/thread_support=false`). The page runs without the
  `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers, so it
  works on GitHub Pages and in Safari on iOS. Audio is slightly more prone to
  crackle under load than a threaded build.
- **GDExtension support** (`variant/extensions_support=true`). Needed for the
  C++ code. The engine is about 10.6 MB gzipped instead of 10.1 MB. The C++
  library must be built for `platform=web` with `threads=no` to match, and
  listed as `web.release.wasm32` / `web.debug.wasm32` in the `.gdextension`
  file.
- ETC2/ASTC and S3TC/BPTC textures are both exported, so phones and desktops
  each get a compressed format.
- It is a progressive web app: on iPhone, **Share > Add to Home Screen**
  opens it full screen in landscape.

CI exports a release build on every push and uploads it as the `falemag-web`
artifact. On pushes to `master` the `pages` job publishes it to
<https://nhatphucpham.github.io/fal-gaming/>. This needs **Settings > Pages >
Source: GitHub Actions** turned on once in the repository.

To try a build locally, export it and serve the folder over HTTP (opening
`index.html` from disk does not work):

```sh
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server --directory build/web 8000
```
