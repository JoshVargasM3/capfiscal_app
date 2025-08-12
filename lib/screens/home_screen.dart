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

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static const _brand = Color(0xFF6B1A1A);

  // -------- BUSCADOR ----------
  final _searchCtrl = TextEditingController();

  void _onSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;

    // Pequeña selección para “buscar en…”
    final where = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Buscar en…',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Documentos'),
              onTap: () => Navigator.pop(context, 'docs'),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: const Text('Videos'),
              onTap: () => Navigator.pop(context, 'videos'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (!mounted || where == null) return;

    if (where == 'docs') {
      // Si tu pantalla de biblioteca soporta argumentos, los enviamos
      Navigator.pushNamed(context, '/biblioteca', arguments: {'query': q});
    } else if (where == 'videos') {
      Navigator.pushNamed(context, '/video', arguments: {'query': q});
    }
  }

  // -------- CARRUSEL ----------
  final _pageCtrl = PageController(viewportFraction: .92);
  int _page = 0;
  Timer? _autoTimer;

  // Reemplaza estas rutas por tus flyers reales (assets o URLs)
  final List<Widget> _flyers = List.generate(
    4,
    (i) => Container(
      decoration: BoxDecoration(
        color: const Color(0xFFECE6E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
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
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
          color: _brand,
        );

    return Scaffold(
      key: _scaffoldKey,
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
            // (sin "Regresar" en Home)

            // Buscador global
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _onSearch(),
                  decoration: InputDecoration(
                    hintText: 'Buscar en la app...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Buscar',
                      onPressed: _onSearch,
                      icon: const Icon(Icons.manage_search),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Colors.black26),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Colors.black26),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide(color: _brand, width: 1.2),
                    ),
                  ),
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
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: 8,
                              width: _page == i ? 20 : 8,
                              decoration: BoxDecoration(
                                color: _page == i ? _brand : Colors.black26,
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

            // SECCIONES
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('SECCIONES', style: titleStyle),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _SectionButton(
                    icon: Icons.menu_book,
                    label: 'Biblioteca',
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/biblioteca'),
                  ),
                  const SizedBox(width: 16),
                  _SectionButton(
                    icon: Icons.play_circle_fill,
                    label: 'Videos',
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/video'),
                  ),
                  const SizedBox(width: 16),
                  _SectionButton(
                    icon: Icons.forum,
                    label: 'Chat',
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/chat'),
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
              // ya estás en Home
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

// ---------- Widgets auxiliares ----------

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const _brand = Color(0xFF6B1A1A);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: _brand,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
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
          color: Colors.white,
          border: Border.all(color: color.withOpacity(.5)),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
