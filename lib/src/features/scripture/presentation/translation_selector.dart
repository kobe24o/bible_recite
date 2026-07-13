import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../domain/scripture_models.dart';

class TranslationSelector extends StatelessWidget {
  const TranslationSelector({
    required this.translations,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<TranslationInfo> translations;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('translation-selector'),
      initialValue: value,
      decoration: InputDecoration(
        labelText:
            AppLocalizations.of(context)?.translationLabel ?? 'Translation',
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final translation in translations)
          DropdownMenuItem(
            value: translation.id,
            child: Text(translation.name),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}
