import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';

import 'verse_unit_assembler.dart';

final class ParallelMappingOverride {
  ParallelMappingOverride({
    required List<String> sourceKeys,
    required List<String> targetKeys,
    required this.relation,
    required this.evidence,
  }) : sourceKeys = List.unmodifiable(sourceKeys),
       targetKeys = List.unmodifiable(targetKeys) {
    if (evidence.trim().isEmpty ||
        (this.sourceKeys.isEmpty && this.targetKeys.isEmpty) ||
        !_validOverrideShape(relation, this.sourceKeys, this.targetKeys)) {
      throw ArgumentError('Invalid reviewed parallel mapping override');
    }
  }

  final List<String> sourceKeys;
  final List<String> targetKeys;
  final ParallelRelation relation;
  final String evidence;
}

final class BuiltParallelGroup {
  BuiltParallelGroup({
    required this.id,
    required List<String> sourceKeys,
    required List<String> targetKeys,
    required this.relation,
    required this.provenance,
    required this.reviewState,
  }) : sourceKeys = List.unmodifiable(sourceKeys),
       targetKeys = List.unmodifiable(targetKeys);

  final String id;
  final List<String> sourceKeys;
  final List<String> targetKeys;
  final ParallelRelation relation;
  final String provenance;
  final String reviewState;
}

final class ParallelMappingResult {
  ParallelMappingResult({
    required List<BuiltParallelGroup> groups,
    required this.sourceTranslationId,
    required this.sourceSemanticSha256,
    required this.targetTranslationId,
    required this.targetSemanticSha256,
    required List<String> unresolvedSourceKeys,
    required List<String> unresolvedTargetKeys,
  }) : groups = List.unmodifiable(groups),
       unresolvedSourceKeys = List.unmodifiable(unresolvedSourceKeys),
       unresolvedTargetKeys = List.unmodifiable(unresolvedTargetKeys) {
    _sourceIndex = _index(groups, (group) => group.sourceKeys);
    _targetIndex = _index(groups, (group) => group.targetKeys);
  }

  final List<BuiltParallelGroup> groups;
  final String sourceTranslationId;
  final String sourceSemanticSha256;
  final String targetTranslationId;
  final String targetSemanticSha256;
  final List<String> unresolvedSourceKeys;
  final List<String> unresolvedTargetKeys;
  late final Map<String, BuiltParallelGroup> _sourceIndex;
  late final Map<String, BuiltParallelGroup> _targetIndex;

  BuiltParallelGroup? groupForSource(String key) => _sourceIndex[key];

  BuiltParallelGroup? groupForTarget(String key) => _targetIndex[key];
}

final class ParallelMappingBuilder {
  ParallelMappingResult build({
    required String sourceTranslationId,
    required String sourceSemanticSha256,
    required List<ParsedVerseUnit> sourceUnits,
    required String targetTranslationId,
    required String targetSemanticSha256,
    required List<ParsedVerseUnit> targetUnits,
    required List<ParallelMappingOverride> overrides,
  }) {
    if (!_sha256.hasMatch(sourceSemanticSha256) ||
        !_sha256.hasMatch(targetSemanticSha256) ||
        sourceTranslationId.isEmpty ||
        targetTranslationId.isEmpty ||
        sourceTranslationId == targetTranslationId) {
      throw ArgumentError('Invalid mapping revision identity');
    }
    final sourceByKey = _unitsByKey(sourceUnits);
    final targetByKey = _unitsByKey(targetUnits);
    final claimedSource = <String>{};
    final claimedTarget = <String>{};
    final pending = <_PendingGroup>[];

    for (final override in overrides) {
      _claimOverrideKeys(
        keys: override.sourceKeys,
        available: sourceByKey,
        claimed: claimedSource,
        side: 'source',
      );
      _claimOverrideKeys(
        keys: override.targetKeys,
        available: targetByKey,
        claimed: claimedTarget,
        side: 'target',
      );
      pending.add(
        _PendingGroup(
          sourceKeys: override.sourceKeys,
          targetKeys: override.targetKeys,
          relation: override.relation,
          provenance: override.evidence,
          reviewState: 'approved',
        ),
      );
    }

    final remainingSource = {
      for (final entry in sourceByKey.entries)
        if (!claimedSource.contains(entry.key)) entry.key: entry.value,
    };
    final remainingTarget = {
      for (final entry in targetByKey.entries)
        if (!claimedTarget.contains(entry.key)) entry.key: entry.value,
    };
    final sourceEdges = <String, Set<String>>{};
    final targetEdges = <String, Set<String>>{};
    final targetsBySlot = <String, Set<String>>{};
    for (final entry in remainingTarget.entries) {
      for (final slot in _slotKeys(entry.value)) {
        targetsBySlot.putIfAbsent(slot, () => <String>{}).add(entry.key);
      }
    }
    for (final entry in remainingSource.entries) {
      for (final slot in _slotKeys(entry.value)) {
        for (final targetKey in targetsBySlot[slot] ?? const <String>{}) {
          sourceEdges.putIfAbsent(entry.key, () => <String>{}).add(targetKey);
          targetEdges.putIfAbsent(targetKey, () => <String>{}).add(entry.key);
        }
      }
    }

    final visitedSource = <String>{};
    final visitedTarget = <String>{};
    for (final seed in remainingSource.keys) {
      if (visitedSource.contains(seed) || sourceEdges[seed] == null) {
        continue;
      }
      final sourceComponent = <String>{};
      final targetComponent = <String>{};
      final sourceQueue = <String>[seed];
      while (sourceQueue.isNotEmpty) {
        final sourceKey = sourceQueue.removeLast();
        if (!visitedSource.add(sourceKey)) {
          continue;
        }
        sourceComponent.add(sourceKey);
        for (final targetKey in sourceEdges[sourceKey] ?? const <String>{}) {
          if (visitedTarget.add(targetKey)) {
            targetComponent.add(targetKey);
            sourceQueue.addAll(targetEdges[targetKey] ?? const <String>{});
          }
        }
      }
      final sourceKeys = sourceComponent.toList()..sort(_compareKeys);
      final targetKeys = targetComponent.toList()..sort(_compareKeys);
      pending.add(
        _PendingGroup(
          sourceKeys: sourceKeys,
          targetKeys: targetKeys,
          relation: _automaticRelation(sourceKeys.length, targetKeys.length),
          provenance: 'automatic-slot-overlap-v1',
          reviewState: 'automatic',
        ),
      );
    }

    pending.sort((left, right) {
      final leftKey = left.sourceKeys.isNotEmpty
          ? left.sourceKeys.first
          : left.targetKeys.first;
      final rightKey = right.sourceKeys.isNotEmpty
          ? right.sourceKeys.first
          : right.targetKeys.first;
      return _compareKeys(leftKey, rightKey);
    });
    final groups = <BuiltParallelGroup>[];
    for (var index = 0; index < pending.length; index++) {
      final group = pending[index];
      groups.add(
        BuiltParallelGroup(
          id: '$sourceTranslationId--$targetTranslationId--${(index + 1).toString().padLeft(5, '0')}',
          sourceKeys: group.sourceKeys,
          targetKeys: group.targetKeys,
          relation: group.relation,
          provenance: group.provenance,
          reviewState: group.reviewState,
        ),
      );
    }
    final resolvedSource = groups.expand((group) => group.sourceKeys).toSet();
    final resolvedTarget = groups.expand((group) => group.targetKeys).toSet();
    return ParallelMappingResult(
      groups: groups,
      sourceTranslationId: sourceTranslationId,
      sourceSemanticSha256: sourceSemanticSha256,
      targetTranslationId: targetTranslationId,
      targetSemanticSha256: targetSemanticSha256,
      unresolvedSourceKeys: sourceByKey.keys
          .where((key) => !resolvedSource.contains(key))
          .toList(growable: false),
      unresolvedTargetKeys: targetByKey.keys
          .where((key) => !resolvedTarget.contains(key))
          .toList(growable: false),
    );
  }
}

final class _PendingGroup {
  const _PendingGroup({
    required this.sourceKeys,
    required this.targetKeys,
    required this.relation,
    required this.provenance,
    required this.reviewState,
  });

  final List<String> sourceKeys;
  final List<String> targetKeys;
  final ParallelRelation relation;
  final String provenance;
  final String reviewState;
}

Map<String, ParsedVerseUnit> _unitsByKey(List<ParsedVerseUnit> units) {
  final result = <String, ParsedVerseUnit>{};
  for (final unit in units) {
    final key = _unitKey(unit);
    if (result[key] != null) {
      throw ArgumentError('Duplicate mapping unit key: $key');
    }
    result[key] = unit;
  }
  return result;
}

void _claimOverrideKeys({
  required List<String> keys,
  required Map<String, ParsedVerseUnit> available,
  required Set<String> claimed,
  required String side,
}) {
  for (final key in keys) {
    if (!available.containsKey(key)) {
      throw ArgumentError('Override $side key does not exist: $key');
    }
    if (!claimed.add(key)) {
      throw ArgumentError('Override $side key is duplicated: $key');
    }
  }
}

Map<String, BuiltParallelGroup> _index(
  List<BuiltParallelGroup> groups,
  List<String> Function(BuiltParallelGroup group) keysOf,
) {
  final result = <String, BuiltParallelGroup>{};
  for (final group in groups) {
    for (final key in keysOf(group)) {
      if (result[key] != null) {
        throw StateError('Mapping key occurs in multiple groups: $key');
      }
      result[key] = group;
    }
  }
  return Map.unmodifiable(result);
}

Iterable<String> _slotKeys(ParsedVerseUnit unit) sync* {
  for (var verse = unit.startVerse; verse <= unit.endVerse; verse++) {
    yield '${unit.bookCode}.${unit.chapter}.$verse';
  }
}

String _unitKey(ParsedVerseUnit unit) {
  return '${unit.bookCode}.${unit.chapter}.${unit.startVerse}';
}

ParallelRelation _automaticRelation(int sourceCount, int targetCount) {
  if (sourceCount == 1 && targetCount == 1) {
    return ParallelRelation.oneToOne;
  }
  if (sourceCount == 1) {
    return ParallelRelation.sourceBridge;
  }
  if (targetCount == 1) {
    return ParallelRelation.targetBridge;
  }
  return ParallelRelation.oneToOne;
}

bool _validOverrideShape(
  ParallelRelation relation,
  List<String> sourceKeys,
  List<String> targetKeys,
) {
  if (relation == ParallelRelation.sourceAbsent) {
    return sourceKeys.isEmpty && targetKeys.isNotEmpty;
  }
  if (relation == ParallelRelation.targetAbsent) {
    return sourceKeys.isNotEmpty && targetKeys.isEmpty;
  }
  return sourceKeys.isNotEmpty && targetKeys.isNotEmpty;
}

int _compareKeys(String left, String right) {
  final leftParts = left.split('.');
  final rightParts = right.split('.');
  final leftBook = protestant66BookOrder[leftParts[0]] ?? 1000;
  final rightBook = protestant66BookOrder[rightParts[0]] ?? 1000;
  final bookComparison = leftBook.compareTo(rightBook);
  if (bookComparison != 0) {
    return bookComparison;
  }
  final chapterComparison = int.parse(
    leftParts[1],
  ).compareTo(int.parse(rightParts[1]));
  return chapterComparison != 0
      ? chapterComparison
      : int.parse(leftParts[2]).compareTo(int.parse(rightParts[2]));
}

final _sha256 = RegExp(r'^[0-9a-f]{64}$');
