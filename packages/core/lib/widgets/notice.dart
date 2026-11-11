import 'dart:async';

import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';

OverlayEntry? _shown;

/// Tells the user something that needs no decision, such as a refused
/// sync. iOS has no snackbars, so there it is a banner that drops from the
/// top, as Mail's "Undo Send" does, and leaves after four seconds or on a
/// tap. Elsewhere it is a Material snackbar, as before.
///
/// [context] may be the root navigator's own, from above any screen.
void showSettloNotice(BuildContext context, String message) {
  if (Theme.of(context).platform != TargetPlatform.iOS) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  if (overlay == null) return;
  _shown?.remove();
  late final OverlayEntry entry;
  void dismiss() {
    if (_shown != entry) return;
    _shown = null;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _Banner(message: message, onDismiss: dismiss),
  );
  _shown = entry;
  overlay.insert(entry);
  Timer(const Duration(seconds: 4), dismiss);
}

class _Banner extends StatelessWidget {
  const new({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final banner = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Semantics(
          liveRegion: true,
          button: true,
          onTapHint: 'Dismiss',
          child: GestureDetector(
            onTap: onDismiss,
            onVerticalDragEnd: (_) => onDismiss(),
            child: Material(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(SettloRadius.button),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SettloRadius.button),
                  border: Border.all(color: SettloElevation.border(dark: dark)),
                  boxShadow: SettloElevation.ambient(dark: dark),
                ),
                child: Text(
                  message,
                  style: SettloTypography.subheadline(color: c.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: MediaQuery.disableAnimationsOf(context)
          ? banner
          : TweenAnimationBuilder<Offset>(
              tween: Tween(begin: const Offset(0, -1), end: Offset.zero),
              duration: SettloMotion.panel,
              curve: SettloMotion.curve,
              builder: (_, offset, child) =>
                  FractionalTranslation(translation: offset, child: child),
              child: banner,
            ),
    );
  }
}
