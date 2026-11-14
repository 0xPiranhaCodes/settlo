import 'package:flutter/cupertino.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/pressable.dart';

/// A clipped inset group with no border or shadow.
class SGroup extends StatelessWidget {
  /// Groups [children], with 16pt side margins by default.
  const new({
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    super.key,
  });

  /// Rows or other group contents.
  final List<Widget> children;

  /// Set to zero when the parent already supplies the inset.
  final EdgeInsetsGeometry margin;
  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(SettloRadius.group),
      child: ColoredBox(
        color: SettloColors.of(context).surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// An accessible grouped row that grows with its text.
class SRow extends StatelessWidget {
  /// The last row in a group should pass [separator] as false.
  const new({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.trailingSub,
    this.trailingSubSemanticsLabel,
    this.onTap,
    this.chevron = false,
    this.separator = true,
    super.key,
  });

  /// Primary text, 17pt regular.
  final String title;

  /// Secondary text, 15pt.
  final String? subtitle;

  /// A 36pt avatar or icon.
  final Widget? leading;

  /// Amount or accessory, inheriting 17pt medium.
  final Widget? trailing;

  /// Secondary amount label, 13pt.
  final String? trailingSub;

  /// Spoken amount, when the visible subtitle uses currency notation.
  final String? trailingSubSemanticsLabel;

  /// Optional activation.
  final VoidCallback? onTap;

  /// Shows a 16pt disclosure indicator.
  final bool chevron;

  /// Draws the half-point separator inset to the title.
  final bool separator;
  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: trailingSub == null ? null : 1,
          overflow: trailingSub == null ? null : TextOverflow.ellipsis,
          style: SettloTypography.body(color: c.textPrimary)
              .copyWith(height: 1.2),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SettloTypography.subheadline(color: c.textSecondary)
                .copyWith(height: 1.2),
          ),
      ],
    );
    final accessory = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: trailingSub == null
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.end,
      children: [
        if (trailing != null)
          DefaultTextStyle(
            style: SettloTypography.body(
              color: c.textPrimary,
              weight: FontWeight.w500,
            ).copyWith(height: 1.2),
            child: trailing!,
          ),
        if (trailingSub != null)
          Text(
            trailingSub!,
            textAlign: TextAlign.end,
            semanticsLabel: trailingSubSemanticsLabel,
            style: SettloTypography.footnote(color: c.textSecondary)
                .copyWith(height: 1.2),
          ),
      ],
    );
    // Keep both accessory lines together; a share may wrap at large text sizes.
    final stacked =
        trailingSub == null &&
        MediaQuery.textScalerOf(context).scale(17) > 25.5;
    final row = LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: subtitle == null ? 44 : 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (leading != null) ...[
                    SizedBox.square(dimension: 36, child: leading),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: stacked
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              text,
                              if (trailing != null) ...[
                                const SizedBox(height: 8),
                                accessory,
                              ],
                            ],
                          )
                        : text,
                  ),
                  if (!stacked &&
                      (trailing != null || trailingSub != null)) ...[
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: trailingSub == null
                            ? MediaQuery.sizeOf(context).width * .5
                            : constraints.maxWidth * .45,
                      ),
                      child: trailingSub == null
                          ? IntrinsicWidth(child: accessory)
                          : accessory,
                    ),
                  ],
                  if (chevron) ...[
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: c.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (separator)
            Padding(
              padding: EdgeInsets.only(left: leading == null ? 16 : 64),
              child: SizedBox(height: .5, child: ColoredBox(color: c.hairline)),
            ),
        ],
      ),
    );
    return onTap == null ? row : SPressable(onTap: onTap, child: row);
  }
}

/// Uppercase grouped-list heading with the shared vertical rhythm.
class SSectionLabel extends StatelessWidget {
  /// Labels the group that follows.
  const new(this.text, {this.semanticsLabel, super.key});

  /// Section name; rendered uppercase.
  final String text;

  /// Optional spoken heading, for formatted amounts.
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        semanticsLabel: semanticsLabel,
        style: SettloTypography.footnote(
          color: SettloColors.of(context).textSecondary,
          weight: FontWeight.w500,
          letterSpacing: .5,
        ).copyWith(height: 1.2),
      ),
    ),
  );
}
