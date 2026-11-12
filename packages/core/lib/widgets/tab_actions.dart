import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/supabase/activity.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/bell.dart';
import 'package:settlo_core/widgets/glass_action.dart';

/// Your display name, for the tab avatar's initial. Features cannot reach
/// Home's provider (ADR 0002), so the app points this at it; null shows `Y`.
final accountNameProvider = Provider<String?>((_) => null);

/// The top-right actions of every tab root (#197): the tab's own [leading]
/// action, then the bell and your avatar.
class SettloTabActions extends ConsumerWidget {
  /// Actions that open Activity ([onBell]) and Profile ([onProfile]).
  const new({
    required this.onBell,
    required this.onProfile,
    this.leading,
    this.name,
    super.key,
  });

  /// Opens Activity; null leaves the bell out, as on Activity itself.
  final VoidCallback? onBell;

  /// Opens Profile.
  final VoidCallback onProfile;

  /// The tab's own action, such as Spaces' +.
  final Widget? leading;

  /// Your name when the screen has it; otherwise [accountNameProvider].
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SettloColors.of(context);
    final name = (this.name ?? ref.watch(accountNameProvider))?.trim() ?? '';
    final initial = name.isEmpty ? 'Y' : name.characters.first.toUpperCase();
    final onBell = this.onBell;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SettloSpacing.x1,
      children: [
        ?leading,
        if (onBell != null)
          SBell(
            unread: ref.watch(activityUnreadProvider).value ?? 0,
            onPressed: onBell,
          ),
        GlassAction(
          label: 'Profile',
          title: initial,
          onPressed: onProfile,
          fallback: IconButton(
            tooltip: 'Profile',
            onPressed: onProfile,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(SettloHomeMetrics.headerControl),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: SettloColors.dark.surfaceRaised,
              side: BorderSide(color: c.hairline),
            ),
            icon: Text(
              initial,
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.3),
              style: SettloTypography.headline(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
