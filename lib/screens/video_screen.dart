// lib/screens/video_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

/// 🎨 Paleta CAPFISCAL local
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

class _VideoScreenState extends State<VideoScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _auth = FirebaseAuth.instance;

  String _search = '';

  WebViewController? _wv;
  String? _activeVideoId;
  _VideoMeta? _activeMeta;
  String? _scheduledInitialId;

  Stream<QuerySnapshot<Map<String, dynamic>>> _videosStream() {
    return FirebaseFirestore.instance
        .collection('videos')
        .orderBy('order', descending: false)
        .snapshots();
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
    final keys = [
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
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
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

  String _embedUrl(String id) =>
      'https://www.youtube.com/embed/$id?playsinline=1&autoplay=1&controls=1&modestbranding=1&rel=0';

  void _loadIntoPlayer(String videoId) {
    final url = _embedUrl(videoId);
    if (_wv == null) {
      _wv = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) => NavigationDecision.navigate,
          ),
        )
        ..loadRequest(Uri.parse(url));
    } else {
      _wv!.loadRequest(Uri.parse(url));
    }
    if (mounted && _activeVideoId != videoId) {
      setState(() => _activeVideoId = videoId);
    }
  }

  void _selectVideo(_VideoMeta v) {
    _activeMeta = v;
    _loadIntoPlayer(v.youtubeId);
    if (mounted) setState(() {});
  }

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

  String _favKeyForVideo(String ytId) => 'video:$ytId';
  Future<bool> _isFavoriteForCurrentUser(String key) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    return FavoritesManager.isFavorite(uid, key);
  }

  Future<void> _toggleFavoriteForCurrentUser(String key) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para usar favoritos')),
      );
      return;
    }
    await FavoritesManager.toggleFavorite(uid, key);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
          onRefresh: () {},
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
              return Center(child: Text('Error: ${snap.error}'));
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
            }).toList()
              ..sort((a, b) => a.order.compareTo(b.order));

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

            _ensureFirstVideoLoaded(filtered);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.arrow_back,
                              size: 18, color: _CapColors.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Regresar',
                        style: TextStyle(
                          color: _CapColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Título
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'VIDEOS',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: _CapColors.gold,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .6,
                              ),
                    ),
                  ),
                ),

                // Buscador
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              colors: [
                                _CapColors.surfaceAlt,
                                Color(0xFF232329)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(color: Colors.white12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.search,
                                  color: _CapColors.textMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  onChanged: (q) => setState(() => _search = q),
                                  cursorColor: _CapColors.gold,
                                  style:
                                      const TextStyle(color: _CapColors.text),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: 'Buscar videos...',
                                    hintStyle:
                                        TextStyle(color: _CapColors.textMuted),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
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

                // Player + meta del activo
                if (_wv != null && _activeVideoId != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: WebViewWidget(controller: _wv!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_activeMeta != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _activeMeta!.title.isEmpty
                                  ? 'NOMBRE VIDEO'
                                  : _activeMeta!.title.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _CapColors.gold,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FutureBuilder<bool>(
                            future: _isFavoriteForCurrentUser(
                                _favKeyForVideo(_activeMeta!.youtubeId)),
                            builder: (context, snap) {
                              final fav = snap.data ?? false;
                              return IconButton(
                                tooltip: fav
                                    ? 'Quitar de favoritos'
                                    : 'Agregar a favoritos',
                                onPressed: () => _toggleFavoriteForCurrentUser(
                                    _favKeyForVideo(_activeMeta!.youtubeId)),
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
                  if (_activeMeta != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _CapColors.surfaceAlt,
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _activeMeta!.description.isEmpty
                              ? 'DESCRIPCIÓN'
                              : _activeMeta!.description,
                          style: const TextStyle(
                            color: _CapColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],

                // ==== GRID/Listado (ya sin Flexible/SingleChildScrollView) ====
                Expanded(
                  child: filtered.isNotEmpty
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: .92,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final v = filtered[i];
                            final isActive = v.youtubeId == _activeVideoId;
                            final favKey = _favKeyForVideo(v.youtubeId);
                            return _VideoCard(
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

// ===== Modelo =====
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

// ===== Card de grid (look negro/dorado) =====
class _VideoCard extends StatelessWidget {
  const _VideoCard({
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: _CapColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? _CapColors.gold : Colors.white12,
            width: isActive ? 1.2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 84,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_CapColors.gold, _CapColors.goldDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.black),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                meta.title.isEmpty ? 'NOMBRE VIDEO' : meta.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _CapColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta.description.isEmpty ? 'Descripción' : meta.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _CapColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FutureBuilder<bool>(
                future: isFavoriteFuture,
                builder: (context, snap) {
                  final fav = snap.data ?? false;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      iconSize: 20,
                      onPressed: onToggleFavorite,
                      icon: Icon(
                        fav ? Icons.favorite : Icons.favorite_border,
                        color: _CapColors.gold,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
