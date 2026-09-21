import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/chat_service.dart';
import '../../services/partner_service.dart';
import '../../widgets/app_avatar.dart';
import '../moments/create_moment_screen.dart';

/// Dark "bubble" background shared with voice_room_detail_screen.dart's own
/// bottom sheets (_RoomOptionsSheet, _InviteFriendsSheet) — kept as a local
/// constant rather than importing that (otherwise-private) screen file, so
/// every sheet this Share flow opens still matches the room's own look.
const Color _bubble = Color(0xFF272753);
const Color _accent = Color(0xFF7B68F4);

/// Entry point for the room's Share option (voice_room_detail_screen.dart's
/// "…" menu → Share): a two-choice sheet — "Share to a Chat" sends a
/// joinable room-invite card to one or more people via chat; "Share to
/// Moments" opens the post composer with the room pre-attached. [context]
/// must stay mounted for the lifetime of this flow (it's reused after the
/// options sheet and, for the chat path, after the recipient sheet, both
/// close) — always call this with the VoiceRoomDetailScreen's own
/// BuildContext, never a sheet's.
Future<void> showShareRoomSheet(BuildContext context, {required VoiceRoom room}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _ShareRoomOptionsSheet(
      onShareToChat: () {
        Navigator.of(sheetContext).pop();
        _openShareToChatSheet(context, room);
      },
      onShareToMoments: () {
        Navigator.of(sheetContext).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreateMomentScreen(
              attachedVoiceRoom: room,
              // A friendly starting caption, same spirit as the reference
              // "Hi! Join me..." prompt — still just a text field the user
              // can edit or clear before posting, not locked-in copy.
              initialText: 'Join me in "${room.title}" to practice listening and speaking!',
            ),
          ),
        );
      },
    ),
  );
}

void _openShareToChatSheet(BuildContext context, VoiceRoom room) {
  showModalBottomSheet(
    context: context,
    backgroundColor: _bubble,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ShareToChatSheet(
      room: room,
      onSent: (successCount, failedNames) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        if (successCount == 0) {
          messenger.showSnackBar(const SnackBar(content: Text("Couldn't send the invite. Please try again.")));
        } else if (failedNames.isEmpty) {
          messenger.showSnackBar(
            SnackBar(content: Text('Room shared with $successCount ${successCount == 1 ? 'person' : 'people'}.')),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('Sent to $successCount. Failed for: ${failedNames.join(', ')}.')),
          );
        }
      },
    ),
  );
}


class _ShareRoomOptionsSheet extends StatelessWidget {
  final VoidCallback onShareToChat;
  final VoidCallback onShareToMoments;
  const _ShareRoomOptionsSheet({required this.onShareToChat, required this.onShareToMoments});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(color: _bubble, borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                    title: const Text(
                      'Share to a Chat',
                      style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Send a joinable invite to people you chat with',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                    onTap: onShareToChat,
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  ListTile(
                    leading: const Icon(Icons.dynamic_feed_rounded, color: Colors.white, size: 20),
                    title: const Text(
                      'Share to Moments',
                      style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Post it to your Moments feed',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                    onTap: onShareToMoments,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share to Chat sheet
// ---------------------------------------------------------------------------

/// Recipient picker for "Share to a Chat". Reuses PartnerService.fetchPartners
/// — the same "eligible users" list connect_screen.dart's Partners tab
/// shows — rather than only people with an existing thread: the invite
/// itself will start a new one if there wasn't already one (ChatService.
/// sendVoiceRoomInvite goes through the same thread-creation path as any
/// other first message — see ChatService.sendWave for the equivalent on the
/// Connect tab), so there's no reason to limit sharing to existing chats.
class _ShareToChatSheet extends StatefulWidget {
  final VoiceRoom room;
  final void Function(int successCount, List<String> failedNames) onSent;
  const _ShareToChatSheet({required this.room, required this.onSent});

  @override
  State<_ShareToChatSheet> createState() => _ShareToChatSheetState();
}

class _ShareToChatSheetState extends State<_ShareToChatSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};
  List<AppUser>? _partners;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final partners = await PartnerService.fetchPartners();
    if (!mounted) return;
    setState(() => _partners = partners);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  Future<void> _send() async {
    final all = _partners;
    if (all == null || _selected.isEmpty || _sending) return;
    setState(() => _sending = true);

    final targets = all.where((p) => _selected.contains(p.id));
    var successCount = 0;
    final failedNames = <String>[];
    for (final user in targets) {
      try {
        await ChatService.sendVoiceRoomInvite(other: user, room: widget.room);
        successCount++;
      } catch (_) {
        failedNames.add(user.name);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSent(successCount, failedNames);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share to a Chat',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick one or more people to invite into this room.',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: 'Search people',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 13.5),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(height: 320, child: _buildList()),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.isEmpty || _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _selected.isEmpty ? 'Send' : 'Send to ${_selected.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final all = _partners;
    if (all == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70));
    }
    final people = _query.isEmpty
        ? all
        : all.where((u) => u.name.toLowerCase().contains(_query) || u.handle.toLowerCase().contains(_query)).toList();

    if (people.isEmpty) {
      return Center(
        child: Text(
          _query.isNotEmpty ? 'No one matching "$_query"' : 'No one to share with yet.',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final person = people[i];
        final selected = _selected.contains(person.id);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => _toggle(person.id),
          // Selection indicator first, avatar right after it — matches the
          // familiar "pick recipients" layout (selection state read
          // left-to-right before the person's identity) rather than
          // trailing it off on the far right where it's easy to miss on a
          // wide sheet.
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? _accent : Colors.white24,
              ),
              const SizedBox(width: 10),
              AppAvatar(seed: person.name, size: 40, imageUrl: person.avatarUrl),
            ],
          ),
          title: Text(
            person.name,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
