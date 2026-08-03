import 'user.dart';

class Moment {
  final AppUser user;
  final String timeAgo;
  final String text;
  final String? imageUrl;
  final String? tag;
  final int likes;
  final int comments;
  final bool isTranslatable;

  const Moment({
    required this.user,
    required this.timeAgo,
    required this.text,
    this.imageUrl,
    this.tag,
    this.likes = 0,
    this.comments = 0,
    this.isTranslatable = false,
  });
}
