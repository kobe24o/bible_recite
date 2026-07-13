import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';

import 'parallel_mapping_builder.dart';

final class ReviewedOverrideSet {
  ReviewedOverrideSet({
    required this.sourceTranslationId,
    required this.sourceSemanticSha256,
    required this.targetTranslationId,
    required this.targetSemanticSha256,
    required List<ParallelMappingOverride> overrides,
  }) : overrides = List.unmodifiable(overrides);

  final String sourceTranslationId;
  final String sourceSemanticSha256;
  final String targetTranslationId;
  final String targetSemanticSha256;
  final List<ParallelMappingOverride> overrides;
}

final class ReviewedOverrideCatalog {
  ReviewedOverrideCatalog(List<ReviewedOverrideSet> sets)
    : sets = List.unmodifiable(sets);

  final List<ReviewedOverrideSet> sets;

  static Future<ReviewedOverrideCatalog> load(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['revision'] != 'parallel-v1') {
      throw const FormatException('Unsupported parallel override catalog');
    }
    final rawSets = decoded['sets'];
    if (rawSets is! List<Object?>) {
      throw const FormatException('Parallel override sets must be a list');
    }
    return ReviewedOverrideCatalog(
      rawSets
          .map((raw) {
            if (raw is! Map<String, Object?>) {
              throw const FormatException('Parallel override set is invalid');
            }
            final rawOverrides = raw['overrides'];
            if (rawOverrides is! List<Object?>) {
              throw const FormatException('Parallel overrides must be a list');
            }
            return ReviewedOverrideSet(
              sourceTranslationId: _requiredString(raw, 'sourceTranslationId'),
              sourceSemanticSha256: _requiredHash(raw, 'sourceSemanticSha256'),
              targetTranslationId: _requiredString(raw, 'targetTranslationId'),
              targetSemanticSha256: _requiredHash(raw, 'targetSemanticSha256'),
              overrides: rawOverrides
                  .map((entry) {
                    if (entry is! Map<String, Object?>) {
                      throw const FormatException(
                        'Parallel override is invalid',
                      );
                    }
                    final sourceKeys = _requiredStringList(entry, 'sourceKeys');
                    final targetKeys = _requiredStringList(entry, 'targetKeys');
                    final relationName = _requiredString(entry, 'relation');
                    final relation = ParallelRelation.values
                        .where((value) => value.name == relationName)
                        .firstOrNull;
                    if (relation == null ||
                        entry['reviewState'] != 'approved') {
                      throw const FormatException(
                        'Parallel override relation or review state is invalid',
                      );
                    }
                    return ParallelMappingOverride(
                      sourceKeys: sourceKeys,
                      targetKeys: targetKeys,
                      relation: relation,
                      evidence: _requiredString(entry, 'evidence'),
                    );
                  })
                  .toList(growable: false),
            );
          })
          .toList(growable: false),
    );
  }

  ReviewedOverrideSet requireExact({
    required String sourceTranslationId,
    required String sourceSemanticSha256,
    required String targetTranslationId,
    required String targetSemanticSha256,
  }) {
    return sets.singleWhere(
      (set) =>
          set.sourceTranslationId == sourceTranslationId &&
          set.sourceSemanticSha256 == sourceSemanticSha256 &&
          set.targetTranslationId == targetTranslationId &&
          set.targetSemanticSha256 == targetSemanticSha256,
      orElse: () => throw StateError(
        'No reviewed overrides match the exact source and target revisions',
      ),
    );
  }
}

final class ParallelMappingValidationException implements Exception {
  const ParallelMappingValidationException(this.message);

  final String message;

  @override
  String toString() => 'ParallelMappingValidationException: $message';
}

final class ParallelMappingValidator {
  void validate(ParallelMappingResult mapping) {
    if (mapping.unresolvedSourceKeys.isNotEmpty ||
        mapping.unresolvedTargetKeys.isNotEmpty) {
      throw ParallelMappingValidationException(
        'Unresolved mapping units: source=${mapping.unresolvedSourceKeys.length}, '
        'target=${mapping.unresolvedTargetKeys.length}; '
        'sourceKeys=${mapping.unresolvedSourceKeys}; '
        'targetKeys=${mapping.unresolvedTargetKeys}',
      );
    }
    final groupIds = <String>{};
    for (final group in mapping.groups) {
      if (!groupIds.add(group.id)) {
        throw const ParallelMappingValidationException('Duplicate group ID');
      }
      if (group.relation == ParallelRelation.sourceAbsent &&
          (group.sourceKeys.isNotEmpty || group.targetKeys.isEmpty)) {
        throw const ParallelMappingValidationException(
          'sourceAbsent must identify target-only units',
        );
      }
      if (group.relation == ParallelRelation.targetAbsent &&
          (group.sourceKeys.isEmpty || group.targetKeys.isNotEmpty)) {
        throw const ParallelMappingValidationException(
          'targetAbsent must identify source-only units',
        );
      }
      for (final key in group.sourceKeys) {
        if (!identical(mapping.groupForSource(key), group)) {
          throw ParallelMappingValidationException(
            'Source direction is not reversible for $key',
          );
        }
      }
      for (final key in group.targetKeys) {
        if (!identical(mapping.groupForTarget(key), group)) {
          throw ParallelMappingValidationException(
            'Target direction is not reversible for $key',
          );
        }
      }
    }
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Parallel override field $key is invalid');
  }
  return value;
}

String _requiredHash(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Parallel override hash $key is invalid');
  }
  return value;
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?> || value.any((entry) => entry is! String)) {
    throw FormatException('Parallel override member list $key is invalid');
  }
  return value.cast<String>();
}
