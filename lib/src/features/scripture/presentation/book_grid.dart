import 'package:flutter/material.dart';

import '../domain/scripture_models.dart';

class BookGrid extends StatelessWidget {
  const BookGrid({
    required this.books,
    required this.onSelected,
    this.selectedBookId,
    super.key,
  });

  final List<BibleBook> books;
  final ValueChanged<BibleBook> onSelected;
  final String? selectedBookId;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 2.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final selected = book.osisId == selectedBookId;
        return selected
            ? FilledButton(
                key: Key('selected-book-${book.osisId}'),
                onPressed: () => onSelected(book),
                child: Text(book.name),
              )
            : OutlinedButton(
                key: Key('book-${book.osisId}'),
                onPressed: () => onSelected(book),
                child: Text(book.name),
              );
      },
    );
  }
}
