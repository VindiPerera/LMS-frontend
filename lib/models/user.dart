class AppUser {
  final int id;
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
  // Fields below only come from the backend (hello-backend's UserResource);
  // mock/local AppUsers leave them at their defaults.
  final String email;
  final String role;
  final String detail;
  final bool profileCompleted;

  const AppUser({
    this.id = 0,
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
    this.email = '',
    this.role = 'student',
    this.detail = '',
    this.profileCompleted = false,
  });

  /// Decodes a `UserResource` JSON object from the Laravel API. Field names
  /// are shared by design — see hello-backend's UserResource docblock.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      handle: json['handle']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      countryFlag: json['countryFlag']?.toString() ?? '',
      nativeLang: json['nativeLang']?.toString() ?? '',
      learningLang: json['learningLang']?.toString() ?? '',
      isOnline: json['isOnline'] == true,
      isVip: json['isVip'] == true,
      age: _asInt(json['age']),
      gender: json['gender']?.toString() ?? 'other',
      bio: json['bio']?.toString() ?? '',
      activeLabel: json['activeLabel']?.toString() ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'student',
      detail: json['detail']?.toString() ?? '',
      profileCompleted: json['profileCompleted'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
