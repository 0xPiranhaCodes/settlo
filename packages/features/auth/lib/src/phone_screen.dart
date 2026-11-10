import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/phone_number.dart';
import 'package:settlo_auth/src/sign_in_controller.dart';
import 'package:settlo_auth/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Phone: the number is the account, so it gets a full screen and a 26px
/// input. +91 is preselected and the picker stays reachable (canvas note
/// n01). The country shows as text (`IN +91`), not a flag emoji, pending
/// the owner's decision.
class PhoneScreen extends ConsumerStatefulWidget {
  /// The Phone screen; [autofocus] raises the keyboard on arrival.
  const new({this.autofocus = true, super.key});

  /// Whether the number field takes focus when the screen opens.
  final bool autofocus;

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  late final TextEditingController _number;

  @override
  void initState() {
    super.initState();
    final state = ref.read(signInProvider);
    _number = TextEditingController(text: state.country.group(state.national));
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await ref.read(signInProvider.notifier).sendCode();
    if (sent && mounted) context.go(SettloRoutes.otp);
  }

  Future<void> _pickCountry() async {
    final current = ref.read(signInProvider).country;
    final picked = await showSettloSheet<Country>(
      context: context,
      // As in AuthPage: no ambient letter spacing.
      builder: (_) => DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0),
        child: _CountrySheet(selected: current),
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(signInProvider.notifier).selectCountry(picked);
    _number.text = picked.group(picked.nationalDigits(_number.text));
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final state = ref.watch(signInProvider);
    final error = state.error;
    return AuthPage(
      top: const StepHeader(step: 1, of: 2),
      content: [
        const SizedBox(height: 36),
        const StepTitle(
          title: "What's your number?",
          subtitle: Text(
            "Friends find you by it, and anything they've already recorded "
            'with you appears the moment you verify.',
          ),
        ),
        const SizedBox(height: 36),
        Text(
          'MOBILE NUMBER',
          style: SettloTypography.footnote(
            letterSpacing: 0.3,
            color: c.textSecondary,
          ),
        ),
        const SizedBox(height: SettloSpacing.x1),
        SCard(
          child: Row(
            children: [
              _CountryChip(country: state.country, onTap: _pickCountry),
              const SizedBox(width: SettloSpacing.x2),
              Expanded(
                child: TextField(
                  key: const ValueKey('phone-number'),
                  controller: _number,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.send,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [NationalNumberFormatter(state.country)],
                  onChanged: ref.read(signInProvider.notifier).updateNumber,
                  onSubmitted: (_) => _send(),
                  style: SettloTypography.body(
                    letterSpacing: 0.5,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    // Bare: the card is the field.
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: state.country == Country.india
                        ? '98765 43210'
                        : 'Number',
                    hintStyle: SettloTypography.body(
                      letterSpacing: 0.5,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SettloSpacing.x2),
        if (error != null)
          AuthErrorText(error.message(state.country))
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthIcon(AuthGlyph.message, color: c.textSecondary, size: 16),
              const SizedBox(width: SettloSpacing.x2),
              Expanded(
                child: Text(
                  "We'll text a 6-digit code. Standard SMS rates may apply.",
                  style: SettloTypography.subheadline(color: c.textSecondary),
                ),
              ),
            ],
          ),
        const Spacer(),
        const SizedBox(height: SettloSpacing.x3),
      ],
      bottom: AuthButton(
        label: 'Send code',
        arrow: true,
        onPressed: state.busy ? null : _send,
      ),
    );
  }
}

/// The country code as text, `IN +91`, opening the picker on tap.
class _CountryChip extends StatelessWidget {
  const new({required this.country, required this.onTap});

  final Country country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      button: true,
      label: 'Country code ${country.name} +${country.dialCode}. Change',
      excludeSemantics: true,
      child: SPressable(
        key: const ValueKey('country-chip'),
        onTap: onTap,
        ringRadius: BorderRadius.circular(SettloRadius.iconTile),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SettloSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: c.hairline)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                country.iso,
                style: SettloTypography.body(color: c.textSecondary),
              ),
              const SizedBox(width: 6),
              Text(
                '+${country.dialCode}',
                style: SettloTypography.body(color: c.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountrySheet extends StatelessWidget {
  const new({required this.selected});

  final Country selected;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'Country code',
              style: SettloTypography.headline(color: c.textPrimary),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: media.padding.bottom + 16),
              children: [
                for (final country in Country.all)
                  Semantics(
                    selected: country == selected,
                    child: SPressable(
                      onTap: () => Navigator.of(context).pop(country),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SettloSpacing.screenMargin,
                          ),
                          child: SResponsiveRow(
                            children: [
                              SizedBox(
                                width:
                                    MediaQuery.textScalerOf(context).scale(1) >=
                                        1.5
                                    ? null
                                    : 76,
                                child: Text(
                                  country.label,
                                  maxLines: 1,
                                  style: SettloTypography.headline(
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  country.name,
                                  style: SettloTypography.headline(
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                              if (country == selected)
                                Text(
                                  'Selected',
                                  style: SettloTypography.subheadline(
                                    color: c.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
