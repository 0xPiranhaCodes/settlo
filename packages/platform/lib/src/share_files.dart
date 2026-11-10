import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file written to the exports folder, to hand to the share sheet.
typedef SharedFile = ({String path, String mimeType});

/// The private `exports/` folder in the app cache. Statements hold
/// financial history, so nothing else is ever written there.
Future<Directory> exportsDirectory() async =>
    Directory('${(await getApplicationCacheDirectory()).path}/exports');

/// Deletes [dir] and everything in it, if it exists.
Future<void> clearExports(Directory dir) async {
  if (dir.existsSync()) await dir.delete(recursive: true);
}

/// Empties the exports folder left by the last run. Called at app start;
/// a failure is ignored, since the next export empties it again.
Future<void> clearExportsAtStart() async {
  try {
    await clearExports(await exportsDirectory());
  } on Object {
    return;
  }
}

/// Where exports are written; tests override this.
final exportsDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => exportsDirectory,
);

/// Opens the system share sheet with files, anchored on iPad to the global
/// rect of the control that asked. False when the user dismissed it.
/// Tests override this.
final shareFilesProvider =
    Provider<Future<bool> Function(List<SharedFile>, Rect origin)>(
      (ref) => (files, origin) async {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [for (final f in files) XFile(f.path, mimeType: f.mimeType)],
            sharePositionOrigin: origin,
          ),
        );
        return result.status != ShareResultStatus.dismissed;
      },
    );

/// Makes an export and shares it: empties the exports folder, lets `write`
/// fill it, and shares the files it returns. A dismissed share deletes them
/// at once. A completed share keeps them until the next export or app
/// start, because the receiving app may still be reading them.
final shareExportProvider =
    Provider<
      Future<void> Function(
        Future<List<SharedFile>> Function(Directory dir) write,
        Rect origin,
      )
    >((ref) {
      final directory = ref.watch(exportsDirectoryProvider);
      final share = ref.watch(shareFilesProvider);
      return (write, origin) async {
        final dir = await directory();
        await clearExports(dir);
        await dir.create(recursive: true);
        try {
          if (!await share(await write(dir), origin)) await clearExports(dir);
        } on Object {
          await clearExports(dir);
          rethrow;
        }
      };
    });
