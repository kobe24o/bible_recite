import 'recitation_alignment.dart';

abstract interface class RecitationComparator {
  const RecitationComparator();

  RecitationAlignment compare(
    String target,
    String transcript, {
    required bool finished,
  });
}
