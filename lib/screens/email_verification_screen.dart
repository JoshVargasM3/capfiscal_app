import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/cap_colors.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.onVerified,
    required this.onResend,
    required this.onSignOut,
  });

  final String email;
  final Future<void> Function() onVerified;
  final Future<void> Function() onResend;
  final Future<void> Function() onSignOut;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ auto-check cada 3s
    _timer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkVerified());

    // check inicial
    _checkVerified();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ al volver a la app, re-check inmediato
    if (state == AppLifecycleState.resumed) {
      _checkVerified();
    }
  }

  Future<void> _checkVerified() async {
    if (_checking) return;
    _checking = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;

      final verified = refreshed?.emailVerified ?? false;
      if (verified) {
        _timer?.cancel();
        await widget.onVerified();
      }
    } catch (_) {
      // silencioso
    } finally {
      _checking = false;
      if (mounted) setState(() {});
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CapColors.surface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(msg, style: const TextStyle(color: CapColors.text)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email =
        widget.email.trim().isEmpty ? 'tu correo' : widget.email.trim();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [CapColors.bgBottom, CapColors.bgMid, CapColors.bgTop],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: BoxDecoration(
                    color: CapColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 18,
                        offset: Offset(4, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mark_email_unread_outlined,
                        color: CapColors.gold,
                        size: 48,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Verifica tu correo',
                        style: TextStyle(
                          color: CapColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Te enviamos un enlace de verificación a:\n$email\n\n'
                        'Cuando lo verifiques, esta pantalla se actualizará automáticamente.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: CapColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ✅ Botón manual por si el usuario quiere forzar el check
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CapColors.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _checkVerified,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text(
                            'Ya verifiqué',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: CapColors.goldDark),
                            foregroundColor: CapColors.gold,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            await widget.onResend();
                            _snack('Correo de verificación reenviado.');
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text(
                            'Reenviar verificación',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: () async => widget.onSignOut(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
