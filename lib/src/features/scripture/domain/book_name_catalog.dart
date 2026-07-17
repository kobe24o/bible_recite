import 'package:flutter/widgets.dart';

abstract interface class BookNameCatalog {
  String nameFor(String osisId, Locale locale);

  String chapterLabel(String osisId, int chapter, Locale locale);
}
