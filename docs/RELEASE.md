# APK release rule

Use `tool/build_versioned_apk.ps1` for every APK handed to the user. The script
increments both the semantic patch version and Android build number before it
builds, then creates a versioned APK filename. This prevents launchers, file
transfer tools, and users from confusing a new package with an older build.

For the current already-bumped source version only, use
`tool/build_versioned_apk.ps1 -SkipVersionBump`.
