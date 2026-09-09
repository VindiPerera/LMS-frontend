import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/location_helper.dart';

/// Professional real-tile Profile Map Header using OpenStreetMap via flutter_map.
///
/// Design goals (matching FaceTalk's language-exchange business context):
///  - Renders the **actual geographic map** of the user's country using
///    Carto Voyager tiles — clean, label-light, globally recognisable.
///  - A precise city pin + animated radar pulse shows exactly where the
///    language partner lives, building social trust immediately.
///  - A frosted-glass location/time pill (bottom-right) gives the viewer
///    the partner's city, country, and live local time at a glance.
///  - Tapping the pill or the map reveals a detail sheet with UTC offset,
///    GPS coordinates, and region — all at a language-app-appropriate level.
///  - Navigation controls (back/more) float above the map with a subtle
///    glassmorphic backdrop.
///  - No external API key is required; Carto's free tile CDN is used.
class ProfileMapHeader extends StatefulWidget {
  final LocationInfo location;
  final VoidCallback onBack;
  final VoidCallback? onMore;

  const ProfileMapHeader({
    super.key,
    required this.location,
    required this.onBack,
    this.onMore,
  });

  @override
  State<ProfileMapHeader> createState() => _ProfileMapHeaderState();
}

class _ProfileMapHeaderState extends State<ProfileMapHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(ProfileMapHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animate to new location when the profile changes (e.g., navigating
    // between partners without rebuilding the route).
    if (oldWidget.location.latitude != widget.location.latitude ||
        oldWidget.location.longitude != widget.location.longitude ||
        oldWidget.location.flag != widget.location.flag) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          _mapCenterForLocation(widget.location),
          _zoomForLocation(widget.location),
        );
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Returns the geographic centre of the user's country so the map camera
  /// frames the entire country — not just the representative city.
  /// The city pin is placed at [loc.latitude / loc.longitude] independently.
  LatLng _mapCenterForLocation(LocationInfo loc) {
    switch (loc.flag) {
      // Sri Lanka: geographic centre of the island (7.85 N, 80.65 E).
      // At zoom 6.35, the full island teardrop (Point Pedro in the north to
      // Dondra Head in the south) fits completely in the 240 px header with
      // the Colombo pin, beacon pulse, and city badge perfectly visible.
      case '🇱🇰': return const LatLng(7.85, 80.65);
      case '🇸🇬': return const LatLng(1.3521, 103.8198);
      case '🇯🇵': return const LatLng(36.2048, 138.2529);
      case '🇬🇧': return const LatLng(54.0, -2.5);
      case '🇩🇪': return const LatLng(51.1657, 10.4515);
      case '🇫🇷': return const LatLng(46.2276, 2.2137);
      case '🇰🇷': return const LatLng(36.2, 127.7669);
      case '🇮🇩': return const LatLng(-2.5489, 118.0149);
      case '🇦🇺': return const LatLng(-25.2744, 133.7751);
      case '🇷🇺': return const LatLng(58.0, 50.0);
      case '🇨🇳': return const LatLng(35.8617, 104.1954);
      case '🇺🇸': return const LatLng(38.5, -96.0);
      case '🇨🇦': return const LatLng(53.0, -96.0);
      case '🇹🇷': return const LatLng(39.0, 35.2433);
      default:
        // Fall back to the city's own coordinates for unlisted countries.
        return LatLng(loc.latitude, loc.longitude);
    }
  }

  /// Returns an appropriate zoom level based on country size.
  /// Sri Lanka at 6.35 shows the full teardrop island inside a 240 px header.
  double _zoomForLocation(LocationInfo loc) {
    switch (loc.flag) {
      case '🇱🇰': return 6.35; // Full island — Jaffna to Dondra Head + clear Colombo pin
      case '🇸🇬': return 11.0; // City-state
      case '🇯🇵': return 5.5;  // Archipelago
      case '🇬🇧': return 5.3;
      case '🇩🇪': return 5.5;
      case '🇫🇷': return 5.5;
      case '🇰🇷': return 6.5;
      case '🇮🇩': return 4.5;  // Wide archipelago
      case '🇦🇺': return 4.0;  // Continent
      case '🇷🇺': return 3.5;  // Massive nation
      case '🇨🇳': return 4.0;
      case '🇺🇸': return 4.0;
      case '🇨🇦': return 3.5;
      case '🇹🇷': return 5.5;
      default:     return 6.0;
    }
  }

  void _showLocationModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LocationDetailSheet(location: widget.location),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final loc = widget.location;
    // cityPin: where the animated beacon is placed (the user's actual city).
    // mapCenter: the geographic centre of the country — keeps the whole
    //            country visible in the fixed 240 px header.
    final cityPin   = LatLng(loc.latitude, loc.longitude);
    final mapCenter = _mapCenterForLocation(loc);
    final zoom      = _zoomForLocation(loc);

    return SizedBox(
      height: 240,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Real OpenStreetMap tile layer (Clean, no API key) ──
          ClipRect(
            child: GestureDetector(
              onTap: _showLocationModal,
              behavior: HitTestBehavior.opaque,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: zoom,
                  interactionOptions: const InteractionOptions(
                    // Disable all gestures: the map is a decorative header,
                    // not a navigable map. Keeps profile page scroll intact.
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  // OpenStreetMap standard tiles — free, no API key, no watermark.
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.facetalk.app',
                    maxZoom: 19,
                  ),

                  // City pin + animated radar pulse placed at the city, not the
                  // country centre — so it always marks the right location.
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: cityPin,
                        width: 120,
                        height: 120,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context2, child) => _PulseMarker(
                            pulse: _pulseController.value,
                            cityName: loc.city,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── 2. Subtle top-to-bottom atmospheric gradient ──
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.32),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── 3. Back & More navigation buttons ──
          Positioned(
            top: topPadding + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlassButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  onPressed: widget.onBack,
                ),
                _GlassButton(
                  icon: Icons.more_horiz_rounded,
                  iconSize: 22,
                  onPressed: widget.onMore ?? () {},
                ),
              ],
            ),
          ),

          // ── 4. Frosted-glass Location + Time pill ──
          Positioned(
            bottom: 20,
            right: 14,
            child: GestureDetector(
              onTap: _showLocationModal,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Online-style pulsing green dot
                        _LiveDot(),
                        const SizedBox(width: 7),
                        // City, Country
                        Text(
                          '${loc.city}, ${loc.country}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                        // Separator dot
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        // Live local time
                        Text(
                          loc.timeLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withValues(alpha: 0.55),
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}


// ────────────────────────────────────────────────────────────────────────────
// City Pin + Radar Pulse Marker
// ────────────────────────────────────────────────────────────────────────────

class _PulseMarker extends StatelessWidget {
  final double pulse;
  final String cityName;

  const _PulseMarker({required this.pulse, required this.cityName});

  @override
  Widget build(BuildContext context) {
    // The marker is 120×120 with the city GPS coordinate at (60, 60).
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer expanding ripple
          _Ring(
            radius: 12 + (30 * pulse),
            alpha: (1.0 - pulse).clamp(0.0, 1.0) * 0.45,
            strokeWidth: 1.6,
          ),
          // Inner ripple (staggered)
          _Ring(
            radius: 12 + (22 * ((pulse + 0.5) % 1.0)),
            alpha: (1.0 - ((pulse + 0.5) % 1.0)).clamp(0.0, 1.0) * 0.3,
            strokeWidth: 1.2,
          ),
          // Glowing center dot directly on the GPS coordinate (60, 60)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.7),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          // Pin body — anchored so the pin tip touches center (60, 60) exactly,
          // with the badge and pin head extending upwards for maximum visibility.
          Positioned(
            bottom: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // City label badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        cityName,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                // Pin head
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                // Pin tail
                CustomPaint(
                  size: const Size(10, 6),
                  painter: _PinTailPainter(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double radius;
  final double alpha;
  final double strokeWidth;

  const _Ring({
    required this.radius,
    required this.alpha,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: alpha),
          width: strokeWidth,
        ),
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    // Use ui.Path explicitly to avoid clash with flutter_map's Path type.
    final path = ui.Path()
      ..moveTo(size.width / 2 - 4, 0)
      ..lineTo(size.width / 2 + 4, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ────────────────────────────────────────────────────────────────────────────
// Live green status dot (pulsing to indicate active/online region)
// ────────────────────────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context2, child) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: _anim.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: _anim.value * 0.6),
              blurRadius: 5,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Floating glass navigation button
// ────────────────────────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;

  const _GlassButton({
    required this.icon,
    required this.iconSize,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Location Detail Bottom Sheet
// ────────────────────────────────────────────────────────────────────────────

class _LocationDetailSheet extends StatelessWidget {
  final LocationInfo location;
  const _LocationDetailSheet({required this.location});

  @override
  Widget build(BuildContext context) {
    final utcSign = location.utcOffsetHours >= 0 ? '+' : '';
    final utcStr =
        '$utcSign${location.utcOffsetHours.toStringAsFixed(location.utcOffsetHours % 1 == 0 ? 0 : 1)}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Flag + Country header
          Row(
            children: [
              Text(location.flag, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${location.city}, ${location.country}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    location.region,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 18),

          // Stat tiles row
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.access_time_rounded,
                  label: 'Local Time',
                  value: location.timeLabel,
                  sub: 'UTC $utcStr',
                  iconColor: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.explore_outlined,
                  label: 'Coordinates',
                  value: location.formattedCoordinates,
                  sub: 'WGS84',
                  iconColor: const Color(0xFF0EA5E9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Language exchange community note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EFFE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.language_rounded,
                  size: 18,
                  color: Color(0xFF7B68F4),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This partner is available for language exchange from ${location.city}.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF4B4B9A),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Map data © OpenStreetMap contributors',
              style: TextStyle(
                fontSize: 10.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color iconColor;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
