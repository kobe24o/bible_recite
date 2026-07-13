import 'package:flutter/material.dart';

import '../domain/scripture_models.dart';

class BookGrid extends StatelessWidget {
  const BookGrid({required this.books, required this.onSelected, super.key});

  final List<BibleBook> books;
  final ValueChanged<BibleBook> onSelected;

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
        return OutlinedButton(
          onPressed: () => onSelected(book),
          child: Text(book.name),
        );
      },
    );
  }
}
