class AppUser {
  final String name;
  final String handle;
  final String avatarUrl;
  final String countryFlag;
  final String nativeLang;
  final String learningLang;
  final bool isOnline;
  final bool isVip;
  final int age;
  final String gender;
  final String bio;
  final String activeLabel;
  final List<String> tags;

  const AppUser({
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.countryFlag,
    required this.nativeLang,
    required this.learningLang,
    this.isOnline = false,
    this.isVip = false,
    this.age = 0,
    this.gender = 'other',
    this.bio = '',
    this.activeLabel = '',
    this.tags = const [],
  });
}
