import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';

/// Stands in for a screen until its feature issue builds it: the screen's
/// [title] and the canvas [artboard] it will match.
class SPlaceholderScreen extends StatelessWidget {
  /// A placeholder for the canvas [artboard], headed [title].
  const new({required this.title, required this.artboard, super.key});

  /// The screen's name, as a user would say it.
  final String title;

  /// The canvas artboard file name, without `.dc.html`.
  final String artboard;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SettloSpacing.screenMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.headlineSmall),
              const SizedBox(height: SettloSpacing.x1),
              Text(
                'Canvas artboard $artboard. This screen arrives in a later '
                'milestone.',
                style: text.bodyMedium?.copyWith(
                  color: SettloColors.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
