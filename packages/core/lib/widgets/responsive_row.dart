import 'package:flutter/widgets.dart';
import 'package:settlo_core/theme/tokens.dart';

/// Related content uses a row normally and full-width blocks at large text.
/// Flexible children lose their horizontal flex when stacked vertically.
class SResponsiveRow extends StatelessWidget {
  /// Creates a row that stacks at 150% text by default.
  const new({
    required this.children,
    this.threshold = 1.5,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    super.key,
  });

  /// Row children, including Expanded or Flexible content.
  final List<Widget> children;

  /// Text scale at which content becomes vertical.
  final double threshold;

  /// Alignment while arranged horizontally.
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) < threshold) {
      return Row(crossAxisAlignment: crossAxisAlignment, children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          switch (child) {
            Flexible(:final child) => child,
            SizedBox(:final width, height: null) when width != null =>
              const SizedBox(height: SettloSpacing.x2),
            _ => child,
          },
      ],
    );
  }
}
