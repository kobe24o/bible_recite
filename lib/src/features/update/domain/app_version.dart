final class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.major, this.minor, this.patch, this.buildNumber);

  final int major;
  final int minor;
  final int patch;
  final int buildNumber;

  factory AppVersion.parse(String name, String build) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(name);
    final parsedBuild = int.tryParse(build);
    if (match == null || parsedBuild == null || parsedBuild < 0) {
      throw const FormatException('Invalid application version');
    }

    return AppVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      parsedBuild,
    );
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (buildNumber, other.buildNumber),
    ]) {
      final value = pair.$1.compareTo(pair.$2);
      if (value != 0) {
        return value;
      }
    }
    return 0;
  }
}
