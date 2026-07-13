import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

class ChapterGrid extends StatelessWidget {
  const ChapterGrid({
    required this.chapterCount,
    required this.onSelected,
    super.key,
  });

  final int chapterCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 2.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: chapterCount,
      itemBuilder: (context, index) {
        final chapter = index + 1;
        return FilledButton.tonal(
          onPressed: () => onSelected(chapter),
          child: Text(
            AppLocalizations.of(context)?.chapterLabel(chapter) ??
                'Chapter $chapter',
          ),
        );
      },
    );
  }
}
