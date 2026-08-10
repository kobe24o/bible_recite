import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/quiz_result.dart';
import '../domain/quiz_scope.dart';
import 'quiz_generation_service.dart';

enum QuizPreparationPhase { idle, waiting, preparing, ready, failed }

/// Drives one quiz-generation lifecycle shared by the three entry screens:
/// Bible reading, plan reading and Today's tasks.  It waits a fixed duration
/// (or prepares immediately when [immediate] is true), then calls
/// [QuizGenerationService.prepare] and surfaces cached or newly generated
/// pending questions plus a retry path for failures.
final class QuizPreparationController extends ChangeNotifier {
  QuizPreparationController({
    required this.scope,
    this.immediate = false,
    required this.serviceLoader,
  });

  final QuizScope scope;
  final bool immediate;
  final Future<QuizGenerationService> Function() serviceLoader;

  QuizPreparationPhase _phase = QuizPreparationPhase.idle;
  QuizPreparationPhase get phase => _phase;
  String? _error;
  String? get error => _error;
  List<PendingQuizQuestion> _questions = const [];
  List<PendingQuizQuestion> get questions => _questions;

  Timer? _timer;
  Future<void>? _task;
  bool _disposed = false;
  int _generation = 0;

  /// Loads the generation service and prepares.  Safe to call multiple
  /// times: duplicate calls while one is running are ignored.
  Future<void> prepare() {
    final running = _task;
    if (running != null) return running;
    final task = _run(++_generation);
    _task = task;
    return task;
  }

  Future<void> _run(int generation) async {
    if (_disposed) return;
    _phase = QuizPreparationPhase.preparing;
    _error = null;
    _notify();
    QuizGenerationService? service;
    try {
      service = await serviceLoader();
      if (_disposed || generation != _generation) return;
      final outcome = await service.prepare(scope);
      if (_disposed || generation != _generation) return;
      if (await _useCachedQuestions(service, generation)) return;
      if (_disposed || generation != _generation) return;
      _questions = const [];
      _error = outcome.success ? '没有可开始的答题题目' : outcome.error;
      _phase = QuizPreparationPhase.failed;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        if (service != null && await _useCachedQuestions(service, generation)) {
          return;
        }
        if (_disposed || generation != _generation) return;
        _questions = const [];
        _error = '生成答题题目失败：$error';
        _phase = QuizPreparationPhase.failed;
      }
    } finally {
      if (generation == _generation) {
        _task = null;
        if (!_disposed) _notify();
      }
    }
  }

  Future<bool> _useCachedQuestions(
    QuizGenerationService service,
    int generation,
  ) async {
    try {
      final questions = await service.repository.listQuizQuestionsForPractice(
        scope,
      );
      if (_disposed || generation != _generation || questions.isEmpty) {
        return false;
      }
      _questions = questions;
      _error = null;
      _phase = QuizPreparationPhase.ready;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Starts the five-second countdown (or prepares immediately when the
  /// generation scope is authoritative, e.g. Today's tasks).  Any earlier
  /// timer or running task is cancelled first.
  void arm() {
    cancel();
    if (_disposed) return;
    if (immediate) {
      unawaited(prepare());
      return;
    }
    _phase = QuizPreparationPhase.waiting;
    _notify();
    _timer = Timer(const Duration(seconds: 5), () {
      _timer = null;
      unawaited(prepare());
    });
  }

  /// Cancels any pending timer and running generation (the task itself will
  /// not be awaited); used when the entry screen is left early.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _task = null;
    if (_disposed) return;
    _phase = QuizPreparationPhase.idle;
    _error = null;
    _questions = const [];
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

const quizPreparationDelay = Duration(seconds: 5);
