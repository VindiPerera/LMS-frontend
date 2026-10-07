import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/media_library_item.dart';
import '../models/whiteboard_library_item.dart';
import '../services/media_library_service.dart';
import '../services/storage_service.dart';

const _bgColor = Color(0xFF1B1B3A);
const _cardColor = Color(0xFF242449);
const _accent = Color(0xFF7B68F4);

/// Opens the "Add to Whiteboard" sheet — a navigable folder browser merging
/// the app's fixed preset topic cards (shown inside the virtual "Library"
/// folder — see MediaLibraryService.libraryFolderId) with the signed-in
/// user's own folders/images (MediaLibraryService). Folder/image
/// create-rename-delete-upload-to-a-folder is handled entirely inside this
/// sheet (none of it needs the room's whiteboard state); only actually
/// placing something on the whiteboard — a preset, an existing library
/// image, or a fresh "Upload from Gallery" pick — calls back out to the
/// caller, since the room/whiteboard state (and the "replace the current
/// photo" / re-upload logic a preset needs) lives there, not here.
Future<void> showWhiteboardLibrarySheet({
  required BuildContext context,
  required ValueChanged<WhiteboardLibraryItem> onSelectPreset,
  required ValueChanged<MediaLibraryItem> onSelectLibraryImage,
  required VoidCallback onUploadToBoard,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => WhiteboardLibrarySheet(
      onSelectPreset: (item) {
        Navigator.of(ctx).pop();
        onSelectPreset(item);
      },
      onSelectLibraryImage: (item) {
        Navigator.of(ctx).pop();
        onSelectLibraryImage(item);
      },
      onUploadToBoard: () {
        Navigator.of(ctx).pop();
        onUploadToBoard();
      },
    ),
  );
}

class WhiteboardLibrarySheet extends StatefulWidget {
  final ValueChanged<WhiteboardLibraryItem> onSelectPreset;
  final ValueChanged<MediaLibraryItem> onSelectLibraryImage;
  final VoidCallback onUploadToBoard;

  const WhiteboardLibrarySheet({
    super.key,
    required this.onSelectPreset,
    required this.onSelectLibraryImage,
    required this.onUploadToBoard,
  });

  @override
  State<WhiteboardLibrarySheet> createState() => _WhiteboardLibrarySheetState();
}

class _FolderStackEntry {
  final String? id;
  final String name;
  const _FolderStackEntry(this.id, this.name);
}

class _WhiteboardLibrarySheetState extends State<WhiteboardLibrarySheet> {
  // Root is always the first stack entry, so "back" from a top-level folder
  // (Library or a custom root folder) always has somewhere defined to land,
  // and the header always has a name to show.
  final List<_FolderStackEntry> _stack = [const _FolderStackEntry(null, 'Add to Whiteboard')];

  String? get _currentId => _stack.last.id;
  bool get _atRoot => _stack.length == 1;
  // The built-in preset cards only ever show while actually inside the
  // virtual Library folder — not at root (where Library is just one tile
  // among others) and not inside some other folder.
  bool get _inLibraryFolder => _currentId == MediaLibraryService.libraryFolderId;

  // Guards the per-folder "+" button against a second tap while an upload
  // from the first one is still in flight — this sheet has no board state
  // to disable the way voice_room_detail_screen.dart's _addingImage does
  // for its own actions, so it needs its own.
  bool _uploadingToFolder = false;

  void _open(String? id, String name) => setState(() => _stack.add(_FolderStackEntry(id, name)));

  void _back() {
    if (_atRoot) return;
    setState(() => _stack.removeLast());
  }

  /// Files a freshly-picked photo directly into [parentId] — library
  /// management only, never placed on the whiteboard (that's what the
  /// "Upload from Gallery" card and tapping an existing image are for).
  /// Self-contained: unlike those two, this needs nothing from the room/
  /// whiteboard the caller has, so it never leaves this sheet.
  Future<void> _addImageToFolder(String? parentId) async {
    if (_uploadingToFolder) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (picked == null) return;

    setState(() => _uploadingToFolder = true);
    try {
      final bytes = await picked.readAsBytes();
      final aspectRatio = await _decodeAspectRatio(bytes);
      final url = await StorageService.uploadWhiteboardImage(uid, bytes);
      await MediaLibraryService.addImage(
        name: 'Image ${DateTime.now().millisecondsSinceEpoch}',
        imageUrl: url,
        aspectRatio: aspectRatio,
        parentId: parentId,
      );
    } catch (e) {
      _showError('Could not add image: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _uploadingToFolder = false);
    }
  }

  /// Same fallback-to-square-ratio behavior as voice_room_detail_screen
  /// .dart's own _decodeAspectRatio — kept local since nothing else here
  /// needs the rest of that screen's state to do this one thing.
  Future<double> _decodeAspectRatio(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return ratio > 0 ? ratio : 1;
    } catch (_) {
      return 1;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createFolder() async {
    final name = await _promptForName(context, title: 'New Folder', hint: 'Folder name');
    if (name == null) return;
    try {
      await MediaLibraryService.createFolder(name: name, parentId: _currentId);
    } catch (e) {
      _showError('Could not create folder: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _renameItem(MediaLibraryItem item) async {
    final name = await _promptForName(context, title: 'Rename', hint: 'Name', initial: item.name);
    if (name == null || name == item.name) return;
    try {
      await MediaLibraryService.renameItem(id: item.id, name: name);
    } catch (e) {
      _showError('Could not rename: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _deleteItem(MediaLibraryItem item) async {
    final confirmed = await _confirmDelete(context, item: item);
    if (confirmed != true) return;
    try {
      await MediaLibraryService.deleteItem(item);
    } catch (e) {
      _showError('Could not delete: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _showItemOptions(MediaLibraryItem item) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.white70),
              title: const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(ctx).pop();
                _renameItem(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text(
                item.isFolder ? 'Delete folder' : 'Delete image',
                style: const TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteItem(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _buildHeader(),
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          if (!_atRoot)
            IconButton(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
              tooltip: 'Back',
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              _stack.last.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          IconButton(
            onPressed: _uploadingToFolder ? null : () => _addImageToFolder(_currentId),
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white70),
            tooltip: 'Add image to this folder',
          ),
          IconButton(
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined, color: Colors.white70),
            tooltip: 'New folder',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return StreamBuilder<List<MediaLibraryItem>>(
      stream: MediaLibraryService.streamChildren(_currentId),
      builder: (context, snapshot) {
        final liveItems = snapshot.data ?? const <MediaLibraryItem>[];
        final liveFolders = liveItems.where((i) => i.isFolder);
        final liveImages = liveItems.where((i) => i.isImage);

        // Folders as compact full-width rows (standard file-browser shape —
        // just an icon and a name, nothing worth a big square thumbnail
        // card for) rather than squeezed into the same grid as image
        // tiles, which left them looking stretched and sparse.
        final folderRows = <Widget>[
          if (_atRoot)
            _FolderRow(
              name: 'Library',
              builtIn: true,
              onTap: () => _open(MediaLibraryService.libraryFolderId, 'Library'),
            ),
          for (final folder in liveFolders)
            _FolderRow(
              name: folder.name,
              builtIn: false,
              onTap: () => _open(folder.id, folder.name),
              onLongPress: () => _showItemOptions(folder),
            ),
        ];

        final mediaTiles = <Widget>[
          if (_inLibraryFolder)
            for (final preset in WhiteboardLibraryItem.presets)
              _PresetImageTile(item: preset, onTap: () => widget.onSelectPreset(preset)),
          for (final image in liveImages)
            _LibraryImageTile(
              item: image,
              onTap: () => widget.onSelectLibraryImage(image),
              onLongPress: () => _showItemOptions(image),
            ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UploadCard(onTap: widget.onUploadToBoard),
              if (folderRows.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (final row in folderRows) Padding(padding: const EdgeInsets.only(bottom: 10), child: row),
              ],
              if (mediaTiles.isNotEmpty) ...[
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mediaTiles.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (context, i) => mediaTiles[i],
                ),
              ],
              if (folderRows.isEmpty && mediaTiles.isEmpty) const _EmptyFolderNotice(),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String hint,
  String? initial,
}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _cardColor,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        cursorColor: _accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
        ),
        onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Save', style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmDelete(BuildContext context, {required MediaLibraryItem item}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _cardColor,
      title: Text(
        item.isFolder ? 'Delete "${item.name}"?' : 'Delete this image?',
        style: const TextStyle(color: Colors.white),
      ),
      content: Text(
        item.isFolder
            ? 'This also deletes everything inside this folder. This can\'t be undone.'
            : 'This can\'t be undone.',
        style: const TextStyle(color: Colors.white60),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class _UploadCard extends StatelessWidget {
  final VoidCallback onTap;
  const _UploadCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_photo_alternate_rounded, color: _accent, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload from Gallery',
                    style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Choose any image from your device',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _EmptyFolderNotice extends StatelessWidget {
  const _EmptyFolderNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.folder_open_rounded, color: Colors.white.withValues(alpha: 0.25), size: 40),
          const SizedBox(height: 10),
          const Text(
            'Nothing here yet',
            style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A folder row — the built-in "Library" folder (locked icon, no long-press
/// menu — see WhiteboardLibraryItem's own doc comment on why it can't be
/// renamed or deleted, though its contents are still addable via the
/// header's own "+" once you've opened it) or a user-created folder (plain
/// folder icon, long-press for rename/delete). A compact full-width row —
/// just an icon and a name — rather than a square grid card, which left
/// folders looking stretched and sparse next to how little they need to
/// show.
class _FolderRow extends StatelessWidget {
  final String name;
  final bool builtIn;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderRow({
    required this.name,
    required this.builtIn,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.folder_rounded, color: _accent, size: 24),
                  if (builtIn)
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(Icons.lock_rounded, color: Colors.white54, size: 11),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// One built-in preset topic card — unchanged from the original flat
/// Library grid, just reused here inside the virtual Library folder.
class _PresetImageTile extends StatelessWidget {
  final WhiteboardLibraryItem item;
  final VoidCallback onTap;

  const _PresetImageTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                item.bytes,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Image.asset(
                  item.assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF8A2BE2),
                    padding: const EdgeInsets.all(10),
                    alignment: Alignment.center,
                    child: Text(
                      item.prompt,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 38,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_rounded, size: 11, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A user-added library image — a network thumbnail (already uploaded when
/// it was added — see MediaLibraryService.addImage), tap to place on the
/// board, long-press (or the corner menu button) to rename/delete.
class _LibraryImageTile extends StatelessWidget {
  final MediaLibraryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LibraryImageTile({required this.item, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                item.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: _cardColor,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_rounded, color: Colors.white38),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 32,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  onTap: onLongPress,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
