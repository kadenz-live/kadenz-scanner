import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.authService});
  final AuthService authService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  ResolvedApiUrl? _resolved;

  @override
  void initState() {
    super.initState();
    _loadResolved();
  }

  Future<void> _loadResolved() async {
    final resolved = await widget.authService.resolveBaseUrl();
    if (!mounted) return;
    setState(() {
      _resolved = resolved;
      // Pre-fill the editor with the currently active URL so a user who
      // wants to nudge it (e.g. swap port) doesn't have to retype.
      _controller.text = resolved.url;
    });
  }

  String _sourceLabel(AppLocalizations l, ApiUrlSource source) {
    switch (source) {
      case ApiUrlSource.buildEnv:
        return l.settingsApiSourceEnv;
      case ApiUrlSource.storedOverride:
        return l.settingsApiSourceStored;
      case ApiUrlSource.defaultProd:
        return l.settingsApiSourceDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final resolved = _resolved;
    final lockedByEnv = resolved?.source == ApiUrlSource.buildEnv;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (resolved != null) ...[
              Container(
                key: const Key('settings.resolved_card'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.settingsApiResolvedTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(resolved.url,
                        key: const Key('settings.resolved_url'),
                        style: const TextStyle(fontFamily: 'monospace')),
                    const SizedBox(height: 4),
                    Text(
                      _sourceLabel(l, resolved.source),
                      key: const Key('settings.resolved_source'),
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(l.settingsApiBaseUrl),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              enabled: !lockedByEnv,
              decoration: InputDecoration(
                hintText: l.settingsApiBaseUrlHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              lockedByEnv
                  ? l.settingsApiBaseUrlLockedByEnv
                  : l.settingsApiBaseUrlTips,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const Spacer(),
            // Backlog #43: even closed-source apps must surface MIT/BSD/
            // Apache copyright notices of the OSS packages they ship.
            // Flutter's built-in `showLicensePage` walks the pubspec license
            // registry and renders the per-package text, so we just expose
            // it as a tap target.
            OutlinedButton.icon(
              onPressed: () {
                showLicensePage(
                  context: context,
                  applicationName: 'Kadenz Scanner',
                );
              },
              icon: const Icon(Icons.description_outlined),
              label: Text(l.settingsLicenses),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: lockedByEnv
                  ? null
                  : () async {
                      await widget.authService.setBaseUrl(_controller.text);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(l.settingsSave),
            ),
          ],
        ),
      ),
    );
  }
}
