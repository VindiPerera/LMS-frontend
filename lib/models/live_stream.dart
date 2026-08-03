class LiveStream {
  final String hostName;
  final String hostFlag;
  final String title;
  final String tag;
  final int viewers;
  final String badgeLabel;
  final String coverSeed;

  const LiveStream({
    required this.hostName,
    required this.hostFlag,
    required this.title,
    required this.tag,
    required this.viewers,
    required this.badgeLabel,
    required this.coverSeed,
  });
}
