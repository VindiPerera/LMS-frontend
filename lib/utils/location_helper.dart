import '../models/user.dart';

class LocationHelper {
  static const Map<String, LocationInfo> _countryMap = {
    '🇱🇰': LocationInfo(
      city: 'Colombo',
      country: 'Sri Lanka',
      flag: '🇱🇰',
      utcOffsetHours: 5.5,
      latitude: 6.9271,
      longitude: 79.8612,
      region: 'South Asia',
    ),
    '🇺🇸': LocationInfo(
      city: 'New York',
      country: 'United States',
      flag: '🇺🇸',
      utcOffsetHours: -4.0,
      latitude: 40.7128,
      longitude: -74.0060,
      region: 'North America',
    ),
    '🇬🇧': LocationInfo(
      city: 'London',
      country: 'United Kingdom',
      flag: '🇬🇧',
      utcOffsetHours: 1.0,
      latitude: 51.5074,
      longitude: -0.1278,
      region: 'Western Europe',
    ),
    '🇨🇦': LocationInfo(
      city: 'Toronto',
      country: 'Canada',
      flag: '🇨🇦',
      utcOffsetHours: -4.0,
      latitude: 43.6532,
      longitude: -79.3832,
      region: 'North America',
    ),
    '🇯🇵': LocationInfo(
      city: 'Tokyo',
      country: 'Japan',
      flag: '🇯🇵',
      utcOffsetHours: 9.0,
      latitude: 35.6762,
      longitude: 139.6503,
      region: 'East Asia',
    ),
    '🇪🇸': LocationInfo(
      city: 'Madrid',
      country: 'Spain',
      flag: '🇪🇸',
      utcOffsetHours: 2.0,
      latitude: 40.4168,
      longitude: -3.7038,
      region: 'Southern Europe',
    ),
    '🇨🇳': LocationInfo(
      city: 'Beijing',
      country: 'China',
      flag: '🇨🇳',
      utcOffsetHours: 8.0,
      latitude: 39.9042,
      longitude: 116.4074,
      region: 'East Asia',
    ),
    '🇮🇩': LocationInfo(
      city: 'Jakarta',
      country: 'Indonesia',
      flag: '🇮🇩',
      utcOffsetHours: 7.0,
      latitude: -6.2088,
      longitude: 106.8456,
      region: 'Southeast Asia',
    ),
    '🇦🇺': LocationInfo(
      city: 'Sydney',
      country: 'Australia',
      flag: '🇦🇺',
      utcOffsetHours: 10.0,
      latitude: -33.8688,
      longitude: 151.2093,
      region: 'Oceania',
    ),
    '🇷🇺': LocationInfo(
      city: 'Moscow',
      country: 'Russia',
      flag: '🇷🇺',
      utcOffsetHours: 3.0,
      latitude: 55.7558,
      longitude: 37.6173,
      region: 'Eastern Europe',
    ),
    '🇹🇷': LocationInfo(
      city: 'Istanbul',
      country: 'Turkey',
      flag: '🇹🇷',
      utcOffsetHours: 3.0,
      latitude: 41.0082,
      longitude: 28.9784,
      region: 'Middle East',
    ),
    '🇩🇪': LocationInfo(
      city: 'Berlin',
      country: 'Germany',
      flag: '🇩🇪',
      utcOffsetHours: 2.0,
      latitude: 52.5200,
      longitude: 13.4050,
      region: 'Central Europe',
    ),
    '🇫🇷': LocationInfo(
      city: 'Paris',
      country: 'France',
      flag: '🇫🇷',
      utcOffsetHours: 2.0,
      latitude: 48.8566,
      longitude: 2.3522,
      region: 'Western Europe',
    ),
    '🇰🇷': LocationInfo(
      city: 'Seoul',
      country: 'South Korea',
      flag: '🇰🇷',
      utcOffsetHours: 9.0,
      latitude: 37.5665,
      longitude: 126.9780,
      region: 'East Asia',
    ),
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
      latitude: 6.9271,
      longitude: 79.8612,
      region: 'South Asia',
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
  final double latitude;
  final double longitude;
  final String region;

  const LocationInfo({
    required this.city,
    required this.country,
    required this.flag,
    required this.utcOffsetHours,
    required this.latitude,
    required this.longitude,
    required this.region,
  });

  String get locationLabel => '$city, $country';

  String get timeLabel => LocationHelper.getLocalTimeString(utcOffsetHours);

  String get formattedCoordinates {
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lonDir = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(4)}° $latDir, ${longitude.abs().toStringAsFixed(4)}° $lonDir';
  }
}
