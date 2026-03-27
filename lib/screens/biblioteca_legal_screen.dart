// lib/screens/biblioteca_legal_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../helpers/favorites_manager.dart';
import '../helpers/view_mode.dart';
import '../services/doc_iap_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/custom_drawer.dart';

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
  static const Color success = Color(0xFF1F8B4C);
  static const Color successDark = Color(0xFF16653A);
}

/// Modelo: archivo dentro de un bundle
class BundleFile {
  final String id;
  final String name; // opcional, si no viene se usa el nombre del archivo
  final int order;
  final String storagePath; // ej: docs/djn_multas_contabilidad/archivo.docx
  final String type; // pdf/docx/etc (o extensión)

  const BundleFile({
    required this.id,
    required this.name,
    required this.order,
    required this.storagePath,
    required this.type,
  });

  String get fileNameFromPath {
    final parts = storagePath.split('/');
    return parts.isEmpty ? storagePath : parts.last;
  }

  factory BundleFile.fromMap(Map<String, dynamic> m) {
    final rawId = (m['id'] ?? '').toString().trim();
    final rawName = (m['name'] ?? '').toString().trim();
    final rawPath = (m['storagePath'] ?? '').toString().trim();
    final rawType = (m['type'] ?? '').toString().trim();
    final rawOrder = m['order'];

    final int parsedOrder = rawOrder is int
        ? rawOrder
        : int.tryParse((rawOrder ?? '').toString()) ?? 999;

    final fallbackName = rawPath.isEmpty ? 'Archivo' : rawPath.split('/').last;

    return BundleFile(
      id: rawId.isEmpty ? 'file' : rawId,
      name: rawName.isEmpty ? fallbackName : rawName,
      order: parsedOrder,
      storagePath: rawPath,
      type: rawType.isEmpty ? _extFromFilename(fallbackName) : rawType,
    );
  }

  static String _extFromFilename(String name) {
    final n = name.toLowerCase().trim();
    final dot = n.lastIndexOf('.');
    if (dot < 0 || dot == n.length - 1) return '';
    return n.substring(dot + 1);
  }
}

/// Modelo: bundle (documento) en Firestore /documents/{id}
class DocBundle {
  final String id; // docId
  final bool active;
  final String title;
  final String description;
  final int price;
  final String currency;
  final List<BundleFile> files;

  const DocBundle({
    required this.id,
    required this.active,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
    required this.files,
  });

  factory DocBundle.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final rawFiles =
        (d['files'] is List) ? List.from(d['files'] as List) : const [];

    final files = rawFiles
        .whereType<Map>()
        .map((e) => BundleFile.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return DocBundle(
      id: doc.id,
      active: (d['active'] == true),
      title: (d['title'] ?? doc.id).toString(),
      description: (d['description'] ?? '').toString(),
      price: (d['price'] is int)
          ? d['price'] as int
          : int.tryParse('${d['price'] ?? 0}') ?? 0,
      currency: (d['currency'] ?? 'MXN').toString(),
      files: files,
    );
  }
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

  static const String _thumbsFolder = 'docs_thumbs';

  bool _loading = true;
  List<DocBundle> _bundles = [];

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

  Set<String> _purchasedProductIds = <String>{};
  final Set<String> _purchaseInProgress = <String>{};

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
      onError: (e) {
        debugPrint('❌ purchaseStream error: $e');
      },
    );

    _fetchBundles();
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
  // Helpers
  // ─────────────────────────────
  String _productIdForBundle(DocBundle b) => 'capfiscal_bundle_${b.id}';
  String _bundleFavKey(DocBundle b) => 'bundle:${b.id}';
  String _docFavKey(BundleFile f) => 'doc:${f.storagePath}';

  String _extFromName(String name) {
    final n = name.toLowerCase().trim();
    final dot = n.lastIndexOf('.');
    if (dot < 0 || dot == n.length - 1) return '';
    return n.substring(dot + 1);
  }

  IconData _iconForFile(BundleFile f) {
    final e = f.type.isNotEmpty ? f.type.toLowerCase() : _extFromName(f.name);
    if (e == 'pdf') return Icons.picture_as_pdf;
    if (e == 'doc' || e == 'docx' || e == 'rtf' || e == 'txt')
      return Icons.description;
    if (e == 'xls' || e == 'xlsx' || e == 'csv') return Icons.table_chart;
    if (e == 'ppt' || e == 'pptx') return Icons.slideshow;
    if (e == 'png' || e == 'jpg' || e == 'jpeg' || e == 'webp' || e == 'gif')
      return Icons.image;
    if (e == 'zip' || e == 'rar' || e == '7z') return Icons.archive;
    return Icons.insert_drive_file;
  }

  // ─────────────────────────────
  // ✅ Thumb para bundle:
  // 1) docs_thumbs/<bundleId>.png/jpg/jpeg/webp
  // 2) fallback: docs_thumbs/<primer-archivo-sin-ext>.png...
  // ─────────────────────────────
  String _baseNameNoExt(String name) {
    var base = name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base;
  }

  Future<String?> _resolveThumbUrlForBundle(DocBundle b) async {
    final candidates = <String>[
      '$_thumbsFolder/${b.id}.png',
      '$_thumbsFolder/${b.id}.jpg',
      '$_thumbsFolder/${b.id}.jpeg',
      '$_thumbsFolder/${b.id}.webp',
    ];

    if (b.files.isNotEmpty) {
      final firstName = b.files.first.fileNameFromPath;
      final base = _baseNameNoExt(firstName);
      candidates.addAll([
        '$_thumbsFolder/$base.png',
        '$_thumbsFolder/$base.jpg',
        '$_thumbsFolder/$base.jpeg',
        '$_thumbsFolder/$base.webp',
      ]);
    }

    for (final path in candidates) {
      try {
        final url = await _storage.ref(path).getDownloadURL();
        return url;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _thumbUrlForBundle(DocBundle b) {
    return _thumbFutureCache.putIfAbsent(
        b.id, () => _resolveThumbUrlForBundle(b));
  }

  Widget _bundleThumb(DocBundle b) {
    return FutureBuilder<String?>(
      future: _thumbUrlForBundle(b),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Center(
            child: Icon(Icons.folder_zip, color: _CapColors.gold, size: 46),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(Icons.folder_zip, color: _CapColors.gold, size: 46),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────
  // ✅ Fetch bundles (Firestore) + IAP bootstrap
  // ─────────────────────────────
  Future<void> _fetchBundles() async {
    setState(() => _loading = true);

    try {
      debugPrint(
          '📦 Fetching bundles from Firestore: /documents where active==true');

      final snap = await FirebaseFirestore.instance
          .collection('documents')
          .where('active', isEqualTo: true)
          .orderBy(FieldPath.documentId)
          .get();

      final bundles = snap.docs.map(DocBundle.fromDoc).toList();

      debugPrint('📦 Bundles encontrados: ${bundles.length}');

      _bundles = bundles;

      // compras del usuario
      _purchasedProductIds = await _iap.loadPurchasedProductIds();

      // cargar catálogo IAP por bundle
      final productIds = _bundles.map(_productIdForBundle).toSet();
      await _iap.loadProducts(productIds);

      // restaurar compras
      await _iap.restorePurchases();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('❌ Error _fetchBundles: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar paquetes: $e')),
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

  bool _isPurchasedBundle(DocBundle b) {
    final productId = _productIdForBundle(b);
    return _purchasedProductIds.contains(productId);
  }

  // ─────────────────────────────
  // Download & open (por storagePath)
  // ─────────────────────────────
  Future<void> _downloadAndOpenStoragePath(String storagePath) async {
    try {
      final ref = _storage.ref(storagePath);
      final dir = await getApplicationDocumentsDirectory();
      final name = ref.name.isNotEmpty ? ref.name : storagePath.split('/').last;
      final file = File('${dir.path}/$name');

      if (!await file.exists()) {
        await ref.writeToFile(file);
      }
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir archivo: $e')),
      );
    }
  }

  Future<void> _buyBundle(DocBundle b) async {
    final productId = _productIdForBundle(b);

    if (!_iap.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Compras no disponibles en este dispositivo')),
      );
      return;
    }

    if (_purchasedProductIds.contains(productId)) {
      // ya comprado
      await _openBundle(b);
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
  // Bundle UI actions
  // ─────────────────────────────
  Future<void> _openBundle(DocBundle b) async {
    final purchased = _isPurchasedBundle(b);

    await showModalBottomSheet(
      context: context,
      backgroundColor: _CapColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final productId = _productIdForBundle(b);
            final busy = _purchaseInProgress.contains(productId);
            final priceLabel = _iap.products[productId]?.price;
            final buyLabel =
                priceLabel == null ? 'Comprar' : 'Comprar $priceLabel';

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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    b.title,
                    style: const TextStyle(
                      color: _CapColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (b.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      b.description,
                      style: const TextStyle(
                          color: _CapColors.textMuted, height: 1.25),
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Lista de archivos del bundle
                if (b.files.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Este paquete no tiene archivos configurados en Firestore (files[]).',
                      style: TextStyle(color: _CapColors.textMuted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: b.files.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12),
                      itemBuilder: (ctx, i) {
                        final f = b.files[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              Icon(_iconForFile(f), color: _CapColors.gold),
                          title: Text(
                            f.name,
                            style: const TextStyle(
                                color: _CapColors.text,
                                fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            f.storagePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _CapColors.textMuted),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FutureBuilder<bool>(
                                future: _isFavoriteForCurrentUser(
                                  _docFavKey(f),
                                ),
                                builder: (context, snap) {
                                  final fav = snap.data ?? false;
                                  return IconButton(
                                    tooltip: fav
                                        ? 'Quitar de favoritos'
                                        : 'Agregar a favoritos',
                                    onPressed: () async {
                                      await _toggleFavoriteForCurrentUser(
                                        _docFavKey(f),
                                      );
                                      if (mounted) {
                                        setState(() {});
                                        setSheetState(() {});
                                      }
                                    },
                                    icon: Icon(
                                      fav
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      color: fav
                                          ? _CapColors.gold
                                          : _CapColors.textMuted,
                                    ),
                                  );
                                },
                              ),
                              ElevatedButton(
                                onPressed: purchased
                                    ? () => _downloadAndOpenStoragePath(
                                          f.storagePath,
                                        )
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: purchased
                                      ? _CapColors.gold
                                      : Colors.white12,
                                  foregroundColor: purchased
                                      ? Colors.black
                                      : _CapColors.textMuted,
                                ),
                                child: Text(purchased ? 'Abrir' : 'Bloqueado'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          foregroundColor: _CapColors.text,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: busy
                            ? null
                            : purchased
                                ? () {
                                    // ya comprado, no hacemos nada extra
                                    Navigator.pop(context);
                                  }
                                : () async {
                                    Navigator.pop(context);
                                    await _buyBundle(b);
                                  },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          backgroundColor:
                              purchased ? _CapColors.success : _CapColors.gold,
                          foregroundColor:
                              purchased ? Colors.white : Colors.black,
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                purchased ? 'Comprado' : buyLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis,
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

  // ─────────────────────────────
  // Filters / favorites
  // ─────────────────────────────
  List<DocBundle> _applyFilters() {
    return _bundles.where((b) {
      final hay = ('${b.title} ${b.description}').toLowerCase();

      if (_search.isNotEmpty) {
        return hay.contains(_search.toLowerCase());
      }

      if (_activeCategories.isNotEmpty) {
        for (final cat in _activeCategories) {
          if (hay.contains(cat.toLowerCase())) return true;
        }
        return false;
      }

      return true;
    }).toList();
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

  Widget _favButtonForBundle(DocBundle b) {
    final key = _bundleFavKey(b);

    return FutureBuilder<bool>(
      future: _isFavoriteForCurrentUser(key),
      builder: (_, snap) {
        final fav = snap.data ?? false;
        return IconButton(
          tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
          onPressed: () => _toggleFavoriteForCurrentUser(key),
          icon: Icon(_favIcon(fav), color: _favColor(fav)),
        );
      },
    );
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
          'PAQUETES',
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
                        hintText: 'Buscar paquetes...',
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

  Widget _bundleActionsRow(DocBundle b) {
    final productId = _productIdForBundle(b);
    final purchased = _purchasedProductIds.contains(productId);
    final busy = _purchaseInProgress.contains(productId);

    final price = _iap.products[productId]?.price;
    final buyLabel = price == null ? 'Comprar' : 'Comprar $price';

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _openBundle(b),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: _CapColors.text,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Ver paquete'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: busy
                ? null
                : purchased
                    ? () => _openBundle(b)
                    : () => _buyBundle(b),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  purchased ? _CapColors.success : _CapColors.gold,
              foregroundColor: purchased ? Colors.white : Colors.black,
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
                    purchased ? 'Comprado' : buyLabel,
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
          onRefresh: _fetchBundles,
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
                            'No se encontraron paquetes',
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
                                final b = filtered[i];
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
                                              child: _bundleThumb(b),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              b.title,
                                              style: const TextStyle(
                                                color: _CapColors.text,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          _favButtonForBundle(b),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (b.description.trim().isNotEmpty)
                                        Text(
                                          b.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: _CapColors.textMuted),
                                        ),
                                      const SizedBox(height: 10),
                                      _bundleActionsRow(b),
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
                                mainAxisExtent: 300,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final b = filtered[i];
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
                                                onTap: () => _openBundle(b),
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
                                                  child: _bundleThumb(b),
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
                                                child: _favButtonForBundle(b),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        b.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _CapColors.text,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${b.files.length} archivo(s)',
                                        style: const TextStyle(
                                            color: _CapColors.textMuted),
                                      ),
                                      const SizedBox(height: 8),
                                      _bundleActionsRow(b),
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
