import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/testflight_link.dart';

final testFlightLinkProvider = Provider<TestFlightLink?>(
  (ref) => TestFlightLink.parse(const String.fromEnvironment('TESTFLIGHT_URL')),
);
