import 'dart:convert';

final class PackManifest {
  PackManifest(Map<String, Object?> values)
    : values = Map.unmodifiable(_sortMap(values));

  final Map<String, Object?> values;

  String toCanonicalJson() {
    return '${const JsonEncoder.withIndent('  ').convert(values)}\n';
  }
}

Map<String, Object?> _sortMap(Map<String, Object?> source) {
  final result = <String, Object?>{};
  for (final key in source.keys.toList()..sort()) {
    result[key] = _sortValue(source[key]);
  }
  return result;
}

Object? _sortValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _sortMap(value);
  }
  if (value is List<Object?>) {
    return value.map(_sortValue).toList(growable: false);
  }
  return value;
}
