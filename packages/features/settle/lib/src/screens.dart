import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Placeholder for the Settle artboard.
class SettleScreen extends StatelessWidget {
  /// The Settle screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Settle up', artboard: 'Settle');
}

/// Placeholder for the SettlePay artboard.
class SettlePayScreen extends StatelessWidget {
  /// The SettlePay screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Settle up', artboard: 'SettlePay');
}
