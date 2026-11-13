import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/confirm.dart';

bool _ios(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// Cupertino controls below it in Figtree and tinted with Settlo tokens:
/// primary text for selection, never system blue.
class SettloCupertinoTheme extends StatelessWidget {
  /// Themes [child].
  const new({required this.child, super.key});

  /// The controls.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final picker = SettloTypography.title3(color: c.textPrimary);
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(
        primaryColor: c.action,
        textTheme: CupertinoTextThemeData(
          primaryColor: c.action,
          textStyle: SettloTypography.body(color: c.textPrimary),
          actionTextStyle: SettloTypography.body(color: c.action),
          pickerTextStyle: picker,
          dateTimePickerTextStyle: picker,
        ),
      ),
      child: child,
    );
  }
}

/// An on/off switch. On iOS a [CupertinoSwitch] whose on track is primary
/// action, using jade in light and marigold in dark.
class SSwitch extends StatelessWidget {
  /// A switch showing [value]; null [onChanged] disables it.
  const new({required this.value, required this.onChanged, super.key});

  /// Whether it is on.
  final bool value;

  /// Called with the new value.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (!_ios(context)) return Switch(value: value, onChanged: onChanged);
    final c = SettloColors.of(context);
    // The switch draws centred in a tight box: 44 tall makes its target
    // the 44pt minimum instead of the 39 it has alone.
    return SizedBox(
      width: 59,
      height: 44,
      child: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: c.action,
        inactiveTrackColor: c.surfaceHighest,
        // Dark thumbs are neutral fills on the marigold track.
        thumbColor: value
            ? (Theme.of(context).brightness == Brightness.dark
                  ? c.background
                  : c.onAction)
            : null,
      ),
    );
  }
}

/// Picks a day between [firstDate] and [lastDate]. On iOS a
/// [CupertinoDatePicker] wheel in a popup with Done; elsewhere Material's
/// calendar. Null when dismissed.
Future<DateTime?> showSettloDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  if (!_ios(context)) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    );
  }
  return _showWheel<DateTime>(
    context,
    initialDate,
    (onChanged) => CupertinoDatePicker(
      mode: CupertinoDatePickerMode.date,
      initialDateTime: initialDate,
      minimumDate: firstDate,
      maximumDate: lastDate,
      onDateTimeChanged: (d) => onChanged(DateUtils.dateOnly(d)),
      selectionOverlayBuilder:
          (context, {required selectedIndex, required columnCount}) =>
              _selectionOverlay(
                context,
                capStart: selectedIndex == 0,
                capEnd: selectedIndex == columnCount - 1,
              ),
    ),
  );
}

/// Picks one of [values] on a [CupertinoPicker] wheel in a popup with
/// Done. Null when dismissed. iOS only.
Future<T?> showSettloPicker<T>({
  required BuildContext context,
  required List<T> values,
  required T selected,
  required String Function(T) label,
}) => _showWheel<T>(
  context,
  selected,
  (onChanged) => CupertinoPicker(
    itemExtent: 36,
    scrollController: FixedExtentScrollController(
      initialItem: values.indexOf(selected),
    ),
    onSelectedItemChanged: (i) => onChanged(values[i]),
    selectionOverlay: _selectionOverlay(context),
    children: [for (final v in values) Center(child: Text(label(v)))],
  ),
);

/// The band behind the selected row: a Settlo surface, not system fill.
Widget _selectionOverlay(
  BuildContext context, {
  bool capStart = true,
  bool capEnd = true,
}) => CupertinoPickerDefaultSelectionOverlay(
  background: SettloColors.of(context).surfaceHighest,
  capStartEdge: capStart,
  capEndEdge: capEnd,
);

Future<T?> _showWheel<T>(
  BuildContext context,
  T initial,
  Widget Function(ValueChanged<T> onChanged) picker,
) {
  var current = initial;
  return showSettloPopup<T>(
    context: context,
    builder: (context) {
      final c = SettloColors.of(context);
      return SettloCupertinoTheme(
        child: Container(
          color: c.surface,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.hairline)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(current),
                      child: Text(
                        'Done',
                        style: SettloTypography.body(
                          weight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 216, child: picker((v) => current = v)),
            ],
          ),
        ),
      );
    },
  );
}

/// The iOS search field, in Figtree on a raised surface. It sits in the
/// content under the large title, so it scrolls away as in Mail.
class SSearchField extends StatelessWidget {
  /// A field calling [onChanged] with each edit.
  const new({required this.onChanged, this.placeholder = 'Search', super.key});

  /// Called with the query.
  final ValueChanged<String> onChanged;

  /// Shown while empty.
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SettloCupertinoTheme(
      child: CupertinoSearchTextField(
        placeholder: placeholder,
        onChanged: onChanged,
        backgroundColor: c.surfaceRaised,
        itemColor: c.textSecondary,
        style: SettloTypography.body(color: c.textPrimary),
        placeholderStyle: SettloTypography.body(color: c.textMuted),
        cursorColor: c.textPrimary,
      ),
    );
  }
}

/// Whether [query] finds [text]: every word, anywhere, ignoring case.
bool searchMatches(String query, String text) {
  final haystack = text.toLowerCase();
  return query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(haystack.contains);
}
