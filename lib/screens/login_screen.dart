import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import 'event_picker_screen.dart';
import 'settings_screen.dart';

typedef LoginNextScreenBuilder = Widget Function(AuthService auth);

Widget _defaultLoginNext(AuthService a) => EventPickerScreen(authService: a);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    LoginNextScreenBuilder nextScreenBuilder = _defaultLoginNext,
  }) : _nextScreenBuilder = nextScreenBuilder;
  final AuthService authService;
  final LoginNextScreenBuilder _nextScreenBuilder;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  ResolvedApiUrl? _resolved;
  bool _reachabilityChecked = false;
  bool _reachable = true;

  @override
  void initState() {
    super.initState();
    _refreshApiState();
  }

  /// Re-evaluate the resolved API URL and ping `/healthz`. Called on first
  /// load and after returning from the settings screen.
  Future<void> _refreshApiState() async {
    final resolved = await widget.authService.resolveBaseUrl();
    if (!mounted) return;
    setState(() {
      _resolved = resolved;
      _reachabilityChecked = false;
    });
    final reachable = await widget.authService.isApiReachable();
    if (!mounted) return;
    setState(() {
      _reachable = reachable;
      _reachabilityChecked = true;
    });
  }

  bool get _bannerVisible {
    final resolved = _resolved;
    if (resolved == null) return false;
    final isHttps = resolved.url.toLowerCase().startsWith('https://');
    final reachable = _reachable || !_reachabilityChecked;
    return !isHttps || !reachable;
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context)!;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.authService.signIn(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => widget._nextScreenBuilder(widget.authService),
      ));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = l.loginErrorConnection(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final resolved = _resolved;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [Color(0xFF7c3aed), Color(0xFF06b6d4)]),
                    ),
                    child: const Icon(Icons.confirmation_num_rounded, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SettingsScreen(authService: widget.authService),
                      ));
                      await _refreshApiState();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(l.loginTitle, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                l.loginServer(resolved?.url ?? ''),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              if (_bannerVisible)
                Container(
                  key: const Key('login.api_unreachable_banner'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB45309), // amber-700 — visible, not chromeless
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.loginApiUnreachableBannerTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.loginApiUnreachableBannerBody(
                                  resolved?.url ?? ''),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(labelText: l.loginEmail, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: l.loginPassword, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF7c3aed),
                ),
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l.loginButton, style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
