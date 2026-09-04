final class TestFlightLink {
  const TestFlightLink._(this.url);

  final Uri url;

  static TestFlightLink? parse(String raw) {
    final url = Uri.tryParse(raw.trim());
    if (url == null ||
        url.scheme != 'https' ||
        url.host.toLowerCase() != 'testflight.apple.com' ||
        url.pathSegments.isEmpty) {
      return null;
    }
    return TestFlightLink._(url);
  }
}
