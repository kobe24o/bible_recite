import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/presentation/quiz_model_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('saves settings and masks the saved key', (tester) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: QuizModelSettingsCard(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('GLM-4.7-Flash'), findsWidgets);
    expect(find.textContaining('未配置密钥'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quiz-model-settings-open')));
    await tester.pumpAndSettle();
    expect(find.text('答题模型设置'), findsOneWidget);

    final keyField = find.widgetWithText(TextField, 'API Key').first;
    await tester.enterText(keyField, 'super-secret');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已配置密钥'), findsOneWidget);
    final saved = await repository.getQuizModelSettings();
    expect(saved.apiKey, 'super-secret');
    expect(saved.model, 'GLM-4.7-Flash');
    expect(saved.baseUrl, QuizModelSettings.defaultBaseUrl);

    await tester.tap(find.byKey(const Key('quiz-model-clear-key')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未配置密钥'), findsOneWidget);
    expect((await repository.getQuizModelSettings()).apiKey, isEmpty);
  });
}
