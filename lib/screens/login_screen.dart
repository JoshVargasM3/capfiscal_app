// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Paleta dark + gold
class _CapColors {
  static const bgTop = Color(0xFF0A0A0B);
  static const bgMid = Color(0xFF2A2A2F);
  static const bgBottom = Color(0xFF4A4A50);

  static const surface = Color(0xFF1C1C21);
  static const surfaceAlt = Color(0xFF2A2A2F);

  static const text = Color(0xFFEFEFEF);
  static const textMuted = Color(0xFFBEBEC6);

  static const gold = Color(0xFFE1B85C);
  static const goldDark = Color(0xFFB88F30);
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _isLogin = true;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _ensureUserDoc(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'phone': '',
        'city': '',
        'photoUrl': user.photoURL,
        'subscription': {
          'startDate': null,
          'endDate': null,
          'paymentMethod': null,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _submit() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _loading = true);
    try {
      UserCredential cred;
      if (_isLogin) {
        cred = await _auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text.trim(),
        );
      } else {
        cred = await _auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text.trim(),
        );
        if (cred.user != null) await _ensureUserDoc(cred.user!);
      }
      if (cred.user != null) await _ensureUserDoc(cred.user!);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu correo para continuar.')),
      );
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Te enviamos un correo a $email')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar: ${e.message ?? e.code}')),
      );
    }
  }

  InputDecoration _fieldDeco({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _CapColors.textMuted),
      prefixIcon: Icon(icon, color: _CapColors.textMuted),
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: _CapColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _CapColors.gold),
      ),
    );
  }

  Widget _goldButton({
    required String text,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_CapColors.gold, _CapColors.goldDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _CapColors.gold.withOpacity(.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_CapColors.bgTop, _CapColors.bgMid, _CapColors.bgBottom],
          stops: [0.0, 0.6, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ===== Logo responsive (usa assets/capfiscal_logo.png) =====
                    LayoutBuilder(
                      builder: (context, c) {
                        // Ancho del logo = 60% del ancho disponible (entre 180 y 420)
                        final w = c.maxWidth.clamp(280.0, 480.0);
                        final logoW = (w * 0.60).clamp(180.0, 420.0);
                        // Altura en relación aproximada del PNG (ancho:alto ~ 4:1)
                        final logoH = logoW / 4.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: logoW,
                            height: logoH,
                            child: Image.asset(
                              'assets/capfiscal_logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Biblioteca & Capacitación',
                      style: TextStyle(
                        color: _CapColors.textMuted,
                        fontSize: 12,
                        letterSpacing: .3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // ===== Card del formulario =====
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      decoration: BoxDecoration(
                        color: _CapColors.surface,
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
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _isLogin ? 'INICIAR SESIÓN' : 'CREAR CUENTA',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: _CapColors.text,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .4,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Email
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              style: const TextStyle(color: _CapColors.text),
                              decoration: _fieldDeco(
                                label: 'Correo',
                                icon: Icons.mail_outline,
                              ),
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return 'Ingresa tu correo';
                                if (!t.contains('@') || !t.contains('.')) {
                                  return 'Correo inválido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),

                            // Password
                            TextFormField(
                              controller: _pass,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              style: const TextStyle(color: _CapColors.text),
                              decoration: _fieldDeco(
                                label: 'Contraseña',
                                icon: Icons.lock_outline,
                                suffix: IconButton(
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: _CapColors.textMuted,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return 'Ingresa tu contraseña';
                                if (t.length < 6) return 'Mínimo 6 caracteres';
                                return null;
                              },
                            ),

                            if (_isLogin) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _loading ? null : _forgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: _CapColors.gold,
                                  ),
                                  child: const Text(
                                    '¿Olvidaste tu contraseña?',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 8),
                            _goldButton(
                              text: _isLogin ? 'Entrar' : 'Registrarme',
                              onPressed: _submit,
                              loading: _loading,
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => setState(() => _isLogin = !_isLogin),
                              child: Text(
                                _isLogin
                                    ? '¿No tienes cuenta? Crear una'
                                    : '¿Ya tienes cuenta? Inicia sesión',
                                style: const TextStyle(
                                  color: _CapColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                    const Text(
                      'Al continuar aceptas nuestros Términos y Aviso de Privacidad.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: _CapColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
