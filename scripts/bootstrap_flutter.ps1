$ErrorActionPreference = 'Stop'

$version = '3.44.4'
$expectedSha256 = '8f2d6224fc6872d2f7f180de86cde989fcea3776efe0edf48a9aac2cd9be2b1b'
$root = Split-Path -Parent $PSScriptRoot
$toolchains = Join-Path $root '.toolchains'
$archive = Join-Path $toolchains "flutter-$version.zip"
$partialArchive = "$archive.partial"
$sdk = Join-Path $toolchains 'flutter'
$flutter = Join-Path $sdk 'bin\flutter.bat'
$url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_${version}-stable.zip"

New-Item -ItemType Directory -Force -Path $toolchains | Out-Null

if (Test-Path -LiteralPath $archive) {
  $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
  if ($existingHash -ne $expectedSha256) {
    Move-Item -LiteralPath $archive -Destination $partialArchive -Force
  }
}

if (-not (Test-Path -LiteralPath $archive)) {
  & curl.exe --fail --location --retry 5 --retry-delay 2 --continue-at - --output $partialArchive $url
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter download failed with curl exit code $LASTEXITCODE"
  }
  Move-Item -LiteralPath $partialArchive -Destination $archive -Force
}

$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($actual -ne $expectedSha256) {
  throw "Flutter archive hash mismatch: expected $expectedSha256, got $actual"
}

if (-not (Test-Path -LiteralPath $flutter)) {
  Expand-Archive -LiteralPath $archive -DestinationPath $toolchains -Force
}

& $flutter --version
