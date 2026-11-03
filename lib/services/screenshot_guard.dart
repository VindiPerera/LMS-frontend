import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

/// Blocks screenshots/screen recording for as long as at least one screen
/// has it enabled — wraps screen_protector's platform mechanics (Android:
/// FLAG_SECURE, so the captured frame comes out solid black; iOS: a secure
/// overlay that blanks the protected content within whatever screenshot/
/// recording still gets taken, since iOS has no API to actually block the
/// capture gesture itself) behind a simple enable/disable pair.
///
/// Reference-counted so two guarded screens open at once (e.g. the library
/// picker opened from within the expanded whiteboard) don't have whichever
/// one closes first switch protection off while the other is still
/// visible.
///
/// Used by whiteboard_library_sheet.dart (picking a library image) and
/// expanded_whiteboard_screen.dart (viewing the board full-screen) — both
/// can show licensed exam-prep images this app has no redistribution
/// rights for.
class ScreenshotGuard {
  ScreenshotGuard._();

  static int _refCount = 0;

  /// Call once from initState. Every [enable] must be paired with exactly
  /// one later [disable] call (dispose) for the ref-counting above to stay
  /// balanced.
  static Future<void> enable(BuildContext context) async {
    _refCount++;
    if (_refCount == 1) {
      await ScreenProtector.preventScreenshotOn();
    }
    // Re-registered on every enable (cheap and idempotent on the native
    // side) so the "can't screenshot this" message always targets
    // whichever guarded screen is currently the one actually on top —
    // iOS only; addListener is a no-op on Android, where preventScreenshotOn
    // above already blocks the capture outright rather than needing a
    // reactive message.
    ScreenProtector.addListener(() {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Screenshots aren't allowed for this content.")),
        );
    }, null);
  }

  static Future<void> disable() async {
    if (_refCount == 0) return;
    _refCount--;
    if (_refCount == 0) {
      ScreenProtector.removeListener();
      await ScreenProtector.preventScreenshotOff();
    }
  }
}
