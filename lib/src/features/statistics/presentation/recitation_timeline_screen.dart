import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../plans/application/plan_providers.dart';
import '../domain/recitation_result.dart';

class RecitationTimelineScreen extends ConsumerStatefulWidget {
  const RecitationTimelineScreen({super.key});
  @override
  ConsumerState<RecitationTimelineScreen> createState() =>
      _RecitationTimelineScreenState();
}

class _RecitationTimelineScreenState
    extends ConsumerState<RecitationTimelineScreen> {
  String _period = 'week';
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.go('/statistics');
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('学习轨迹')),
      body: FutureBuilder<List<RecitationTimelinePoint>>(
        future: ref
            .read(planRepositoryProvider.future)
            .then((r) => r.listRecitationTimeline(_period)),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final points = snapshot.data!;
          final maxVerses = points.fold(
            0,
            (max, point) => point.verses > max ? point.verses : max,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'week', label: Text('周')),
                  ButtonSegment(value: 'month', label: Text('月')),
                  ButtonSegment(value: 'quarter', label: Text('季')),
                  ButtonSegment(value: 'year', label: Text('年')),
                ],
                selected: {_period},
                onSelectionChanged: (value) =>
                    setState(() => _period = value.first),
              ),
              const SizedBox(height: 16),
              if (points.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('完成背诵后，会在这里形成你的学习轨迹。')),
                ),
              for (final point in points)
                Card(
                  child: ListTile(
                    title: Text(point.label),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 5),
                        Text(
                          '背诵 ${point.verses} 节 · ${point.characters} 字 · 准确率 ${(point.accuracy * 100).round()}% · ${_duration(point.seconds)}',
                        ),
                        const SizedBox(height: 7),
                        LinearProgressIndicator(
                          value: maxVerses == 0 ? 0 : point.verses / maxVerses,
                        ),
                        const SizedBox(height: 3),
                        const Text('背诵节数趋势'),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

String _duration(int seconds) =>
    seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分 ${seconds % 60} 秒';
