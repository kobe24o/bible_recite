import 'package:bible_recite/src/features/distribution/domain/testflight_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts an HTTPS TestFlight public link', () {
    final link = TestFlightLink.parse(
      'https://testflight.apple.com/join/AbCdEf12',
    );

    expect(link?.url.toString(), 'https://testflight.apple.com/join/AbCdEf12');
  });

  test('rejects an APK or arbitrary HTTPS link', () {
    expect(TestFlightLink.parse('https://example.com/app.apk'), isNull);
    expect(
      TestFlightLink.parse('http://testflight.apple.com/join/AbCdEf12'),
      isNull,
    );
  });
}
