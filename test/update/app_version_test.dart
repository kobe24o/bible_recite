import 'package:bible_recite/src/features/update/domain/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semantic version wins before build number', () {
    final local = AppVersion.parse('1.0.4', '20');

    expect(AppVersion.parse('1.0.5', '1').isNewerThan(local), isTrue);
    expect(AppVersion.parse('1.0.3', '99').isNewerThan(local), isFalse);
    expect(AppVersion.parse('1.0.4', '21').isNewerThan(local), isTrue);
    expect(AppVersion.parse('1.0.4', '20').isNewerThan(local), isFalse);
  });

  test('rejects non numeric semantic versions and builds', () {
    expect(() => AppVersion.parse('1.0-beta', '2'), throwsFormatException);
    expect(() => AppVersion.parse('1.0.0', '2a'), throwsFormatException);
  });
}
