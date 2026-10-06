import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Full-screen crop editor — the standard Instagram/WhatsApp-style profile
/// photo cropper. The user pinches to zoom and drags to position the image
/// inside a fixed circular viewport; tapping "Use" returns the cropped PNG
/// bytes as a [Uint8List] via [Navigator.pop].
///
/// Usage:
/// ```dart
/// final bytes = await Navigator.of(context).push<Uint8List>(
///   MaterialPageRoute(builder: (_) => ImageCropScreen(imageBytes: raw)),
/// );
/// if (bytes != null) { /* upload */ }
/// ```
///
/// Implementation notes:
/// • Gesture detection is done with Flutter's own [GestureDetector] (scale
///   callback covers both pinch-zoom and simultaneous pan), so no third-party
///   crop package is required.
/// • The actual pixel crop is performed with [dart:ui]'s PictureRecorder /
///   Canvas, mapping the viewport state back to image-space coordinates, so
///   the export is always pixel-accurate to what the user sees.
/// • Output is a square PNG at [outputSize]×[outputSize] px clipped to a
///   circle — ready to hand straight to StorageService.uploadAvatar.
class ImageCropScreen extends StatefulWidget {
  final Uint8List imageBytes;

  /// Side length (px) of the exported square image. 512 is crisp on 3× screens.
  final int outputSize;

  const ImageCropScreen({
    super.key,
    required this.imageBytes,
    this.outputSize = 512,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;

  // Current transform: zoom level and pan offset (screen-space, relative to
  // the centre of the crop area).
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // Captured at gesture-start so incremental deltas compose correctly.
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocalPoint = Offset.zero;

  // Minimum scale that keeps the image fully covering the crop circle.
  double _minScale = 1.0;

  // Diameter of the circular viewport — set on every build() call once the
  // MediaQuery size is available.
  double _cropDiameter = 0;

  bool _exporting = false;

  // Spring-back animation when the user pans the image out of the valid range.
  late AnimationController _snapCtrl;
  Animation<Offset>? _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_snapAnim != null) setState(() => _offset = _snapAnim!.value);
      });
    _decodeImage();
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _snapCtrl.stop();
    _startScale = _scale;
    _startOffset = _offset;
    _startFocalPoint = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_image == null) return;

    final newScale = (_startScale * d.scale).clamp(_minScale, 5.0);
    final focalDelta = d.focalPoint - _startFocalPoint;

    // Keep the focal point stationary in image-space as scale changes.
    final scaleRatio = newScale / _startScale;
    final rawOffset =
        (_startOffset - _startFocalPoint) * scaleRatio + _startFocalPoint + focalDelta;

    setState(() {
      _scale = newScale;
      _offset = _clampOffset(rawOffset, newScale);
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    final clamped = _clampOffset(_offset, _scale);
    if (clamped == _offset) return;
    _snapAnim = Tween<Offset>(begin: _offset, end: clamped)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut));
    _snapCtrl.forward(from: 0);
  }

  // ── Pan-range helpers ─────────────────────────────────────────────────────

  /// The image's rendered size on screen when [_scale] == 1 (fit-to-circle).
  Size _baseSize(ui.Image img) {
    if (_cropDiameter <= 0) return Size(img.width.toDouble(), img.height.toDouble());
    final ar = img.width / img.height;
    return ar >= 1
        ? Size(_cropDiameter * ar, _cropDiameter)
        : Size(_cropDiameter, _cropDiameter / ar);
  }

  /// Maximum pan in each axis so the image edge never retreats inside the circle.
  Offset _maxPan(double scale) {
    if (_image == null) return Offset.zero;
    final base = _baseSize(_image!);
    final r = _cropDiameter / 2;
    return Offset(
      math.max(0, base.width * scale / 2 - r),
      math.max(0, base.height * scale / 2 - r),
    );
  }

  Offset _clampOffset(Offset raw, double scale) {
    final max = _maxPan(scale);
    return Offset(
      raw.dx.clamp(-max.dx, max.dx),
      raw.dy.clamp(-max.dy, max.dy),
    );
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _export() async {
    final img = _image;
    if (img == null) return;
    setState(() => _exporting = true);
    try {
      final out = widget.outputSize.toDouble();
      final base = _baseSize(img);

      // The user sees the image at base*_scale, shifted by _offset from centre.
      // We want the sub-rectangle of the original image that falls inside the
      // crop circle (a square of side cropDiameter in screen space).

      // Centre of the crop circle in the drawn-image's own coordinate space
      // (origin = top-left of the image widget, before the pan/scale).
      final drawnW = base.width * _scale;
      final drawnH = base.height * _scale;

      // Image centre in screen space (before pan).
      // After pan, image top-left in screen space = screenCentre + offset - drawnSize/2
      // => crop circle centre in image-space = (screenCentre - imageTopLeft) / _scale
      final imgCx = (drawnW / 2 - _offset.dx) / _scale; // image-space x
      final imgCy = (drawnH / 2 - _offset.dy) / _scale; // image-space y

      // Half-size of the crop circle in image-space units.
      final halfCrop = (_cropDiameter / 2) / _scale;

      // Convert image-space coords to original pixel coords.
      final scaleX = img.width / base.width;
      final scaleY = img.height / base.height;

      final srcRect = Rect.fromCenter(
        center: Offset(imgCx * scaleX, imgCy * scaleY),
        width: halfCrop * 2 * scaleX,
        height: halfCrop * 2 * scaleY,
      ).intersect(Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()));

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, out, out));

      // Clip to circle for the final export.
      canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, out, out)));
      canvas.drawImageRect(
        img,
        srcRect,
        Rect.fromLTWH(0, 0, out, out),
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final outImg = await picture.toImage(out.toInt(), out.toInt());
      final byteData = await outImg.toByteData(format: ui.ImageByteFormat.png);

      if (!mounted) return;
      if (byteData != null) {
        Navigator.of(context).pop(byteData.buffer.asUint8List());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not crop image: $e')),
        );
        setState(() => _exporting = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    _cropDiameter = math.min(screenSize.width, screenSize.height) * 0.85;

    // Once image is decoded, ensure scale covers the circle.
    if (_image != null) {
      final base = _baseSize(_image!);
      final minNeeded = math.max(
        _cropDiameter / base.width,
        _cropDiameter / base.height,
      );
      if (_minScale != minNeeded) {
        _minScale = minNeeded;
        if (_scale < _minScale) _scale = _minScale;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Cancel',
        ),
        title: const Text(
          'Move and Scale',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        centerTitle: true,
        actions: [
          _exporting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _image == null ? null : _export,
                  child: const Text(
                    'Use',
                    style: TextStyle(
                      color: Color(0xFF7B68F4),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white54))
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final base = _baseSize(_image!);
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Image layer.
                            Transform.translate(
                              offset: _offset,
                              child: Transform.scale(
                                scale: _scale,
                                child: CustomPaint(
                                  size: base,
                                  painter: _ImagePainter(image: _image!),
                                ),
                              ),
                            ),

                            // Dark scrim with circular hole.
                            CustomPaint(
                              size: constraints.biggest,
                              painter: _OverlayPainter(diameter: _cropDiameter),
                            ),

                            // Rule-of-thirds grid.
                            CustomPaint(
                              size: constraints.biggest,
                              painter: _GridPainter(diameter: _cropDiameter),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Hint text.
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 36),
                  child: Text(
                    'Pinch to zoom  ·  Drag to reposition',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Custom painters ───────────────────────────────────────────────────────────

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  const _ImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image;
}

/// Dark translucent scrim everywhere OUTSIDE the circular viewport, plus a
/// thin white ring around the crop circle's edge.
class _OverlayPainter extends CustomPainter {
  final double diameter;
  const _OverlayPainter({required this.diameter});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCenter(center: centre, width: diameter, height: diameter))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.6));

    canvas.drawCircle(
      centre,
      diameter / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.diameter != diameter;
}

/// Subtle rule-of-thirds grid lines visible only inside the crop circle,
/// matching the style common in professional crop editors.
class _GridPainter extends CustomPainter {
  final double diameter;
  const _GridPainter({required this.diameter});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = diameter / 2;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 0.8;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centre, radius: r)),
    );

    for (var i = 1; i <= 2; i++) {
      final x = centre.dx - r + diameter * i / 3;
      canvas.drawLine(Offset(x, centre.dy - r), Offset(x, centre.dy + r), paint);
      final y = centre.dy - r + diameter * i / 3;
      canvas.drawLine(Offset(centre.dx - r, y), Offset(centre.dx + r, y), paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.diameter != diameter;
}
