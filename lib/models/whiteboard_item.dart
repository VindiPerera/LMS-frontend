import 'package:cloud_firestore/cloud_firestore.dart';

/// One item on a voice room's shared whiteboard — backed by
/// `voiceRooms/{roomId}/whiteboard/{itemId}` (see WhiteboardService). A
/// free-position canvas: every item carries its own transform (`x`/`y`/
/// `width`/`height`, all fractions of the canvas — 0..1 — so the same
/// layout renders correctly regardless of how big the canvas is on any
/// given viewer's screen; `rotation` in degrees; `zIndex` for stacking
/// order) plus, for text items, simple styling (`fontSize`/`colorHex`/
/// `bold`/`textAlign`).
class WhiteboardItem {
  final String id;
  // 'image' | 'text'.
  final String type;
  final String imageUrl;
  final String text;
  final String addedBy;
  final String addedByName;
  final DateTime? createdAt;

  // Transform — fractions of the canvas' own width/height (0..1), not
  // pixels, so a room's board looks the same shape on a phone and a
  // desktop window alike. See WhiteboardCanvas for the pixel conversion.
  final double x;
  final double y;
  final double width;
  final double height;
  // Degrees, image items only (text stays upright — a rotated multi-line
  // text box gets awkward to read and edit for little benefit here).
  final double rotation;
  // Higher draws on top. Only meaningful relative to the other items on
  // the same board — see WhiteboardService.bringToFront/sendToBack.
  final int zIndex;

  // Text styling.
  final double fontSize;
  // 8-hex ARGB, e.g. 'FFFFFFFF' for opaque white — Color(int.parse('0x$x')).
  final String colorHex;
  final bool bold;
  // 'left' | 'center' | 'right'.
  final String textAlign;

  // Image only — width / height of the original picked image, so a resize
  // handle can keep the displayed box in proportion without needing the
  // image re-decoded. Null for text items, and for images added before
  // this existed (their resize handle falls back to free resizing).
  final double? aspectRatio;

  const WhiteboardItem({
    this.id = '',
    required this.type,
    this.imageUrl = '',
    this.text = '',
    this.addedBy = '',
    this.addedByName = '',
    this.createdAt,
    this.x = 0.06,
    this.y = 0.06,
    this.width = 0.32,
    this.height = 0.28,
    this.rotation = 0,
    this.zIndex = 0,
    this.fontSize = 16,
    this.colorHex = 'FFFFFFFF',
    this.bold = false,
    this.textAlign = 'left',
    this.aspectRatio,
  });

  bool get isImage => type == 'image';
  bool get isText => type == 'text';

  factory WhiteboardItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return WhiteboardItem(
      id: doc.id,
      type: data['type']?.toString() ?? 'text',
      imageUrl: data['imageUrl']?.toString() ?? '',
      text: data['text']?.toString() ?? '',
      addedBy: data['addedBy']?.toString() ?? '',
      addedByName: data['addedByName']?.toString() ?? 'Someone',
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
      x: _asDouble(data['x'], 0.06),
      y: _asDouble(data['y'], 0.06),
      width: _asDouble(data['width'], 0.32),
      height: _asDouble(data['height'], 0.28),
      rotation: _asDouble(data['rotation'], 0),
      zIndex: (data['zIndex'] as num?)?.toInt() ?? 0,
      fontSize: _asDouble(data['fontSize'], 16),
      colorHex: (data['colorHex']?.toString().isNotEmpty ?? false) ? data['colorHex'].toString() : 'FFFFFFFF',
      bold: data['bold'] == true,
      textAlign: (data['textAlign']?.toString().isNotEmpty ?? false) ? data['textAlign'].toString() : 'left',
      aspectRatio: data['aspectRatio'] is num ? (data['aspectRatio'] as num).toDouble() : null,
    );
  }

  static double _asDouble(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  WhiteboardItem copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
    double? fontSize,
    String? colorHex,
    bool? bold,
    String? textAlign,
    String? text,
  }) {
    return WhiteboardItem(
      id: id,
      type: type,
      imageUrl: imageUrl,
      text: text ?? this.text,
      addedBy: addedBy,
      addedByName: addedByName,
      createdAt: createdAt,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      fontSize: fontSize ?? this.fontSize,
      colorHex: colorHex ?? this.colorHex,
      bold: bold ?? this.bold,
      textAlign: textAlign ?? this.textAlign,
      aspectRatio: aspectRatio,
    );
  }
}
