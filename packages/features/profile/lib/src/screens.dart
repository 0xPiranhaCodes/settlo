import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:settlo_profile/src/export_sheet.dart';
import 'package:settlo_profile/src/glyphs.dart';
import 'package:settlo_profile/src/profile_controller.dart';
import 'package:settlo_profile/src/profile_repository.dart';
import 'package:settlo_profile/src/reminder_toggle.dart';
import 'package:settlo_profile/src/theme_mode.dart';

final Uri _supportUri = Uri.parse('https://settlo.hellojosh.studio/support/');

/// Profile and settings (canvas Profile, note n31).
class ProfileScreen extends ConsumerWidget {
  /// The profile screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final data = profile.value;
    final media = MediaQuery.of(context);
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: SettloScrollScaffold(
          title: 'You',
          padding: EdgeInsets.fromLTRB(
            SettloSpacing.screenMargin,
            math.max(media.padding.top, 44) + 16,
            SettloSpacing.screenMargin,
            media.padding.bottom + SettloSpacing.x2,
          ),
          children: [
            const _Header(),
            const SizedBox(height: 24),
            if (data != null) ...[
              _Identity(data),
              const SizedBox(height: SettloSpacing.x3),
              _UpiCard(data),
              const SizedBox(height: SettloSpacing.x3),
              const _SectionLabel('Preferences'),
              const SizedBox(height: SettloSpacing.x2),
              const ReminderToggle(),
              const SizedBox(height: SettloSpacing.x2),
              const _QuietPreferences(),
              const SizedBox(height: 16),
              const _SectionLabel('Help'),
              const SizedBox(height: SettloSpacing.x2),
              const _HelpCard(),
              const SizedBox(height: 16),
              const _SectionLabel('Account'),
              const SizedBox(height: SettloSpacing.x2),
              _AccountCard(data),
            ] else if (profile.hasError) ...[
              const SizedBox(height: 80),
              Text(
                "We couldn't load your profile.",
                textAlign: TextAlign.center,
                style: SettloTypography.headline(
                  color: SettloColors.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: SettloSpacing.x2),
              Center(
                child: SSecondaryButton(
                  label: 'Try again',
                  onPressed: () => ref.invalidate(profileProvider),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Back',
              onPressed: context.pop,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(44),
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
                backgroundColor: colors.surface,
                side: BorderSide(color: colors.hairline),
              ),
              icon: ProfileIcon(
                ProfileGlyph.back,
                color: colors.textPrimary,
                size: 18,
              ),
            ),
          ),
          Text(
            'You',
            style: SettloTypography.headline(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const new(this.data);

  final ProfileData data;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return Row(
      children: [
        SAvatar(data.name, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SettloTypography.title3(
                  letterSpacing: -0.3,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _groupPhone(data.phone),
                style: SettloTypography.subheadline(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpiCard extends StatelessWidget {
  const new(this.data);

  final ProfileData data;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return SCard(
      child: Row(
        children: [
          const _IconTile(ProfileGlyph.wallet, action: true),
          const SizedBox(width: SettloSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UPI ID for settle-ups',
                  style: SettloTypography.footnote(color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  data.upiId ?? 'Not added',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettloTypography.headline(color: colors.textPrimary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showEditProfile(context, data),
            style: TextButton.styleFrom(
              foregroundColor: colors.action,
              minimumSize: const Size(64, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _QuietPreferences extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => _SettingsCard(
    rows: [
      const _SettingRowData(
        ProfileGlyph.person,
        'Contacts matching',
        'Find friends already on Settlo',
      ),
      const _SettingRowData(
        ProfileGlyph.shield,
        'App lock',
        'Face ID when opening',
      ),
      _SettingRowData(
        ProfileGlyph.download,
        'Export',
        'Statements as PDF or CSV',
        onTap: () => showSettloSheet<void>(
          context: context,
          builder: (_) => const ExportSheet(),
        ),
      ),
    ],
  );
}

class _AccountCard extends ConsumerWidget {
  const new(this.data);

  final ProfileData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.dark;
    return _SettingsCard(
      rows: [
        const _SettingRowData(
          ProfileGlyph.phone,
          'Change number',
          'Keep your ledgers, move your account',
        ),
        _SettingRowData(ProfileGlyph.appearance, 'Appearance', switch (mode) {
          ThemeMode.system => 'Follows system',
          ThemeMode.dark => 'Dark',
          ThemeMode.light => 'Light',
        }, onTap: () => _showAppearance(context, mode)),
        _SettingRowData(
          ProfileGlyph.edit,
          'Name and UPI ID',
          'Edit your settle-up details',
          onTap: () => _showEditProfile(context, data),
        ),
        _SettingRowData(
          ProfileGlyph.logout,
          'Sign out',
          'Your ledgers stay safely recorded',
          onTap: () => _signOut(context, ref),
        ),
        _SettingRowData(
          ProfileGlyph.trash,
          'Delete account',
          'Remove your profile and sign-in for good',
          onTap: () => _deleteAccount(context, ref),
        ),
      ],
    );
  }

  /// Signs out, after asking first when changes made offline have not
  /// reached the server: signing out deletes them from this phone.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider.notifier);
    // Not widget state: a second tap in the same frame must see it.
    if (profile.leaving) return;
    profile.leaving = true;
    try {
      final unsent = ref.read(unsentChangesProvider);
      final count = await unsent?.count() ?? 0;
      if (unsent != null && count > 0) {
        if (!context.mounted) return;
        final title = 'You have ${_changes(count)}';
        const body =
            "They haven't reached the server yet. Signing out now "
            'deletes them from this phone.';
        final ios = Theme.of(context).platform == TargetPlatform.iOS;
        final leave = ios
            ? await showSettloActionSheet(
                context: context,
                title: title,
                message: body,
                destructive: 'Sign Out Anyway',
                cancel: 'Keep',
              )
            : await showSettloSheet<bool>(
                context: context,
                builder: (_) => _LeaveSheet(
                  title: title,
                  body: body,
                  keep: 'Keep',
                  leave: 'Sign out anyway',
                  onKeep: unsent.drain,
                ),
              );
        // The action sheet's Keep sends them now, as the sheet's Keep does.
        if (ios && leave == false) unawaited(unsent.drain().catchError((_) {}));
        if (leave != true) return;
      }
      await profile.signOut();
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("We couldn't sign you out. Try again.")),
      );
    } finally {
      profile.leaving = false;
    }
  }

  /// Deletes the account after a confirmation that says what goes and what
  /// stays, and that unsent changes go too, as when signing out.
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider.notifier);
    // Shared with sign-out: only one way of leaving runs at a time.
    if (profile.leaving) return;
    profile.leaving = true;
    try {
      final count = await ref.read(unsentChangesProvider)?.count() ?? 0;
      if (!context.mounted) return;
      const title = 'Delete your account?';
      final body =
          'This removes your name, UPI ID, phone number and friends '
          'list, and signs you out. Expenses, loans and settle-ups you '
          "share stay in the other people's records. "
          '${count > 0 ? 'Your ${_changes(count)} will be lost. ' : ''}'
          "This can't be undone.";
      final delete = Theme.of(context).platform == TargetPlatform.iOS
          ? await showSettloAlert(
              context: context,
              title: title,
              message: body,
              destructive: 'Delete Account',
              cancel: 'Keep My Account',
            )
          : await showSettloSheet<bool>(
              context: context,
              builder: (_) => _LeaveSheet(
                title: title,
                body: body,
                keep: 'Keep my account',
                leave: 'Delete account',
              ),
            );
      if (delete != true) return;
      await profile.deleteAccount();
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We couldn't delete your account. Try again."),
        ),
      );
    } finally {
      profile.leaving = false;
    }
  }
}

String _changes(int count) =>
    count == 1 ? '1 unsent change' : '$count unsent changes';

class _HelpCard extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SettingsCard(
    rows: [
      _SettingRowData(
        ProfileGlyph.help,
        'Help and support',
        'Guides, privacy, and contact details',
        onTap: () => _openSupport(context, ref),
      ),
    ],
  );

  Future<void> _openSupport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await ref.read(openUrlProvider)(_supportUri);
      if (opened || !context.mounted) return;
    } on Object {
      if (!context.mounted) return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text("We couldn't open support. Try again.")),
    );
  }
}

/// Asks before signing out with unsent changes, or deleting the account.
/// Pops true to leave; the keep button stays and runs [onKeep].
class _LeaveSheet extends StatefulWidget {
  const new({
    required this.title,
    required this.body,
    required this.keep,
    required this.leave,
    this.onKeep,
  });

  final String title;
  final String body;
  final String keep;
  final String leave;
  final Future<void> Function()? onKeep;

  @override
  State<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends State<_LeaveSheet> {
  bool _busy = false;

  void _close({required bool leave}) {
    // Not state: a second tap in the same frame would pop Profile too.
    if (_busy) return;
    _busy = true;
    // Sent in the background; nothing here waits for the network.
    if (!leave) unawaited(widget.onKeep?.call().catchError((_) {}));
    Navigator.of(context).pop(leave);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: SettloTypography.title3(color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: SettloTypography.body(color: colors.textSecondary)
                  .copyWith(height: 1.4),
            ),
            const SizedBox(height: SettloSpacing.x3),
            SizedBox(
              width: double.infinity,
              child: SPrimaryButton(
                label: widget.keep,
                onPressed: () => _close(leave: false),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SSecondaryButton(
                label: widget.leave,
                onPressed: () => _close(leave: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: SettloTypography.footnote(
      letterSpacing: 0.3,
      color: SettloColors.of(context).textSecondary,
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const new({required this.rows});

  final List<_SettingRowData> rows;

  @override
  Widget build(BuildContext context) => SCard(
    padding: const EdgeInsets.all(SettloSpacing.screenMargin),
    child: Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          _SettingRow(rows[index]),
          if (index != rows.length - 1)
            const SizedBox(height: SettloSpacing.x2),
        ],
      ],
    ),
  );
}

class _SettingRowData {
  const new(this.icon, this.title, this.subtitle, {this.onTap});

  final ProfileGlyph icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

class _SettingRow extends StatelessWidget {
  const new(this.data);

  final _SettingRowData data;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return Semantics(
      button: data.onTap != null,
      child: SPressable(
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              _IconTile(data.icon),
              const SizedBox(width: SettloSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.title,
                      style: SettloTypography.headline(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SettloTypography.footnote(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (data.onTap != null)
                ProfileIcon(ProfileGlyph.chevron, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const new(this.icon, {this.action = false});

  final ProfileGlyph icon;
  final bool action;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: action
            ? Color.alphaBlend(
                colors.action.withValues(alpha: 0.14),
                colors.surface,
              )
            : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(SettloRadius.iconTile),
      ),
      alignment: Alignment.center,
      child: ProfileIcon(
        icon,
        color: action ? colors.action : colors.textPrimary,
      ),
    );
  }
}

Future<void> _showEditProfile(BuildContext context, ProfileData data) =>
    showSettloSheet<void>(
      context: context,
      builder: (_) => _EditProfileSheet(data),
    );

class _EditProfileSheet extends ConsumerStatefulWidget {
  const new(this.data);

  final ProfileData data;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _upi;
  String? _serverError;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.data.name);
    _upi = TextEditingController(text: widget.data.upiId);
  }

  @override
  void dispose() {
    _name.dispose();
    _upi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name and UPI ID',
              style: SettloTypography.title3(color: colors.textPrimary),
            ),
            const SizedBox(height: SettloSpacing.x3),
            TextFormField(
              key: const ValueKey('profile-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: validateProfileName,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('profile-upi-id'),
              controller: _upi,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'UPI ID',
                hintText: 'name@bank',
              ),
              validator: validateUpiId,
            ),
            if (_serverError != null) ...[
              const SizedBox(height: SettloSpacing.x2),
              Text(
                _serverError!,
                style: SettloTypography.subheadline(color: colors.textPrimary),
              ),
            ],
            const SizedBox(height: SettloSpacing.x3),
            SizedBox(
              width: double.infinity,
              child: SPrimaryButton(
                label: _saving ? 'Saving…' : 'Save',
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileProvider.notifier)
          .save(name: _name.text, upiId: _upi.text);
      if (mounted) Navigator.of(context).pop();
    } on ProfileInputException catch (error) {
      if (mounted) setState(() => _serverError = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _serverError = "We couldn't save your profile. Try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> _showAppearance(BuildContext context, ThemeMode selected) =>
    showSettloSheet<void>(
      context: context,
      builder: (_) => _AppearanceSheet(selected),
    );

class _AppearanceSheet extends ConsumerWidget {
  const new(this.selected);

  final ThemeMode selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SettloColors.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: SettloTypography.title3(color: colors.textPrimary),
          ),
          const SizedBox(height: SettloSpacing.x2),
          for (final mode in ThemeMode.values)
            SPressable(
              onTap: () async {
                try {
                  await ref.read(themeModeProvider.notifier).setMode(mode);
                  if (context.mounted) Navigator.of(context).pop();
                } on Object {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "We couldn't change your appearance. Try again.",
                      ),
                    ),
                  );
                }
              },
              child: ListTile(
                minTileHeight: 52,
                contentPadding: EdgeInsets.zero,
                title: Text(_themeLabel(mode)),
                trailing: mode == selected
                    ? ProfileIcon(ProfileGlyph.check, color: colors.textPrimary)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

String _themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Use system setting',
  ThemeMode.dark => 'Dark',
  ThemeMode.light => 'Light',
};

String _groupPhone(String e164) => e164.startsWith('+91') && e164.length == 13
    ? '+91 ${e164.substring(3, 8)} ${e164.substring(8)}'
    : e164;
