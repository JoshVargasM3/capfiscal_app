// lib/screens/video_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';

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

  // Búsqueda local
  String _search = '';

  // Player (WebView)
  WebViewController? _wv;
  bool _showPlayer = false; // muestra WebView solo cuando el usuario le da play
  bool _playerLoading = false;
  String? _playerError;

  String? _activeVideoId;
  _VideoMeta? _activeMeta;
  String? _scheduledInitialId;

  // ---- Firestore stream ----
  Stream<QuerySnapshot<Map<String, dynamic>>> _videosStream() {
    return widget.videosStream ??
        _db
            .collection('videos')
            .orderBy('order', descending: false)
            .snapshots();
  }

  // Normaliza ID de YouTube desde variantes
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

  // Acepta varias llaves en Firestore
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

  int _extractOrder(Map<String, dynamic> data) {
    final v = data['order'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 1 << 30;
    return 1 << 30;
  }

  // Embed “nocookie” (preview primero), y play al tocar.
  String _embedUrl(String id, {required bool autoplay}) =>
      'https://www.youtube-nocookie.com/embed/$id'
      '?playsinline=1'
      '&autoplay=${autoplay ? 1 : 0}'
      '&controls=1'
      '&modestbranding=1'
      '&rel=0'
      '&fs=1'
      '&iv_load_policy=3';

  String _watchUrl(String id) => 'https://www.youtube.com/watch?v=$id';
  String _thumbUrl(String id) => 'https://img.youtube.com/vi/$id/hqdefault.jpg';

  WebViewController _buildWebViewController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setMediaPlaybackRequiresUserGesture(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _playerLoading = true;
              _playerError = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _playerLoading = false);
          },
          onWebResourceError: (err) {
            if (!err.isForMainFrame) return;
            if (!mounted) return;
            setState(() {
              _playerLoading = false;
              _playerError =
                  'No se pudo cargar el reproductor (${err.errorCode}). ${err.description}';
              _showPlayer = false;
            });
          },
        ),
      );
  }

  Future<void> _playActive() async {
    final v = _activeMeta;
    if (v == null) return;

    final controller = _buildWebViewController();

    setState(() {
      _wv = controller;
      _playerError = null;
      _showPlayer = true;
      _playerLoading = true;
    });

    try {
      await _wv!.loadRequest(Uri.parse(_embedUrl(v.youtubeId, autoplay: true)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playerLoading = false;
        _playerError = 'Error al iniciar el reproductor: $e';
        _showPlayer = false;
      });
    }
  }

  void _selectVideo(_VideoMeta v) {
    setState(() {
      _activeMeta = v;
      _activeVideoId = v.youtubeId;
      _playerError = null;
      _showPlayer = false;
      _playerLoading = false;
    });
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
        _showPlayer = false;
        _playerError = null;
        _playerLoading = false;
        setState(() {});
      }
      _scheduledInitialId = null;
    });
  }

  // ===== Favoritos (⭐ como Biblioteca) =====
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
  // =========================================

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? FirebaseAuth.instance;
    _db = widget.firestore ?? FirebaseFirestore.instance;
  }

  // ---------- UI helpers ----------
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
                child: const Icon(Icons.arrow_back,
                    size: 18, color: _CapColors.text),
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

  Future<void> _openInYouTube(String id) async {
    final uri = Uri.parse(_watchUrl(id));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ✅ Abre pantalla completa (propia) con botón cerrar
  Future<void> _openFullscreen() async {
    final meta = _activeMeta;
    if (meta == null) return;

    // evita tener 2 players simultáneos en pantalla
    setState(() => _showPlayer = false);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenYouTubePage(
          youtubeId: meta.youtubeId,
          title: meta.title.isEmpty ? 'Video' : meta.title,
          embedUrl: _embedUrl(meta.youtubeId, autoplay: true),
          onOpenExternal: () => _openInYouTube(meta.youtubeId),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _playerBlock() {
    final meta = _activeMeta;
    if (meta == null) return const SizedBox.shrink();

    final thumb = _thumbUrl(meta.youtubeId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                thumb,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: const Icon(Icons.ondemand_video,
                      color: _CapColors.gold, size: 42),
                ),
              ),

              // WebView encima si está activo
              if (_showPlayer && _wv != null)
                Positioned.fill(
                  child: WebViewWidget(
                    key: ValueKey('yt_${meta.youtubeId}'),
                    controller: _wv!,
                  ),
                ),

              // Overlay play si NO está el player
              if (!_showPlayer)
                Material(
                  color: Colors.black.withOpacity(.25),
                  child: InkWell(
                    onTap: _playActive,
                    child: Center(
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_CapColors.gold, _CapColors.goldDark],
                          ),
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.black, size: 38),
                      ),
                    ),
                  ),
                ),

              // ✅ Botón fullscreen (cuando el player está activo)
              if (_showPlayer)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: InkWell(
                    onTap: _openFullscreen,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _CapColors.surface.withOpacity(.85),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(
                        Icons.fullscreen,
                        color: _CapColors.gold,
                        size: 22,
                      ),
                    ),
                  ),
                ),

              if (_playerLoading)
                const Positioned(
                  left: 12,
                  top: 12,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),

              if (_playerError != null && !_showPlayer)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _CapColors.surface.withOpacity(.95),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.orangeAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _playerError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _CapColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => _openInYouTube(meta.youtubeId),
                          child: const Text(
                            'Abrir',
                            style: TextStyle(
                              color: _CapColors.gold,
                              fontWeight: FontWeight.w800,
                            ),
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
          FutureBuilder<bool>(
            future: _isFavoriteForCurrentUser(_favKeyForVideo(meta.youtubeId)),
            builder: (context, snap) {
              final fav = snap.data ?? false;
              return IconButton(
                tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                onPressed: () => _toggleFavoriteForCurrentUser(
                    _favKeyForVideo(meta.youtubeId)),
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
          onRefresh: () => setState(() {}),
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

            final allVideos = docs.map((d) {
              final data = d.data();
              final title = (data['title'] ?? '').toString();
              final description = (data['description'] ?? '').toString();
              final raw = _extractYoutubeRaw(data);
              final id = _normalizeYouTubeId(raw);
              final ord = _extractOrder(data);
              return _VideoMeta(
                id: d.id,
                youtubeId: id,
                title: title,
                description: description,
                raw: raw,
                order: ord,
              );
            }).toList();

            allVideos.sort((a, b) => a.order.compareTo(b.order));

            final valid = allVideos
                .where(
                    (v) => RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v.youtubeId))
                .toList();

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

                            return _VideoListTile(
                              meta: v,
                              isActive: isActive,
                              onTap: () => _selectVideo(v),
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
  final String youtubeId;
  final String title;
  final String description;
  final String raw;
  final int order;

  _VideoMeta({
    required this.id,
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
    required this.isFavoriteFuture,
    required this.onToggleFavorite,
  });

  final _VideoMeta meta;
  final VoidCallback onTap;
  final bool isActive;
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
                      child: const Icon(Icons.ondemand_video,
                          color: _CapColors.gold, size: 28),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_CapColors.gold, _CapColors.goldDark],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.black),
                  )
                ],
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
                          horizontal: 8, vertical: 6),
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
                  ],
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

/// ✅ Pantalla completa propia (con botón de cerrar)
class _FullscreenYouTubePage extends StatefulWidget {
  const _FullscreenYouTubePage({
    required this.youtubeId,
    required this.title,
    required this.embedUrl,
    required this.onOpenExternal,
  });

  final String youtubeId;
  final String title;
  final String embedUrl;
  final VoidCallback onOpenExternal;

  @override
  State<_FullscreenYouTubePage> createState() => _FullscreenYouTubePageState();
}

class _FullscreenYouTubePageState extends State<_FullscreenYouTubePage> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  List<DeviceOrientation> _prevOrientations = const [];
  SystemUiMode? _prevUiMode;

  @override
  void initState() {
    super.initState();

    // Guardar estado anterior y forzar modo fullscreen
    _enterFullscreen();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setMediaPlaybackRequiresUserGesture(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _loading = true;
            _error = null;
          }),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (err) {
            if (!err.isForMainFrame) return;
            setState(() {
              _loading = false;
              _error = 'Error (${err.errorCode}): ${err.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.embedUrl));
  }

  Future<void> _enterFullscreen() async {
    // Nota: Flutter no expone lectura directa de orientaciones previas.
    // Guardamos “best effort” y restauramos a portrait al salir.
    _prevOrientations = const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    _prevUiMode = SystemUiMode.edgeToEdge;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(
        _prevUiMode ?? SystemUiMode.edgeToEdge);
    // Restaurar a portrait para que tu app no se quede “acostada”
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    _exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _exitFullscreen();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),

              if (_loading)
                const Positioned(
                  left: 16,
                  top: 16,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),

              // ✅ Botón cerrar (arriba derecha)
              Positioned(
                right: 10,
                top: 10,
                child: InkWell(
                  onTap: () async {
                    await _exitFullscreen();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C21).withOpacity(.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(Icons.close,
                        color: _CapColors.gold, size: 22),
                  ),
                ),
              ),

              // Error + abrir externo
              if (_error != null)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C21).withOpacity(.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.orangeAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFBEBEC6),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: widget.onOpenExternal,
                          child: const Text(
                            'Abrir en YouTube',
                            style: TextStyle(
                              color: _CapColors.gold,
                              fontWeight: FontWeight.w800,
                            ),
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
}
