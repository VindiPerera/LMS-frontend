import '../models/user.dart';

class LocationHelper {
  static const Map<String, LocationInfo> _countryMap = {
    '🇱🇰': LocationInfo(city: 'Colombo', country: 'Sri Lanka', flag: '🇱🇰', utcOffsetHours: 5.5),
    '🇺🇸': LocationInfo(city: 'New York', country: 'United States', flag: '🇺🇸', utcOffsetHours: -4.0),
    '🇬🇧': LocationInfo(city: 'London', country: 'United Kingdom', flag: '🇬🇧', utcOffsetHours: 1.0),
    '🇨🇦': LocationInfo(city: 'Toronto', country: 'Canada', flag: '🇨🇦', utcOffsetHours: -4.0),
    '🇯🇵': LocationInfo(city: 'Tokyo', country: 'Japan', flag: '🇯🇵', utcOffsetHours: 9.0),
    '🇪🇸': LocationInfo(city: 'Madrid', country: 'Spain', flag: '🇪🇸', utcOffsetHours: 2.0),
    '🇨🇳': LocationInfo(city: 'Beijing', country: 'China', flag: '🇨🇳', utcOffsetHours: 8.0),
    '🇮🇩': LocationInfo(city: 'Jakarta', country: 'Indonesia', flag: '🇮🇩', utcOffsetHours: 7.0),
    '🇦🇺': LocationInfo(city: 'Sydney', country: 'Australia', flag: '🇦🇺', utcOffsetHours: 10.0),
    '🇷🇺': LocationInfo(city: 'Moscow', country: 'Russia', flag: '🇷🇺', utcOffsetHours: 3.0),
    '🇹🇷': LocationInfo(city: 'Istanbul', country: 'Turkey', flag: '🇹🇷', utcOffsetHours: 3.0),
    '🇩🇪': LocationInfo(city: 'Berlin', country: 'Germany', flag: '🇩🇪', utcOffsetHours: 2.0),
    '🇫🇷': LocationInfo(city: 'Paris', country: 'France', flag: '🇫🇷', utcOffsetHours: 2.0),
    '🇰🇷': LocationInfo(city: 'Seoul', country: 'South Korea', flag: '🇰🇷', utcOffsetHours: 9.0),
  };

  /// Resolves location info based on user countryFlag, native language, or defaults.
  static LocationInfo getLocationInfo(AppUser user) {
    if (user.countryFlag.isNotEmpty && _countryMap.containsKey(user.countryFlag)) {
      return _countryMap[user.countryFlag]!;
    }

    final native = user.nativeLang.toLowerCase();
    if (native.contains('sinhala')) {
      return _countryMap['🇱🇰']!;
    } else if (native.contains('japanese')) {
      return _countryMap['🇯🇵']!;
    } else if (native.contains('spanish')) {
      return _countryMap['🇪🇸']!;
    } else if (native.contains('chinese')) {
      return _countryMap['🇨🇳']!;
    } else if (native.contains('indonesian')) {
      return _countryMap['🇮🇩']!;
    } else if (native.contains('russian')) {
      return _countryMap['🇷🇺']!;
    }

    // Default to Sri Lanka (matching the design specifications)
    return const LocationInfo(
      city: 'Colombo',
      country: 'Sri Lanka',
      flag: '🇱🇰',
      utcOffsetHours: 5.5,
    );
  }

  /// Calculates real-time local time in `h:mm a` format for the specified UTC offset.
  static String getLocalTimeString(double utcOffsetHours) {
    final utcNow = DateTime.now().toUtc();
    final offsetMinutes = (utcOffsetHours * 60).round();
    final localTime = utcNow.add(Duration(minutes: offsetMinutes));

    final hour24 = localTime.hour;
    final hour12 = (hour24 == 0 || hour24 == 12) ? 12 : hour24 % 12;
    final minute = localTime.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';

    return '$hour12:$minute $period';
  }
}

class LocationInfo {
  final String city;
  final String country;
  final String flag;
  final double utcOffsetHours;

  const LocationInfo({
    required this.city,
    required this.country,
    required this.flag,
    required this.utcOffsetHours,
  });

  String get locationLabel => '$city, $country';

  String get timeLabel => LocationHelper.getLocalTimeString(utcOffsetHours);
}
