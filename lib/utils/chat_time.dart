/// Formats a message/thread timestamp for display in the chat list and
/// message bubbles (hellotalk/chat_list_screen.dart,
/// hellotalk/chat_detail_screen.dart) without pulling in the `intl` package
/// for just this.
String formatChatTime(DateTime dt) {
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  if (sameDay(dt, now)) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  final yesterday = now.subtract(const Duration(days: 1));
  if (sameDay(dt, yesterday)) return 'Yesterday';

  if (now.difference(dt).inDays < 7) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[dt.weekday - 1];
  }

  return '${dt.month}/${dt.day}/${dt.year % 100}';
}
