import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

/// Your spaces, to pick one to export.
final FutureProvider<List<SpaceSummary>> exportSpacesProvider =
    FutureProvider.autoDispose(
      (ref) => ref.watch(spacesRepositoryProvider).load(),
    );

/// Profile › Export: pick a space, and its expenses as CSV and a summary
/// PDF are made on this phone and handed to the share sheet. Loan
/// statements are on each loan.
class ExportSheet extends ConsumerStatefulWidget {
  /// The export sheet.
  const new({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  /// The space being exported; one at a time.
  String? _busy;
  String? _error;

  Future<void> _export(SpaceSummary space, Rect origin) async {
    if (_busy != null) return;
    setState(() {
      _busy = space.id;
      _error = null;
    });
    final export = ref.read(shareExportProvider);
    try {
      final ledger = await ref
          .read(spaceLedgerRepositoryProvider)
          .load(space.id);
      final now = DateTime.now();
      final stamp = _istDay(now);
      final name = _slug(space.name);
      final summary = spaceSummary(space, ledger, generatedAt: now);
      final fonts = await loadStatementFonts();
      // Names the fonts cannot draw are shaped by Flutter here, on the UI
      // isolate; the CSV and PDF are written on a background one.
      final images = await renderTextImages(textsOutsideFonts(summary, fonts));
      await export((dir) async {
        final csv = File('${dir.path}/settlo-$name-expenses-$stamp.csv');
        final pdf = File('${dir.path}/settlo-$name-summary-$stamp.pdf');
        await writeSpaceExport(
          space,
          ledger,
          summary,
          csv: csv,
          pdf: pdf,
          fonts: fonts,
          images: images,
        );
        return [
          (path: csv.path, mimeType: 'text/csv'),
          (path: pdf.path, mimeType: 'application/pdf'),
        ];
      }, origin);
    } on Object {
      if (mounted) {
        setState(() => _error = "We couldn't make the export. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    final spaces = ref.watch(exportSpacesProvider);
    final small = SettloTypography.subheadline(color: colors.textSecondary);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export',
            style: SettloTypography.title3(color: colors.textPrimary),
          ),
          const SizedBox(height: SettloSpacing.x1),
          Text(
            'Every expense as CSV and a summary PDF, made on this phone. '
            'Members appear by name, never by number. Loan statements are '
            'on each loan.',
            style: small,
          ),
          const SizedBox(height: SettloSpacing.x2),
          switch (spaces) {
            AsyncData(value: final list) when list.isEmpty => Padding(
              padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
              child: Text('No spaces to export yet.', style: small),
            ),
            AsyncData(value: final list) => Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final space in list)
                    Builder(
                      builder: (row) => SPressable(
                        onTap: _busy != null
                            ? null
                            : () async {
                                final box =
                                    row.findRenderObject()! as RenderBox;
                                await _export(
                                  space,
                                  box.localToGlobal(Offset.zero) & box.size,
                                );
                              },
                        child: ListTile(
                          minTileHeight: 52,
                          contentPadding: EdgeInsets.zero,
                          title: Text(space.name),
                          subtitle: Text(
                            _busy == space.id ? 'Preparing…' : 'CSV and PDF',
                          ),
                          // iOS: the share sheet opens once these are made.
                          trailing:
                              _busy == space.id &&
                                  Theme.of(context).platform ==
                                      TargetPlatform.iOS
                              ? const CupertinoActivityIndicator()
                              : null,
                          enabled: _busy == null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            AsyncError() => Padding(
              padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
              child: Text("We couldn't load your spaces.", style: small),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: SettloSpacing.x2),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          },
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: SettloTypography.subheadline(color: colors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

/// `2026-11-10`, India's date at [instant].
String _istDay(DateTime instant) => instant
    .toUtc()
    .add(const Duration(hours: 5, minutes: 30))
    .toIso8601String()
    .substring(0, 10);

/// A file-name-safe form of a space name; `space` when nothing is left.
String _slug(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return s.isEmpty ? 'space' : s;
}
