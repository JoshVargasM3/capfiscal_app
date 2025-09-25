// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/custom_drawer.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/loading_skeleton.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _CapColors {
  static const Color bgTop = Color(0xFF0A0A0B);
  static const Color bgMid = Color(0xFF2A2A2F);
  static const Color bgBottom = Color(0xFF4A4A50);
  static const Color surface = Color(0xFF1C1C21);
  static const Color surfaceAlt = Color(0xFF2A2A2F);
  static const Color text = Color(0xFFEFEFEF);
  static const Color textMuted = Color(0xFFBEBEC6);
  static const Color gold = Color(0xFFE1B85C);
  static const Color goldDark = Color(0xFFB88F30);
}

class _ImageStreamHandle {
  const _ImageStreamHandle(this.stream, this.listener);

  final ImageStream stream;
  final ImageStreamListener listener;
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // -------- BUSCADOR ----------
  final _searchCtrl = TextEditingController();

  void _onSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;

    final where = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _CapColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Buscar en…',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _CapColors.text)),
            ListTile(
              leading: const Icon(Icons.menu_book, color: _CapColors.gold),
              title: const Text('Documentos',
                  style: TextStyle(color: _CapColors.text)),
              onTap: () => Navigator.pop(context, 'docs'),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle, color: _CapColors.gold),
              title: const Text('Videos',
                  style: TextStyle(color: _CapColors.text)),
              onTap: () => Navigator.pop(context, 'videos'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || where == null) return;

    if (where == 'docs') {
      Navigator.pushNamed(context, '/biblioteca', arguments: {'query': q});
    } else if (where == 'videos') {
      Navigator.pushNamed(context, '/video', arguments: {'query': q});
    }
  }

  // -------- CARRUSEL CURSOS ----------
  final _pageCtrl = PageController(viewportFraction: 1.0);
  int _page = 0;
  Timer? _autoTimer;

  final _storage = FirebaseStorage.instance;
  bool _loadingCursos = true;
  List<Reference> _cursoRefs = [];
  List<String> _cursoUrls = [];
  String? _errorCursos;

  // Aspect ratios por imagen (width / height).
  List<double?> _cursoAspect = [];
  final List<_ImageStreamHandle> _prefetchHandles = [];

  Future<void> _loadCursos() async {
    _disposePrefetchHandles();
    setState(() {
      _loadingCursos = true;
      _errorCursos = null;
      _cursoRefs = [];
      _cursoUrls = [];
      _cursoAspect = [];
    });
    try {
      final list = await _storage.ref('cursos').listAll();
      final items = [...list.items]..sort((a, b) => a.name.compareTo(b.name));

      final urls = <String>[];
      for (final ref in items) {
        try {
          final url = await ref.getDownloadURL();
          urls.add(url);
        } catch (_) {}
      }
      if (!mounted) return;

      setState(() {
        _cursoRefs = items;
        _cursoUrls = urls;
        _cursoAspect = List<double?>.filled(urls.length, null);
        _loadingCursos = false;
      });

      _prefetchAspectRatios();
      _startAutoSlide();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCursos = 'No se pudieron cargar los cursos: $e';
        _loadingCursos = false;
      });
    }
  }

  void _prefetchAspectRatios() {
    if (!mounted) return;
    _disposePrefetchHandles();
    for (int i = 0; i < _cursoUrls.length; i++) {
      final provider = NetworkImage(_cursoUrls[i]);
      final stream = provider.resolve(const ImageConfiguration());
      final listener = ImageStreamListener((ImageInfo info, bool _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0 && mounted) {
          setState(() {
            if (i < _cursoAspect.length) {
              _cursoAspect[i] = w / h;
            }
          });
        }
      }, onError: (dynamic _, __) {
        if (mounted && i < _cursoAspect.length) {
          setState(() {
            _cursoAspect[i] = null;
          });
        }
      });
      stream.addListener(listener);
      _prefetchHandles.add(_ImageStreamHandle(stream, listener));
      precacheImage(provider, context);
    }
  }

  void _startAutoSlide() {
    _autoTimer?.cancel();
    if (_cursoUrls.isEmpty) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageCtrl.hasClients || _cursoUrls.isEmpty) return;
      final next = (_page + 1) % _cursoUrls.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _loadCursos();
  }

  @override
  void dispose() {
    _disposePrefetchHandles();
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Altura dinámica del carrusel según imagen actual + orientación
  double _carouselHeight(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width - 24; // padding horizontal 12+12
    final h = size.height;
    final isLandscape = size.width > size.height;

    final ratio = (_cursoAspect.isNotEmpty && _page < _cursoAspect.length)
        ? (_cursoAspect[_page] ?? (16 / 9))
        : (16 / 9);

    final rawH = w / ratio;
    // Topes más generosos en landscape para aprovechar pantallas anchas
    final maxH = h * (isLandscape ? 0.8 : 0.65);
    final minH = isLandscape ? 180.0 : 200.0;

    return rawH.clamp(minH, maxH);
  }

  void _disposePrefetchHandles() {
    for (final handle in _prefetchHandles) {
      handle.stream.removeListener(handle.listener);
    }
    _prefetchHandles.clear();
  }

  int? _carouselCacheWidth(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return null;
    final logicalWidth = (mq.size.width - 24).clamp(0.0, double.infinity);
    final pxWidth = logicalWidth * mq.devicePixelRatio;
    if (!pxWidth.isFinite || pxWidth <= 0) return null;
    final clamped = pxWidth.clamp(600, 3600);
    return clamped.round();
  }

  int? _fullscreenCacheWidth(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return null;
    final pxWidth = mq.size.width * mq.devicePixelRatio;
    if (!pxWidth.isFinite || pxWidth <= 0) return null;
    final clamped = pxWidth.clamp(800, 4096);
    return clamped.round();
  }

  int? _fullscreenCacheHeight(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return null;
    final pxHeight = mq.size.height * mq.devicePixelRatio;
    if (!pxHeight.isFinite || pxHeight <= 0) return null;
    final clamped = pxHeight.clamp(800, 4096);
    return clamped.round();
  }

  // -------- Visor Pantalla Completa ----------
  Future<void> _openFullScreen(int startIndex) async {
    if (_cursoUrls.isEmpty) return;
    final controller = PageController(initialPage: startIndex);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withOpacity(.9),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                PageView.builder(
                  controller: controller,
                  itemCount: _cursoUrls.length,
                  itemBuilder: (_, i) {
                    final url = _cursoUrls[i];
                    return Center(
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Hero(
                          tag: 'curso_$i',
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            cacheWidth: _fullscreenCacheWidth(context),
                            cacheHeight: _fullscreenCacheHeight(context),
                            filterQuality: FilterQuality.high,
                            loadingBuilder: (c, w, p) => p == null
                                ? w
                                : const SizedBox(
                                    height: 64,
                                    width: 64,
                                    child: CircularProgressIndicator(
                                      color: _CapColors.gold,
                                    ),
                                  ),
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: IconButton(
                    tooltip: 'Cerrar',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------- Redes sociales ----------
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
          color: _CapColors.gold,
        );

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
          onRefresh: _loadCursos,
          onProfile: () => Navigator.of(context).pushNamed('/perfil'),
        ),

        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              // Buscador global
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: _CapColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onSubmitted: (_) => _onSearch(),
                          cursorColor: _CapColors.gold,
                          style: const TextStyle(color: _CapColors.text),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Buscar en la app...',
                            hintStyle: TextStyle(color: _CapColors.textMuted),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _onSearch,
                        child: Container(
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
                      ),
                    ],
                  ),
                ),
              ),

              // PRÓXIMOS CURSOS
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    Text('PRÓXIMOS CURSOS', style: titleStyle),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Recargar',
                      onPressed: _loadCursos,
                      icon: const Icon(Icons.refresh, color: _CapColors.text),
                    ),
                  ],
                ),
              ),

              // Carrusel responsive (rellena contenedor)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    height: _loadingCursos || _cursoUrls.isEmpty
                        ? 200
                        : _carouselHeight(context),
                    color: _CapColors.surface,
                    child: _loadingCursos
                        ? const HomeModuleSkeleton()
                        : (_errorCursos != null)
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text(
                                    _errorCursos!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _CapColors.textMuted,
                                    ),
                                  ),
                                ),
                              )
                            : (_cursoUrls.isEmpty)
                                ? const Center(
                                    child: Text(
                                      'Aún no hay cursos publicados.',
                                      style: TextStyle(
                                        color: _CapColors.textMuted,
                                      ),
                                    ),
                                  )
                                : Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      PageView.builder(
                                        controller: _pageCtrl,
                                        itemCount: _cursoUrls.length,
                                        onPageChanged: (i) =>
                                            setState(() => _page = i),
                                        itemBuilder: (_, i) {
                                          final url = _cursoUrls[i];
                                          return GestureDetector(
                                            onTap: () => _openFullScreen(i),
                                            child: Hero(
                                              tag: 'curso_$i',
                                              child: Container(
                                                color: _CapColors.surfaceAlt,
                                                alignment: Alignment.center,
                                                child: Image.network(
                                                  url,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                  gaplessPlayback: true,
                                                  cacheWidth:
                                                      _carouselCacheWidth(context),
                                                  filterQuality:
                                                      FilterQuality.medium,
                                                  loadingBuilder: (c, w, p) =>
                                                      p == null
                                                          ? w
                                                          : const Center(
                                                              child:
                                                                  CircularProgressIndicator(
                                                                color:
                                                                    _CapColors
                                                                        .gold,
                                                              ),
                                                            ),
                                                  errorBuilder: (_, __, ___) =>
                                                      const Center(
                                                    child: Icon(
                                                      Icons
                                                          .image_not_supported_outlined,
                                                      color: Colors.white38,
                                                      size: 48,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      // Indicadores
                                      Positioned(
                                        bottom: 10,
                                        child: Row(
                                          children: List.generate(
                                            _cursoUrls.length,
                                            (i) => AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 3),
                                              height: 8,
                                              width: _page == i ? 20 : 8,
                                              decoration: BoxDecoration(
                                                color: _page == i
                                                    ? _CapColors.gold
                                                    : Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                  ),
                ),
              ),

              // CATEGORÍAS
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text('CATEGORÍAS', style: titleStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _CategoryButton(
                      icon: Icons.description_rounded,
                      label: 'Documentos',
                      onTap: () => Navigator.pushReplacementNamed(
                          context, '/biblioteca'),
                    ),
                    const SizedBox(width: 12),
                    _CategoryButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Videos',
                      onTap: () =>
                          Navigator.pushReplacementNamed(context, '/video'),
                    ),
                    const SizedBox(width: 12),
                    _CategoryButton(
                      icon: Icons.forum_rounded,
                      label: 'Chat',
                      onTap: () =>
                          Navigator.pushReplacementNamed(context, '/chat'),
                    ),
                    const SizedBox(width: 12),
                    _CategoryButton(
                      icon: Icons.favorite_rounded,
                      label: 'Favoritos',
                      onTap: () =>
                          Navigator.pushReplacementNamed(context, '/perfil'),
                    ),
                  ],
                ),
              ),

              // REDES SOCIALES
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text('REDES SOCIALES', style: titleStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SocialChip(
                      color: const Color(0xFF000000),
                      icon: Icons.music_note, // TikTok
                      label: '@capfiscal.corporativo',
                      onTap: () => _openUrl(
                          'https://www.tiktok.com/@capfiscal.corporativo'),
                    ),
                    _SocialChip(
                      color: Colors.red,
                      icon: Icons.ondemand_video, // YouTube
                      label: '@CapFiscalMéxico',
                      onTap: () => _openUrl(
                          'https://www.youtube.com/@CapFiscalM%C3%A9xico'),
                    ),
                    _SocialChip(
                      color: Colors.green,
                      icon: Icons.podcasts, // Spotify/Podcast
                      label: 'Capfiscal Sin Filtro',
                      onTap: () => _openUrl(
                          'https://open.spotify.com/show/7maJrFMnD8uyUfZkt1d5Xh?si=94736585551e4549'),
                    ),
                    _SocialChip(
                      color: Colors.purple,
                      icon: Icons.camera_alt, // Instagram
                      label: '@capfiscal.corporativo',
                      onTap: () => _openUrl(
                          'https://www.instagram.com/capfiscal.corporativo/?next=%2F'),
                    ),
                    _SocialChip(
                      color: Colors.blue,
                      icon: Icons.facebook, // Facebook
                      label: 'Capfiscal Corporativo',
                      onTap: () => _openUrl(
                          'https://www.facebook.com/CapFiscalCorporativo/'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // Bottom nav (Home = índice 2)
        bottomNavigationBar: CapfiscalBottomNav(
          currentIndex: 2,
          onTap: (i) {
            switch (i) {
              case 0:
                Navigator.pushReplacementNamed(context, '/biblioteca');
                break;
              case 1:
                Navigator.pushReplacementNamed(context, '/video');
                break;
              case 2:
                break;
              case 3:
                Navigator.pushReplacementNamed(context, '/chat');
                break;
              case 4:
                Navigator.pushReplacementNamed(context, '/perfil');
                break;
            }
          },
        ),
      ),
    );
  }
}

// ---------- Widgets auxiliares ----------

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: _CapColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: _CapColors.gold.withOpacity(.12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _CapColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialChip extends StatelessWidget {
  const _SocialChip({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _CapColors.surface,
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            const SizedBox(width: 2),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _CapColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
