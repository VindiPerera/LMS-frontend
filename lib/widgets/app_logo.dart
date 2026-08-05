import 'package:flutter/material.dart';

/// FaceTalk official brand logo widget (stacked vertical layout matching design).
class AppLogo extends StatelessWidget {
  final double height;
  final bool isHorizontal;

  const AppLogo({
    super.key,
    double? height,
    double? size,
    bool showLabel = false,
    this.isHorizontal = false,
  }) : height = height ?? size ?? 110.0;

  @override
  Widget build(BuildContext context) {
    final assetPath = isHorizontal
        ? 'assets/images/facetalk_logo.png'
        : 'assets/images/facetalk_logo_vertical.png';

    return Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFF3B7AC5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 6),
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                children: [
                  TextSpan(text: 'Face', style: TextStyle(color: Color(0xFF3B7AC5))),
                  TextSpan(text: 'Talk', style: TextStyle(color: Color(0xFF98489A))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
