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

/// Empties the exports folder left by the last run. Awaited at app start,
/// before any share can be active; a failure is ignored, since each export
/// deletes its own folder anyway.
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
/// rect of the control that asked. Completes when the sheet closes.
/// Tests override this.
final shareFilesProvider =
    Provider<Future<void> Function(List<SharedFile>, Rect origin)>(
      (ref) =>
          (files, origin) => SharePlus.instance.share(
            ShareParams(
              files: [
                for (final f in files) XFile(f.path, mimeType: f.mimeType),
              ],
              sharePositionOrigin: origin,
            ),
          ),
    );

/// Makes an export and shares it: `write` fills a new folder of its own,
/// `exports/<random>/`, and the files it returns are shared. The folder is
/// deleted when the share completes, is dismissed or fails. Another export
/// started meanwhile gets its own folder, so it never touches these files.
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
        final root = await directory();
        await root.create(recursive: true);
        final dir = await root.createTemp('share-');
        try {
          await share(await write(dir), origin);
        } finally {
          await clearExports(dir);
        }
      };
    });
