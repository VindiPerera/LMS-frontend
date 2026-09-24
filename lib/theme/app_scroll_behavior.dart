import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Flutter's default [MaterialScrollBehavior] only lets touch and stylus
/// drag a scrollable — mouse/trackpad drag is deliberately left out, since
/// on most desktop/web widgets a mouse instead drives things like text
/// selection or a scrollbar. That default is exactly why a horizontally
/// scrollable row (e.g. voice_room_detail_screen.dart's toolbar) can look
/// entirely broken on Windows desktop or in a browser: nothing is actually
/// missing or cut off, but there is no touchscreen to swipe with, so the
/// off-screen options are simply unreachable.
///
/// Wiring this into MaterialApp.scrollBehavior (see main.dart) restores
/// mouse/trackpad drag-to-scroll app-wide, so every horizontal/vertical
/// scrollable — this toolbar included — behaves the same on a phone, a
/// trackpad-only laptop, or a desktop with just a mouse.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
