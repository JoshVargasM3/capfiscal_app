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

      // Carga favoritos en paralelo
      await _loadFavorites();
    } catch (_) {
      // opcional: log
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final favNames =
          await FavoritesManager.getFavorites(); // Set<String> o List<String>
      final favSet = favNames.toSet();

      // --- Documentos favoritos (Storage raíz) ---
      final root = await _storage.ref('/').listAll();
      final docs =
          root.items.where((ref) => favSet.contains(ref.name)).toList();

      // --- Videos favoritos (Firestore 'videos') ---
      final vSnap = await _db.collection('videos').get();
      final List<_FavVideo> vids = [];
      for (final d in vSnap.docs) {
        final data = d.data();
        final raw = (data['youtubeId'] ?? '').toString().trim();
        final title = (data['title'] ?? '').toString().trim();
        final desc = (data['description'] ?? '').toString().trim();
        final id = _normalizeYouTubeId(raw);

        // Coincidimos por tres posibles llaves: title, youtubeId (id) o docId
        if (favSet.contains(title) ||
            favSet.contains(id) ||
            favSet.contains(d.id)) {
          if (id.length == 11) {
            vids.add(_FavVideo(
              docId: d.id,
              youtubeId: id,
              title: title.isEmpty ? 'Video' : title,
              description: desc,
            ));
          }
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

  // Descarga y abre archivo
  Future<void> _downloadAndOpenFile(Reference ref) async {
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

  // Diálogo para pedir contraseña y reautenticar al cambiar email
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
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar')),
        ],
      ),
    );
    if (ok != true) return false;

    try {
      final user = _auth.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: email, password: passCtrl.text.trim());
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
      // 1) Cambio de correo
      final currentEmail = user.email ?? '';
      final newEmail = _emailCtrl.text.trim();
      if (newEmail.isNotEmpty && newEmail != currentEmail) {
        try {
          await user.updateEmail(newEmail);
          await _reloadAuthUser();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            final ok = await _reauthWithPassword(
                currentEmail.isNotEmpty ? currentEmail : newEmail);
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

      // 2) Actualiza displayName y photoURL
      await user.updateDisplayName(_nameCtrl.text.trim());
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        await user.updatePhotoURL(_photoUrl);
      }

      // 3) Guarda en Firestore
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

      // Actualiza Firestore + Auth
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
    } catch (_) {
      // si no existía, ignoramos
    }
    await _db.collection('users').doc(user.uid).set(
      {'photoUrl': null, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await user.updatePhotoURL(null);

    if (mounted) setState(() => _photoUrl = null);
  }

  // --------- Acciones de cuenta ---------

  // ignore: unused_element
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
        SnackBar(
            content: Text(
                'Te enviamos un correo para restablecer la contraseña a $email')),
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

  // ignore: unused_element
  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // ------------------- UI -------------------

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

  // Normaliza ID de YouTube desde url/shorts/watch/embed
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

  @override
  Widget build(BuildContext context) {
    final isVerified = _auth.currentUser?.emailVerified ?? false;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const CustomDrawer(),

      appBar: CapfiscalTopBar(
        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
        onRefresh: () async {
          await _reloadAuthUser();
          await _loadProfile();
        },
        onProfile: () {}, // ya estamos aquí
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Regresar
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_back, size: 18),
                        const SizedBox(width: 6),
                        TextButton(
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0)),
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Regresar',
                              style: TextStyle(color: Colors.black87)),
                        ),
                      ],
                    ),
                  ),

                  // Título
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Text(
                      'MI PERFIL',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: .5,
                                color: const Color(0xFF6B1A1A),
                              ),
                      textAlign: TextAlign.left,
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

                  // Avatar + botón EDITAR
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 46,
                            backgroundColor: Colors.black12,
                            backgroundImage: _photoUrl != null
                                ? NetworkImage(_photoUrl!)
                                : null,
                            child: _photoUrl == null
                                ? const Icon(Icons.person,
                                    size: 46, color: Colors.black45)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTapDown: (d) => _showAvatarMenu(d.globalPosition),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.edit,
                                    size: 16, color: Color(0xFF6B1A1A)),
                                SizedBox(width: 4),
                                Text(
                                  'EDITAR',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Campos de perfil
                  const SizedBox(height: 6),
                  _ProfileField(
                    icon: Icons.person,
                    label: 'NOMBRE',
                    controller: _nameCtrl,
                    enabled: _editing,
                  ),
                  _ProfileField(
                    icon: Icons.phone,
                    label: 'TELEFONO',
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    enabled: _editing,
                  ),
                  _ProfileField(
                    icon: Icons.mail,
                    label: 'CORREO',
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    enabled: _editing,
                  ),
                  _ProfileField(
                    icon: Icons.location_city,
                    label: 'CIUDAD',
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
                              onPressed: () => setState(() => _editing = true),
                              icon: const Icon(Icons.edit),
                              label: const Text('Editar'),
                            ),
                          ),
                        if (_editing) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() {
                                _editing = false;
                                _loadProfile(); // descartar cambios
                              }),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B1A1A)),
                              onPressed: _saving ? null : _saveProfile,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Sección de suscripción
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'DATOS DE LA SUSCRIPCIÓN',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF6B1A1A),
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

                  // ================== MIS FAVORITOS ==================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'MIS FAVORITOS',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF6B1A1A),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),

                  if (_loadingFavs)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    // ---- Documentos favoritos ----
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _FavCard(
                        title: 'Documentos',
                        child: _favDocs.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No tienes documentos favoritos'),
                              )
                            : GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: .95,
                                ),
                                itemCount: _favDocs.length,
                                itemBuilder: (ctx, i) {
                                  final ref = _favDocs[i];
                                  return _DocTile(
                                    name: ref.name,
                                    onTap: () => _downloadAndOpenFile(ref),
                                  );
                                },
                              ),
                      ),
                    ),

                    // ---- Videos favoritos ----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _FavCard(
                        title: 'Videos',
                        child: _favVideos.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No tienes videos favoritos'),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                                itemCount: _favVideos.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (ctx, i) {
                                  final v = _favVideos[i];
                                  return _VideoTile(
                                    title: v.title,
                                    youtubeId: v.youtubeId,
                                    description: v.description,
                                    // Por ahora, solo mostramos. Si quieres que abra VideoScreen con ese ID,
                                    // podemos agregar navegación con argumentos.
                                    onTap: () {
                                      // Navega a la pantalla de videos
                                      Navigator.pushReplacementNamed(
                                          context, '/video');
                                    },
                                  );
                                },
                              ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                ],
              ),
            ),

      // Bottom nav — usa navegación por defecto: ['/biblioteca','/video','/home','/chat']
      bottomNavigationBar: const CapfiscalBottomNav(
        currentIndex: 3, // Perfil
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
          Icon(icon, color: const Color(0xFF6B1A1A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: const Color(0xFFE7E7E7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
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
                  color: Colors.black54,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 56,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE7E7E7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(value, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
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
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Color(0xFF6B1A1A),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, size: 40, color: Color(0xFF6B1A1A)),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 2,
              offset: Offset(0, 1),
            )
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Image.network(
                _thumb,
                width: 92,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Video' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7E7E7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        description.isEmpty ? 'Descripción' : description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87),
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
