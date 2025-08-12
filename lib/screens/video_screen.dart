// lib/screens/video_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Búsqueda local simple
  String _search = '';

  // Player
  YoutubePlayerController? _yt;
  String? _activeVideoId;

  // ---- Firestore stream ----
  Stream<QuerySnapshot<Map<String, dynamic>>> _videosStream() {
    // Puedes quitar orderBy si no usas el campo 'order'
    return FirebaseFirestore.instance
        .collection('videos')
        .orderBy('order', descending: false)
        .snapshots();
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

      // /shorts/<id>
      final segs = u.pathSegments;
      final i = segs.indexOf('shorts');
      if (i >= 0 && i + 1 < segs.length && idRe.hasMatch(segs[i + 1])) {
        return segs[i + 1];
      }

      // /embed/<id>
      final j = segs.indexOf('embed');
      if (j >= 0 && j + 1 < segs.length && idRe.hasMatch(segs[j + 1])) {
        return segs[j + 1];
      }
    }
    return v;
  }

  // Inicializa o cambia el video en el player
  void _loadIntoPlayer(String videoId) {
    if (_yt == null) {
      _yt = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        params: const YoutubePlayerParams(
          showFullscreenButton: false,
          playsInline: true,
          enableCaption: true,
          strictRelatedVideos: true,
          showControls: true,
          // mute: true, // si lo necesitas
        ),
      );
    } else {
      _yt!.loadVideoById(videoId: videoId);
    }
    setState(() => _activeVideoId = videoId);
  }

  @override
  void dispose() {
    _yt?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
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
            return Center(
              child: Text('Error: ${snap.error}'),
            );
          }

          final docs = snap.data?.docs ?? [];
          // Mapea y normaliza
          final allVideos = docs
              .map((d) {
                final data = d.data();
                final title = (data['title'] ?? '').toString();
                final description = (data['description'] ?? '').toString();
                final raw = (data['youtubeId'] ?? '').toString();
                final id = _normalizeYouTubeId(raw);
                return _VideoMeta(
                  id: d.id,
                  youtubeId: id,
                  title: title,
                  description: description,
                );
              })
              .where((v) => v.youtubeId.length == 11)
              .toList();

          // Filtro por búsqueda
          final filtered = allVideos.where((v) {
            if (_search.trim().isEmpty) return true;
            final q = _search.trim().toLowerCase();
            return v.title.toLowerCase().contains(q) ||
                v.description.toLowerCase().contains(q);
          }).toList();

          // Carga el primer video al player si aún no hay activo
          if (filtered.isNotEmpty && _activeVideoId == null) {
            _loadIntoPlayer(filtered.first.youtubeId);
          }

          return Column(
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
                        minimumSize: const Size(0, 0),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text(
                        'Regresar',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),

              // Título
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'VIDEOS',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                          color: const Color(0xFF6B1A1A),
                        ),
                  ),
                ),
              ),

              // Buscador + Filtros
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          onChanged: (q) => setState(() => _search = q),
                          decoration: InputDecoration(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            hintText: 'Buscar videos...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide:
                                  const BorderSide(color: Colors.black26),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide:
                                  const BorderSide(color: Colors.black26),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(24)),
                              borderSide: BorderSide(
                                  color: Color(0xFF6B1A1A), width: 1.2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        // Aquí puedes abrir un bottom sheet de filtros
                      },
                      icon: const Icon(Icons.filter_list),
                      label: const Text('Filtros'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // Player grande
              if (_activeVideoId != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: YoutubePlayer(
                        controller: _yt!,
                        backgroundColor: const Color(0xFF6B1A1A),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Lista de videos
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No hay videos'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final v = filtered[i];
                          final isActive = v.youtubeId == _activeVideoId;
                          return _VideoListTile(
                            meta: v,
                            isActive: isActive,
                            onTap: () => _loadIntoPlayer(v.youtubeId),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: CapfiscalBottomNav(
        currentIndex: 1,
        onTap: (i) {
          switch (i) {
            case 0:
              Navigator.pushReplacementNamed(context, '/biblioteca');
              break;
            case 1:
              // ya estás en videos
              break;
            case 2:
              Navigator.pushReplacementNamed(context, '/biblioteca'); // home?
              break;
            case 3:
              Navigator.pushReplacementNamed(context, '/chat');
              break;
          }
        },
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

  _VideoMeta({
    required this.id,
    required this.youtubeId,
    required this.title,
    required this.description,
  });
}

// ----- Tile de lista -----
class _VideoListTile extends StatelessWidget {
  const _VideoListTile({
    required this.meta,
    required this.onTap,
    required this.isActive,
  });

  final _VideoMeta meta;
  final VoidCallback onTap;
  final bool isActive;

  String get _thumb =>
      'https://img.youtube.com/vi/${meta.youtubeId}/hqdefault.jpg';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isActive ? const Color(0xFF6B1A1A) : Colors.black12),
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
                    width: 92,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6B1A1A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white),
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
                        meta.description.isEmpty
                            ? 'Descripción'
                            : meta.description,
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
