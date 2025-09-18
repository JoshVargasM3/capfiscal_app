// lib/screens/biblioteca_legal_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ UID para favoritos por usuario

import '../widgets/filters_sheet.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/file_grid_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';

import '../helpers/favorites_manager.dart';
import '../helpers/view_mode.dart';

/// === Paleta nueva CAPFISCAL (oscuro + dorado) ===
class _CapColors {
  static const Color bgTop = Color(0xFF0A0A0B); // negro más profundo arriba
  static const Color bgMid = Color(0xFF2A2A2F); // gris oscuro intermedio
  static const Color bgBottom =
      Color(0xFF4A4A50); // gris más claro abajo (más notorio)
  static const Color surface = Color(0xFF1C1C21);
  static const Color white = Colors.white;
  static const Color text = Color(0xFFEFEFEF);
  static const Color textMuted = Color(0xFFBEBEC6);
  static const Color gold = Color(0xFFE1B85C); // acento
  static const Color goldDark = Color(0xFFB88F30);
}

class BibliotecaLegalScreen extends StatefulWidget {
  const BibliotecaLegalScreen({super.key});

  @override
  State<BibliotecaLegalScreen> createState() => _BibliotecaLegalScreenState();
}

class _BibliotecaLegalScreenState extends State<BibliotecaLegalScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // ✅

  List<Reference> _files = [];
  bool _loading = true;

  String _search = '';
  String _activeCategory = '';
  ViewMode _viewMode = ViewMode.list;

  final List<String> _categories = const [
    'Demanda',
    'Contrato',
    'Juicio',
    'Requisición'
  ];

  bool _appliedRouteQuery =
      false; // para aplicar argumentos de búsqueda una sola vez

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  // Si vienes desde Home con arguments: {'query': '...'} lo aplicamos 1 sola vez
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedRouteQuery) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map &&
        args['query'] is String &&
        (args['query'] as String).isNotEmpty) {
      setState(() {
        _search = (args['query'] as String).trim();
        _activeCategory = '';
        _appliedRouteQuery = true;
      });
    } else {
      _appliedRouteQuery = true;
    }
  }

  Future<void> _fetchFiles() async {
    setState(() => _loading = true);
    try {
      final result = await _storage.ref('/').listAll();
      setState(() {
        _files = result.items;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar archivos: $e')),
        );
      }
    }
  }

  Future<void> _downloadAndOpenFile(Reference ref) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${ref.name}');
      if (!await file.exists()) await ref.writeToFile(file);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  List<Reference> _applyFilters() {
    return _files.where((f) {
      final name = f.name.toLowerCase();
      if (_search.isNotEmpty) return name.contains(_search.toLowerCase());
      if (_activeCategory.isNotEmpty) {
        return name.contains(_activeCategory.toLowerCase());
      }
      return true;
    }).toList();
  }

  void _openFiltersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _CapColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => FiltersSheet(
        categories: _categories,
        activeCategory: _activeCategory,
        onApply: (sel) {
          setState(() {
            _activeCategory = sel ?? '';
            _search = '';
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  // === Helpers favoritos por usuario ===

  Future<bool> _isFavoriteForCurrentUser(String itemKey) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false; // si no hay sesión, no hay favs
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
    if (mounted) setState(() {}); // refresca íconos
  }

  // === Widgets de UI nueva ===

  Widget _topBackBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
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
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'ARCHIVOS',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _CapColors.text,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
        ),
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          // Toggle vista
          InkWell(
            onTap: () => setState(() {
              _viewMode =
                  _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
            }),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                _viewMode == ViewMode.list
                    ? Icons.view_list
                    : Icons.grid_view_rounded,
                color: _CapColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Search
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A2A2F), Color(0xFF232329)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white12,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, color: _CapColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (q) => setState(() {
                        _search = q;
                        _activeCategory = '';
                      }),
                      cursorColor: _CapColors.gold,
                      style: const TextStyle(color: _CapColors.text),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Buscar documentos...',
                        hintStyle: TextStyle(color: _CapColors.textMuted),
                      ),
                    ),
                  ),
                  // Botón dorado
                  GestureDetector(
                    onTap: () {}, // buscador es reactivo; mantenemos el look
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
          const SizedBox(width: 8),
          // Filtros (outline dorado)
          OutlinedButton.icon(
            onPressed: _openFiltersSheet,
            icon:
                const Icon(Icons.filter_list, size: 18, color: _CapColors.gold),
            label: const Text('Filtros',
                style: TextStyle(
                    color: _CapColors.gold, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _CapColors.goldDark, width: 1),
              foregroundColor: _CapColors.gold,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilters();

    return Container(
      decoration: const BoxDecoration(
        // 🔥 Degradado más notorio: gris claro (abajo) → negro (arriba)
        gradient: LinearGradient(
          colors: [_CapColors.bgBottom, _CapColors.bgMid, _CapColors.bgTop],
          stops: [0.0, 0.4, 1.0],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        drawer: const CustomDrawer(),

        // === TOP BAR estilo CAPFISCAL (con logo 1x/2x/3x) ===
        appBar: CapfiscalTopBar(
          onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          onRefresh: _fetchFiles,
          onProfile: () => Navigator.of(context).pushNamed('/perfil'),
        ),

        body: Column(
          children: [
            _topBackBar(),
            _headline(),
            _searchRow(),

            // Contenido
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_CapColors.gold),
                      ),
                    )
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No se encontraron documentos',
                            style: TextStyle(color: _CapColors.textMuted),
                          ),
                        )
                      : (_viewMode == ViewMode.list
                          ? ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final ref = filtered[i];
                                return FileListTile(
                                  name: ref.name,
                                  onTap: () => _downloadAndOpenFile(ref),
                                  // ✅ favoritos por usuario
                                  isFavoriteFuture:
                                      _isFavoriteForCurrentUser(ref.name),
                                  onToggleFavorite: () =>
                                      _toggleFavoriteForCurrentUser(ref.name),
                                );
                              },
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: .78,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final ref = filtered[i];
                                return FileGridCard(
                                  name: ref.name,
                                  onTap: () => _downloadAndOpenFile(ref),
                                  // ✅ favoritos por usuario
                                  isFavoriteFuture:
                                      _isFavoriteForCurrentUser(ref.name),
                                  onToggleFavorite: () =>
                                      _toggleFavoriteForCurrentUser(ref.name),
                                );
                              },
                            )),
            ),
          ],
        ),

        // === BOTTOM NAV estilo mockup ===
        // 👉 Deja SIN onTap para usar la navegación por defecto:
        // ['/biblioteca', '/video', '/home', '/chat']
        bottomNavigationBar: const CapfiscalBottomNav(
          currentIndex: 0, // Biblioteca
        ),
      ),
    );
  }
}
