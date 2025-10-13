// lib/screens/biblioteca_legal_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ UID para favoritos por usuario

import '../widgets/file_list_tile.dart';
import '../widgets/file_grid_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';

import '../helpers/subscription_guard.dart';

import '../helpers/favorites_manager.dart';
import '../helpers/view_mode.dart';

/// === Paleta CAPFISCAL (oscuro + dorado) ===
class _CapColors {
  static const Color bgTop = Color(0xFF0A0A0B);
  static const Color bgMid = Color(0xFF2A2A2F);
  static const Color bgBottom = Color(0xFF4A4A50);
  static const Color surface = Color(0xFF1C1C21);
  static const Color text = Color(0xFFEFEFEF);
  static const Color textMuted = Color(0xFFBEBEC6);
  static const Color gold = Color(0xFFE1B85C);
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Reference> _files = [];
  bool _loading = true;

  String _search = '';

  /// 🔁 Antes: String _activeCategory
  /// Ahora: múltiples categorías activas
  final Set<String> _activeCategories = <String>{};

  /// 👉 Arranca en GRID para ver **2 columnas grandes**
  ViewMode _viewMode = ViewMode.grid;

  final List<String> _categories = const [
    'Demanda',
    'Contrato',
    'Juicio',
    'Requisición'
  ];

  bool _appliedRouteQuery = false;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

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
        _activeCategories.clear();
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
    if (!await SubscriptionGuard.ensureActive(context)) return;
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

      // búsqueda por texto (tiene prioridad)
      if (_search.isNotEmpty) {
        return name.contains(_search.toLowerCase());
      }

      // si hay categorías activas: coincide con CUALQUIERA de ellas
      if (_activeCategories.isNotEmpty) {
        for (final cat in _activeCategories) {
          if (name.contains(cat.toLowerCase())) return true;
        }
        return false;
      }

      // sin filtros
      return true;
    }).toList();
  }

  void _openFiltersSheet() {
    // copia local editable, iniciada con las activas actuales
    final Set<String> tempSel = Set<String>.from(_activeCategories);

    showModalBottomSheet(
      context: context,
      backgroundColor: _CapColors.surface,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        // StatefulBuilder para refrescar el contenido del sheet
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Filtros',
                        style: TextStyle(
                          color: _CapColors.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Chips multi-selección con aplicación en tiempo real
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _categories.map((c) {
                          final selected = tempSel.contains(c);
                          return FilterChip(
                            label: Text(
                              c,
                              style: TextStyle(
                                color:
                                    selected ? Colors.black : _CapColors.text,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            backgroundColor: const Color(0xFF2C2C31),
                            selectedColor: _CapColors.gold,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected
                                    ? _CapColors.goldDark
                                    : Colors.white24,
                              ),
                            ),
                            selected: selected,
                            onSelected: (val) {
                              // actualiza selección local
                              setSheetState(() {
                                if (val) {
                                  tempSel.add(c);
                                } else {
                                  tempSel.remove(c);
                                }
                              });
                              // aplica inmediatamente a la pantalla de atrás
                              setState(() {
                                _activeCategories
                                  ..clear()
                                  ..addAll(tempSel);
                                _search = '';
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              // limpia en ambos lados
                              setSheetState(() => tempSel.clear());
                              setState(() {
                                _activeCategories.clear();
                                _search = '';
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _CapColors.text,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Limpiar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: _CapColors.gold,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text(
                              'Cerrar',
                              style: TextStyle(fontWeight: FontWeight.w800),
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

  // === Favoritos por usuario ===
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

  // === UI ===
  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    final didPop = await navigator.maybePop();
    if (!mounted || didPop || !navigator.mounted) return;
    navigator.pushReplacementNamed('/home');
  }

  Widget _topBackBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: InkWell(
        onTap: _handleBack,
        borderRadius: BorderRadius.circular(24),
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
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
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
                    ? Icons.grid_view_rounded
                    : Icons.view_list,
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
                border: Border.all(color: Colors.white12),
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
                        _activeCategories
                            .clear(); // al buscar, se limpian chips
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
                  // Botón dorado (look)
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
                    child:
                        const Icon(Icons.search, size: 18, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filtros
          OutlinedButton.icon(
            onPressed: _openFiltersSheet,
            icon:
                const Icon(Icons.filter_list, size: 18, color: _CapColors.gold),
            label: Text(
              _activeCategories.isEmpty
                  ? 'Filtros'
                  : 'Filtros (${_activeCategories.length})',
              style: const TextStyle(
                  color: _CapColors.gold, fontWeight: FontWeight.w600),
            ),
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

                          /// --- LISTA ---
                          ? ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              physics: const BouncingScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final ref = filtered[i];
                                return FileListTile(
                                  name: ref.name,
                                  onTap: () => _downloadAndOpenFile(ref),
                                  isFavoriteFuture:
                                      _isFavoriteForCurrentUser(ref.name),
                                  onToggleFavorite: () =>
                                      _toggleFavoriteForCurrentUser(ref.name),
                                );
                              },
                            )

                          /// --- GRID 2 columnas GRANDES ---
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              physics: const BouncingScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2, // 👈 SIEMPRE 2 columnas
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 240, // tarjetas altas
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final ref = filtered[i];
                                return FileGridCard(
                                  name: ref.name,
                                  onTap: () => _downloadAndOpenFile(ref),
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
        bottomNavigationBar: const CapfiscalBottomNav(currentIndex: 0),
      ),
    );
  }
}
