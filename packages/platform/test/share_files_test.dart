import 'dart:async';
import 'dart:io';
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

const _origin = Rect.fromLTWH(10, 20, 44, 44);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _Platform();
  SharePlatform.instance = platform;
  late Directory exports;
  late ProviderContainer container;
  late List<List<SharedFile>> shared;

  /// While set, the share sheet stays open until it completes.
  Completer<void>? sheet;

  setUp(() async {
    platform.shared.clear();
    exports = Directory(
      '${(await Directory.systemTemp.createTemp('settlo')).path}/exports',
    );
    addTearDown(() => exports.parent.delete(recursive: true));
    shared = [];
    sheet = null;
    container = ProviderContainer(
      overrides: [
        exportsDirectoryProvider.overrideWithValue(() async => exports),
        shareFilesProvider.overrideWithValue((files, _) async {
          shared.add(files);
          await sheet?.future;
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> export(String name) =>
      container.read(shareExportProvider)((dir) async {
        final file = File('${dir.path}/$name');
        await file.writeAsString('statement');
        return [(path: file.path, mimeType: 'application/pdf')];
      }, _origin);

  test('the share sheet gets the files, their types and the origin', () async {
    final share = ProviderContainer().read(shareFilesProvider);
    const file = (path: '/tmp/a.csv', mimeType: 'text/csv');

    await share([file], _origin);
    final params = platform.shared.single;
    expect(params.files!.single.path, '/tmp/a.csv');
    expect(params.files!.single.mimeType, 'text/csv');
    expect(params.sharePositionOrigin, _origin);
  });

  test(
    'each export gets its own folder, deleted when its share ends',
    () async {
      await export('a.pdf');
      final [(:path, mimeType: _)] = shared.single;
      expect(path, matches(RegExp('^${exports.path}/share-[^/]+/a.pdf\$')));
      expect(File(path).existsSync(), isFalse);
      expect(exports.listSync(), isEmpty);
    },
  );

  test("a second export while the first share is open leaves the first's "
      'files alone', () async {
    final a = sheet = Completer<void>();
    final first = export('a.pdf');
    await pumpEventQueue();
    final aFile = File(shared.single.single.path);
    expect(aFile.existsSync(), isTrue);

    sheet = null;
    await export('b.pdf');
    expect(File(shared.last.single.path).existsSync(), isFalse);
    expect(aFile.existsSync(), isTrue, reason: 'A is still being read');

    a.complete();
    await first;
    expect(aFile.existsSync(), isFalse);
    expect(exports.listSync(), isEmpty);
  });

  test('a failed export leaves nothing behind', () async {
    await expectLater(
      container.read(shareExportProvider)((dir) async {
        await File('${dir.path}/half.pdf').writeAsString('half');
        throw StateError('disk full');
      }, _origin),
      throwsStateError,
    );
    expect(exports.listSync(), isEmpty);
    expect(shared, isEmpty);
  });

  test('app start clears what the last run left', () async {
    await Directory('${exports.path}/share-old').create(recursive: true);
    await clearExports(exports);
    expect(exports.existsSync(), isFalse);
    // Again, with nothing there.
    await clearExports(exports);
    // Without a platform cache directory (as here) it gives up quietly.
    await clearExportsAtStart();
  });
}
