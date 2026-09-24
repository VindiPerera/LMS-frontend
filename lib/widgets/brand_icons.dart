import 'package:flutter/material.dart';

/// Pixel-perfect vector brand icons for WhatsApp, Telegram, and Messenger.
/// Implemented directly via Canvas [Path] and [PathFillType.evenOdd] so they:
///  1. Never depend on external icon font packages like `font_awesome_flutter`
///     (which broke under Flutter 3.44 due to `final class IconData`).
///  2. Render instantly with full hardware acceleration on all platforms.
///  3. Scale smoothly to any requested [size].
class BrandIcon extends StatelessWidget {
  final BrandIconType type;
  final double size;
  final Color color;

  const BrandIcon({
    super.key,
    required this.type,
    this.size = 24.0,
    this.color = Colors.white,
  });

  const BrandIcon.whatsapp({
    super.key,
    this.size = 24.0,
    this.color = Colors.white,
  }) : type = BrandIconType.whatsapp;

  const BrandIcon.telegram({
    super.key,
    this.size = 24.0,
    this.color = Colors.white,
  }) : type = BrandIconType.telegram;

  const BrandIcon.messenger({
    super.key,
    this.size = 24.0,
    this.color = Colors.white,
  }) : type = BrandIconType.messenger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandIconPainter(type: type, color: color),
      ),
    );
  }
}

enum BrandIconType {
  whatsapp,
  telegram,
  messenger,
}

class _BrandIconPainter extends CustomPainter {
  final BrandIconType type;
  final Color color;

  _BrandIconPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // All paths are normalized on a 16x16 grid
    final s = size.width / 16.0;
    final path = Path()..fillType = PathFillType.evenOdd;

    switch (type) {
      case BrandIconType.whatsapp:
        _drawWhatsApp(path, s);
        break;
      case BrandIconType.telegram:
        _drawTelegram(path, s);
        break;
      case BrandIconType.messenger:
        _drawMessenger(path, s);
        break;
    }

    canvas.drawPath(path, paint);
  }

  void _drawWhatsApp(Path path, double s) {
    path.moveTo(13.6010 * s, 2.3260 * s);
    path.arcToPoint(Offset(7.9940 * s, 0.0000 * s), radius: Radius.elliptical(7.8500 * s, 7.8500 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.cubicTo(3.6270 * s, 0.0000 * s, 0.0680 * s, 3.5580 * s, 0.0640 * s, 7.9260 * s);
    path.relativeCubicTo(0.0000 * s, 1.3990 * s, 0.3660 * s, 2.7600 * s, 1.0570 * s, 3.9650 * s);
    path.lineTo(0.0000 * s, 16.0000 * s);
    path.relativeLineTo(4.2040 * s, -1.1020 * s);
    path.arcToPoint(Offset(7.9940 * s, 15.8630 * s), radius: Radius.elliptical(7.9000 * s, 7.9000 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.relativeLineTo(0.0040 * s, 0.0000 * s);
    path.relativeCubicTo(4.3680 * s, 0.0000 * s, 7.9260 * s, -3.5580 * s, 7.9300 * s, -7.9300 * s);
    path.arcToPoint(Offset(13.6010 * s, 2.3260 * s), radius: Radius.elliptical(7.9000 * s, 7.9000 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.close();

    path.moveTo(7.9940 * s, 14.5210 * s);
    path.arcToPoint(Offset(4.6380 * s, 13.6010 * s), radius: Radius.elliptical(6.6000 * s, 6.6000 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.relativeLineTo(-0.2400 * s, -0.1440 * s);
    path.relativeLineTo(-2.4940 * s, 0.6540 * s);
    path.relativeLineTo(0.6660 * s, -2.4330 * s);
    path.relativeLineTo(-0.1560 * s, -0.2510 * s);
    path.arcToPoint(Offset(1.4070 * s, 7.9220 * s), radius: Radius.elliptical(6.5600 * s, 6.5600 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.relativeCubicTo(0.0000 * s, -3.6260 * s, 2.9570 * s, -6.5840 * s, 6.5910 * s, -6.5840 * s);
    path.arcToPoint(Offset(12.6580 * s, 3.2690 * s), radius: Radius.elliptical(6.5600 * s, 6.5600 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.arcToPoint(Offset(14.5860 * s, 7.9290 * s), radius: Radius.elliptical(6.5600 * s, 6.5600 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.relativeCubicTo(-0.0040 * s, 3.6390 * s, -2.9610 * s, 6.5920 * s, -6.5920 * s, 6.5920 * s);

    path.relativeMoveTo(3.6150 * s, -4.9340 * s);
    path.relativeCubicTo(-0.1970 * s, -0.0990 * s, -1.1700 * s, -0.5780 * s, -1.3530 * s, -0.6460 * s);
    path.relativeCubicTo(-0.1820 * s, -0.0650 * s, -0.3150 * s, -0.0990 * s, -0.4450 * s, 0.0990 * s);
    path.relativeCubicTo(-0.1330 * s, 0.1970 * s, -0.5130 * s, 0.6460 * s, -0.6270 * s, 0.7750 * s);
    path.relativeCubicTo(-0.1140 * s, 0.1330 * s, -0.2320 * s, 0.1480 * s, -0.4300 * s, 0.0500 * s);
    path.relativeCubicTo(-0.1970 * s, -0.1000 * s, -0.8360 * s, -0.3080 * s, -1.5920 * s, -0.9850 * s);
    path.relativeCubicTo(-0.5900 * s, -0.5250 * s, -0.9850 * s, -1.1750 * s, -1.1030 * s, -1.3720 * s);
    path.relativeCubicTo(-0.1140 * s, -0.1980 * s, -0.0110 * s, -0.3040 * s, 0.0880 * s, -0.4030 * s);
    path.relativeCubicTo(0.0870 * s, -0.0880 * s, 0.1970 * s, -0.2320 * s, 0.2960 * s, -0.3460 * s);
    path.relativeCubicTo(0.1000 * s, -0.1140 * s, 0.1330 * s, -0.1980 * s, 0.1980 * s, -0.3300 * s);
    path.relativeCubicTo(0.0650 * s, -0.1340 * s, 0.0340 * s, -0.2480 * s, -0.0150 * s, -0.3470 * s);
    path.relativeCubicTo(-0.0500 * s, -0.0990 * s, -0.4450 * s, -1.0760 * s, -0.6120 * s, -1.4700 * s);
    path.relativeCubicTo(-0.1600 * s, -0.3890 * s, -0.3230 * s, -0.3350 * s, -0.4450 * s, -0.3400 * s);
    path.relativeCubicTo(-0.1140 * s, -0.0070 * s, -0.2470 * s, -0.0070 * s, -0.3800 * s, -0.0070 * s);
    path.arcToPoint(Offset(4.6600 * s, 4.5120 * s), radius: Radius.elliptical(0.7300 * s, 0.7300 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.relativeCubicTo(-0.1820 * s, 0.1980 * s, -0.6910 * s, 0.6770 * s, -0.6910 * s, 1.6540 * s);
    path.relativeCubicTo(0.0000 * s, 0.9770 * s, 0.7100 * s, 1.9160 * s, 0.8100 * s, 2.0490 * s);
    path.relativeCubicTo(0.0980 * s, 0.1330 * s, 1.3940 * s, 2.1320 * s, 3.3830 * s, 2.9920 * s);
    path.relativeCubicTo(0.4700 * s, 0.2050 * s, 0.8400 * s, 0.3260 * s, 1.1290 * s, 0.4180 * s);
    path.relativeCubicTo(0.4750 * s, 0.1520 * s, 0.9040 * s, 0.1290 * s, 1.2460 * s, 0.0800 * s);
    path.relativeCubicTo(0.3800 * s, -0.0580 * s, 1.1710 * s, -0.4800 * s, 1.3380 * s, -0.9430 * s);
    path.relativeCubicTo(0.1640 * s, -0.4640 * s, 0.1640 * s, -0.8600 * s, 0.1140 * s, -0.9430 * s);
    path.relativeCubicTo(-0.0490 * s, -0.0840 * s, -0.1820 * s, -0.1330 * s, -0.3800 * s, -0.2320 * s);
  }

  void _drawTelegram(Path path, double s) {
    path.moveTo(16.0000 * s, 8.0000 * s);
    path.arcToPoint(Offset(0.0000 * s, 8.0000 * s), radius: Radius.elliptical(8.0000 * s, 8.0000 * s), rotation: 0.0, largeArc: true, clockwise: true);
    path.arcToPoint(Offset(16.0000 * s, 8.0000 * s), radius: Radius.elliptical(8.0000 * s, 8.0000 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.close();

    path.moveTo(8.2870 * s, 5.9060 * s);
    path.relativeQuadraticBezierTo(-1.1680 * s, 0.4860 * s, -4.6660 * s, 2.0100 * s);
    path.relativeQuadraticBezierTo(-0.5670 * s, 0.2250 * s, -0.5950 * s, 0.4420 * s);
    path.relativeCubicTo(-0.0300 * s, 0.2430 * s, 0.2750 * s, 0.3390 * s, 0.6900 * s, 0.4700 * s);
    path.relativeLineTo(0.1750 * s, 0.0550 * s);
    path.relativeCubicTo(0.4080 * s, 0.1330 * s, 0.9580 * s, 0.2880 * s, 1.2430 * s, 0.2940 * s);
    path.relativeQuadraticBezierTo(0.3900 * s, 0.0100 * s, 0.8680 * s, -0.3200 * s);
    path.relativeQuadraticBezierTo(3.2690 * s, -2.2060 * s, 3.3740 * s, -2.2300 * s);
    path.relativeCubicTo(0.0500 * s, -0.0120 * s, 0.1200 * s, -0.0260 * s, 0.1660 * s, 0.0160 * s);
    path.relativeCubicTo(0.0460 * s, 0.0420 * s, 0.0420 * s, 0.1200 * s, 0.0370 * s, 0.1410 * s);
    path.relativeCubicTo(-0.0300 * s, 0.1290 * s, -1.2270 * s, 1.2410 * s, -1.8460 * s, 1.8170 * s);
    path.relativeCubicTo(-0.1930 * s, 0.1800 * s, -0.3300 * s, 0.3070 * s, -0.3580 * s, 0.3360 * s);
    path.arcToPoint(Offset(7.1870 * s, 9.1230 * s), radius: Radius.elliptical(8.0000 * s, 8.0000 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.relativeCubicTo(-0.3800 * s, 0.3660 * s, -0.6640 * s, 0.6400 * s, 0.0150 * s, 1.0880 * s);
    path.relativeCubicTo(0.3270 * s, 0.2160 * s, 0.5890 * s, 0.3930 * s, 0.8500 * s, 0.5710 * s);
    path.relativeCubicTo(0.2840 * s, 0.1940 * s, 0.5680 * s, 0.3870 * s, 0.9360 * s, 0.6290 * s);
    path.relativeQuadraticBezierTo(0.1400 * s, 0.0920 * s, 0.2700 * s, 0.1870 * s);
    path.relativeCubicTo(0.3310 * s, 0.2360 * s, 0.6300 * s, 0.4480 * s, 0.9970 * s, 0.4140 * s);
    path.relativeCubicTo(0.2140 * s, -0.0200 * s, 0.4350 * s, -0.2200 * s, 0.5470 * s, -0.8200 * s);
    path.relativeCubicTo(0.2650 * s, -1.4170 * s, 0.7860 * s, -4.4860 * s, 0.9060 * s, -5.7510 * s);
    path.arcToPoint(Offset(11.6950 * s, 5.1260 * s), radius: Radius.elliptical(1.4000 * s, 1.4000 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.arcToPoint(Offset(11.5810 * s, 4.9090 * s), radius: Radius.elliptical(0.3400 * s, 0.3400 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.arcToPoint(Offset(11.2710 * s, 4.8160 * s), radius: Radius.elliptical(0.5300 * s, 0.5300 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.relativeCubicTo(-0.3000 * s, 0.0050 * s, -0.7630 * s, 0.1660 * s, -2.9840 * s, 1.0900 * s);
  }

  void _drawMessenger(Path path, double s) {
    path.moveTo(0.0000 * s, 7.7600 * s);
    path.cubicTo(0.0000 * s, 3.3010 * s, 3.4930 * s, 0.0000 * s, 8.0000 * s, 0.0000 * s);
    path.relativeCubicTo(4.5070 * s, 0.0000 * s, 8.0000 * s, 3.3010 * s, 8.0000 * s, 7.7600 * s);
    path.relativeCubicTo(0.0000 * s, 4.4590 * s, -3.4930 * s, 7.7600 * s, -8.0000 * s, 7.7600 * s);
    path.relativeCubicTo(-0.8100 * s, 0.0000 * s, -1.5860 * s, -0.1070 * s, -2.3160 * s, -0.3070 * s);
    path.arcToPoint(Offset(5.2570 * s, 15.2430 * s), radius: Radius.elliptical(0.6400 * s, 0.6400 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.relativeLineTo(-1.5880 * s, 0.7020 * s);
    path.arcToPoint(Offset(2.7710 * s, 15.3790 * s), radius: Radius.elliptical(0.6400 * s, 0.6400 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.relativeLineTo(-0.0440 * s, -1.4230 * s);
    path.arcToPoint(Offset(2.5120 * s, 13.5000 * s), radius: Radius.elliptical(0.6400 * s, 0.6400 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.cubicTo(0.9560 * s, 12.1080 * s, 0.0000 * s, 10.0920 * s, 0.0000 * s, 7.7600 * s);
    path.close();

    path.moveTo(5.5460 * s, 6.3010 * s);
    path.relativeLineTo(-2.3500 * s, 3.7280 * s);
    path.relativeCubicTo(-0.2250 * s, 0.3580 * s, 0.2140 * s, 0.7610 * s, 0.5510 * s, 0.5060 * s);
    path.relativeLineTo(2.5250 * s, -1.9160 * s);
    path.arcToPoint(Offset(6.8500 * s, 8.6170 * s), radius: Radius.elliptical(0.4800 * s, 0.4800 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.relativeLineTo(1.8690 * s, 1.4020 * s);
    path.arcToPoint(Offset(10.4540 * s, 9.6990 * s), radius: Radius.elliptical(1.2000 * s, 1.2000 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.relativeLineTo(2.3500 * s, -3.7280 * s);
    path.relativeCubicTo(0.2260 * s, -0.3580 * s, -0.2140 * s, -0.7610 * s, -0.5510 * s, -0.5060 * s);
    path.lineTo(9.7280 * s, 7.3810 * s);
    path.arcToPoint(Offset(9.1500 * s, 7.3830 * s), radius: Radius.elliptical(0.4800 * s, 0.4800 * s), rotation: 0.0, largeArc: false, clockwise: true);
    path.lineTo(7.2810 * s, 5.9800 * s);
    path.arcToPoint(Offset(5.5460 * s, 6.3000 * s), radius: Radius.elliptical(1.2000 * s, 1.2000 * s), rotation: 0.0, largeArc: false, clockwise: false);
    path.close();
  }

  @override
  bool shouldRepaint(covariant _BrandIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
