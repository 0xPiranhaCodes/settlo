import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

final class _Platform extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('', ShareResultStatus.success);
  }
}

void main() {
  test(
    'hands named in-memory files to the share sheet at the origin',
    () async {
      final platform = _Platform();
      SharePlatform.instance = platform;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const origin = Rect.fromLTWH(10, 20, 44, 44);

      await container.read(shareFilesProvider)([
        (
          name: 'a.csv',
          mimeType: 'text/csv',
          bytes: Uint8List.fromList([1, 2]),
        ),
        (
          name: 'b.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([3]),
        ),
      ], origin);

      final params = platform.shared.single;
      expect(params.fileNameOverrides, ['a.csv', 'b.pdf']);
      expect(params.sharePositionOrigin, origin);
      expect(
        [for (final f in params.files!) f.mimeType],
        ['text/csv', 'application/pdf'],
      );
      expect(await params.files!.first.readAsBytes(), [1, 2]);
    },
  );
}
