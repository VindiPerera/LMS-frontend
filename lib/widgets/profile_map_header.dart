import 'package:flutter/material.dart';

import '../utils/location_helper.dart';

class ProfileMapHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Map Background with realistic terrain styling
          CustomPaint(
            painter: _MapPainter(flag: location.flag),
            size: Size.infinite,
          ),

          // Gradient overlay for smooth contrast at edges
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
          ),

          // Top Navigation Controls: Back Button & More Options
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  size: 28,
                  onPressed: onBack,
                ),
                _GlassIconButton(
                  icon: Icons.more_horiz_rounded,
                  size: 22,
                  onPressed: onMore ?? () {},
                ),
              ],
            ),
          ),

          // Location & Local Time Pill (Top right of map area)
          Positioned(
            bottom: 24,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF4A6B8A).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
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
                  Text(
                    '${location.locationLabel}  ${location.timeLabel}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const _GlassIconButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final String flag;
  _MapPainter({required this.flag});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Ocean Water Gradient (matching realistic Google Maps satellite/vector style)
    final oceanPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF6795BD),
          Color(0xFF7CA6CD),
          Color(0xFF8EB7DC),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, oceanPaint);

    // Landmass contour
    final landPaint = Paint()
      ..color = const Color(0xFFDCE2C8)
      ..style = PaintingStyle.fill;

    final forestPaint = Paint()
      ..color = const Color(0xFFC7D8B6)
      ..style = PaintingStyle.fill;

    // Draw main land contour (Island / continent shape)
    final path = Path();
    final centerX = size.width * 0.58;
    final centerY = size.height * 0.42;

    path.moveTo(centerX - 40, centerY - 65);
    path.quadraticBezierTo(centerX + 30, centerY - 80, centerX + 55, centerY - 40);
    path.quadraticBezierTo(centerX + 80, centerY, centerX + 60, centerY + 50);
    path.quadraticBezierTo(centerX + 30, centerY + 85, centerX - 10, centerY + 75);
    path.quadraticBezierTo(centerX - 55, centerY + 45, centerX - 50, centerY);
    path.close();

    canvas.drawPath(path, landPaint);

    // Draw secondary land / topography patch
    final forestPath = Path();
    forestPath.moveTo(centerX - 20, centerY - 50);
    forestPath.quadraticBezierTo(centerX + 40, centerY - 45, centerX + 40, centerY + 20);
    forestPath.quadraticBezierTo(centerX + 10, centerY + 55, centerX - 30, centerY + 30);
    forestPath.close();
    canvas.drawPath(forestPath, forestPaint);

    // Top-left continental edge (e.g. South India / neighbouring land)
    final northLand = Path();
    northLand.moveTo(0, 0);
    northLand.lineTo(size.width * 0.48, 0);
    northLand.quadraticBezierTo(size.width * 0.38, size.height * 0.35, 0, size.height * 0.5);
    northLand.close();
    canvas.drawPath(northLand, landPaint);

    // Road network lines
    final roadPaint = Paint()
      ..color = const Color(0xFFEBD2A0)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final road = Path();
    road.moveTo(centerX - 20, centerY - 60);
    road.quadraticBezierTo(centerX - 10, centerY, centerX - 25, centerY + 40);
    canvas.drawPath(road, roadPaint);

    final road2 = Path();
    road2.moveTo(centerX - 25, centerY + 10);
    road2.lineTo(centerX + 45, centerY - 10);
    canvas.drawPath(road2, roadPaint);

    // Geographic labels
    const labelStyle = TextStyle(
      color: Color(0xFF334455),
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.3,
    );
    final textPainter = TextPainter(
      text: const TextSpan(text: 'Sri Lanka', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(centerX - 22, centerY - 22));

    const waterStyle = TextStyle(
      color: Color(0xFFE2F0FD),
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    final waterPainter = TextPainter(
      text: const TextSpan(text: 'Laccadive Sea', style: waterStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    waterPainter.paint(canvas, Offset(size.width * 0.22, size.height * 0.65));

    // Pin location dot & marker
    final pinX = centerX - 26;
    final pinY = centerY + 18;

    // Pin target shadow
    canvas.drawCircle(
      Offset(pinX, pinY + 2),
      5,
      Paint()..color = Colors.black26,
    );

    // Red Pin Circle
    canvas.drawCircle(
      Offset(pinX, pinY),
      5.5,
      Paint()..color = const Color(0xFFE53935),
    );
    canvas.drawCircle(
      Offset(pinX, pinY),
      2.2,
      Paint()..color = Colors.white,
    );

    // City name label under pin
    const cityStyle = TextStyle(
      color: Color(0xFF1E293B),
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
    );
    final cityPainter = TextPainter(
      text: const TextSpan(text: 'Colombo', style: cityStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    cityPainter.paint(canvas, Offset(pinX - 18, pinY - 14));
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => oldDelegate.flag != flag;
}
