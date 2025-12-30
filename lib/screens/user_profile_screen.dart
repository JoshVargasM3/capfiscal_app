// lib/screens/user_profile_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/subscription_config.dart';
import '../helpers/favorites_manager.dart';
import '../helpers/subscription_guard.dart';
import '../models/fav_video.dart';
import '../services/subscription_service.dart';
import '../theme/cap_colors.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/favorites/doc_tile.dart';
import '../widgets/favorites/fav_card.dart';
import '../widgets/favorites/video_tile.dart';
import '../widgets/profile/profile_field.dart';
import '../widgets/profile/subscription_row.dart';

/// (Nota) Ya no se usa aquí porque el backend decide el monto por type.
const int _kVerifyAmountCents = 1000;

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    this.auth,
    this.firestore,
    this.storage,
    this.subscriptionService,
  });

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final FirebaseStorage? storage;
  final SubscriptionService? subscriptionService;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final FirebaseAuth _auth;
  late final FirebaseFirestore _db;
  late final FirebaseStorage _storage;
  late final SubscriptionService _subscriptionService;

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
  List<FavVideo> _favVideos = [];

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
    _auth = widget.auth ?? FirebaseAuth.instance;
    _db = widget.firestore ?? FirebaseFirestore.instance;
    _storage = widget.storage ?? FirebaseStorage.instance;
    _subscriptionService =
        widget.subscriptionService ?? SubscriptionService(firestore: _db);
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

  // ------------------- Helpers StoredPaymentMethod (sin copyWith) -------------------

  StoredPaymentMethod _setDefaultFlag(StoredPaymentMethod m, bool isDefault) {
    return StoredPaymentMethod(
      id: m.id,
      label: m.label,
      brand: m.brand,
      last4: m.last4,
      isDefault: isDefault,
      createdAt: m.createdAt,
    );
  }

  List<StoredPaymentMethod> _sortMethods(List<StoredPaymentMethod> methods) {
    final copy = List<StoredPaymentMethod>.from(methods);
    copy.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad); // más nuevas arriba (después de la principal)
    });
    return copy;
  }

  // ------------------- PaymentMethods: encode/decode -------------------

  List<StoredPaymentMethod> _decodePaymentMethods(dynamic raw) {
    if (raw is! List) return <StoredPaymentMethod>[];

    final out = <StoredPaymentMethod>[];
    for (final item in raw) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final created = m['createdAt'];
        DateTime? createdAt;
        if (created is Timestamp) createdAt = created.toDate();
        if (created is int) {
          createdAt = DateTime.fromMillisecondsSinceEpoch(created);
        }
        out.add(
          StoredPaymentMethod(
            id: (m['id'] ?? '').toString(),
            label: (m['label'] ?? '').toString(),
            brand: (m['brand'] ?? '').toString(),
            last4: (m['last4'] ?? '----').toString(),
            isDefault: (m['isDefault'] == true),
            createdAt: createdAt,
          ),
        );
      }
    }

    // normaliza principal
    if (out.isNotEmpty && out.every((e) => e.isDefault == false)) {
      out[0] = _setDefaultFlag(out[0], true);
    }
    return _sortMethods(out);
  }

  List<Map<String, dynamic>> _encodePaymentMethods(
      List<StoredPaymentMethod> methods) {
    return methods.map((m) {
      return <String, dynamic>{
        'id': m.id,
        'label': m.label,
        'brand': m.brand,
        'last4': m.last4,
        'isDefault': m.isDefault,
        if (m.createdAt != null) 'createdAt': Timestamp.fromDate(m.createdAt!),
      };
    }).toList();
  }

  StoredPaymentMethod? _primaryMethod(List<StoredPaymentMethod> methods) {
    if (methods.isEmpty) return null;
    return methods.firstWhere((m) => m.isDefault, orElse: () => methods.first);
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
      final data = snap.data() ?? <String, dynamic>{};

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

      // ✅ YA NO existe status.cancellationEffectiveDate en el service nuevo
      // usamos: cancelsAt -> endDate -> graceEndsAt
      _cancelsAt = status.cancelsAt ?? status.endDate ?? status.graceEndsAt;

      // paymentMethod y lista de métodos
      final subData = (data['subscription'] is Map)
          ? Map<String, dynamic>.from(data['subscription'] as Map)
          : <String, dynamic>{};

      // 1) intenta traer desde SubscriptionStatus
      var methods = status.paymentMethods;

      // 2) si viene vacío, trae desde Firestore: subscription.paymentMethods
      if (methods.isEmpty) {
        methods = _decodePaymentMethods(subData['paymentMethods']);
      } else {
        methods = _sortMethods(methods);
      }

      // 3) paymentMethod legacy (sin primaryPaymentMethod)
      final legacyPaymentMethod = (status.paymentMethod ??
              _primaryMethod(status.paymentMethods)?.label ??
              subData['paymentMethod'])
          ?.toString();

      _paymentMethod = legacyPaymentMethod;

      // 4) si aún no hay lista pero hay legacy, crea uno virtual
      if (methods.isEmpty &&
          legacyPaymentMethod != null &&
          legacyPaymentMethod.trim().isNotEmpty) {
        methods = [
          StoredPaymentMethod(
            id: 'pm_initial',
            label: legacyPaymentMethod,
            brand: legacyPaymentMethod,
            last4: '----',
            isDefault: true,
            createdAt: _startDate ?? DateTime.now().toUtc(),
          ),
        ];
      }

      // normaliza principal y asigna
      if (methods.isNotEmpty && methods.every((m) => m.isDefault == false)) {
        methods[0] = _setDefaultFlag(methods[0], true);
      }

      methods = _sortMethods(methods);
      _paymentMethods = methods;

      // asegura paymentMethod UI = label del principal si existe
      final primary = _primaryMethod(_paymentMethods);
      if (primary != null) _paymentMethod = primary.label;

      await _loadFavorites();
    } catch (_) {
      // silencioso
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
      final List<FavVideo> vids = [];
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
          vids.add(FavVideo(
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
                  content: Text('No se pudo actualizar el correo: ${e.code}'),
                ),
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

      // ✅ FIX: NO tocar subscription aquí (evita borrar fechas o métodos).
      await _db.collection('users').doc(user.uid).set({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': newEmail.isNotEmpty ? newEmail : (user.email ?? ''),
        'city': _cityCtrl.text.trim(),
        'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
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

  InputDecoration _dialogFieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: CapColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: CapColors.surfaceAlt,
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
        borderSide: const BorderSide(color: CapColors.gold),
      ),
      counterText: '',
    );
  }

  Future<void> _addPaymentMethod() async {
    if (_updatingPaymentMethods) return;

    final aliasCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Nuevo método de pago',
          style: TextStyle(color: CapColors.text, fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: aliasCtrl,
                style: const TextStyle(color: CapColors.text),
                decoration: _dialogFieldDeco('Alias (opcional)'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Se abrirá Stripe PaymentSheet para validar la tarjeta con un cargo de 10 MXN.',
                style: TextStyle(color: CapColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: CapColors.text,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CapColors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (ok != true) {
      aliasCtrl.dispose();
      return;
    }

    setState(() => _updatingPaymentMethods = true);
    try {
      final alias = aliasCtrl.text.trim();

      final verified = await _verifyPaymentMethod();
      if (!verified) return;

      final label = alias.isNotEmpty ? alias : 'Tarjeta verificada';

      final newMethod = StoredPaymentMethod(
        id: 'pm_${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        brand: 'tarjeta',
        last4: '----',
        isDefault: _paymentMethods.isEmpty,
        createdAt: DateTime.now().toUtc(),
      );

      await _savePaymentMethods([..._paymentMethods, newMethod]);
    } finally {
      aliasCtrl.dispose();
      if (mounted) setState(() => _updatingPaymentMethods = false);
    }
  }

  /// ✅ Cambiar tarjeta principal (SIN cobro)
  Future<void> _setPrimaryMethod(StoredPaymentMethod method) async {
    if (method.isDefault) return;

    final updated = _paymentMethods
        .map((m) => _setDefaultFlag(m, m.id == method.id))
        .toList();

    await _savePaymentMethods(updated);
  }

  Future<void> _removePaymentMethod(StoredPaymentMethod method) async {
    final updated =
        _paymentMethods.where((m) => m.id != method.id).toList(growable: true);
    if (updated.isNotEmpty && updated.every((m) => m.isDefault == false)) {
      updated[0] = _setDefaultFlag(updated[0], true);
    }
    await _savePaymentMethods(updated);
  }

  /// ✅ Persistir paymentMethods en Firestore (merge)
  Future<void> _savePaymentMethods(List<StoredPaymentMethod> methods) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => _updatingPaymentMethods = true);
    try {
      // normaliza principal
      if (methods.isNotEmpty && methods.every((m) => m.isDefault == false)) {
        methods[0] = _setDefaultFlag(methods[0], true);
      }

      methods = _sortMethods(methods);

      final primary = _primaryMethod(methods);
      final primaryLabel = primary?.label;

      await _db.collection('users').doc(uid).set({
        'subscription': {
          'paymentMethods': _encodePaymentMethods(methods),
          'paymentMethod': primaryLabel,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // (Opcional) también por service
      try {
        await _subscriptionService.updateSubscription(
          uid,
          paymentMethods: methods,
          paymentMethod: primaryLabel,
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        _paymentMethod = primaryLabel;
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
  Future<bool> _verifyPaymentMethod() async {
    if (kIsWeb) return false;
    if (SubscriptionConfig.stripePublishableKey.isEmpty) return false;

    final paymentUrl = SubscriptionConfig.stripePaymentIntentUrl;
    if (paymentUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Configura STRIPE_PAYMENT_INTENT_URL para verificar.'),
          ),
        );
      }
      return false;
    }

    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final email = user.email ?? '${user.uid}@capfiscal.local';
      final idToken = await user.getIdToken(true);

      final resp = await http.post(
        Uri.parse(paymentUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'type': 'payment_method_verification',
          'currency': 'mxn',
          'email': email,
          'uid': user.uid,
          'description': 'Verificación de método de pago CAPFISCAL',
          'metadata': {'uid': user.uid, 'type': 'payment_method_verification'},
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception('Stripe init falló: ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception('Stripe init falló: ${data['error']}');
      }

      final clientSecret = data['paymentIntent'] as String?;
      final customerId = data['customer'] as String?;
      final ephemeralKey = data['ephemeralKey'] as String?;

      if (clientSecret == null || customerId == null || ephemeralKey == null) {
        throw Exception('Respuesta incompleta del servidor (Stripe keys).');
      }

      await stripe.Stripe.instance.initPaymentSheet(
        paymentSheetParameters: stripe.SetupPaymentSheetParameters(
          merchantDisplayName: SubscriptionConfig.merchantDisplayName,
          paymentIntentClientSecret: clientSecret,
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKey,
          allowsDelayedPaymentMethods: true,
        ),
      );

      await stripe.Stripe.instance.presentPaymentSheet();

      await _db.collection('users').doc(user.uid).set({
        'subscription': {
          'lastPaymentVerificationAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tarjeta verificada. Se realizó un cargo de validación de \$10 MXN.',
          ),
        ),
      );
      return true;
    } on stripe.StripeException catch (e) {
      if (!mounted) return false;
      final msg = e.error.localizedMessage ?? e.error.message ?? e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operación cancelada o fallida: $msg')),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos verificar el método de pago: $e')),
      );
      return false;
    }
  }

  // ------- Cancelación manual vía correo -------

  Future<void> _sendCancellationEmail() async {
    final user = _auth.currentUser;
    final email = (user?.email ?? _emailCtrl.text.trim()).trim();
    final uid = user?.uid ?? '';
    final now = DateTime.now().toLocal();

    final bodyText = ''
        'Hola equipo CAPFISCAL,\n\n'
        'Quiero solicitar la cancelación de mi suscripción a la Biblioteca CAPFISCAL.\n\n'
        'Datos de la cuenta:\n'
        '- Correo: ${email.isEmpty ? 'N/A' : email}\n'
        '- UID: ${uid.isEmpty ? 'N/A' : uid}\n'
        '- Fecha de solicitud: ${now.toIso8601String()}\n\n'
        'Gracias.\n';

    final uri = Uri(
      scheme: 'mailto',
      path: 'petmega.redes@gmail.com',
      queryParameters: {
        'subject': 'Solicitud de cancelación de suscripción CAPFISCAL',
        'body': bodyText,
      },
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      if (!launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir la app de correo. Verifica que tengas una configurada.',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se abrió tu app de correo. Envía el mensaje para completar la solicitud.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir correo: $e')),
      );
    }
  }

  Future<void> _confirmManualCancellation() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Solicitar cancelación',
          style: TextStyle(color: CapColors.text, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Si solicitas la cancelación de tu suscripción, perderás todos los '
          'beneficios y el acceso a los documentos una vez que el equipo de '
          'CAPFISCAL procese tu solicitud.\n\n'
          'La cancelación se realiza de forma manual en un plazo máximo de 3 días. '
          'Al continuar, prepararemos un correo con tus datos para completar el proceso.',
          style: TextStyle(color: CapColors.textMuted),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: CapColors.text,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Seguir con mi suscripción'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CapColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _sendCancellationEmail();
    }
  }

  Future<void> _openManageSubscription() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Administra tu suscripción desde la tienda de tu móvil.'),
        ),
      );
      return;
    }

    final url = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => SubscriptionConfig.iosManageSubscriptionUrl,
      TargetPlatform.android =>
        SubscriptionConfig.playStoreManageSubscriptionUrl,
      _ => '',
    };

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Configura ANDROID_PACKAGE_NAME para abrir Play Store.'),
        ),
      );
      return;
    }

    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la gestión de pagos.')),
      );
    }
  }

  Future<void> _restoreSubscription() async {
    await _loadProfile();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Estado de suscripción actualizado.')),
    );
  }

  // --------- Acciones de cuenta ---------

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
        backgroundColor: CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Cerrar sesión',
          style: TextStyle(color: CapColors.text, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '¿Seguro que deseas cerrar tu sesión?',
          style: TextStyle(color: CapColors.textMuted),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: CapColors.text,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: CapColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
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

  String _methodSubtitle(StoredPaymentMethod m) {
    final parts = <String>[];
    final b = m.brand.trim();
    if (b.isNotEmpty) parts.add(b);
    final l4 = m.last4.trim();
    if (l4.isNotEmpty && l4 != '----') parts.add('•••• $l4');
    return parts.isEmpty ? 'Método guardado' : parts.join(' · ');
  }

  Widget _paymentMethodTile(StoredPaymentMethod method) {
    final isPrimary = method.isDefault;

    final borderColor = isPrimary ? CapColors.gold : Colors.white12;
    final bg = isPrimary ? CapColors.surface : CapColors.surfaceAlt;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Icon(
              isPrimary ? Icons.verified : Icons.credit_card,
              color: isPrimary ? CapColors.gold : CapColors.text,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method.label.trim().isEmpty ? 'Tarjeta' : method.label.trim(),
                  style: const TextStyle(
                    color: CapColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _methodSubtitle(method),
                  style: const TextStyle(
                    color: CapColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ✅ Un solo botón: o “PRINCIPAL” (disabled) o “Hacer principal”
          if (isPrimary)
            ElevatedButton.icon(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: CapColors.gold,
                foregroundColor: Colors.black,
                disabledBackgroundColor: CapColors.gold,
                disabledForegroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: const Text(
                'PRINCIPAL',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            )
          else
            OutlinedButton(
              onPressed: _updatingPaymentMethods
                  ? null
                  : () async {
                      await _setPrimaryMethod(method);
                    },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: CapColors.goldDark),
                foregroundColor: CapColors.gold,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _updatingPaymentMethods
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(CapColors.gold),
                      ),
                    )
                  : const Text(
                      'Hacer principal',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
            ),

          const SizedBox(width: 8),

          // Eliminar (icono)
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _updatingPaymentMethods
                ? null
                : () async {
                    // Si solo hay 1, evita dejarlo vacío (opcional)
                    if (_paymentMethods.length <= 1) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Debes conservar al menos un método de pago.'),
                        ),
                      );
                      return;
                    }
                    await _removePaymentMethod(method);
                  },
            icon: const Icon(Icons.delete_outline, color: CapColors.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = _auth.currentUser?.emailVerified ?? false;
    final w = MediaQuery.of(context).size.width;
    final avatarSize = (w * 0.60).clamp(160.0, 300.0);

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
                  valueColor: AlwaysStoppedAnimation<Color>(CapColors.gold),
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
                                  child: const Icon(
                                    Icons.arrow_back,
                                    size: 18,
                                    color: CapColors.text,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Regresar',
                                  style: TextStyle(
                                    color: CapColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
                                color: CapColors.gold,
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
                            'Tu correo no está verificado. Verifica para mejorar la seguridad de tu cuenta.',
                          ),
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
                                  colors: [CapColors.gold, CapColors.goldDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            ClipOval(
                              child: Container(
                                width: avatarSize * 0.86,
                                height: avatarSize * 0.86,
                                color: CapColors.surfaceAlt,
                                child: _photoUrl == null
                                    ? const Center(
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.black,
                                          size: 80,
                                        ),
                                      )
                                    : Image.network(
                                        _photoUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.black,
                                            size: 80,
                                          ),
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
                    ProfileField(
                      icon: Icons.person,
                      label: 'Nombre',
                      controller: _nameCtrl,
                      enabled: _editing,
                    ),
                    ProfileField(
                      icon: Icons.mail,
                      label: 'E-mail',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      enabled: _editing,
                    ),
                    ProfileField(
                      icon: Icons.phone,
                      label: 'Teléfono',
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      enabled: _editing,
                    ),
                    ProfileField(
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
                                    color: CapColors.goldDark,
                                  ),
                                  foregroundColor: CapColors.gold,
                                  backgroundColor: CapColors.surface,
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
                                  foregroundColor: CapColors.text,
                                  side: const BorderSide(color: Colors.white24),
                                ),
                                onPressed: () {
                                  setState(() => _editing = false);
                                  _loadProfile();
                                },
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CapColors.gold,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: _saving ? null : _saveProfile,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
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
                                  color: CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    SubscriptionRow(
                      label: 'MIEMBRO DESDE',
                      value: _fmtDate(_createdAt),
                    ),
                    SubscriptionRow(
                      label: 'FECHA DE INICIO',
                      value: _fmtDate(_startDate),
                    ),
                    SubscriptionRow(
                      label: 'FECHA DE TÉRMINO',
                      value: _fmtDate(_endDate),
                    ),
                    SubscriptionRow(
                      label: 'MÉTODO DE PAGO',
                      value: _paymentMethod ??
                          (_primaryMethod(_paymentMethods)?.label ?? '--'),
                    ),

                    if (_subscriptionState != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
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
                                  isActive ? Colors.black : CapColors.text;
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
                          horizontal: 16,
                          vertical: 4,
                        ),
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
                            style: const TextStyle(color: CapColors.text),
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
                                backgroundColor: CapColors.gold,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: CapColors.goldDark),
                                foregroundColor: CapColors.gold,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _openManageSubscription,
                              child: const Text(
                                'Administrar suscripción',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: CapColors.goldDark),
                                foregroundColor: CapColors.gold,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _restoreSubscription,
                              child: const Text(
                                'Restaurar compra',
                                style: TextStyle(fontWeight: FontWeight.w700),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ===== Métodos de pago =====
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
                                  color: CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Agregar',
                            onPressed: _updatingPaymentMethods
                                ? null
                                : _addPaymentMethod,
                            icon: const Icon(Icons.add, color: CapColors.text),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _paymentMethods.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.only(top: 6, bottom: 6),
                              child: Text(
                                'Aún no guardas métodos de pago alternos.',
                                style: TextStyle(color: CapColors.textMuted),
                              ),
                            )
                          : Column(
                              children: _paymentMethods
                                  .map((m) => _paymentMethodTile(m))
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
                                  color: CapColors.gold,
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
                                AlwaysStoppedAnimation<Color>(CapColors.gold),
                          ),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: FavCard(
                          title: 'Documentos',
                          child: _favDocs.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'No tienes documentos favoritos',
                                    style:
                                        TextStyle(color: CapColors.textMuted),
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
                                        child: DocTile(
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: FavCard(
                          title: 'Videos',
                          child: _favVideos.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'No tienes videos favoritos',
                                    style:
                                        TextStyle(color: CapColors.textMuted),
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
                                          8,
                                          8,
                                          8,
                                          12,
                                        ),
                                        itemCount: _favVideos.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 10),
                                        itemBuilder: (ctx, i) {
                                          final v = _favVideos[i];
                                          return SizedBox(
                                            width: cardWidth,
                                            child: VideoTile(
                                              title: v.title,
                                              youtubeId: v.youtubeId,
                                              description: v.description,
                                              onTap: () {
                                                Navigator.pushReplacementNamed(
                                                  context,
                                                  '/video',
                                                );
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
        bottomNavigationBar: const CapfiscalBottomNav(currentIndex: 4),
      ),
    );
  }
}
