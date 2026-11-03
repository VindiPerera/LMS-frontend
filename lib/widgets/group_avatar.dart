import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/mock_data.dart' show avatarColorFor;
import '../services/partner_service.dart';

/// A group thread's avatar — a real uploaded photo if the group has one
/// (ChatService.updateGroupAvatar), otherwise a ring of small circular
/// photos arranged evenly around the perimeter (each member's own photo,
/// overlapping slightly like a cluster of contact bubbles), so a group
/// reads as "these people" at a glance instead of a single flat initial
/// letter. Used wherever a group's identity renders: chat_list_screen.dart's
/// row, chat_detail_screen.dart's header, group_info_screen.dart's header.
class GroupAvatar extends StatelessWidget {
  final String groupName;
  final String groupAvatar;
  // (uid, name) pairs in member order — only the first [_maxInRing] are
  // ever drawn, so callers don't need to trim this themselves. Deliberately
  // uids, not pre-resolved avatar URLs: the group's own participantInfo/
  // ChatThread snapshot is only as fresh as whenever that member last
  // joined (same staleness class as every other participantInfo-backed
  // avatar in this app — see choose_group_members_screen.dart/
  // group_info_screen.dart's member rows), so each bubble below looks its
  // member's CURRENT photo up live instead of trusting that snapshot. name
  // only ever backs that same bubble's no-photo fallback (an initial
  // letter, same as AppAvatar's own), never a live lookup of its own.
  final List<({String uid, String name})> members;
  final double size;

  const GroupAvatar({
    super.key,
    required this.groupName,
    required this.groupAvatar,
    required this.members,
    this.size = 48,
  });

  static const int _maxInRing = 6;

  bool get _hasPhoto => groupAvatar.startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (_hasPhoto) {
      return ClipOval(
        child: Image.network(
          groupAvatar,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _ring(),
        ),
      );
    }
    return _ring();
  }

  Widget _ring() {
    final shown = members.where((m) => m.uid.isNotEmpty).take(_maxInRing).toList();
    if (shown.isEmpty) return _initialFallback();

    // Each bubble's own diameter shrinks a bit as more members join, so a
    // full ring of 6 doesn't crowd past the outer circle; the radius they
    // sit on leaves just enough room for that bubble (plus its white
    // border) to stay fully inside [size].
    final bubbleSize = size * (shown.length <= 2 ? 0.58 : shown.length <= 4 ? 0.46 : 0.38);
    final ringRadius = (size - bubbleSize) / 2;
    final center = size / 2;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              // Starts at 12 o'clock (-pi/2) and places the rest clockwise,
              // evenly spaced — the usual "contacts cluster" arrangement.
              left: center + ringRadius * math.cos((2 * math.pi * i / shown.length) - math.pi / 2) - bubbleSize / 2,
              top: center + ringRadius * math.sin((2 * math.pi * i / shown.length) - math.pi / 2) - bubbleSize / 2,
              child: _bubble(shown[i].uid, shown[i].name, bubbleSize),
            ),
        ],
      ),
    );
  }

  // No member has a resolvable photo either (or none at all) — the same
  // flat initial-letter circle a plain AppAvatar would show.
  Widget _initialFallback() {
    final color = avatarColorFor(groupName);
    final initial = groupName.isNotEmpty ? groupName.substring(0, 1).toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4),
      ),
    );
  }

  Widget _bubble(String uid, String name, double diameter) {
    final color = avatarColorFor(name.isNotEmpty ? name : uid);
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    // Same no-photo look as AppAvatar: the name's initial over a colored
    // gradient, not a bare color swatch — only ever shown while this
    // member's own live avatar (below) hasn't resolved to a real photo.
    Widget fallback() => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Text(
            initial,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: diameter * 0.42),
          ),
        );

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The white ring is what makes overlapping bubbles read as
        // separate photos rather than one smeared blob where they touch.
        border: Border.all(color: Colors.white, width: math.max(1, diameter * 0.08)),
      ),
      child: ClipOval(
        child: StreamBuilder<String?>(
          stream: PartnerService.streamAvatarUrl(uid),
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url == null || url.isEmpty) return fallback();
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            );
          },
        ),
      ),
    );
  }
}
