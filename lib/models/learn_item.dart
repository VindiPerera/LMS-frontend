class Tutor {
  final String id;
  final String name;
  final String flag;
  final String languages;
  final String bio;
  final bool isPro;
  final String avatarUrl;
  final int age;
  final String gender;
  final String handle;
  final double rating;
  final int reviewCount;
  final int studentsCount;
  final int lessonsCount;

  const Tutor({
    this.id = '',
    required this.name,
    required this.flag,
    required this.languages,
    required this.bio,
    this.isPro = false,
    this.avatarUrl = '',
    this.age = 30,
    this.gender = 'other',
    this.handle = '',
    this.rating = 4.9,
    this.reviewCount = 58,
    this.studentsCount = 120,
    this.lessonsCount = 450,
  });
}

