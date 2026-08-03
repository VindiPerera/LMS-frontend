class VoiceRoom {
  final String title;
  final String hostName;
  final String hostAvatar;
  final String hostFlag;
  final String category;
  final String tag;
  final String coverGradientSeed;
  final List<String> participantAvatars;
  final int participantCount;
  final bool isTop;
  final bool isCreator;

  const VoiceRoom({
    required this.title,
    required this.hostName,
    required this.hostAvatar,
    required this.hostFlag,
    required this.category,
    required this.tag,
    this.coverGradientSeed = 'a',
    this.participantAvatars = const [],
    this.participantCount = 0,
    this.isTop = false,
    this.isCreator = false,
  });
}
