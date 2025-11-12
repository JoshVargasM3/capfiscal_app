// lib/screens/user_profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';
import '../helpers/subscription_guard.dart';

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

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  bool _signingOut = false;

  // Favoritos
  bool _loadingFavs = true;
  List<Reference> _favDocs = [];
  List<_FavVideo> _favVideos = [];

  String? _photoUrl;

  // Suscripción (solo lectura por ahora)
  DateTime? _startDate;
  DateTime? _endDate;
  String? _paymentMethod;

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

      _nameCtrl.text = (data['name'] ?? '').toString();
      _phoneCtrl.text = (data['phone'] ?? '').toString();
      _emailCtrl.text = (data['email'] ?? user.email ?? '').toString();
      _cityCtrl.text = (data['city'] ?? '').toString();
      _photoUrl = data['photoUrl'] as String?;

      final sub = data['subscription'] as Map<String, dynamic>?;
      if (sub != null) {
        final start = sub['startDate'];
        final end = sub['endDate'];
        _paymentMethod = sub['paymentMethod']?.toString();
        if (start is Timestamp) _startDate = start.toDate();
        if (end is Timestamp) _endDate = end.toDate();
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
          // Cancelar (outline tenue, estilo app)
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
          // Cerrar sesión (dorado, estilo app)
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
                    // Back + cerrar sesión (oscuro)
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
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side:
                                  const BorderSide(color: _CapColors.goldDark),
                              foregroundColor: _CapColors.gold,
                              backgroundColor: _CapColors.surface,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            onPressed: _signingOut ? null : _confirmSignOut,
                            icon: _signingOut
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Cerrar sesión'),
                          ),
                        ],
                      ),
                    ),

                    // Título dorado centrado
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

                    // Avatar gigante (~60% ancho) con botón de edición
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Círculo dorado de fondo
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
                            // Foto (si hay), recortada
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
                            // Botón blanco de editar (abajo-derecha)
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

                    // ==== Campos de perfil (labels blancos + campos gris claro) ====
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

                    // Botones Editar / Guardar
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
                        label: 'FECHA DE INICIO', value: _fmtDate(_startDate)),
                    _SubscriptionRow(
                        label: 'FECHA DE TÉRMINO', value: _fmtDate(_endDate)),
                    _SubscriptionRow(
                        label: 'MÉTODO DE PAGO', value: _paymentMethod ?? '--'),

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

        // ✅ Bottom nav — Perfil = índice 4 (iluminado)
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

// ---- Tarjetas y tiles de Favoritos (tema oscuro + dorado) ----

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
