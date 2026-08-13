import 'package:flutter/material.dart';

import '../../quiz/domain/quiz_scope.dart';
import '../../scripture/domain/scripture_models.dart';

final class RandomQuizOptions {
  const RandomQuizOptions({
    required this.scopes,
    required this.maxQuestionCount,
  });

  final List<QuizScope> scopes;
  final int maxQuestionCount;
}

class RandomQuizOptionsDialog extends StatefulWidget {
  const RandomQuizOptionsDialog({required this.books, super.key});

  final List<BibleBook> books;

  @override
  State<RandomQuizOptionsDialog> createState() =>
      _RandomQuizOptionsDialogState();
}

class _RandomQuizOptionsDialogState extends State<RandomQuizOptionsDialog> {
  late BibleBook _startBook;
  late BibleBook _endBook;
  int _startChapter = 1;
  int _endChapter = 1;
  final _countController = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _startBook = widget.books.first;
    _endBook = widget.books.last;
    _endChapter = _endBook.chapterCount;
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endBooks = widget.books
        .where((book) => book.ordinal >= _startBook.ordinal)
        .toList(growable: false);
    return AlertDialog(
      title: const Text('随机答题'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bookField('开始卷', _startBook, widget.books, (book) {
              setState(() {
                _startBook = book;
                if (_startChapter > book.chapterCount) {
                  _startChapter = book.chapterCount;
                }
                if (_endBook.ordinal < book.ordinal) {
                  _endBook = book;
                  _endChapter = book.chapterCount;
                }
                if (_endBook == book && _endChapter < _startChapter) {
                  _endChapter = _startChapter;
                }
              });
            }),
            _chapterField('开始章', _startBook, _startChapter, (chapter) {
              setState(() {
                _startChapter = chapter;
                if (_startBook == _endBook && _endChapter < chapter) {
                  _endChapter = chapter;
                }
              });
            }),
            const Divider(),
            _bookField('结束卷', _endBook, endBooks, (book) {
              setState(() {
                _endBook = book;
                _endChapter = book == _startBook
                    ? _startChapter
                    : book.chapterCount;
              });
            }),
            _chapterField('结束章', _endBook, _endChapter, (chapter) {
              setState(() => _endChapter = chapter);
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _countController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '最大题数',
                helperText: '默认 10 道，最多 50 道',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('开始答题')),
      ],
    );
  }

  Widget _bookField(
    String label,
    BibleBook value,
    Iterable<BibleBook> books,
    ValueChanged<BibleBook> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:${value.osisId}'),
    initialValue: value.osisId,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final book in books)
        DropdownMenuItem(value: book.osisId, child: Text(book.name)),
    ],
    onChanged: (id) => onChanged(books.firstWhere((book) => book.osisId == id)),
  );

  Widget _chapterField(
    String label,
    BibleBook book,
    int value,
    ValueChanged<int> onChanged,
  ) => DropdownButtonFormField<int>(
    key: ValueKey('$label:${book.osisId}'),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (var chapter = 1; chapter <= book.chapterCount; chapter++)
        DropdownMenuItem(value: chapter, child: Text('$chapter')),
    ],
    onChanged: (chapter) {
      if (chapter != null) onChanged(chapter);
    },
  );

  void _save() {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count < 1 || count > 50) return;
    final startIndex = widget.books.indexOf(_startBook);
    final endIndex = widget.books.indexOf(_endBook);
    final scopes = <QuizScope>[];
    for (var index = startIndex; index <= endIndex; index++) {
      final book = widget.books[index];
      scopes.add(
        QuizScope(
          translationId: 'cmn-cu89s',
          bookId: book.osisId,
          startChapter: book == _startBook ? _startChapter : 1,
          startVerse: 1,
          endChapter: book == _endBook ? _endChapter : book.chapterCount,
          // The screen resolves this chapter boundary to the actual final
          // verse before either local selection or model generation.
          endVerse: 999,
        ),
      );
    }
    Navigator.pop(
      context,
      RandomQuizOptions(scopes: scopes, maxQuestionCount: count),
    );
  }
}
