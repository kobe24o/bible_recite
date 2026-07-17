final class CloudPassageRef {
  const CloudPassageRef({
    required this.order,
    required this.bookId,
    required this.startChapter,
    required this.endChapter,
    this.startVerse,
    this.endVerse,
  });

  final int order;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final int? startVerse;
  final int? endVerse;

  CloudPassageRef copyWith({
    int? order,
    String? bookId,
    int? startChapter,
    int? endChapter,
    int? startVerse,
    int? endVerse,
  }) => CloudPassageRef(
    order: order ?? this.order,
    bookId: bookId ?? this.bookId,
    startChapter: startChapter ?? this.startChapter,
    endChapter: endChapter ?? this.endChapter,
    startVerse: startVerse ?? this.startVerse,
    endVerse: endVerse ?? this.endVerse,
  );
}

final class CloudPlanDefinition {
  const CloudPlanDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.passages,
  });

  final String id;
  final String title;
  final String description;
  final List<CloudPassageRef> passages;
}
