// lib/screens/user_profile_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../helpers/favorites_manager.dart';
import '../models/fav_video.dart';
import '../services/doc_iap_service.dart';
import '../theme/cap_colors.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/favorites/doc_tile.dart';
import '../widgets/favorites/fav_card.dart';
import '../widgets/favorites/video_tile.dart';
import '../widgets/profile/profile_field.dart';

class FavBundle {
  final String docId;
  final String title;
  final String description;
  final int filesCount;

  FavBundle({
    required this.docId,
    required this.title,
    required this.description,
    required this.filesCount,
  });
}

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    this.auth,
    this.firestore,
    this.storage,
  });

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final FirebaseStorage? storage;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final FirebaseAuth _auth;
  late final FirebaseFirestore _db;
  late final FirebaseStorage _storage;

  late final DocIapService _iap;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  bool _signingOut = false;
  bool _deletingAccount = false;

  Future<List<Reference>> _listAllRecursive(Reference root) async {
    final out = <Reference>[];
    final res = await root.listAll();

    out.addAll(res.items);

    for (final sub in res.prefixes) {
      out.addAll(await _listAllRecursive(sub));
    }
    return out;
  }

  // Favoritos
  bool _loadingFavs = true;
  List<Reference> _favDocs = [];
  List<FavVideo> _favVideos = [];
  List<FavBundle> _favBundles = [];

  // Foto perfil
  String? _photoUrlRaw;
  String? _photoUrl;

  // Compras por documento (entitlements)
  bool _restoring = false;
  Set<String> _purchasedProductIds = <String>{};
  final Map<String, String> _bundleProductIdByStoragePath = <String, String>{};

  // Meta
  DateTime? _createdAt;

  static const String _docsFolder = 'docs';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _auth = widget.auth ?? FirebaseAuth.instance;
    _db = widget.firestore ?? FirebaseFirestore.instance;
    _storage = widget.storage ?? FirebaseStorage.instance;

    _iap = DocIapService(auth: _auth, firestore: _db);

    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_) {},
    );

    FavoritesManager.changes.addListener(_handleFavoritesChanged);

    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FavoritesManager.changes.removeListener(_handleFavoritesChanged);
    _purchaseSub?.cancel();

    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final u = _auth.currentUser;
      if (u != null) {
        unawaited(u.reload().then((_) {
          if (!mounted) return;
          _handleFavoritesChanged();
          setState(() {});
        }));
      }
    }
  }

  void _handleFavoritesChanged() {
    if (!mounted || _loadingFavs) return;
    unawaited(_loadFavorites());
  }

  // ─────────────────────────────
  // Helpers: docKey/productId
  // ─────────────────────────────
  String _docKeyFromFilename(String name) {
    var base = name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);

    base = base.toLowerCase().trim();
    base = base.replaceAll(RegExp(r'\s+'), '_');
    base = base.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
    return base;
  }

  String _productIdForRef(Reference ref) {
    final key = _docKeyFromFilename(ref.name);
    return 'capfiscal_doc_$key';
  }

  String _bundleProductIdForDocId(String docId) => 'capfiscal_bundle_$docId';

  String? _bundleProductIdForRef(Reference ref) {
    final fullPath = ref.fullPath.trim();
    if (fullPath.isNotEmpty) {
      final pid = _bundleProductIdByStoragePath[fullPath];
      if (pid != null && pid.isNotEmpty) return pid;
    }

    final docsPath = '$_docsFolder/${ref.name}'.trim();
    final byDocsPath = _bundleProductIdByStoragePath[docsPath];
    if (byDocsPath != null && byDocsPath.isNotEmpty) return byDocsPath;

    return null;
  }

  bool _isPurchased(Reference ref) {
    final legacyPid = _productIdForRef(ref);
    if (_purchasedProductIds.contains(legacyPid)) return true;

    final bundlePid = _bundleProductIdForRef(ref);
    if (bundlePid != null && _purchasedProductIds.contains(bundlePid)) {
      return true;
    }

    return false;
  }

  // ─────────────────────────────
  // Purchases stream
  // ─────────────────────────────
  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        try {
          await _iap.grantEntitlement(p);
          _purchasedProductIds.add(p.productID);
        } catch (_) {}
      }

      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadPurchasedDocs() async {
    final ids = await _iap.loadPurchasedProductIds();
    if (!mounted) return;
    setState(() => _purchasedProductIds = ids);
  }

  Future<void> _restorePurchases() async {
    if (_restoring) return;
    setState(() => _restoring = true);

    try {
      await _iap.restorePurchases();
      await _loadPurchasedDocs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compras restauradas ✅')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo restaurar: $e')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  // ─────────────────────────────
  // FOTO PERFIL
  // ─────────────────────────────
  String _cacheBustUrl(String url) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final uri = Uri.parse(url);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['v'] = ts;
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      return url.contains('?') ? '$url&v=$ts' : '$url?v=$ts';
    }
  }

  Future<String?> _getProfilePhotoUrlRawFromStorage(String uid) async {
    try {
      final ref = _storage.ref('users/$uid/profile.jpg');
      final url = await ref.getDownloadURL();
      return url;
    } catch (_) {
      return null;
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

      await ref.putFile(
        file,
        SettableMetadata(
          contentType: 'image/jpeg',
          cacheControl: 'no-cache, no-store, must-revalidate',
        ),
      );

      final raw = await _getProfilePhotoUrlRawFromStorage(user.uid);
      if (raw == null || raw.isEmpty) {
        throw Exception('No se pudo obtener downloadURL de la foto.');
      }

      setState(() {
        _photoUrlRaw = raw;
        _photoUrl = _cacheBustUrl(raw);
      });

      await _db.collection('users').doc(user.uid).set(
        {'photoUrl': _photoUrlRaw, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

      await user.updatePhotoURL(_photoUrlRaw);

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

    if (mounted) {
      setState(() {
        _photoUrlRaw = null;
        _photoUrl = null;
      });
    }
  }

  // ─────────────────────────────
  // DATA
  // ─────────────────────────────
  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _loadingFavs = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingFavs = false;
          });
        }
        return;
      }

      final snap = await _db.collection('users').doc(user.uid).get();
      final data = snap.data() ?? <String, dynamic>{};

      final createdTs = data['createdAt'];
      if (createdTs is Timestamp) {
        _createdAt = createdTs.toDate();
      } else {
        _createdAt = null;
      }

      _nameCtrl.text =
          (data['name'] ?? user.displayName ?? '').toString().trim();
      _phoneCtrl.text = (data['phone'] ?? '').toString().trim();
      _emailCtrl.text = (data['email'] ?? user.email ?? '').toString().trim();
      _cityCtrl.text = (data['city'] ?? '').toString().trim();

      _photoUrlRaw = (data['photoUrl'] as String?)?.trim();
      _photoUrl = (_photoUrlRaw == null || _photoUrlRaw!.isEmpty)
          ? null
          : _cacheBustUrl(_photoUrlRaw!);

      final storageRaw = await _getProfilePhotoUrlRawFromStorage(user.uid);
      if (storageRaw != null && storageRaw.trim().isNotEmpty) {
        _photoUrlRaw = storageRaw.trim();
        _photoUrl = _cacheBustUrl(_photoUrlRaw!);

        final firestoreRaw = (data['photoUrl'] as String?)?.trim();
        if (firestoreRaw != _photoUrlRaw) {
          await _db.collection('users').doc(user.uid).set(
            {
              'photoUrl': _photoUrlRaw,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      await _loadPurchasedDocs();
      await _loadFavorites();
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────
  // FAVORITOS
  // ─────────────────────────────
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

  bool _isFavDocRef(Set<String> favSet, Reference ref) {
    final name = ref.name.trim();
    final fullPath = ref.fullPath.trim();
    final baseFromPath =
        fullPath.contains('/') ? fullPath.split('/').last.trim() : fullPath;

    final keyByName = _docKeyFromFilename(name);
    final keyByPath = _docKeyFromFilename(baseFromPath);

    final candidates = <String>{
      name,
      baseFromPath,
      fullPath,
      keyByName,
      keyByPath,
      'doc:$name',
      'doc:$baseFromPath',
      'doc:$fullPath',
      'doc:$keyByName',
      'doc:$keyByPath',
      'document:$name',
      'document:$keyByName',
      'document:$keyByPath',
    };

    for (final c in candidates) {
      if (c.isNotEmpty && favSet.contains(c)) return true;
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

      final raw = await FavoritesManager.getFavorites(uid);
      final favSet = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();

      final docFavoriteKeys = favSet.where((e) => e.startsWith('doc:')).toList()
        ..sort();

      if (kDebugMode) {
        debugPrint('⭐️ Doc favorite keys: $docFavoriteKeys');
      }

      _bundleProductIdByStoragePath.clear();
      final Map<String, Reference> favDocRefsByPath = <String, Reference>{};

      final docsCatalog = await _db
          .collection('documents')
          .where('active', isEqualTo: true)
          .get();
      for (final d in docsCatalog.docs) {
        final data = d.data();
        final rawFiles = (data['files'] is List)
            ? List.from(data['files'] as List)
            : const [];
        final bundlePid = _bundleProductIdForDocId(d.id);

        for (final rawFile in rawFiles.whereType<Map>()) {
          final map = Map<String, dynamic>.from(rawFile);
          final storagePath = (map['storagePath'] ?? '').toString().trim();
          if (storagePath.isEmpty) continue;

          _bundleProductIdByStoragePath[storagePath] = bundlePid;

          final ref = _storage.ref(storagePath);

          if (kDebugMode) {
            debugPrint('📄 documents.files storagePath: ${ref.fullPath}');
          }

          if (_isFavDocRef(favSet, ref)) {
            favDocRefsByPath[ref.fullPath] = ref;

            if (kDebugMode) {
              debugPrint(
                '✅ Matched favorite doc from documents: ${ref.fullPath}',
              );
            }
          }
        }
      }

      final bundleIds = favSet
          .where((k) => k.startsWith('bundle:'))
          .map((k) => k.substring('bundle:'.length).trim())
          .where((id) => id.isNotEmpty)
          .toList();

      final List<FavBundle> bundles = [];

      const chunkSize = 10;
      for (var i = 0; i < bundleIds.length; i += chunkSize) {
        final chunk = bundleIds.sublist(
          i,
          (i + chunkSize > bundleIds.length) ? bundleIds.length : i + chunkSize,
        );

        final snap = await _db
            .collection('documents')
            .where('active', isEqualTo: true)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final d in snap.docs) {
          final data = d.data();
          final title = (data['title'] ?? d.id).toString().trim();
          final desc = (data['description'] ?? '').toString().trim();
          final files =
              (data['files'] is List) ? (data['files'] as List) : const [];

          bundles.add(
            FavBundle(
              docId: d.id,
              title: title.isEmpty ? d.id : title,
              description: desc,
              filesCount: files.length,
            ),
          );
        }
      }

      bundles.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );

      final allDocRefs = await _listAllRecursive(_storage.ref(_docsFolder));
      for (final ref in allDocRefs) {
        if (_isFavDocRef(favSet, ref)) {
          favDocRefsByPath.putIfAbsent(ref.fullPath, () => ref);
        }
      }

      final docs = favDocRefsByPath.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (kDebugMode) {
        debugPrint(
          '🗂️ Final favorite docs in profile: ${docs.map((e) => e.fullPath).toList()}',
        );
      }

      final vSnap = await _db.collection('videos').get();
      final List<FavVideo> vids = [];

      for (final d in vSnap.docs) {
        final data = d.data();
        final rawYt = _extractYoutubeRaw(data);
        final id = _normalizeYouTubeId(rawYt);
        final title = (data['title'] ?? '').toString().trim();
        final desc = (data['description'] ?? '').toString().trim();

        final isFav = _inFav(favSet, id, typePrefix: 'video') ||
            _inFav(favSet, d.id, typePrefix: 'video') ||
            _inFav(favSet, title, typePrefix: 'video') ||
            favSet.contains(d.id) ||
            favSet.contains(title);

        if (isFav && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
          vids.add(
            FavVideo(
              docId: d.id,
              youtubeId: id,
              title: title.isEmpty ? 'Video' : title,
              description: desc,
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _favBundles = bundles;
        _favDocs = docs;
        _favVideos = vids;
        _loadingFavs = false;
      });

      if (kDebugMode) {
        debugPrint('📚 Favorite docs rendered count: ${_favDocs.length}');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFavs = false);
    }
  }

  // ─────────────────────────────
  // Descarga gated por compra
  // ─────────────────────────────
  Future<void> _downloadAndOpenFile(Reference ref) async {
    if (!_isPurchased(ref)) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes comprar este documento para descargarlo'),
        ),
      );

      Navigator.of(context).pushNamed(
        '/biblioteca',
        arguments: {'query': ref.name},
      );
      return;
    }

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

  // ─────────────────────────────
  // Cuenta
  // ─────────────────────────────
  Future<void> _reloadAuthUser() async {
    try {
      await _auth.currentUser?.reload();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await user.sendEmailVerification();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo de verificación enviado')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar verificación: $e')),
      );
    }
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

    if (ok != true) {
      passCtrl.dispose();
      return false;
    }

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
    } finally {
      passCtrl.dispose();
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

      if (_photoUrlRaw != null && _photoUrlRaw!.isNotEmpty) {
        await user.updatePhotoURL(_photoUrlRaw);
      }

      await _db.collection('users').doc(user.uid).set({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': newEmail.isNotEmpty ? newEmail : (user.email ?? ''),
        'city': _cityCtrl.text.trim(),
        'photoUrl': _photoUrlRaw,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
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

    if (ok == true) await _signOut();
  }

  // ─────────────────────────────
  // Eliminación de cuenta para cumplimiento Apple 5.1.1(v)
  // ─────────────────────────────
  Future<bool> _reauthForAccountDeletion(String email) async {
    final passCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Confirmar identidad',
          style: TextStyle(
            color: CapColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Por seguridad, ingresa tu contraseña para eliminar tu cuenta.',
              style: TextStyle(color: CapColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              style: const TextStyle(color: CapColors.text),
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                labelStyle: TextStyle(color: CapColors.textMuted),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CapColors.gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (ok != true) {
      passCtrl.dispose();
      return false;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final password = passCtrl.text.trim();

      if (password.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingresa tu contraseña.')),
          );
        }
        return false;
      }

      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.reauthenticateWithCredential(cred);
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return false;

      String msg = 'No se pudo confirmar tu identidad.';

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'La contraseña no es correcta.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Demasiados intentos. Intenta más tarde.';
      } else if (e.code == 'user-mismatch') {
        msg = 'La cuenta no coincide con el usuario actual.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );

      return false;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al confirmar identidad: $e')),
      );

      return false;
    } finally {
      passCtrl.dispose();
    }
  }

  Future<void> _deleteQueryInBatches(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(450).get();
      if (snap.docs.isEmpty) break;

      final batch = _db.batch();

      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (snap.docs.length < 450) break;
    }
  }

  Future<void> _deleteStorageFolder(String path) async {
    try {
      final refs = await _listAllRecursive(_storage.ref(path));

      for (final ref in refs) {
        try {
          await ref.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  // SOFT DELETE: marca usuario como eliminado sin borrar datos
  // Permite que restaurar compras (IAP nativo) siga funcionando
  // si el usuario crea nueva cuenta con el mismo email
  Future<void> _deleteUserKnownData(String uid) async {
    try {
      await _db.collection('users').doc(uid).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'name': '[Cuenta eliminada]',
        'email': '',
        'phone': '',
        'city': '',
        'photoUrl': null,
      });

      debugPrint('✅ Usuario marcado como eliminado: $uid');

      // Borrar solo la foto de perfil del Storage
      try {
        await _storage.ref('users/$uid/profile.jpg').delete();
      } catch (e) {
        debugPrint('⚠️ Error borrando foto: $e');
      }
    } catch (e) {
      debugPrint('❌ Error en soft delete: $e');
      rethrow;
    }
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final email = user.email ?? _emailCtrl.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Eliminar cuenta permanentemente',
          style: TextStyle(
            color: CapColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Se eliminarán:\n'
          '• Tu perfil visible\n'
          '• Tu foto de perfil\n\n'
          'Se conservarán tus compras para que puedas restaurarlas si creas una nueva cuenta con el mismo email.\n\n'
          'Esta acción NO se puede deshacer.',
          style: TextStyle(color: CapColors.textMuted),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: CapColors.text,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Eliminar cuenta'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingAccount = true);

    try {
      final usesPasswordProvider =
          user.providerData.any((p) => p.providerId == 'password');

      if (usesPasswordProvider && email.isNotEmpty) {
        final reauthOk = await _reauthForAccountDeletion(email);
        if (!reauthOk) {
          if (mounted) setState(() => _deletingAccount = false);
          return;
        }
      }

      // 1️⃣ Soft delete en Firestore (marcar como eliminada)
      try {
        await _deleteUserKnownData(uid);
      } catch (e, st) {
        debugPrint('⚠️ Error marcando usuario como eliminado: $e\n$st');
      }

      // 2️⃣ Borrar usuario de Auth (libera email para nueva cuenta)
      try {
        await _auth.currentUser?.delete();
        debugPrint('✅ Usuario borrado de Auth: $uid');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login' && email.isNotEmpty) {
          final reauthOk = await _reauthForAccountDeletion(email);
          if (!reauthOk) {
            if (mounted) setState(() => _deletingAccount = false);
            return;
          }
          await _auth.currentUser?.delete();
          debugPrint('✅ Usuario borrado de Auth (reauth): $uid');
        } else {
          rethrow;
        }
      }

      // 3️⃣ Sign out
      await _auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu cuenta fue eliminada correctamente.\n\n'
            'Puedes crear una nueva con el mismo email y restaurar tus compras.',
          ),
          duration: Duration(seconds: 4),
        ),
      );

      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/', (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String msg = 'No se pudo eliminar la cuenta.';

      if (e.code == 'requires-recent-login') {
        msg =
            'Por seguridad, vuelve a iniciar sesión e intenta eliminar la cuenta nuevamente.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar cuenta: $e')),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Eliminar cuenta',
          style: TextStyle(
            color: CapColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Esta acción eliminará tu cuenta y los datos asociados a tu perfil. No se puede deshacer.\n\n¿Deseas continuar?',
          style: TextStyle(color: CapColors.textMuted),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: CapColors.text,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Eliminar cuenta'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteAccount();
    }
  }

  // ─────────────────────────────
  // UI helpers
  // ─────────────────────────────
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

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: CapColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: CapColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: const TextStyle(
                color: CapColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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
                          IconButton(
                            onPressed: _signingOut ? null : _confirmSignOut,
                            icon:
                                const Icon(Icons.logout, color: CapColors.text),
                          ),
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
                                        key: ValueKey(_photoUrl),
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
                                  child: const Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Colors.black,
                                  ),
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

                    // ===== Compras (IAP) =====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Text(
                        'COMPRAS',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    _infoRow(
                      label: 'MIEMBRO DESDE',
                      value: _fmtDate(_createdAt),
                    ),
                    _infoRow(
                      label: 'DOCUMENTOS COMPRADOS',
                      value: _purchasedProductIds.length.toString(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: CapColors.goldDark,
                                ),
                                foregroundColor: CapColors.gold,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _restoring ? null : _restorePurchases,
                              child: _restoring
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Restaurar compras',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/biblioteca'),
                              child: const Text(
                                'Ir a Biblioteca',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ===== Cuenta / eliminación requerida por Apple =====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                      child: Text(
                        'CUENTA',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: CapColors.gold,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: CapColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(.45),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Eliminar cuenta',
                              style: TextStyle(
                                color: CapColors.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Puedes eliminar tu cuenta y los datos asociados a tu perfil. Esta acción no se puede deshacer.',
                              style: TextStyle(
                                color: CapColors.textMuted,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _deletingAccount
                                  ? null
                                  : _confirmDeleteAccount,
                              icon: _deletingAccount
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.redAccent,
                                      ),
                                    )
                                  : const Icon(Icons.delete_forever),
                              label: Text(
                                _deletingAccount
                                    ? 'Eliminando cuenta...'
                                    : 'Eliminar mi cuenta',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
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
                          title: 'Paquetes',
                          child: _favBundles.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    'No tienes paquetes favoritos',
                                    style:
                                        TextStyle(color: CapColors.textMuted),
                                  ),
                                )
                              : SizedBox(
                                  height: 170,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      12,
                                    ),
                                    itemCount: _favBundles.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (ctx, i) {
                                      final b = _favBundles[i];

                                      return SizedBox(
                                        width: 190,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.of(context).pushNamed(
                                              '/biblioteca',
                                              arguments: {'query': b.title},
                                            );
                                          },
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: CapColors.surfaceAlt,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: Colors.white12,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Icon(
                                                  Icons.folder_zip_rounded,
                                                  color: CapColors.gold,
                                                  size: 24,
                                                ),
                                                const SizedBox(height: 6),
                                                Expanded(
                                                  child: Text(
                                                    b.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: CapColors.text,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${b.filesCount} archivo(s)',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: CapColors.textMuted,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
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
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      12,
                                    ),
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
