import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/glyphs.dart';
import 'package:settlo_loans/src/loans_provider.dart';
import 'package:settlo_platform/settlo_platform.dart';

/// Download statement (Loan artboard header): makes [loan]'s statement
/// PDF on device and opens the share sheet. A second tap while one is
/// being made does nothing.
class StatementButton extends ConsumerStatefulWidget {
  /// The button for [loan]; [yourName] names your side.
  const new(this.loan, {this.yourName, super.key});

  /// The loan the statement covers.
  final Loan loan;

  /// Your profile name, if set.
  final String? yourName;

  @override
  ConsumerState<StatementButton> createState() => _StatementButtonState();
}

class _StatementButtonState extends ConsumerState<StatementButton> {
  var _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final share = ref.read(shareFilesProvider);
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    try {
      final now = DateTime.now();
      final day = indiaDate(now).toIso8601String().substring(0, 10);
      // shortcut: built on the UI isolate; fine for a loan's few dozen
      // repayments, move to an isolate if statements grow to many pages.
      final pdf = await statementPdf(
        loanStatement(widget.loan, generatedAt: now, yourName: widget.yourName),
        fonts: await loadStatementFonts(),
      );
      await share([
        (
          name: 'settlo-loan-statement-$day.pdf',
          mimeType: 'application/pdf',
          bytes: pdf,
        ),
      ], origin);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("We couldn't make the statement. Try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return IconButton(
      tooltip: 'Download statement',
      onPressed: _busy ? null : _share,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(SettloSpacing.minTouchTarget),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: c.surface,
        disabledBackgroundColor: c.surface,
        side: BorderSide(color: c.hairline),
      ),
      icon: LoanGlyph(
        LoanGlyph.download,
        color: _busy ? c.textMuted : c.textPrimary,
      ),
    );
  }
}
