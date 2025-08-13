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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilters();

    return Scaffold(
      key: _scaffoldKey,
      drawer: const CustomDrawer(),

      // === TOP BAR estilo CAPFISCAL (con logo 1x/2x/3x) ===
      appBar: CapfiscalTopBar(
        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
        onRefresh: _fetchFiles,
        onProfile: () => Navigator.of(context).pushNamed('/perfil'),
      ),

      body: Column(
        children: [
          // Barra "Regresar"
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, size: 18),
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Regresar',
                      style: TextStyle(color: Colors.black87)),
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
                'ARCHIVOS',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
              ),
            ),
          ),

          // Buscador + Toggle vista + Filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: _viewMode == ViewMode.list
                      ? 'Vista lista'
                      : 'Vista cuadricula',
                  onPressed: () => setState(() {
                    _viewMode = _viewMode == ViewMode.list
                        ? ViewMode.grid
                        : ViewMode.list;
                  }),
                  icon: Icon(_viewMode == ViewMode.list
                      ? Icons.view_list
                      : Icons.grid_view_rounded),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      onChanged: (q) => setState(() {
                        _search = q;
                        _activeCategory = '';
                      }),
                      decoration: InputDecoration(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        hintText: 'Buscar documentos...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
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
                          borderSide:
                              BorderSide(color: Color(0xFF6B1A1A), width: 1.2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _openFiltersSheet,
                  icon: const Icon(Icons.filter_list),
                  label: const Text('Filtros'),
                  style: TextButton.styleFrom(foregroundColor: Colors.black87),
                ),
              ],
            ),
          ),

          // Contenido
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('No se encontraron documentos'))
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
    );
  }
}
