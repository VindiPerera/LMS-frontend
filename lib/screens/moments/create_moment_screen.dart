import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/moment.dart';
import '../../services/connectivity_service.dart';
import '../../services/media_service.dart';
import '../../services/moment_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/visibility_selector.dart';
import '../../services/auth_service.dart';

int _keySeed = 0;
String _nextKey() => 'm${DateTime.now().microsecondsSinceEpoch}_${_keySeed++}';

class _ImageItem {
  final String key = _nextKey();
  final String? existingUrl;
  Uint8List? bytes;
  double progress = 0;
  bool uploading = false;
  bool failed = false;
  String? finalUrl;

  _ImageItem.existing(String url)
      : existingUrl = url,
        finalUrl = url;

  _ImageItem.picked(this.bytes) : existingUrl = null;

  bool get isDone => finalUrl != null;
}

/// The composer no longer lets anyone attach a *new* video — moments are
/// photos-and-text only now. This only reflects a video an existing post
/// already had, so re-saving edits to an old video moment doesn't silently
/// strip it.
class _VideoItem {
  final String existingUrl;
  final String? existingThumbUrl;

  _VideoItem.existing({required String url, String? thumbUrl})
      : existingUrl = url,
        existingThumbUrl = thumbUrl;
}

/// Create a new moment, or (when [existing] is passed) edit one. Only newly
/// picked media gets uploaded on save — images kept from [existing] reuse
/// their existing Storage URL untouched.
class CreateMomentScreen extends StatefulWidget {
  final Moment? existing;
  final String? initialText;
  final String? initialPicker;

  const CreateMomentScreen({
    super.key,
    this.existing,
    this.initialText,
    this.initialPicker,
  });

  @override
  State<CreateMomentScreen> createState() => _CreateMomentScreenState();
}

class _CreateMomentScreenState extends State<CreateMomentScreen> {
  late final _textController = TextEditingController(
    text: widget.existing?.text ?? widget.initialText ?? '',
  );
  late MomentVisibility _visibility = widget.existing?.visibility ?? MomentVisibility.public;

  /// Allocated once (either the post being edited, or a fresh id from
  /// MomentService.newPostId()) and reused for every upload — including
  /// retries — so all of a post's media always lands under the same
  /// `moments/{uid}/{postId}/` Storage prefix.
  late final String _postId = widget.existing?.id ?? MomentService.newPostId();

  final List<_ImageItem> _images = [];
  _VideoItem? _video;

  bool _posting = false;
  bool _online = true;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _images.addAll(widget.existing!.imageUrls.map(_ImageItem.existing));
      if (widget.existing!.mediaType == MomentMediaType.video && widget.existing!.videoUrl != null) {
        _video = _VideoItem.existing(
          url: widget.existing!.videoUrl!,
          thumbUrl: widget.existing!.videoThumbnailUrl,
        );
      }
    }
    ConnectivityService.instance.isOnlineNow.then((value) {
      if (mounted) setState(() => _online = value);
    });
    ConnectivityService.instance.onlineStatus.listen((value) {
      if (mounted) setState(() => _online = value);
    });

    if (widget.initialPicker == 'image') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage(ImageSource.gallery));
    }
  }



  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canAddMore => _video == null && _images.length < 9;

  Future<void> _pickImage(ImageSource source) async {
    if (_video != null) return;
    try {
      final file = await MediaService.pickImage(source);
      if (file == null) return;
      final rawBytes = await file.readAsBytes();
      final compressed = await MediaService.compressImageBytes(rawBytes);
      if (!mounted) return;
      setState(() => _images.add(_ImageItem.picked(compressed)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to select image: $e');
    }
  }

  void _removeImage(_ImageItem item) => setState(() => _images.remove(item));

  bool get _canPost {
    final hasText = _textController.text.trim().isNotEmpty;
    final hasMedia = _images.isNotEmpty || _video != null;
    return (hasText || hasMedia) && !_posting;
  }

  Future<void> _submit() async {
    if (!_canPost) return;

    if (!_online) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No internet connection.')));
      return;
    }

    setState(() {
      _posting = true;
      _error = null;
    });

    final uid = AuthService.instance.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      setState(() {
        _posting = false;
        _error = 'You must be signed in to post.';
      });
      return;
    }

    final uploadsOk = await _uploadPendingImages(uid, _postId);

    if (!uploadsOk) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = 'Some media failed to upload. Tap retry on the thumbnail, then post again.';
      });
      return;
    }

    final imageUrls = _images.map((item) => item.finalUrl!).toList();
    final mediaType = _video != null
        ? MomentMediaType.video
        : imageUrls.isNotEmpty
            ? MomentMediaType.image
            : MomentMediaType.none;

    try {
      if (_isEditing) {
        await MomentService.updateMoment(
          postId: _postId,
          text: _textController.text,
          imageUrls: imageUrls,
          videoUrl: _video?.existingUrl,
          videoThumbnailUrl: _video?.existingThumbUrl,
          mediaType: mediaType,
          visibility: _visibility,
        );
      } else {
        await MomentService.createMoment(
          text: _textController.text,
          postId: _postId,
          imageUrls: imageUrls,
          mediaType: mediaType,
          visibility: _visibility,
        );
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error!)));
    }
  }

  Future<bool> _uploadPendingImages(String uid, String postId) async {
    final pending = _images.where((item) => !item.isDone).toList();
    if (pending.isEmpty) return true;

    final results = await Future.wait(pending.map((item) => _uploadImage(item, uid, postId)));
    return results.every((ok) => ok);
  }

  Future<bool> _uploadImage(_ImageItem item, String uid, String postId) async {
    if (item.bytes == null) return false;
    setState(() {
      item.uploading = true;
      item.failed = false;
      item.progress = 0;
    });
    try {
      final url = await MediaService.uploadImageBytes(
        bytes: item.bytes!,
        uid: uid,
        postId: postId,
        onProgress: (p) {
          if (mounted) setState(() => item.progress = p);
        },
      );
      if (mounted) {
        setState(() {
          item.uploading = false;
          item.finalUrl = url;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          item.uploading = false;
          item.failed = true;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_isEditing ? 'Edit moment' : 'New moment', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ElevatedButton(
                onPressed: _canPost ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.divider,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                ),
                child: _posting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Post'),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_online)
            Container(
              width: double.infinity,
              color: AppColors.badgeRed,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Text(
                'No internet connection',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (user != null) AppAvatar.forUser(user, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          autofocus: true,
                          minLines: 3,
                          maxLines: 10,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: "What's on your mind?",
                            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 15),
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(fontSize: 15.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Who can see this?',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  VisibilitySelector(value: _visibility, onChanged: (v) => setState(() => _visibility = v)),
                  if (_images.isNotEmpty || _video != null) ...[
                    const SizedBox(height: 16),
                    _buildMediaRow(),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: AppColors.badgeRed, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined, color: AppColors.primaryPurple),
                    tooltip: 'Photo from gallery',
                    onPressed: _canAddMore ? () => _pickImage(ImageSource.gallery) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primaryPurple),
                    tooltip: 'Take a photo',
                    onPressed: _canAddMore ? () => _pickImage(ImageSource.camera) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaRow() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._images.map((item) => _MediaThumb(
                key: ValueKey(item.key),
                progress: item.uploading ? item.progress : null,
                failed: item.failed,
                onRemove: () => _removeImage(item),
                onRetry: () => _uploadImage(item, AuthService.instance.currentUser!.id, _postId),
                child: item.existingUrl != null && item.bytes == null
                    ? CachedNetworkImage(imageUrl: item.existingUrl!, fit: BoxFit.cover, width: 88, height: 88)
                    : Image.memory(item.bytes!, fit: BoxFit.cover, width: 88, height: 88),
              )),
          // Read-only: this is the video an existing post already had.
          // Video is no longer something the composer can add or replace.
          if (_video != null)
            _MediaThumb(
              key: const ValueKey('video'),
              isVideo: true,
              child: _video!.existingThumbUrl != null
                  ? CachedNetworkImage(imageUrl: _video!.existingThumbUrl!, fit: BoxFit.cover, width: 88, height: 88)
                  : Container(color: Colors.black, width: 88, height: 88),
            ),
        ],
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final Widget child;
  final bool isVideo;
  final double? progress;
  final bool failed;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  const _MediaThumb({
    super.key,
    required this.child,
    this.isVideo = false,
    this.progress,
    this.failed = false,
    this.onRemove,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
            if (isVideo)
              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 32)),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  child: LinearProgressIndicator(
                    value: progress! > 0 ? progress : null,
                    minHeight: 4,
                    backgroundColor: Colors.black26,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primaryPurple),
                  ),
                ),
              ),
            if (failed)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    onPressed: onRetry,
                  ),
                ),
              ),
            if (onRemove != null)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
