import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

final class _Platform extends SharePlatform {
  final shared = <ShareParams>[];
  ShareResultStatus status = ShareResultStatus.success;

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return ShareResult('', status);
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
  late bool completes;

  setUp(() async {
    platform.shared.clear();
    exports = Directory(
      '${(await Directory.systemTemp.createTemp('settlo')).path}/exports',
    );
    addTearDown(() => exports.parent.delete(recursive: true));
    shared = [];
    completes = true;
    container = ProviderContainer(
      overrides: [
        exportsDirectoryProvider.overrideWithValue(() async => exports),
        shareFilesProvider.overrideWithValue((files, _) async {
          shared.add(files);
          return completes;
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

  List<String> left() => exports.existsSync()
      ? [for (final f in exports.listSync()) f.uri.pathSegments.last]
      : [];

  test('the share sheet gets the files, their types and the origin', () async {
    final share = ProviderContainer().read(shareFilesProvider);
    const file = (path: '/tmp/a.csv', mimeType: 'text/csv');

    expect(await share([file], _origin), isTrue);
    final params = platform.shared.single;
    expect(params.files!.single.path, '/tmp/a.csv');
    expect(params.files!.single.mimeType, 'text/csv');
    expect(params.sharePositionOrigin, _origin);

    platform.status = ShareResultStatus.dismissed;
    expect(await share([file], _origin), isFalse);
    platform.status = ShareResultStatus.success;
  });

  test('a completed share keeps its files until the next export', () async {
    await export('first.pdf');
    expect(shared.single.single.path, '${exports.path}/first.pdf');
    expect(left(), ['first.pdf']);

    await export('second.pdf');
    expect(left(), ['second.pdf']);
  });

  test('a cancelled share deletes its files at once', () async {
    completes = false;
    await export('first.pdf');
    expect(shared, hasLength(1));
    expect(exports.existsSync(), isFalse);
  });

  test('a failed export leaves nothing behind', () async {
    await expectLater(
      container.read(shareExportProvider)((dir) async {
        await File('${dir.path}/half.pdf').writeAsString('half');
        throw StateError('disk full');
      }, _origin),
      throwsStateError,
    );
    expect(exports.existsSync(), isFalse);
    expect(shared, isEmpty);
  });

  test('app start clears what the last run left', () async {
    await export('old.pdf');
    await clearExports(exports);
    expect(exports.existsSync(), isFalse);
    // Again, with nothing there.
    await clearExports(exports);
    // Without a platform cache directory (as here) it gives up quietly.
    await clearExportsAtStart();
  });
}
