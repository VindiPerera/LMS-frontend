class LearnCard {
  final String title;
  final String subtitle;
  final String badge;
  final String coverSeed;

  const LearnCard({
    required this.title,
    required this.subtitle,
    this.badge = '',
    this.coverSeed = 'a',
  });
}

class WordPack {
  final String title;
  final String progress;
  final bool locked;
  final String badge;

  const WordPack({
    required this.title,
    required this.progress,
    this.locked = false,
    this.badge = '',
  });
}

class CourseBanner {
  final String tagline;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final String coverSeed;

  const CourseBanner({
    required this.tagline,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.coverSeed,
  });
}

class Tutor {
  final String name;
  final String flag;
  final String languages;
  final String bio;
  final bool isPro;

  const Tutor({
    required this.name,
    required this.flag,
    required this.languages,
    required this.bio,
    this.isPro = false,
  });
}
