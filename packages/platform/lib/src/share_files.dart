import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// A file made on device to hand to the share sheet.
typedef SharedFile = ({String name, String mimeType, Uint8List bytes});

/// Opens the system share sheet with [SharedFile]s, anchored on iPad to
/// the global rect of the control that asked. Tests override this.
final shareFilesProvider =
    Provider<Future<void> Function(List<SharedFile>, Rect origin)>(
      (ref) =>
          (files, origin) => SharePlus.instance.share(
            ShareParams(
              files: [
                for (final f in files)
                  XFile.fromData(f.bytes, mimeType: f.mimeType),
              ],
              // XFile.fromData drops its name on device; this one is shared.
              fileNameOverrides: [for (final f in files) f.name],
              sharePositionOrigin: origin,
            ),
          ),
    );
