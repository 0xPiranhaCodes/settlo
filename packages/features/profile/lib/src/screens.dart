import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/src/export_sheet.dart';
import 'package:settlo_profile/src/glyphs.dart';
import 'package:settlo_profile/src/profile_controller.dart';
import 'package:settlo_profile/src/profile_repository.dart';
import 'package:settlo_profile/src/theme_mode.dart';

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
        child: ListView(
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
              const SizedBox(height: 20),
              _UpiCard(data),
              const SizedBox(height: 20),
              const _SectionLabel('Preferences'),
              const SizedBox(height: 10),
              const _QuietPreferences(),
              const SizedBox(height: 16),
              const _SectionLabel('Account'),
              const SizedBox(height: 10),
              _AccountCard(data),
            ] else if (profile.hasError) ...[
              const SizedBox(height: 80),
              Text(
                "We couldn't load your profile.",
                textAlign: TextAlign.center,
                style: SettloTypography.figtree(
                  15,
                  color: SettloColors.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: 12),
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
            style: SettloTypography.figtree(
              15,
              weight: FontWeight.w500,
              color: colors.textPrimary,
            ),
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
                style: SettloTypography.figtree(
                  20,
                  weight: FontWeight.w500,
                  letterSpacing: -0.3,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _groupPhone(data.phone),
                style: SettloTypography.figtree(
                  13,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          const _IconTile(ProfileGlyph.wallet, action: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UPI ID for settle-ups',
                  style: SettloTypography.figtree(
                    12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.upiId ?? 'Not added',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettloTypography.figtree(
                    15,
                    weight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
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
        ProfileGlyph.bell,
        'Reminders',
        'Gentle nudges before due dates',
      ),
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
      ],
    );
  }

  /// Signs out, after asking first when changes made offline have not
  /// reached the server: signing out deletes them from this phone.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider.notifier);
    // Not widget state: a second tap in the same frame must see it.
    if (profile.signingOut) return;
    profile.signingOut = true;
    try {
      final unsent = ref.read(unsentChangesProvider);
      final count = await unsent?.count() ?? 0;
      if (unsent != null && count > 0) {
        if (!context.mounted) return;
        final leave = await showSettloSheet<bool>(
          context: context,
          builder: (_) => _UnsentSheet(count, drain: unsent.drain),
        );
        if (leave != true) return;
      }
      await profile.signOut();
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("We couldn't sign you out. Try again.")),
      );
    } finally {
      profile.signingOut = false;
    }
  }
}

/// Asks before a sign-out that would delete [count] unsent changes.
/// Pops true to sign out anyway; Keep tries to send them and stays.
class _UnsentSheet extends StatefulWidget {
  const new(this.count, {required this.drain});

  final int count;
  final Future<void> Function() drain;

  @override
  State<_UnsentSheet> createState() => _UnsentSheetState();
}

class _UnsentSheetState extends State<_UnsentSheet> {
  bool _busy = false;

  void _close({required bool leave}) {
    // Not state: a second tap in the same frame would pop Profile too.
    if (_busy) return;
    _busy = true;
    // Sent in the background; nothing here waits for the network.
    if (!leave) unawaited(widget.drain().catchError((_) {}));
    Navigator.of(context).pop(leave);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    final changes = widget.count == 1
        ? '1 unsent change'
        : '${widget.count} unsent changes';
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have $changes',
            style: SettloTypography.figtree(
              20,
              weight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "They haven't reached the server yet. Signing out now deletes "
            'them from this phone.',
            style: SettloTypography.figtree(
              14,
              color: colors.textSecondary,
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: SPrimaryButton(
              label: 'Keep',
              onPressed: () => _close(leave: false),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SSecondaryButton(
              label: 'Sign out anyway',
              onPressed: () => _close(leave: true),
            ),
          ),
        ],
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
    style: SettloTypography.figtree(
      12,
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
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
    child: Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          _SettingRow(rows[index]),
          if (index != rows.length - 1) const Divider(height: 1),
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
      child: InkWell(
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              _IconTile(data.icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.title,
                      style: SettloTypography.figtree(
                        15,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SettloTypography.figtree(
                        12,
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
        borderRadius: BorderRadius.circular(14),
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
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name and UPI ID',
              style: SettloTypography.figtree(
                20,
                weight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
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
              const SizedBox(height: 12),
              Text(
                _serverError!,
                style: SettloTypography.figtree(13, color: colors.textPrimary),
              ),
            ],
            const SizedBox(height: 20),
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
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: SettloTypography.figtree(
              20,
              weight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (final mode in ThemeMode.values)
            ListTile(
              minTileHeight: 52,
              contentPadding: EdgeInsets.zero,
              title: Text(_themeLabel(mode)),
              trailing: mode == selected
                  ? ProfileIcon(ProfileGlyph.check, color: colors.textPrimary)
                  : null,
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
