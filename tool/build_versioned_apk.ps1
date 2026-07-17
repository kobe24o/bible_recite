param(
    [switch]$SkipVersionBump
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw -Encoding UTF8
$match = [regex]::Match(
    $pubspec,
    '(?m)^version:\s+(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$'
)
if (-not $match.Success) {
    throw 'Unable to read version from pubspec.yaml'
}

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$build = [int]$match.Groups[4].Value
if (-not $SkipVersionBump) {
    $patch++
    $build++
    $version = "$major.$minor.$patch+$build"
    $pubspec = $pubspec.Remove($match.Index, $match.Length).Insert(
        $match.Index,
        "version: $version"
    )
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($pubspecPath, $pubspec, $utf8WithoutBom)
} else {
    $version = "$major.$minor.$patch+$build"
}

$flutter = Join-Path $root '.toolchains\flutter\bin\flutter.bat'
& $flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    throw "Flutter build failed with exit code $LASTEXITCODE"
}

$source = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
$destination = Join-Path $root "build\app\outputs\flutter-apk\BibleRecite-$version.apk"
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Output $destination
