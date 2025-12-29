// lib/screens/video_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  String? _activeVideoId;
  _VideoMeta? _activeMeta; // para mostrar título/desc del video activo
  String? _scheduledInitialId;

  // ---- Firestore stream ----
  Stream<QuerySnapshot<Map<String, dynamic>>> _videosStream() {
    return widget.videosStream ??
        _db.collection('videos').orderBy('order', descending: false).snapshots();
  }

  // Normaliza ID de YouTube desde variantes (url, shorts, embed, watch)
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

  // Acepta varias llaves en Firestore por si no siempre es 'youtubeId'
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

  // Extrae el order como entero. Si no hay, lo manda al final.
  int _extractOrder(Map<String, dynamic> data) {
    final v = data['order'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 1 << 30;
    return 1 << 30;
  }

  String _embedUrl(String id) =>
      'https://www.youtube.com/embed/$id?playsinline=1&autoplay=1&controls=1&modestbranding=1&rel=0';

  // Inicializa o cambia el video en el WebView
  void _loadIntoPlayer(String videoId) {
    final url = _embedUrl(videoId);

    if (_wv == null) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) => NavigationDecision.navigate,
          ),
        )
        ..loadRequest(Uri.parse(url));
      _wv = controller;
    } else {
      _wv!.loadRequest(Uri.parse(url));
    }

    if (mounted && _activeVideoId != videoId) {
      setState(() => _activeVideoId = videoId);
    }
  }

  // Selecciona un video desde la lista
  void _selectVideo(_VideoMeta v) {
    _activeMeta = v;
    _loadIntoPlayer(v.youtubeId);
    if (mounted) setState(() {});
  }

  // Programa (post-frame) la carga del primer video para evitar setState durante build
  void _ensureFirstVideoLoaded(List<_VideoMeta> list) {
    if (_activeVideoId != null || list.isEmpty) return;
    final id = list.first.youtubeId;
    if (_scheduledInitialId == id) return;
    _scheduledInitialId = id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeMeta = list.first;
      if (_activeVideoId == null) _loadIntoPlayer(id);
      _scheduledInitialId = null;
      setState(() {});
    });
  }

  // ======== FAVORITOS por usuario (usa FavoritesManager per-UID) ========
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
  // =====================================================================

  @override
  void dispose() {
    super.dispose(); // WebViewController no requiere dispose explícito
  }

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
      child: LayoutBuilder(
        builder: (ctx, c) {
          final isNarrow = c.maxWidth < 360;
          return Row(
            children: [
              if (!isNarrow)
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.08),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.view_list,
                      color: _CapColors.text, size: 20),
                ),
              if (!isNarrow) const SizedBox(width: 8),

              // Search
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
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          gradient: const LinearGradient(
                            colors: [_CapColors.gold, _CapColors.goldDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _CapColors.gold.withOpacity(.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.search,
                            size: 18, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Filtros
              isNarrow
                  ? IconButton(
                      onPressed: () {},
                      icon:
                          const Icon(Icons.filter_list, color: _CapColors.gold),
                      visualDensity: VisualDensity.compact,
                    )
                  : OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.filter_list,
                          size: 18, color: _CapColors.gold),
                      label: const Text('Filtros',
                          style: TextStyle(
                              color: _CapColors.gold,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: _CapColors.goldDark, width: 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
            ],
          );
        },
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
          onRefresh: () {},
          onProfile: () => Navigator.of(context).pushNamed('/perfil'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _videosStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }

            final docs = snap.data?.docs ?? [];

            // Mapea y normaliza
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

            // Orden seguro en memoria
            allVideos.sort((a, b) => a.order.compareTo(b.order));

            // Solo IDs válidos
            final valid = allVideos
                .where(
                  (v) => RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v.youtubeId),
                )
                .toList();

            // Filtro por búsqueda (preserva orden ya aplicado)
            final filtered = valid.where((v) {
              if (_search.trim().isEmpty) return true;
              final q = _search.trim().toLowerCase();
              return v.title.toLowerCase().contains(q) ||
                  v.description.toLowerCase().contains(q);
            }).toList();

            // Programa la carga del primer video fuera del build actual
            _ensureFirstVideoLoaded(filtered);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ====== BLOQUE SUPERIOR DESPLAZABLE (evita overflow) ======
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
                        if (_wv != null && _activeVideoId != null) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: WebViewWidget(controller: _wv!),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_activeMeta != null)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _activeMeta!.title.isEmpty
                                          ? 'Título del video'
                                          : _activeMeta!.title,
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
                                    future: _isFavoriteForCurrentUser(
                                        _favKeyForVideo(
                                            _activeMeta!.youtubeId)),
                                    builder: (context, snap) {
                                      final fav = snap.data ?? false;
                                      return IconButton(
                                        tooltip: fav
                                            ? 'Quitar de favoritos'
                                            : 'Agregar a favoritos',
                                        onPressed: () =>
                                            _toggleFavoriteForCurrentUser(
                                                _favKeyForVideo(
                                                    _activeMeta!.youtubeId)),
                                        icon: Icon(
                                          fav
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: _CapColors.gold,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (_activeMeta != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _CapColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Text(
                                  _activeMeta!.description.isEmpty
                                      ? 'Descripción'
                                      : _activeMeta!.description,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _CapColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                // ==========================================================

                // Lista de videos
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

// ----- Modelo simple -----
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

// ----- Tile de lista con favorito -----
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
            // Miniatura
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
            // Texto
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
                            fontSize: 12, color: _CapColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Botón favorito
            FutureBuilder<bool>(
              future: isFavoriteFuture,
              builder: (context, snap) {
                final fav = snap.data ?? false;
                return IconButton(
                  tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    fav ? Icons.favorite : Icons.favorite_border,
                    color: _CapColors.gold,
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
