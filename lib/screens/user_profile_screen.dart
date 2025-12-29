// lib/screens/user_profile_screen.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:http/http.dart' as http;
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';
import '../helpers/subscription_guard.dart';
import '../services/subscription_service.dart';
import '../services/payment_service.dart';
import '../config/subscription_config.dart';

/// Cloud Function para PaymentIntent (la misma que usas en suscripción)
const String _kStripeVerifyPaymentUrl =
    'https://us-central1-capfiscal-biblioteca-app.cloudfunctions.net/stripePaymentIntentRequest';

/// Monto de verificación: $10.00 MXN => 1000 centavos
const int _kVerifyAmountCents = 1000;

/// 🎨 Paleta CAPFISCAL
class _CapColors {
  static const bgTop = Color(0xFF0A0A0B);
  static const bgMid = Color(0xFF2A2A2F);
  static const bgBottom = Color(0xFF4A4A50);
  static const surface = Color(0xFF1C1C21);
  static const surfaceAlt = Color(0xFF2A2A2F);
  static const text = Color(0xFFEFEFEF);
  static const textMuted = Color(0xFFBEBEC6);
  static const field = Color(0xFF9D9FA3); // gris de campos
  static const gold = Color(0xFFE1B85C);
  static const goldDark = Color(0xFFB88F30);
}

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final SubscriptionService _subscriptionService = SubscriptionService();
  final SubscriptionPaymentService _paymentService =
      SubscriptionPaymentService.instance;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  bool _signingOut = false;
  bool _updatingPaymentMethods = false;

  // Favoritos
  bool _loadingFavs = true;
  List<Reference> _favDocs = [];
  List<_FavVideo> _favVideos = [];

  String? _photoUrl;

  // Suscripción
  DateTime? _createdAt; // fecha creación cuenta
  DateTime? _startDate;
  DateTime? _endDate;
  String? _paymentMethod;
  List<StoredPaymentMethod> _paymentMethods = [];
  bool _cancelAtPeriodEnd = false;
  DateTime? _cancelsAt;
  String? _stripeSubscriptionId;
  SubscriptionState? _subscriptionState;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  // ------------------- DATA -------------------

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _loadingFavs = true;
    });
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _loadingFavs = false;
        });
        return;
      }
      final snap = await _db.collection('users').doc(user.uid).get();
      final data = snap.data() ?? {};

      // createdAt desde Firestore (campo raíz)
      final createdTs = data['createdAt'];
      if (createdTs is Timestamp) {
        _createdAt = createdTs.toDate();
      } else {
        _createdAt = null;
      }

      // Datos básicos de perfil
      _nameCtrl.text =
          (data['name'] ?? user.displayName ?? '').toString().trim();
      _phoneCtrl.text = (data['phone'] ?? '').toString().trim();
      _emailCtrl.text = (data['email'] ?? user.email ?? '').toString().trim();
      _cityCtrl.text = (data['city'] ?? '').toString().trim();
      _photoUrl = data['photoUrl'] as String?;

      // Datos de suscripción normalizados
      final status = SubscriptionStatus.fromUserData(data);
      _startDate = status.startDate;
      _endDate = status.endDate;
      _subscriptionState = status.state;
      _stripeSubscriptionId = status.stripeSubscriptionId;
      _cancelAtPeriodEnd = status.cancelAtPeriodEnd;
      _cancelsAt = status.cancellationEffectiveDate;

      // paymentMethod y lista de métodos
      final subData = (data['subscription'] as Map<String, dynamic>?) ?? {};
      _paymentMethod = (status.paymentMethod ??
              status.primaryPaymentMethod?.label ??
              subData['paymentMethod'])
          ?.toString();

      _paymentMethods = status.paymentMethods;

      // Si no hay lista de métodos pero sí hay paymentMethod inicial,
      // construimos un método principal para mostrarlo en la UI.
      if (_paymentMethods.isEmpty &&
          _paymentMethod != null &&
          _paymentMethod!.trim().isNotEmpty) {
        _paymentMethods = [
          StoredPaymentMethod(
            id: 'pm_initial',
            label: _paymentMethod!,
            brand: _paymentMethod!,
            last4: '----',
            isDefault: true,
            createdAt: _startDate ?? DateTime.now().toUtc(),
          ),
        ];
      }

      await _loadFavorites();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractYoutubeRaw(Map<String, dynamic> data) {
    final candidates = [
      'youtubeId',
      'youtube_id',
      'ytId',
      'yt_id',
      'videoId',
      'video_id',
      'url',
      'link',
      'youtube',
      'video',
    ];
    for (final k in candidates) {
      final val = data[k];
      if (val is String && val.trim().isNotEmpty) return val.trim();
    }
    return '';
  }

  String _normalizeYouTubeId(String raw) {
    final v = raw.trim();
    final idRe = RegExp(r'^[a-zA-Z0-9_-]{11}$');
    if (idRe.hasMatch(v)) return v;

    Uri? u;
    try {
      u = Uri.parse(v);
    } catch (_) {
      return v;
    }

    if (u.host.contains('youtu.be')) {
      if (u.pathSegments.isNotEmpty && idRe.hasMatch(u.pathSegments.first)) {
        return u.pathSegments.first;
      }
    }

    if (u.host.contains('youtube.com')) {
      final q = u.queryParameters['v'];
      if (q != null && idRe.hasMatch(q)) return q;

      final segs = u.pathSegments;
      final i = segs.indexOf('shorts');
      if (i >= 0 && i + 1 < segs.length && idRe.hasMatch(segs[i + 1])) {
        return segs[i + 1];
      }
      final j = segs.indexOf('embed');
      if (j >= 0 && j + 1 < segs.length && idRe.hasMatch(segs[j + 1])) {
        return segs[j + 1];
      }
    }
    return v;
  }

  bool _inFav(Set<String> favSet, String value, {String? typePrefix}) {
    if (value.isEmpty) return false;
    if (favSet.contains(value)) return true;
    if (typePrefix != null && favSet.contains('$typePrefix:$value')) {
      return true;
    }
    return false;
  }

  Future<void> _loadFavorites() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _loadingFavs = false);
        return;
      }

      final favNames = await FavoritesManager.getFavorites(uid);
      final favSet = favNames.map((e) => e.trim()).toSet();

      final root = await _storage.ref('/').listAll();
      final docs = root.items.where((ref) {
        return _inFav(favSet, ref.name) ||
            _inFav(favSet, ref.name, typePrefix: 'doc');
      }).toList();

      final vSnap = await _db.collection('videos').get();
      final List<_FavVideo> vids = [];
      for (final d in vSnap.docs) {
        final data = d.data();
        final raw = _extractYoutubeRaw(data);
        final id = _normalizeYouTubeId(raw);
        final title = (data['title'] ?? '').toString().trim();
        final desc = (data['description'] ?? '').toString().trim();

        final isFav = _inFav(favSet, id, typePrefix: 'video') ||
            _inFav(favSet, d.id, typePrefix: 'video') ||
            _inFav(favSet, title, typePrefix: 'video') ||
            favSet.contains(d.id) ||
            favSet.contains(title);

        if (isFav && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
          vids.add(_FavVideo(
            docId: d.id,
            youtubeId: id,
            title: title.isEmpty ? 'Video' : title,
            description: desc,
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _favDocs = docs;
        _favVideos = vids;
        _loadingFavs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFavs = false);
    }
  }

  String _subscriptionLabel() {
    final state = _subscriptionState;
    if (state == null) return 'Sin información';
    switch (state) {
      case SubscriptionState.active:
        return _cancelAtPeriodEnd
            ? 'Activa (se cancelará al final del periodo)'
            : 'Activa';
      case SubscriptionState.grace:
        return 'En periodo de gracia';
      case SubscriptionState.pending:
        return 'Pago pendiente de confirmación';
      case SubscriptionState.blocked:
        return 'Cuenta bloqueada';
      case SubscriptionState.expired:
        return 'Expirada';
      case SubscriptionState.none:
        return 'Sin suscripción';
    }
  }

  Future<void> _downloadAndOpenFile(Reference ref) async {
    if (!await SubscriptionGuard.ensureActive(context)) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${ref.name}');
      if (!await file.exists()) {
        await ref.writeToFile(file);
      }
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir archivo: $e')),
      );
    }
  }

  Future<void> _reloadAuthUser() async {
    try {
      await _auth.currentUser?.reload();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<bool> _reauthWithPassword(String email) async {
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reautenticación requerida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ingresa tu contraseña para actualizar el correo ($email).'),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    try {
      final user = _auth.currentUser!;
      final cred = EmailAuthProvider.credential(
        email: email,
        password: passCtrl.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reautenticación fallida: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final currentEmail = user.email ?? '';
      final newEmail = _emailCtrl.text.trim();
      if (newEmail.isNotEmpty && newEmail != currentEmail) {
        try {
          await user.updateEmail(newEmail);
          await _reloadAuthUser();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            final ok = await _reauthWithPassword(
              currentEmail.isNotEmpty ? currentEmail : newEmail,
            );
            if (ok) {
              await user.updateEmail(newEmail);
              await _reloadAuthUser();
            } else {
              if (mounted) setState(() => _saving = false);
              return;
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('No se pudo actualizar el correo: ${e.code}')),
              );
            }
            if (mounted) setState(() => _saving = false);
            return;
          }
        }
      }

      await user.updateDisplayName(_nameCtrl.text.trim());
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        await user.updatePhotoURL(_photoUrl);
      }

      await _db.collection('users').doc(user.uid).set({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': newEmail.isNotEmpty ? newEmail : (user.email ?? ''),
        'city': _cityCtrl.text.trim(),
        'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'subscription': {
          'startDate':
              _startDate != null ? Timestamp.fromDate(_startDate!) : null,
          'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
          'paymentMethod': _paymentMethod,
        }
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil guardado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeImage() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null) return;

    try {
      final file = File(picked.path);
      final ref = _storage.ref('users/${user.uid}/profile.jpg');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      setState(() => _photoUrl = url);

      await _db.collection('users').doc(user.uid).set(
        {'photoUrl': url, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await user.updatePhotoURL(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto actualizada')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir imagen: $e')),
      );
    }
  }

  Future<void> _deleteImage() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _storage.ref('users/${user.uid}/profile.jpg').delete();
    } catch (_) {}
    await _db.collection('users').doc(user.uid).set(
      {'photoUrl': null, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await user.updatePhotoURL(null);

    if (mounted) setState(() => _photoUrl = null);
  }

  // ------- Métodos de pago -------

  String _detectCardBrand(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Tarjeta';
    switch (digits[0]) {
      case '4':
        return 'Visa';
      case '5':
        return 'Mastercard';
      case '3':
        return 'Amex';
      case '6':
        return 'Discover';
      default:
        return 'Tarjeta';
    }
  }

  InputDecoration _dialogFieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _CapColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: _CapColors.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _CapColors.gold),
      ),
      counterText: '',
    );
  }

  Future<void> _addPaymentMethod() async {
    final aliasCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    final cvvCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      // <-- resto igual
      context: context,
      barrierDismissible: !_updatingPaymentMethods,
      builder: (_) => AlertDialog(
        backgroundColor: _CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Nuevo método de pago',
          style: TextStyle(
            color: _CapColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: aliasCtrl,
                  style: const TextStyle(color: _CapColors.text),
                  decoration: _dialogFieldDeco('Alias (opcional)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: _CapColors.text),
                  decoration:
                      _dialogFieldDeco('Número de tarjeta (16 dígitos)'),
                  maxLength: 19,
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 16) {
                      return 'Debes ingresar 16 dígitos';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: expCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: _CapColors.text),
                        decoration: _dialogFieldDeco('Vencimiento (MM/AA)'),
                        maxLength: 5,
                        onChanged: (value) {
                          final digits =
                              value.replaceAll(RegExp(r'[^0-9]'), '');
                          String formatted = digits;
                          if (digits.length > 4) {
                            formatted = digits.substring(0, 4);
                          }
                          if (formatted.length >= 3) {
                            formatted =
                                '${formatted.substring(0, 2)}/${formatted.substring(2)}';
                          }
                          if (formatted != value) {
                            expCtrl.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                  offset: formatted.length),
                            );
                          }
                        },
                        validator: (v) {
                          final text = (v ?? '').trim();
                          final regex = RegExp(r'^\d{2}/\d{2}$');
                          if (!regex.hasMatch(text)) {
                            return 'Formato MM/AA';
                          }
                          final parts = text.split('/');
                          final mm = int.tryParse(parts[0]) ?? 0;
                          if (mm < 1 || mm > 12) {
                            return 'Mes inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: cvvCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: _CapColors.text),
                        decoration: _dialogFieldDeco('CVV'),
                        obscureText: true,
                        maxLength: 4,
                        validator: (v) {
                          final digits =
                              (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (digits.length < 3 || digits.length > 4) {
                            return 'CVV inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Por seguridad no almacenamos el número completo ni el CVV; '
                  'solo se guardan alias, marca y últimos 4 dígitos.',
                  style: TextStyle(
                    color: _CapColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: _CapColors.text,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _CapColors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final rawNumber = numberCtrl.text.replaceAll(RegExp(r'\D'), '');
      final last4 = rawNumber.substring(rawNumber.length - 4);
      final brand = _detectCardBrand(rawNumber);
      final exp = expCtrl.text.trim();
      final alias = aliasCtrl.text.trim();

      final label = alias.isNotEmpty
          ? '$alias · vence $exp'
          : '$brand terminación $last4 · vence $exp';

      final newMethod = StoredPaymentMethod(
        id: 'pm_${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        brand: brand,
        last4: last4,
        isDefault: _paymentMethods.isEmpty,
        createdAt: DateTime.now().toUtc(),
      );

      await _savePaymentMethods([..._paymentMethods, newMethod]);
      await _verifyPaymentMethod(); // verificación de $10
    }

    aliasCtrl.dispose();
    numberCtrl.dispose();
    expCtrl.dispose();
    cvvCtrl.dispose();
  }

  Future<void> _setPrimaryMethod(StoredPaymentMethod method) async {
    final updated = _paymentMethods
        .map((m) => m.copyWith(isDefault: m.id == method.id))
        .toList();
    await _savePaymentMethods(updated);
    await _verifyPaymentMethod(); // verificación al cambiar principal
  }

  Future<void> _removePaymentMethod(StoredPaymentMethod method) async {
    final updated =
        _paymentMethods.where((m) => m.id != method.id).toList(growable: false);
    if (updated.isNotEmpty && updated.every((m) => m.isDefault == false)) {
      updated[0] = updated[0].copyWith(isDefault: true);
    }
    await _savePaymentMethods(updated);
  }

  Future<void> _savePaymentMethods(List<StoredPaymentMethod> methods) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    setState(() => _updatingPaymentMethods = true);
    try {
      await _subscriptionService.updateSubscription(
        uid,
        paymentMethods: methods,
        paymentMethod: methods.isNotEmpty
            ? methods
                .firstWhere((m) => m.isDefault, orElse: () => methods.first)
                .label
            : null,
      );
      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        _paymentMethod = methods.isNotEmpty
            ? methods
                .firstWhere((m) => m.isDefault, orElse: () => methods.first)
                .label
            : null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Métodos actualizados.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron guardar los cambios: $e')),
      );
    } finally {
      if (mounted) setState(() => _updatingPaymentMethods = false);
    }
  }

  /// Verifica el método de pago con Stripe cobrando $10 MXN mediante PaymentSheet.
  Future<void> _verifyPaymentMethod() async {
    // Solo en móvil, como en la pantalla de suscripción
    if (kIsWeb) return;

    // Si Stripe no está configurado, salimos silenciosamente
    if (SubscriptionConfig.stripePublishableKey.isEmpty) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final email = user.email ?? '${user.uid}@capfiscal.local';

      // 1) Llamar a la Cloud Function con monto de verificación de $10 MXN.
      final resp = await http.post(
        Uri.parse(_kStripeVerifyPaymentUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': _kVerifyAmountCents, // 1000 centavos = $10 MXN
          'currency': 'mxn',
          'email': email,
          'uid': user.uid,
          'description': 'Verificación de método de pago CAPFISCAL',
          'metadata': {
            'uid': user.uid,
            'type': 'payment_method_verification',
          },
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception('Stripe init falló: ${resp.body}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception('Stripe init falló: ${data['error']}');
      }

      // 2) Inicializar PaymentSheet usando SetupPaymentSheetParameters
      await stripe.Stripe.instance.initPaymentSheet(
        paymentSheetParameters: stripe.SetupPaymentSheetParameters(
          merchantDisplayName: 'CAPFISCAL',
          paymentIntentClientSecret: data['paymentIntent'] as String,
          customerId: data['customer'] as String,
          customerEphemeralKeySecret: data['ephemeralKey'] as String,
          allowsDelayedPaymentMethods: true,
        ),
      );

      // 3) Presentar PaymentSheet
      await stripe.Stripe.instance.presentPaymentSheet();

      // 4) Guardar marca de verificación
      await _db.collection('users').doc(user.uid).set({
        'subscription': {
          'lastPaymentVerificationAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Método verificado correctamente. Se realizó un cargo de prueba de \$10 MXN.',
          ),
        ),
      );
    } on stripe.StripeException catch (e) {
      if (!mounted) return;
      final msg = e.error.localizedMessage ?? e.error.message ?? e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verificación cancelada o fallida: $msg'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No pudimos verificar el método de pago: $e'),
        ),
      );
    }
  }

  // ------- Cancelación manual vía correo -------

  Future<void> _sendCancellationEmail() async {
    final user = _auth.currentUser;
    final email = user?.email ?? _emailCtrl.text.trim();
    final uid = user?.uid ?? '';
    final now = DateTime.now();

    final subject = Uri.encodeComponent(
        'Solicitud de cancelación de suscripción CAPFISCAL');
    final body = Uri.encodeComponent(
      'Hola equipo CAPFISCAL,\n\n'
      'Quiero solicitar la cancelación de mi suscripción a la Biblioteca CAPFISCAL.\n\n'
      'Datos de la cuenta:\n'
      '- Correo: $email\n'
      '- UID: $uid\n'
      '- Fecha de solicitud: $now\n\n'
      'Entiendo que la cancelación se realizará manualmente dentro de un plazo '
      'máximo de 3 días.\n\n'
      'Gracias.',
    );

    final uri =
        Uri.parse('mailto:petmega.redes@gmail.com?subject=$subject&body=$body');

    try {
      // primero verificamos si hay app de correo disponible
      final can = await canLaunchUrl(uri);
      if (!can) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se encontró ninguna app de correo configurada en este dispositivo.'),
          ),
        );
        return;
      }

      // forzamos abrir la app de correo externa
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No se pudo abrir la app de correo en este dispositivo.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Abrimos tu app de correo. Envía el mensaje para completar la solicitud.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Ocurrió un problema al intentar abrir la app de correo.'),
        ),
      );
    }
  }

  Future<void> _confirmManualCancellation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Solicitar cancelación',
          style: TextStyle(
            color: _CapColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'Si solicitas la cancelación de tu suscripción, perderás todos los '
          'beneficios y el acceso a los documentos una vez que el equipo de '
          'CAPFISCAL procese tu solicitud.\n\n'
          'La cancelación se realiza de forma manual en un plazo máximo de 3 días. '
          'Al continuar, prepararemos un correo dirigido a petmega.redes@gmail.com '
          'con tus datos para completar el proceso.',
          style: TextStyle(color: _CapColors.textMuted),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: _CapColors.text,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir con mi suscripción'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _CapColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _sendCancellationEmail();
    }
  }

  // --------- Acciones de cuenta ---------

  Future<void> _sendPasswordReset() async {
    final email = _auth.currentUser?.email ?? _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay correo para enviar el reinicio.')),
      );
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Te enviamos un correo a $email')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar correo: $e')),
      );
    }
  }

  Future<void> _sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo de verificación enviado')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar verificación: $e')),
      );
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cerrar sesión: $e')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cerrar sesión',
            style:
                TextStyle(color: _CapColors.text, fontWeight: FontWeight.w800)),
        content: const Text('¿Seguro que deseas cerrar tu sesión?',
            style: TextStyle(color: _CapColors.textMuted)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: _CapColors.text,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _CapColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _signOut();
    }
  }

  // ------------------- UI -------------------

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    final didPop = await navigator.maybePop();
    if (!mounted || didPop || !navigator.mounted) return;
    navigator.pushReplacementNamed('/home');
  }

  void _showAvatarMenu(Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: 'view', child: Text('Ver imagen')),
        PopupMenuItem(value: 'change', child: Text('Cambiar imagen')),
        PopupMenuItem(value: 'delete', child: Text('Eliminar imagen')),
      ],
    );
    if (result == 'view') {
      if (_photoUrl == null) return;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            child: Image.network(_photoUrl!, fit: BoxFit.contain),
          ),
        ),
      );
    } else if (result == 'change') {
      _changeImage();
    } else if (result == 'delete') {
      _deleteImage();
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '--';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = _auth.currentUser?.emailVerified ?? false;
    final w = MediaQuery.of(context).size.width;
    final avatarSize = (w * 0.60).clamp(160.0, 300.0); // ~60% del ancho

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_CapColors.bgBottom, _CapColors.bgMid, _CapColors.bgTop],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        drawer: const CustomDrawer(),
        appBar: CapfiscalTopBar(
          onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          onRefresh: () async {
            await _reloadAuthUser();
            await _loadProfile();
          },
          onProfile: () {},
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_CapColors.gold),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Back
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: _handleBack,
                            borderRadius: BorderRadius.circular(24),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(.08),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.arrow_back,
                                      size: 18, color: _CapColors.text),
                                ),
                                const SizedBox(width: 8),
                                const Text('Regresar',
                                    style: TextStyle(
                                        color: _CapColors.text,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),

                    // Título
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                      child: Center(
                        child: Text(
                          'PERFIL',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: _CapColors.gold,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .6,
                              ),
                        ),
                      ),
                    ),

                    // Banner verificación
                    if (!isVerified)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: MaterialBanner(
                          backgroundColor: const Color(0xFFFFF3CD),
                          content: const Text(
                              'Tu correo no está verificado. Verifica para mejorar la seguridad de tu cuenta.'),
                          leading: const Icon(Icons.info_outline),
                          actions: [
                            TextButton(
                              onPressed: _sendEmailVerification,
                              child: const Text('ENVIAR VERIFICACIÓN'),
                            ),
                            TextButton(
                              onPressed: _reloadAuthUser,
                              child: const Text('YA VERIFIQUÉ'),
                            ),
                          ],
                        ),
                      ),

                    // Avatar
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    _CapColors.gold,
                                    _CapColors.goldDark
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            ClipOval(
                              child: Container(
                                width: avatarSize * 0.86,
                                height: avatarSize * 0.86,
                                color: _CapColors.surfaceAlt,
                                child: _photoUrl == null
                                    ? const Center(
                                        child: Icon(Icons.person,
                                            color: Colors.black, size: 80),
                                      )
                                    : Image.network(
                                        _photoUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                          child: Icon(Icons.person,
                                              color: Colors.black, size: 80),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              right: avatarSize * 0.14 * 0.20,
                              bottom: avatarSize * 0.14 * 0.20,
                              child: GestureDetector(
                                onTapDown: (d) =>
                                    _showAvatarMenu(d.globalPosition),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  child: const Icon(Icons.edit, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Campos perfil
                    _ProfileField(
                      icon: Icons.person,
                      label: 'Nombre',
                      controller: _nameCtrl,
                      enabled: _editing,
                    ),
                    _ProfileField(
                      icon: Icons.mail,
                      label: 'E-mail',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      enabled: _editing,
                    ),
                    _ProfileField(
                      icon: Icons.phone,
                      label: 'Teléfono',
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      enabled: _editing,
                    ),
                    _ProfileField(
                      icon: Icons.location_city,
                      label: 'Estado / Ciudad',
                      controller: _cityCtrl,
                      enabled: _editing,
                    ),

                    // Botones editar / guardar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          if (!_editing)
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: _CapColors.goldDark),
                                  foregroundColor: _CapColors.gold,
                                  backgroundColor: _CapColors.surface,
                                ),
                                onPressed: () =>
                                    setState(() => _editing = true),
                                icon: const Icon(Icons.edit),
                                label: const Text('Editar'),
                              ),
                            ),
                          if (_editing) ...[
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _CapColors.text,
                                  side: const BorderSide(color: Colors.white24),
                                ),
                                onPressed: () {
                                  setState(() => _editing = false);
                                  _loadProfile(); // descarta cambios
                                },
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _CapColors.gold,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: _saving ? null : _saveProfile,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black),
                                      )
                                    : const Icon(Icons.save),
                                label: const Text('Guardar'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ===== Suscripción =====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'DATOS DE LA SUSCRIPCIÓN',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: _CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    _SubscriptionRow(
                        label: 'MIEMBRO DESDE', value: _fmtDate(_createdAt)),
                    _SubscriptionRow(
                        label: 'FECHA DE INICIO', value: _fmtDate(_startDate)),
                    _SubscriptionRow(
                        label: 'FECHA DE TÉRMINO', value: _fmtDate(_endDate)),
                    _SubscriptionRow(
                      label: 'MÉTODO DE PAGO',
                      value: _paymentMethod ??
                          _paymentMethods
                              .firstWhere(
                                (m) => m.isDefault,
                                orElse: () => _paymentMethods.isNotEmpty
                                    ? _paymentMethods.first
                                    : const StoredPaymentMethod(
                                        id: 'default',
                                        label: '--',
                                        brand: '--',
                                        last4: '----',
                                        isDefault: true,
                                      ),
                              )
                              .label,
                    ),

                    if (_subscriptionState != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Builder(
                            builder: (_) {
                              final isActive = _subscriptionState ==
                                      SubscriptionState.active &&
                                  !_cancelAtPeriodEnd;
                              final bg = isActive
                                  ? Colors.greenAccent
                                  : Colors.white10;
                              final textColor =
                                  isActive ? Colors.black : _CapColors.text;
                              return Chip(
                                backgroundColor: bg,
                                label: Text(
                                  _subscriptionLabel(),
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    if (_cancelAtPeriodEnd)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _cancelsAt == null
                                ? 'La suscripción se cancelará al final del periodo actual.'
                                : 'La suscripción seguirá activa hasta ${_fmtDate(_cancelsAt)}.',
                            style: const TextStyle(color: _CapColors.text),
                          ),
                        ),
                      ),

                    // Botón para solicitar cancelación manual
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _CapColors.gold,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _confirmManualCancellation,
                              child: const Text(
                                'Solicitar cancelación de suscripción',
                                style: TextStyle(fontWeight: FontWeight.w700),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Gestión de métodos de pago
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: Row(
                        children: [
                          Text(
                            'MÉTODOS DE PAGO',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: _CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Agregar',
                            onPressed: _updatingPaymentMethods
                                ? null
                                : _addPaymentMethod,
                            icon: const Icon(Icons.add, color: _CapColors.text),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: _paymentMethods.isEmpty
                            ? const [
                                Text(
                                  'Aún no guardas métodos de pago alternos.',
                                  style: TextStyle(color: _CapColors.textMuted),
                                ),
                              ]
                            : _paymentMethods
                                .map(
                                  (method) => _PaymentMethodCard(
                                    method: method,
                                    isUpdating: _updatingPaymentMethods,
                                    onSetPrimary: () =>
                                        _setPrimaryMethod(method),
                                    onRemove: () =>
                                        _removePaymentMethod(method),
                                  ),
                                )
                                .toList(),
                      ),
                    ),

                    // ===== Favoritos =====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: Text(
                        'MIS FAVORITOS',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: _CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    if (_loadingFavs)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_CapColors.gold),
                          ),
                        ),
                      )
                    else ...[
                      // Docs
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _FavCard(
                          title: 'Documentos',
                          child: _favDocs.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'No tienes documentos favoritos',
                                    style:
                                        TextStyle(color: _CapColors.textMuted),
                                  ),
                                )
                              : SizedBox(
                                  height: 150,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    padding:
                                        const EdgeInsets.fromLTRB(8, 8, 8, 12),
                                    itemCount: _favDocs.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (ctx, i) {
                                      final ref = _favDocs[i];
                                      return SizedBox(
                                        width: 150,
                                        child: _DocTile(
                                          name: ref.name,
                                          onTap: () =>
                                              _downloadAndOpenFile(ref),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                      // Videos
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: _FavCard(
                          title: 'Videos',
                          child: _favVideos.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'No tienes videos favoritos',
                                    style:
                                        TextStyle(color: _CapColors.textMuted),
                                  ),
                                )
                              : SizedBox(
                                  height: 130,
                                  child: LayoutBuilder(
                                    builder: (ctx, constraints) {
                                      double cardWidth =
                                          MediaQuery.of(ctx).size.width - 48;
                                      if (cardWidth < 220) cardWidth = 220;
                                      if (cardWidth > 340) cardWidth = 340;
                                      return ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 8, 8, 12),
                                        itemCount: _favVideos.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 10),
                                        itemBuilder: (ctx, i) {
                                          final v = _favVideos[i];
                                          return SizedBox(
                                            width: cardWidth,
                                            child: _VideoTile(
                                              title: v.title,
                                              youtubeId: v.youtubeId,
                                              description: v.description,
                                              onTap: () {
                                                Navigator.pushReplacementNamed(
                                                    context, '/video');
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),

        // ✅ Bottom nav — Perfil = índice 4
        bottomNavigationBar: const CapfiscalBottomNav(currentIndex: 4),
      ),
    );
  }
}

// ----------- Widgets auxiliares de UI -----------

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.icon,
    required this.label,
    required this.controller,
    this.enabled = false,
    this.keyboardType,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _CapColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _CapColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  style: const TextStyle(color: _CapColors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: _CapColors.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'Descripción',
                    hintStyle: const TextStyle(color: Colors.white),
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

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _CapColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 48,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _CapColors.field,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                style: const TextStyle(color: _CapColors.text, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.method,
    required this.isUpdating,
    required this.onSetPrimary,
    required this.onRemove,
  });

  final StoredPaymentMethod method;
  final bool isUpdating;
  final VoidCallback onSetPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _CapColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          method.label,
          style: const TextStyle(color: _CapColors.text),
        ),
        subtitle: Text(
          '${method.brand.toUpperCase()} · •••• ${method.last4}',
          style: const TextStyle(color: _CapColors.textMuted),
        ),
        trailing: method.isDefault
            ? const Chip(
                label: Text('Principal'),
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(color: _CapColors.text),
              )
            : Wrap(
                spacing: 6,
                children: [
                  TextButton(
                    onPressed: isUpdating ? null : onSetPrimary,
                    child: const Text('Principal'),
                  ),
                  IconButton(
                    onPressed: isUpdating ? null : onRemove,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---- Tarjetas y tiles de Favoritos ----

class _FavCard extends StatelessWidget {
  const _FavCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _CapColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _CapColors.gold,
                )),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.name,
    required this.onTap,
  });

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _CapColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, size: 40, color: _CapColors.gold),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _CapColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavVideo {
  final String docId;
  final String youtubeId;
  final String title;
  final String description;

  _FavVideo({
    required this.docId,
    required this.youtubeId,
    required this.title,
    required this.description,
  });
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.title,
    required this.youtubeId,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String youtubeId;
  final String description;
  final VoidCallback onTap;

  String get _thumb => 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: _CapColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: SizedBox(
                width: 120,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    _thumb,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF3A3A3F),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported,
                          color: _CapColors.textMuted),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Video' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _CapColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _CapColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        description.isEmpty ? 'Descripción' : description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: _CapColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
