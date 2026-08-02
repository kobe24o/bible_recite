import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../plans/application/plan_providers.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/domain/scripture_models.dart';
import '../domain/recitation_result.dart';

class RecitationMapScreen extends ConsumerStatefulWidget {
  const RecitationMapScreen({
    this.translationId,
    this.testament,
    this.bookId,
    this.chapter,
    super.key,
  });

  final String? translationId;
  final String? testament;
  final String? bookId;
  final int? chapter;

  @override
  ConsumerState<RecitationMapScreen> createState() =>
      _RecitationMapScreenState();
}

class _RecitationMapScreenState extends ConsumerState<RecitationMapScreen> {
  late Future<_MapData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MapData> _load() async {
    final repository = await ref.read(planRepositoryProvider.future);
    final metrics = await repository.listRecitationVerseMetrics(
      translationId: widget.translationId,
      bookId: widget.bookId,
      chapter: widget.chapter,
    );
    if (metrics.isEmpty) return const _MapData.empty();
    final translation = widget.translationId ?? metrics.first.translationId;
    final scripture = await ref.read(scriptureRepositoryProvider.future);
    final books = await scripture.listBooks(translation, CanonId.protestant66);
    return _MapData(translation, books, metrics, scripture);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title())),
    body: FutureBuilder<_MapData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        if (data.metrics.isEmpty) {
          return const Center(child: Text('完成一次背诵后，这里会生成你的背诵地图。'));
        }
        if (widget.testament == null) return _testaments(context, data);
        if (widget.bookId == null) return _books(context, data);
        if (widget.chapter == null) return _chapters(context, data);
        return _verses(context, data);
      },
    ),
  );

  String _title() => widget.chapter != null
      ? '第 ${widget.chapter} 章'
      : widget.bookId != null
      ? '背诵地图 · 章节'
      : widget.testament == null
      ? '背诵地图'
      : widget.testament == 'old'
      ? '旧约'
      : '新约';

  Widget _testaments(BuildContext context, _MapData data) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _MapRow(
        icon: Icons.auto_stories_outlined,
        title: '旧约',
        summary: data.summaryForBooks(data.books.where((b) => b.ordinal <= 39)),
        total: 39,
        onTap: () => context.push(
          '/statistics/map?translation=${data.translationId}&testament=old',
        ),
      ),
      const SizedBox(height: 10),
      _MapRow(
        icon: Icons.menu_book_outlined,
        title: '新约',
        summary: data.summaryForBooks(data.books.where((b) => b.ordinal > 39)),
        total: 27,
        onTap: () => context.push(
          '/statistics/map?translation=${data.translationId}&testament=new',
        ),
      ),
    ],
  );

  Widget _books(BuildContext context, _MapData data) {
    final old = widget.testament == 'old';
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: data.books.where((b) => (b.ordinal <= 39) == old).length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final book = data.books
            .where((b) => (b.ordinal <= 39) == old)
            .elementAt(index);
        return _MapRow(
          icon: Icons.book_outlined,
          title: book.name,
          summary: data.summaryForBook(book),
          total: book.chapterCount,
          onTap: () => context.push(
            '/statistics/map?translation=${data.translationId}&testament=${widget.testament}&book=${book.osisId}',
          ),
        );
      },
    );
  }

  Widget _chapters(BuildContext context, _MapData data) {
    final book = data.books.singleWhere((b) => b.osisId == widget.bookId);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: book.chapterCount,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final chapter = index + 1;
        return _MapRow(
          icon: Icons.format_list_numbered_rounded,
          title: '第 $chapter 章',
          summary: data.summaryForChapter(book.osisId, chapter),
          total: null,
          onTap: () => context.push(
            '/statistics/map?translation=${data.translationId}&testament=${widget.testament}&book=${book.osisId}&chapter=$chapter',
          ),
        );
      },
    );
  }

  Widget _verses(BuildContext context, _MapData data) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: data.metrics.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, index) {
      final metric = data.metrics[index];
      return ListTile(
        leading: CircleAvatar(child: Text('${metric.verse}')),
        title: Text('第 ${metric.verse} 节 · 背诵 ${metric.sessions} 次'),
        subtitle: Text(
          '准确率 ${(metric.averageAccuracy * 100).round()}% · 累计 ${_duration(metric.totalSeconds)}',
        ),
      );
    },
  );
}

class _MapData {
  const _MapData(this.translationId, this.books, this.metrics, this.scripture);
  const _MapData.empty()
    : translationId = '',
      books = const [],
      metrics = const [],
      scripture = null;
  final String translationId;
  final List<BibleBook> books;
  final List<RecitationVerseMetric> metrics;
  final Object? scripture;

  _MapSummary summaryForBooks(Iterable<BibleBook> books) =>
      _summary(metrics.where((m) => books.any((b) => b.osisId == m.bookId)));
  _MapSummary summaryForBook(BibleBook book) => _summary(
    metrics.where((m) => m.bookId == book.osisId),
    total: book.chapterCount,
  );
  _MapSummary summaryForChapter(String book, int chapter) =>
      _summary(metrics.where((m) => m.bookId == book && m.chapter == chapter));
  _MapSummary _summary(Iterable<RecitationVerseMetric> values, {int? total}) {
    final list = values.toList();
    final chapters = list.map((m) => '${m.bookId}:${m.chapter}').toSet().length;
    final seconds = list.fold(0, (sum, m) => sum + m.totalSeconds);
    final sessions = list.fold(0, (sum, m) => sum + m.sessions);
    final double accuracy = sessions == 0
        ? 0
        : list.fold(0.0, (sum, m) => sum + m.averageAccuracy * m.sessions) /
              sessions;
    return _MapSummary(chapters, total, seconds, accuracy);
  }
}

class _MapSummary {
  const _MapSummary(this.completed, this.total, this.seconds, this.accuracy);
  final int completed;
  final int? total;
  final int seconds;
  final double accuracy;
}

class _MapRow extends StatelessWidget {
  const _MapRow({
    required this.icon,
    required this.title,
    required this.summary,
    required this.total,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final _MapSummary summary;
  final int? total;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final denominator = total ?? summary.total;
    final progress = denominator == null || denominator == 0
        ? 0.0
        : (summary.completed / denominator).clamp(0.0, 1.0);
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        onTap: onTap,
        trailing: const Icon(Icons.chevron_right_rounded),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              denominator == null
                  ? '已背诵 ${summary.completed} 节'
                  : '完成 ${summary.completed}/$denominator 章',
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 5),
            Text(
              '准确率 ${(summary.accuracy * 100).round()}% · 累计 ${_duration(summary.seconds)}',
            ),
          ],
        ),
      ),
    );
  }
}

String _duration(int seconds) =>
    seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分 ${seconds % 60} 秒';
