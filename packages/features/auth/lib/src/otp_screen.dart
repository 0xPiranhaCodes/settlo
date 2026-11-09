import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/sign_in_controller.dart';
import 'package:settlo_auth/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Seconds before another code can be asked for.
const resendCooldown = 30;

/// OTP: six boxes, the one being typed into in gold (focus is an action),
/// filled from the SMS by the platform (canvas note n02).
///
/// One hidden field holds the code, so paste and one-time-code autofill
/// (iOS from Messages, Android from the keyboard's SMS suggestion) fill
/// every box at once. The screen shows the number and nothing else: what
/// is attached to it appears only on Home after verifying.
class OtpScreen extends ConsumerStatefulWidget {
  /// The OTP screen; [autofocus] raises the keyboard on arrival.
  const new({this.autofocus = true, super.key});

  /// Whether the code field takes focus when the screen opens.
  final bool autofocus;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode(debugLabel: 'otp');
  Timer? _timer;
  int _wait = resendCooldown;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    _code.addListener(_rebuild);
    _startCooldown();
    if (ref.read(signInProvider).sentTo == null) {
      // Opened without sending a code (a stale link or a restored route).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) GoRouter.maybeOf(context)?.go(SettloRoutes.phone);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _startCooldown() {
    _timer?.cancel();
    _wait = resendCooldown;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _wait--);
      if (_wait <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final controller = ref.read(signInProvider.notifier);
    await controller.verifyCode(_code.text);
    if (!mounted) return;
    if (ref.read(signInProvider).error == SignInError.codeRejected) {
      _code.clear();
      _focus.requestFocus();
    }
  }

  Future<void> _resend() async {
    final sent = await ref.read(signInProvider.notifier).resendCode();
    if (!sent || !mounted) return;
    _code.clear();
    _focus.requestFocus();
    setState(_startCooldown);
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final state = ref.watch(signInProvider);
    final sentTo = state.sentTo;
    final error = state.error;
    final caption = SettloTypography.figtree(13, color: c.textSecondary);
    return AuthPage(
      top: const StepHeader(step: 2, of: 2),
      content: [
        const SizedBox(height: 36),
        StepTitle(
          title: 'Enter the code',
          // The change link's 44pt target replaces the 10px gap above it.
          gap: 0,
          subtitle: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Sent to '),
                      TextSpan(
                        text: sentTo == null
                            ? 'your number'
                            : state.country.display(sentTo),
                        style: TextStyle(color: c.textPrimary),
                      ),
                      const TextSpan(text: ' · '),
                    ],
                  ),
                ),
              ),
              _TextAction(
                label: 'change',
                semanticLabel: 'Change number',
                size: 15,
                onTap: () => StepHeader.goBack(context),
              ),
            ],
          ),
        ),
        // 36 on the canvas, less the 11px of target under the change link.
        const SizedBox(height: 25),
        _CodeBoxes(
          controller: _code,
          focusNode: _focus,
          autofocus: widget.autofocus,
          onCompleted: _verify,
        ),
        // 44pt tall so Resend code has a full target; the text sits 14px
        // under the boxes as on the canvas.
        SizedBox(
          height: SettloSpacing.minTouchTarget,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Fills in automatically',
                  style: caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SettloSpacing.x1),
              if (_wait > 0)
                Text(
                  'Resend in 0:${_wait.toString().padLeft(2, '0')}',
                  style: caption,
                )
              else
                _TextAction(
                  label: 'Resend code',
                  onTap: state.busy ? null : _resend,
                ),
            ],
          ),
        ),
        if (error != null) ...[AuthErrorText(error.message(state.country))],
        const Spacer(),
        const SizedBox(height: SettloSpacing.x3),
        SCard(
          padding: const EdgeInsets.all(SettloSpacing.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthIcon(AuthGlyph.shield, color: c.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This code is valid for 10 minutes. Settlo will never ask '
                  'for it on a call or chat.',
                  style: caption.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SettloSpacing.x2),
      ],
      bottom: AuthButton(
        label: 'Verify and continue',
        onPressed: state.busy ? null : _verify,
      ),
    );
  }
}

/// Six boxes drawn over one transparent field that takes the input.
class _CodeBoxes extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onCompleted;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final code = controller.text;
    final active = focusNode.hasFocus ? code.length : -1;
    Widget box(int i) => Container(
      constraints: const BoxConstraints(maxWidth: 50),
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SettloRadius.button),
        // The box being typed into is the one gold thing that is not a
        // button (canvas note n02).
        border: i == active
            ? Border.all(color: c.action, width: 2)
            : Border.all(color: i < code.length ? c.textPrimary : c.hairline),
      ),
      child: Text(
        i < code.length ? code[i] : '',
        style: SettloTypography.figtree(
          26,
          weight: FontWeight.w500,
          color: c.textPrimary,
        ),
      ),
    );
    // Boxes are 50 wide with at least 8 between, narrowing on small screens.
    return SizedBox(
      height: 64,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < otpLength; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Flexible(child: box(i)),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: TextField(
              key: const ValueKey('otp-code'),
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(otpLength),
              ],
              onChanged: (value) {
                if (value.length == otpLength) onCompleted();
              },
              onSubmitted: (_) => onCompleted(),
              // The boxes draw the code; the field only takes input.
              showCursor: false,
              expands: true,
              maxLines: null,
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              enableSuggestions: false,
              autocorrect: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// An inline text action in the action colour, with a 44pt tall target.
class _TextAction extends StatelessWidget {
  const new({
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.size = 13,
  });

  final String label;
  final double size;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // A 44pt tall target around the text.
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            style: SettloTypography.figtree(
              size,
              color: onTap == null ? c.textMuted : c.action,
            ),
          ),
        ),
      ),
    );
  }
}
