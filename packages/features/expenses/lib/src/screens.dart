import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/src/add_expense_sheet.dart';

/// The spaces an expense can go in, loaded when Add expense opens and
/// again whenever [ledgerRevisionProvider] is bumped.
final FutureProvider<List<SpaceSummary>> expenseSpacesProvider =
    FutureProvider.autoDispose<List<SpaceSummary>>((ref) {
      ref.watch(ledgerRevisionProvider);
      return ref.watch(spacesRepositoryProvider).load();
    });

/// Add expense (AddExpense artboard), risen to 54px below the top of the
/// screen. Opened from a space it goes straight to [AddExpenseSheet];
/// from Home it uses your only space, or asks which one when you have
/// more than one.
class AddExpenseScreen extends ConsumerStatefulWidget {
  /// Add expense in [spaceId], or in a space still to be chosen.
  const new({this.spaceId, super.key});

  /// The space it was opened from, if any.
  final String? spaceId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  late String? _spaceId = widget.spaceId;

  void _close() => popSettloTask(
    context,
    fallback: switch (widget.spaceId) {
      final id? => SettloRoutes.space(id),
      null => SettloRoutes.home,
    },
  );

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(expenseSpacesProvider);
    final media = MediaQuery.of(context);
    final list = spaces.value;
    final space = switch (list) {
      [final only] => only,
      _ => list?.where((s) => s.id == _spaceId).firstOrNull,
    };
    return Padding(
      padding: EdgeInsets.only(
        top: settloSheetTop(context),
        bottom: media.viewInsets.bottom,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: switch ((space, list)) {
          (final space?, _) => AddExpenseSheet(
            space: space,
            onClose: _close,
            onSaved: _close,
          ),
          (null, null) when spaces.hasError => _Frame(
            onClose: _close,
            message:
                "We couldn't load your spaces. Check your connection and try "
                'again.',
            action: SPrimaryButton(
              label: 'Try again',
              onPressed: () => ref.invalidate(expenseSpacesProvider),
            ),
          ),
          (null, null) => _Frame(onClose: _close),
          (null, []) => _Frame(
            onClose: _close,
            message: 'Expenses are shared in a space. Start one first.',
            action: SPrimaryButton(
              label: 'Start a space',
              onPressed: () => context.go(SettloRoutes.spaces),
            ),
          ),
          (null, final list?) => _Frame(
            onClose: _close,
            label: 'WHICH SPACE?',
            children: [
              for (final s in list)
                _SpaceRow(s, onTap: () => setState(() => _spaceId = s.id)),
            ],
          ),
        },
      ),
    );
  }
}

/// The sheet's frame without an amount: handle, close and title, then
/// [children] or [message] and [action].
class _Frame extends StatelessWidget {
  const new({
    required this.onClose,
    this.label,
    this.message,
    this.action,
    this.children = const [],
  });

  final VoidCallback onClose;
  final String? label;
  final String? message;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.specular)),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SettloRadius.cardHero),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SSheetScaffold(
          title: 'New expense',
          onClose: onClose,
          children: [
            if (label case final label?) ...[
              Text(
                label,
                style: SettloTypography.footnote(
                  letterSpacing: 0.3,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: SettloSpacing.x1),
            ],
            ...children,
            if (message case final message?) ...[
              Text(
                message,
                style: SettloTypography.headline(color: c.textPrimary),
              ),
              const SizedBox(height: SettloSpacing.x3),
            ],
            ?action,
          ],
        ),
      ),
    );
  }
}

class _SpaceRow extends StatelessWidget {
  const new(this.space, {required this.onTap});

  final SpaceSummary space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final others = [for (final m in space.others) m.name];
    return MergeSemantics(
      child: SPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SettloSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                space.name,
                style: SettloTypography.headline(color: c.textPrimary),
              ),
              if (others.isNotEmpty)
                Text(
                  others.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettloTypography.subheadline(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
