import 'package:flutter/material.dart';

import '../domain/achievement.dart';

Future<void> showAchievementUnlockDialog(
  BuildContext context,
  AchievementProgress progress, {
  bool newlyUnlocked = false,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      AchievementUnlockDialog(progress: progress, newlyUnlocked: newlyUnlocked),
);

class AchievementUnlockDialog extends StatefulWidget {
  const AchievementUnlockDialog({
    required this.progress,
    required this.newlyUnlocked,
    super.key,
  });

  final AchievementProgress progress;
  final bool newlyUnlocked;

  @override
  State<AchievementUnlockDialog> createState() =>
      _AchievementUnlockDialogState();
}

class _AchievementUnlockDialogState extends State<AchievementUnlockDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badgeController;
  late final Animation<double> _badgeScale;

  @override
  void initState() {
    super.initState();
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..forward();
    _badgeScale = Tween<double>(begin: 0.32, end: 1).animate(
      CurvedAnimation(parent: _badgeController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _badgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final newlyUnlocked = widget.newlyUnlocked;
    final unlocked = progress.unlockedAt != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: TweenAnimationBuilder<double>(
        key: const Key('achievement-unlock-animation'),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutBack,
        tween: Tween(begin: 0.68, end: 1),
        builder: (context, value, child) => Opacity(
          opacity: ((value - 0.68) / 0.32).clamp(0, 1),
          child: Transform.scale(scale: value, child: child),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE3B64F), width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3D7A5710),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned(
                    top: 0,
                    right: 7,
                    child: Icon(Icons.auto_awesome, color: Color(0xFFE3B64F)),
                  ),
                  const Positioned(
                    left: 3,
                    bottom: 13,
                    child: Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFF3CF73),
                      size: 18,
                    ),
                  ),
                  ScaleTransition(
                    key: const Key('achievement-detail-badge-animation'),
                    scale: _badgeScale,
                    child: AchievementBadgeArtwork(
                      key: const Key('achievement-detail-badge-artwork'),
                      progress: progress,
                      size: 132,
                      showSymbol: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                newlyUnlocked ? '获得新成就' : progress.definition.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF7B5615),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (newlyUnlocked)
                Text(
                  progress.definition.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                progress.definition.description,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text('当前进度：${(progress.fraction * 100).round()}%'),
              if (unlocked) ...[
                const SizedBox(height: 4),
                Text('已获得', style: TextStyle(color: Colors.green.shade700)),
                if (!newlyUnlocked)
                  Text(
                    '获得时间：${_formatDateTime(progress.unlockedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(newlyUnlocked ? '太棒了' : '关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AchievementBadgeArtwork extends StatelessWidget {
  const AchievementBadgeArtwork({
    required this.progress,
    this.size = 48,
    this.compact = false,
    this.showSymbol = true,
    super.key,
  });

  final AchievementProgress progress;
  final double size;
  final bool compact;
  final bool showSymbol;

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.unlockedAt != null;
    if (!unlocked) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.lock_outline, size: size * .42),
      );
    }
    if (compact) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF4C9),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _symbolFor(progress.definition.id),
          size: size * .58,
          color: const Color(0xFF7B5615),
        ),
      );
    }
    if (!showSymbol) {
      return Image.asset(
        'assets/achievements/golden_bible_badge.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/achievements/golden_bible_badge.png',
            width: size,
            height: size,
            filterQuality: FilterQuality.high,
          ),
          Container(
            width: size * .34,
            height: size * .34,
            decoration: const BoxDecoration(
              color: Color(0xE6FFF8E8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _symbolFor(progress.definition.id),
              size: size * .2,
              color: const Color(0xFF7B5615),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _symbolFor(String id) {
  if (id.startsWith('preset_plan_')) return Icons.menu_book_rounded;
  if (id.startsWith('book_complete_') || id.contains('testament')) {
    return Icons.auto_stories_rounded;
  }
  if (id.startsWith('sessions_') || id == 'first_recitation') {
    return Icons.record_voice_over_rounded;
  }
  if (id.startsWith('verses_') || id.startsWith('chapter_')) {
    return Icons.format_quote_rounded;
  }
  if (id.startsWith('accuracy_') || id.startsWith('perfect_')) {
    return Icons.verified_rounded;
  }
  if (id.startsWith('plan_') || id == 'first_plan') {
    return Icons.event_available_rounded;
  }
  if (id.startsWith('streak_')) return Icons.local_fire_department_rounded;
  return Icons.workspace_premium_rounded;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
