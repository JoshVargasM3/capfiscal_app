// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/custom_drawer.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';

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

  // -------- CARRUSEL ----------
  final _pageCtrl = PageController(viewportFraction: .92);
  int _page = 0;
  Timer? _autoTimer;

  final List<Widget> _flyers = List.generate(
    4,
    (i) => Container(
      decoration: BoxDecoration(
        color: const Color(0xFFECE6E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Icon(Icons.image, size: 80, color: Colors.black26),
      ),
    ),
  );

  void _startAutoSlide() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_page + 1) % _flyers.length;
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
    _startAutoSlide();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
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
        // Gris claro abajo → negro arriba (más notorio)
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
          onRefresh: () {}, // hook si quieres recargar algo en Home
          onProfile: () => Navigator.of(context).pushNamed('/perfil'),
        ),

        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              // Buscador global (oscuro + botón dorado)
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
                child: Text('PRÓXIMOS CURSOS', style: titleStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        PageView.builder(
                          controller: _pageCtrl,
                          itemCount: _flyers.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, i) => _flyers[i],
                        ),
                        // Indicadores
                        Positioned(
                          bottom: 10,
                          child: Row(
                            children: List.generate(
                              _flyers.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                height: 8,
                                width: _page == i ? 20 : 8,
                                decoration: BoxDecoration(
                                  color: _page == i
                                      ? _CapColors.gold
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(10),
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

              // CATEGORÍAS (secciones rápidas)
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: _CapColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
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
