// lib/screens/biblioteca_legal_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/custom_drawer.dart';

import '../helpers/favorites_manager.dart';
import '../helpers/view_mode.dart';

import '../services/doc_iap_service.dart';
import 'document_preview_screen.dart';

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
  const BibliotecaLegalScreen({
    super.key,
    this.storage,
    this.auth,
  });

  final FirebaseStorage? storage;
  final FirebaseAuth? auth;

  @override
  State<BibliotecaLegalScreen> createState() => _BibliotecaLegalScreenState();
}

class _BibliotecaLegalScreenState extends State<BibliotecaLegalScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final FirebaseStorage _storage;
  late final FirebaseAuth _auth;

  late final DocIapService _iap;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  // ✅ Carpetas “fuente de verdad”
  static const String _docsFolder = 'docs';
  static const String _thumbsFolder = 'docs_thumbs';

  List<Reference> _files = [];
  bool _loading = true;

  String _search = '';
  final Set<String> _activeCategories = <String>{};
  ViewMode _viewMode = ViewMode.grid;

  final List<String> _categories = const [
    'Demanda',
    'Contrato',
    'Juicio',
    'Requisición'
  ];

  bool _appliedRouteQuery = false;

  /// Compras y estados UI
  Set<String> _purchasedProductIds = <String>{};
  final Set<String> _purchaseInProgress = <String>{};

  /// ✅ Cache de thumbnails (para que NO “parpadeen” ni se pidan 50 veces)
  final Map<String, Future<String?>> _thumbFutureCache = {};

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? FirebaseStorage.instance;
    _auth = widget.auth ?? FirebaseAuth.instance;

    _iap = DocIapService(
      auth: _auth,
      firestore: FirebaseFirestore.instance,
    );

    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_) {},
    );

    _fetchFiles();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
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

  // ─────────────────────────────
  // Helpers: docKey/productId
  // ─────────────────────────────
  String _docKeyFromFilename(String name) {
    var base = name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);

    base = base.toLowerCase().trim();
    base = base.replaceAll(RegExp(r'\s+'), '_');
    base = base.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
    return base;
  }

  String _baseNameNoExt(String name) {
    var base = name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base;
  }

  String _ext(String name) {
    final n = name.toLowerCase().trim();
    final dot = n.lastIndexOf('.');
    if (dot < 0 || dot == n.length - 1) return '';
    return n.substring(dot + 1);
  }

  bool _isPdf(Reference ref) => _ext(ref.name) == 'pdf';

  bool _isImage(Reference ref) {
    final e = _ext(ref.name);
    return e == 'png' || e == 'jpg' || e == 'jpeg' || e == 'webp' || e == 'gif';
  }

  IconData _iconForRef(Reference ref) {
    final e = _ext(ref.name);
    if (e == 'pdf') return Icons.picture_as_pdf;
    if (e == 'doc' || e == 'docx' || e == 'rtf' || e == 'txt') {
      return Icons.description;
    }
    if (e == 'xls' || e == 'xlsx' || e == 'csv') return Icons.table_chart;
    if (e == 'ppt' || e == 'pptx') return Icons.slideshow;
    if (_isImage(ref)) return Icons.image;
    if (e == 'zip' || e == 'rar' || e == '7z') return Icons.archive;
    return Icons.insert_drive_file;
  }

  /// Product ID que debes crear en iOS/Android stores.
  /// EJ: capfiscal_doc_contrato_arrendamiento_v1
  String _productIdForRef(Reference ref) {
    final key = _docKeyFromFilename(ref.name);
    return 'capfiscal_doc_$key';
  }

  // ─────────────────────────────
  // ✅ Thumbnail: docs_thumbs/<base>.png (o fallback jpg/jpeg/webp)
  // ─────────────────────────────
  Future<String?> _resolveThumbUrl(Reference docRef) async {
    final base = _baseNameNoExt(docRef.name);

    final candidates = <String>[
      '$_thumbsFolder/$base.png',
      '$_thumbsFolder/$base.jpg',
      '$_thumbsFolder/$base.jpeg',
      '$_thumbsFolder/$base.webp',
    ];

    for (final path in candidates) {
      try {
        final url = await _storage.ref(path).getDownloadURL();
        return url;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _thumbUrlForDoc(Reference docRef) {
    final key = docRef.fullPath; // "docs/xxx.ext"
    return _thumbFutureCache.putIfAbsent(key, () => _resolveThumbUrl(docRef));
  }

  Widget _docThumb(Reference docRef) {
    return FutureBuilder<String?>(
      future: _thumbUrlForDoc(docRef),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Center(
            child: Icon(
              _iconForRef(docRef),
              color: _CapColors.gold,
              size: 42,
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(
                _iconForRef(docRef),
                color: _CapColors.gold,
                size: 42,
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────
  // Fetch + IAP bootstrap
  // ─────────────────────────────
  Future<void> _fetchFiles() async {
    setState(() => _loading = true);

    try {
      final result = await _storage.ref(_docsFolder).listAll();

      // ✅ Ahora mostramos TODO tipo de documento (no solo PDF)
      _files = result.items.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _thumbFutureCache.removeWhere(
        (k, _) => !_files.any((r) => r.fullPath == k),
      );

      // 1) Compras del usuario (Firestore)
      _purchasedProductIds = await _iap.loadPurchasedProductIds();

      // 2) Catálogo IAP (para todos los docs)
      final productIds = _files.map(_productIdForRef).toSet();
      await _iap.loadProducts(productIds);

      // 3) Restaurar compras (store)
      await _iap.restorePurchases();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar archivos: $e')),
      );
    }
  }

  // ─────────────────────────────
  // Purchases stream handler
  // ─────────────────────────────
  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final productId = p.productID;

      if (p.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchaseInProgress.add(productId));
        continue;
      }

      if (p.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() => _purchaseInProgress.remove(productId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compra fallida: ${p.error}')),
          );
        }
      }

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        try {
          await _iap.grantEntitlement(p);
          _purchasedProductIds.add(productId);

          if (mounted) {
            setState(() => _purchaseInProgress.remove(productId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Compra confirmada ✅')),
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() => _purchaseInProgress.remove(productId));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo aplicar la compra: $e')),
            );
          }
        }
      }

      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }

  bool _isPurchased(Reference ref) {
    final productId = _productIdForRef(ref);
    return _purchasedProductIds.contains(productId);
  }

  // ─────────────────────────────
  // Preview / download / buy
  // ─────────────────────────────
  Future<void> _openPreview(Reference ref) async {
    final purchased = _isPurchased(ref);

    // ✅ Solo PDFs van al preview renderizado
    if (_isPdf(ref)) {
      final docKey = _docKeyFromFilename(ref.name);

      final bool? wantsBuy = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            docKey: docKey,
            title: ref.name,
            storage: _storage,
            isPurchased: purchased,
            maxPreviewPages: 1, // ajusta a 1 o 2 según quieras
          ),
        ),
      );

      if (wantsBuy == true && !purchased) {
        await _buy(ref);
      }
      return;
    }

    // ✅ Para otros tipos: evitamos crash y mostramos CTA limpia
    final bool? action = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _CapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          ref.name,
          style: const TextStyle(
            color: _CapColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          purchased
              ? 'Este tipo de archivo no tiene vista previa dentro de la app.\nPuedes abrirlo completo.'
              : 'Este tipo de archivo no tiene vista previa dentro de la app.\nPara consultarlo completo y editarlo, realiza la compra.',
          style: const TextStyle(color: _CapColors.textMuted, height: 1.25),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: _CapColors.text,
            ),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _CapColors.gold,
              foregroundColor: Colors.black,
            ),
            icon: Icon(purchased ? Icons.open_in_new : Icons.shopping_cart),
            label: Text(
              purchased ? 'Abrir archivo' : 'Comprar',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (action == true) {
      if (purchased) {
        await _downloadAndOpenFile(ref);
      } else {
        await _buy(ref);
      }
    }
  }

  Future<void> _downloadAndOpenFile(Reference ref) async {
    if (!_isPurchased(ref)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes comprar este documento para descargarlo'),
        ),
      );
      return;
    }

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

  Future<void> _buy(Reference ref) async {
    final productId = _productIdForRef(ref);

    if (!_iap.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compras no disponibles en este dispositivo'),
        ),
      );
      return;
    }

    if (_purchasedProductIds.contains(productId)) {
      await _downloadAndOpenFile(ref);
      return;
    }

    try {
      if (mounted) setState(() => _purchaseInProgress.add(productId));
      await _iap.buyNonConsumable(productId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchaseInProgress.remove(productId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la compra: $e')),
      );
    }
  }

  // ─────────────────────────────
  // Filters / favorites
  // ─────────────────────────────
  List<Reference> _applyFilters() {
    return _files.where((f) {
      final name = f.name.toLowerCase();

      if (_search.isNotEmpty) {
        return name.contains(_search.toLowerCase());
      }

      if (_activeCategories.isNotEmpty) {
        for (final cat in _activeCategories) {
          if (name.contains(cat.toLowerCase())) return true;
        }
        return false;
      }

      return true;
    }).toList();
  }

  void _openFiltersSheet() {
    final Set<String> tempSel = Set<String>.from(_activeCategories);

    showModalBottomSheet(
      context: context,
      backgroundColor: _CapColors.surface,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
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
                              setSheetState(() {
                                if (val) {
                                  tempSel.add(c);
                                } else {
                                  tempSel.remove(c);
                                }
                              });
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

  Color _favColor(bool fav) => fav ? _CapColors.gold : _CapColors.goldDark;

  IconData _favIcon(bool fav) =>
      fav ? Icons.star_rounded : Icons.star_border_rounded;

  Widget _favButton(Reference ref) {
    return FutureBuilder<bool>(
      future: _isFavoriteForCurrentUser(ref.name),
      builder: (_, snap) {
        final fav = snap.data ?? false;
        return IconButton(
          tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
          onPressed: () => _toggleFavoriteForCurrentUser(ref.name),
          icon: Icon(_favIcon(fav), color: _favColor(fav)),
        );
      },
    );
  }

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
                        _activeCategories.clear();
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
          OutlinedButton.icon(
            onPressed: _openFiltersSheet,
            icon:
                const Icon(Icons.filter_list, size: 18, color: _CapColors.gold),
            label: Text(
              _activeCategories.isEmpty
                  ? 'Filtros'
                  : 'Filtros (${_activeCategories.length})',
              style: const TextStyle(
                color: _CapColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _CapColors.goldDark, width: 1),
              foregroundColor: _CapColors.gold,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _docActionsRow(Reference ref) {
    final productId = _productIdForRef(ref);
    final purchased = _purchasedProductIds.contains(productId);
    final busy = _purchaseInProgress.contains(productId);

    final price = _iap.products[productId]?.price; // ej "$19.00"
    final buyLabel = price == null ? 'Comprar' : 'Comprar $price';

    final previewLabel = _isPdf(ref) ? 'Vista previa (1 pág.)' : 'Vista previa';

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _openPreview(ref),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: _CapColors.text,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(previewLabel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: busy
                ? null
                : purchased
                    ? () => _downloadAndOpenFile(ref)
                    : () => _buy(ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: _CapColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    purchased ? 'Descargar' : buyLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
      ],
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
                              physics: const BouncingScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final ref = filtered[i];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _CapColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: SizedBox(
                                              width: 52,
                                              height: 52,
                                              child: _docThumb(ref),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              ref.name,
                                              style: const TextStyle(
                                                color: _CapColors.text,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          _favButton(ref),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      _docActionsRow(ref),
                                    ],
                                  ),
                                );
                              },
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              physics: const BouncingScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 290,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final ref = filtered[i];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _CapColors.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: InkWell(
                                                onTap: () => _openPreview(ref),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                    color: Colors.white
                                                        .withOpacity(.05),
                                                    border: Border.all(
                                                        color: Colors.white10),
                                                  ),
                                                  child: _docThumb(ref),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withOpacity(.35),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: Colors.white12),
                                                ),
                                                child: _favButton(ref),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        ref.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _CapColors.text,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _docActionsRow(ref),
                                    ],
                                  ),
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
