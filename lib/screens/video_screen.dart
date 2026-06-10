// lib/screens/video_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';
import '../services/doc_iap_service.dart';

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

  static const success = Color(0xFF1F8B4C);
  static const successDark = Color(0xFF16653A);
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({
    super.key,
    this.firestore,
    this.auth,
    this.videosStream,
  });

  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? videosStream;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final FirebaseAuth _auth;
  late final FirebaseFirestore _db;

  late final DocIapService _iap;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  Set<String> _purchasedProductIds = <String>{};
  final Set<String> _purchaseInProgress = <String>{};

  String _search = '';

  String? _activeVideoId;
  _VideoMeta? _activeMeta;
  String? _scheduledInitialId;

  @override
  void initState() {
    super.initState();

    _auth = widget.auth ?? FirebaseAuth.instance;
    _db = widget.firestore ?? FirebaseFirestore.instance;

    _iap = DocIapService(
      auth: _auth,
      firestore: _db,
    );

    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (e) {
        debugPrint('❌ video purchaseStream error: $e');
      },
    );

    _bootstrapVideoPurchases();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _videosStream() {
    return widget.videosStream ??
        _db
            .collection('videos')
            .orderBy('order', descending: false)
            .snapshots();
  }

  String _productIdForVideo(_VideoMeta v) {
    final configuredProductId = v.productId.trim();

    if (configuredProductId.isNotEmpty) {
      return configuredProductId;
    }

    return 'capfiscal_video_${v.id.toLowerCase()}';
  }

  bool _isPurchasedVideo(_VideoMeta v) {
    final productId = _productIdForVideo(v);
    return _purchasedProductIds.contains(productId);
  }

  Future<void> _bootstrapVideoPurchases() async {
    try {
      _purchasedProductIds = await _iap.loadPurchasedProductIds();

      final snap = await _db
          .collection('videos')
          .orderBy('order', descending: false)
          .get();

      final videos = snap.docs.map(_videoFromDoc).where((v) {
        return v.active &&
            v.productId.trim().isNotEmpty &&
            RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v.youtubeId);
      }).toList();

      final productIds = videos.map(_productIdForVideo).toSet();

      debugPrint('🎬 Video IAP Requested IDs: ${productIds.join(', ')}');

      if (productIds.isNotEmpty) {
        await _iap.loadProducts(productIds);
      }

      debugPrint('🎬 Video IAP Found IDs: ${_iap.products.keys.join(', ')}');

      await _iap.restorePurchases();

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('❌ Error _bootstrapVideoPurchases: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar compras de videos: $e')),
      );
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final productId = p.productID;

      if (p.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() => _purchaseInProgress.add(productId));
        }
        continue;
      }

      if (p.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() => _purchaseInProgress.remove(productId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compra fallida: ${p.error}')),
          );
        }
      }

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        try {
          await _iap.grantEntitlement(p);
          _purchasedProductIds.add(productId);

          if (mounted) {
            setState(() => _purchaseInProgress.remove(productId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video desbloqueado ✅')),
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() => _purchaseInProgress.remove(productId));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo aplicar la compra: $e')),
            );
          }
        }
      }

      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }

  Future<void> _buyVideo(_VideoMeta v) async {
    final productId = _productIdForVideo(v);

    debugPrint('🛒 Intentando comprar video productId: $productId');

    if (productId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Este video no tiene productId configurado en Firebase'),
        ),
      );
      return;
    }

    if (!_iap.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compras no disponibles en este dispositivo'),
        ),
      );
      return;
    }

    if (_purchasedProductIds.contains(productId)) {
      await _openInYouTube(v.youtubeId);
      return;
    }

    try {
      if (mounted) {
        setState(() => _purchaseInProgress.add(productId));
      }

      await _iap.buyNonConsumable(productId);
    } catch (e) {
      if (!mounted) return;

      setState(() => _purchaseInProgress.remove(productId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la compra: $e')),
      );
    }
  }

  Future<void> _openPurchasedVideo(_VideoMeta v) async {
    if (!_isPurchasedVideo(v)) {
      await _showLockedVideoSheet(v);
      return;
    }

    await _openInYouTube(v.youtubeId);
  }

  Future<void> _showLockedVideoSheet(_VideoMeta v) async {
    final productId = _productIdForVideo(v);

    await showModalBottomSheet(
      context: context,
      backgroundColor: _CapColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final busy = _purchaseInProgress.contains(productId);
            final priceLabel = _iap.products[productId]?.price;
            final buyLabel =
                priceLabel == null ? 'Comprar' : 'Comprar $priceLabel';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Video bloqueado',
                      style: TextStyle(
                        color: _CapColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      v.title.isEmpty
                          ? 'Este video requiere una compra válida para desbloquearse.'
                          : v.title,
                      style: const TextStyle(
                        color: _CapColors.textMuted,
                        height: 1.25,
                      ),
                    ),
                    if (v.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        v.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _CapColors.textMuted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              foregroundColor: _CapColors.text,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cerrar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    Navigator.pop(context);
                                    await _buyVideo(v);
                                  },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: _CapColors.gold,
                              foregroundColor: Colors.black,
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    buyLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  _VideoMeta _videoFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();

    final title = (data['title'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final productId = (data['productId'] ?? '').toString().trim();

    final raw = _extractYoutubeRaw(data);
    final youtubeId = _normalizeYouTubeId(raw);
    final order = _extractOrder(data);

    final active = data['active'] == null ? true : data['active'] == true;

    return _VideoMeta(
      id: d.id,
      productId: productId,
      active: active,
      youtubeId: youtubeId,
      title: title,
      description: description,
      raw: raw,
      order: order,
    );
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
      if (val is String && val.trim().isNotEmpty) {
        return val.trim();
      }
    }

    return '';
  }

  int _extractOrder(Map<String, dynamic> data) {
    final v = data['order'];

    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 1 << 30;

    return 1 << 30;
  }

  String _thumbUrl(String id) => 'https://img.youtube.com/vi/$id/hqdefault.jpg';

  Future<void> _openInYouTube(String id) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID de YouTube vacío')),
      );
      return;
    }

    final youtubeAppUri = Uri.parse('vnd.youtube:$cleanId');
    final youtubeWebUri = Uri.parse('https://www.youtube.com/watch?v=$cleanId');
    final youtubeShortUri = Uri.parse('https://youtu.be/$cleanId');

    debugPrint('▶️ Intentando abrir YouTube app: $youtubeAppUri');

    try {
      final openedApp = await launchUrl(
        youtubeAppUri,
        mode: LaunchMode.externalApplication,
      );

      if (openedApp) return;
    } catch (e) {
      debugPrint('⚠️ No se pudo abrir app de YouTube: $e');
    }

    debugPrint('▶️ Intentando abrir YouTube web: $youtubeWebUri');

    try {
      final openedWeb = await launchUrl(
        youtubeWebUri,
        mode: LaunchMode.externalApplication,
      );

      if (openedWeb) return;
    } catch (e) {
      debugPrint('⚠️ No se pudo abrir YouTube web externo: $e');
    }

    debugPrint('▶️ Intentando abrir fallback youtu.be: $youtubeShortUri');

    try {
      final openedFallback = await launchUrl(
        youtubeShortUri,
        mode: LaunchMode.platformDefault,
      );

      if (openedFallback) return;
    } catch (e) {
      debugPrint('⚠️ No se pudo abrir fallback youtu.be: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo abrir YouTube. Verifica que el dispositivo tenga navegador o la app de YouTube.',
        ),
      ),
    );
  }

  void _selectVideo(_VideoMeta v) {
    setState(() {
      _activeMeta = v;
      _activeVideoId = v.youtubeId;
    });

    if (!_isPurchasedVideo(v)) {
      _showLockedVideoSheet(v);
    }
  }

  void _ensureFirstVideoSelected(List<_VideoMeta> list) {
    if (_activeVideoId != null || list.isEmpty) return;

    final id = list.first.youtubeId;

    if (_scheduledInitialId == id) return;

    _scheduledInitialId = id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_activeVideoId == null) {
        _activeMeta = list.first;
        _activeVideoId = id;
        setState(() {});
      }

      _scheduledInitialId = null;
    });
  }

  String _favKeyForVideo(String ytId) => 'video:$ytId';

  Future<bool> _isFavoriteForCurrentUser(String itemKey) async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) return false;

    return FavoritesManager.isFavorite(uid, itemKey);
  }

  Future<void> _toggleFavoriteForCurrentUser(String itemKey) async {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para usar favoritos')),
      );
      return;
    }

    await FavoritesManager.toggleFavorite(uid, itemKey);

    if (mounted) setState(() {});
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    final didPop = await navigator.maybePop();

    if (!mounted || didPop || !navigator.mounted) return;

    navigator.pushReplacementNamed('/home');
  }

  Widget _topBackBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: InkWell(
        onTap: _handleBack,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
                  color: _CapColors.text,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Regresar',
                style: TextStyle(
                  color: _CapColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Text(
        'VIDEOS',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
              color: _CapColors.gold,
            ),
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [_CapColors.surfaceAlt, Color(0xFF232329)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.search, color: _CapColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (q) => setState(() => _search = q),
                      cursorColor: _CapColors.gold,
                      style: const TextStyle(color: _CapColors.text),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Buscar videos...',
                        hintStyle: TextStyle(color: _CapColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerBlock() {
    final meta = _activeMeta;

    if (meta == null) return const SizedBox.shrink();

    final thumb = _thumbUrl(meta.youtubeId);
    final purchased = _isPurchasedVideo(meta);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openPurchasedVideo(meta),
                  child: Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.ondemand_video,
                        color: _CapColors.gold,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.black.withOpacity(purchased ? .25 : .55),
                child: InkWell(
                  onTap: () => _openPurchasedVideo(meta),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: purchased
                              ? const [
                                  _CapColors.success,
                                  _CapColors.successDark,
                                ]
                              : const [
                                  _CapColors.gold,
                                  _CapColors.goldDark,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            purchased
                                ? Icons.open_in_new_rounded
                                : Icons.lock_open_rounded,
                            color: purchased ? Colors.white : Colors.black,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            purchased
                                ? 'Abrir en YouTube'
                                : 'Desbloquear video',
                            style: TextStyle(
                              color: purchased ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!purchased)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          color: _CapColors.gold,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Bloqueado',
                          style: TextStyle(
                            color: _CapColors.gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeMetaBlock() {
    final meta = _activeMeta;

    if (meta == null) return const SizedBox.shrink();

    final purchased = _isPurchasedVideo(meta);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              meta.title.isEmpty ? 'Título del video' : meta.title,
              maxLines: 2,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _CapColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: purchased
                  ? _CapColors.success.withOpacity(.18)
                  : Colors.white.withOpacity(.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: purchased ? _CapColors.success : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  purchased ? Icons.lock_open_rounded : Icons.lock_rounded,
                  color: purchased ? _CapColors.success : _CapColors.gold,
                  size: 15,
                ),
                const SizedBox(width: 5),
                Text(
                  purchased ? 'Comprado' : 'Bloqueado',
                  style: TextStyle(
                    color: purchased ? _CapColors.success : _CapColors.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FutureBuilder<bool>(
            future: _isFavoriteForCurrentUser(_favKeyForVideo(meta.youtubeId)),
            builder: (context, snap) {
              final fav = snap.data ?? false;

              return IconButton(
                tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                onPressed: () => _toggleFavoriteForCurrentUser(
                  _favKeyForVideo(meta.youtubeId),
                ),
                icon: Icon(
                  fav ? Icons.star : Icons.star_border,
                  color: fav ? _CapColors.gold : _CapColors.textMuted,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _activeDescriptionBlock() {
    final meta = _activeMeta;

    if (meta == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _CapColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          meta.description.isEmpty ? 'Descripción' : meta.description,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: _CapColors.textMuted,
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
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        drawer: const CustomDrawer(),
        appBar: CapfiscalTopBar(
          onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          onRefresh: () async {
            await _bootstrapVideoPurchases();
            if (mounted) setState(() {});
          },
          onProfile: () => Navigator.of(context).pushNamed('/perfil'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _videosStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_CapColors.gold),
                ),
              );
            }

            if (snap.hasError) {
              return Center(
                child: Text(
                  'Error: ${snap.error}',
                  style: const TextStyle(color: _CapColors.textMuted),
                ),
              );
            }

            final docs = snap.data?.docs ?? [];

            final allVideos = docs.map(_videoFromDoc).toList();

            allVideos.sort((a, b) => a.order.compareTo(b.order));

            final valid = allVideos.where((v) {
              return v.active &&
                  RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v.youtubeId);
            }).toList();

            final filtered = valid.where((v) {
              if (_search.trim().isEmpty) return true;

              final q = _search.trim().toLowerCase();

              return v.title.toLowerCase().contains(q) ||
                  v.description.toLowerCase().contains(q);
            }).toList();

            _ensureFirstVideoSelected(filtered);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _topBackBar(),
                        _headline(),
                        _searchRow(),
                        if (_activeMeta != null) ...[
                          _playerBlock(),
                          const SizedBox(height: 12),
                          _activeMetaBlock(),
                          _activeDescriptionBlock(),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isNotEmpty
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final v = filtered[i];
                            final isActive = v.youtubeId == _activeVideoId;
                            final favKey = _favKeyForVideo(v.youtubeId);

                            final productId = _productIdForVideo(v);
                            final purchased =
                                _purchasedProductIds.contains(productId);
                            final busy =
                                _purchaseInProgress.contains(productId);
                            final price = _iap.products[productId]?.price;

                            return _VideoListTile(
                              meta: v,
                              isActive: isActive,
                              purchased: purchased,
                              busy: busy,
                              priceLabel: price,
                              onTap: () => _selectVideo(v),
                              onBuy: () => _buyVideo(v),
                              isFavoriteFuture:
                                  _isFavoriteForCurrentUser(favKey),
                              onToggleFavorite: () =>
                                  _toggleFavoriteForCurrentUser(favKey),
                            );
                          },
                        )
                      : const Center(
                          child: Text(
                            'No hay videos',
                            style: TextStyle(color: _CapColors.textMuted),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: const CapfiscalBottomNav(currentIndex: 1),
      ),
    );
  }
}

class _VideoMeta {
  final String id;
  final String productId;
  final bool active;
  final String youtubeId;
  final String title;
  final String description;
  final String raw;
  final int order;

  _VideoMeta({
    required this.id,
    required this.productId,
    required this.active,
    required this.youtubeId,
    required this.title,
    required this.description,
    required this.raw,
    required this.order,
  });
}

class _VideoListTile extends StatelessWidget {
  const _VideoListTile({
    required this.meta,
    required this.onTap,
    required this.isActive,
    required this.purchased,
    required this.busy,
    required this.priceLabel,
    required this.onBuy,
    required this.isFavoriteFuture,
    required this.onToggleFavorite,
  });

  final _VideoMeta meta;
  final VoidCallback onTap;
  final bool isActive;

  final bool purchased;
  final bool busy;
  final String? priceLabel;
  final VoidCallback onBuy;

  final Future<bool> isFavoriteFuture;
  final VoidCallback onToggleFavorite;

  String get _thumb =>
      'https://img.youtube.com/vi/${meta.youtubeId}/hqdefault.jpg';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: _CapColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? _CapColors.gold : Colors.white12,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    _thumb,
                    width: 110,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 110,
                      height: 80,
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.ondemand_video,
                        color: _CapColors.gold,
                        size: 28,
                      ),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: purchased
                            ? const [
                                _CapColors.success,
                                _CapColors.successDark,
                              ]
                            : const [
                                _CapColors.gold,
                                _CapColors.goldDark,
                              ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      purchased ? Icons.play_arrow : Icons.lock_rounded,
                      color: purchased ? Colors.white : Colors.black,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title.isEmpty ? 'Título del video' : meta.title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _CapColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _CapColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        meta.description.isEmpty
                            ? 'Descripción'
                            : meta.description,
                        maxLines: 2,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _CapColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          purchased
                              ? Icons.lock_open_rounded
                              : Icons.lock_rounded,
                          color:
                              purchased ? _CapColors.success : _CapColors.gold,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          purchased ? 'Comprado' : 'Bloqueado',
                          style: TextStyle(
                            color: purchased
                                ? _CapColors.success
                                : _CapColors.gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ElevatedButton(
                onPressed: busy
                    ? null
                    : purchased
                        ? onTap
                        : onBuy,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      purchased ? _CapColors.success : _CapColors.gold,
                  foregroundColor: purchased ? Colors.white : Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(72, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        purchased
                            ? 'Abrir'
                            : priceLabel == null
                                ? 'Comprar'
                                : priceLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
            FutureBuilder<bool>(
              future: isFavoriteFuture,
              builder: (context, snap) {
                final fav = snap.data ?? false;

                return IconButton(
                  tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    fav ? Icons.star : Icons.star_border,
                    color: fav ? _CapColors.gold : _CapColors.textMuted,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
