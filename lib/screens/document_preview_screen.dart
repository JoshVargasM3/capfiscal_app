// lib/screens/document_preview_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Paleta CAPFISCAL
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

class DocumentPreviewScreen extends StatefulWidget {
  const DocumentPreviewScreen({
    super.key,
    required this.docKey,
    required this.title, // nombre real del archivo en Storage (ej: "FORMATO.pdf")
    required this.storage,
    required this.isPurchased,
    this.maxPreviewPages = 1,
  });

  final String docKey;
  final String title;
  final FirebaseStorage storage;

  /// ✅ Si es true, el botón permite abrir el archivo completo.
  /// Si es false, muestra CTA para comprar.
  final bool isPurchased;

  /// ✅ Máximo de páginas a mostrar en vista previa (solo aplica a PDF)
  final int maxPreviewPages;

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  bool _loading = true;
  String? _error;

  File? _localFile;

  // PDF
  int _totalPages = 0;
  final List<Uint8List> _previewPages = [];
  int _pageIndex = 0;

  // Imagen / Thumbnail
  Uint8List? _singleImageBytes;

  // Texto
  String? _textPreview;

  // Visor web (Office/Google viewer)
  String? _viewerUrl;
  WebViewController? _webCtrl;

  static const String _docsFolder = 'docs';
  static const String _thumbsFolder = 'docs_thumbs';

  String _safeFileName(String name) => name.replaceAll(RegExp(r'[\/\\]'), '_');

  String _extLower(String name) {
    final n = name.toLowerCase().trim();
    final dot = n.lastIndexOf('.');
    if (dot < 0 || dot == n.length - 1) return '';
    return n.substring(dot + 1);
  }

  bool get _isPdf => _extLower(widget.title) == 'pdf';

  bool get _isImage {
    final e = _extLower(widget.title);
    return e == 'png' || e == 'jpg' || e == 'jpeg' || e == 'webp' || e == 'gif';
  }

  bool get _isText {
    final e = _extLower(widget.title);
    return e == 'txt' ||
        e == 'md' ||
        e == 'json' ||
        e == 'xml' ||
        e == 'csv' ||
        e == 'log';
  }

  bool get _isOffice {
    final e = _extLower(widget.title);
    return e == 'doc' ||
        e == 'docx' ||
        e == 'ppt' ||
        e == 'pptx' ||
        e == 'xls' ||
        e == 'xlsx' ||
        e == 'rtf';
  }

  String _baseNameNoExt(String name) {
    var base = name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base;
  }

  @override
  void initState() {
    super.initState();
    _loadAndRender();
  }

  Future<Uint8List?> _loadThumbBytesForFileName(String fileName) async {
    final base = _baseNameNoExt(fileName);

    final candidates = <String>[
      '$_thumbsFolder/$base.png',
      '$_thumbsFolder/$base.jpg',
      '$_thumbsFolder/$base.jpeg',
      '$_thumbsFolder/$base.webp',
    ];

    for (final path in candidates) {
      try {
        final bytes = await widget.storage.ref(path).getData(4 * 1024 * 1024);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _initWebViewer(String url) async {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() {
              _error = 'No se pudo cargar el visor: ${err.description}';
            });
          },
        ),
      );

    await ctrl.loadRequest(Uri.parse(url));
    _webCtrl = ctrl;
  }

  String _officeViewerUrl(String downloadUrl) {
    // Microsoft Office Online viewer
    final encoded = Uri.encodeComponent(downloadUrl);
    return 'https://view.officeapps.live.com/op/view.aspx?src=$encoded';
  }

  String _googleViewerUrl(String downloadUrl) {
    // Google docs viewer (fallback)
    final encoded = Uri.encodeComponent(downloadUrl);
    return 'https://docs.google.com/gview?embedded=1&url=$encoded';
  }

  Future<void> _loadAndRender() async {
    setState(() {
      _loading = true;
      _error = null;
      _previewPages.clear();
      _singleImageBytes = null;
      _textPreview = null;
      _viewerUrl = null;
      _webCtrl = null;
      _pageIndex = 0;
      _totalPages = 0;
    });

    try {
      final ref = widget.storage.ref('$_docsFolder/${widget.title}');
      if (!widget.isPurchased) {
        final thumb = await _loadThumbBytesForFileName(widget.title);
        if (!mounted) return;
        setState(() {
          _singleImageBytes = thumb;
          _loading = false;
        });
        return;
      }

      final tmp = await getTemporaryDirectory();
      final local = File('${tmp.path}/${_safeFileName(widget.title)}');

      // Descarga desde Storage: docs/<archivo.ext>
      await ref.writeToFile(local);
      _localFile = local;

      // 1) PDF -> render de páginas como imágenes (limitado)
      if (_isPdf) {
        final doc = await PdfDocument.openFile(local.path);
        _totalPages = doc.pagesCount;

        final limit = _totalPages < widget.maxPreviewPages
            ? _totalPages
            : widget.maxPreviewPages;

        for (int i = 1; i <= limit; i++) {
          final page = await doc.getPage(i);

          final img = await page.render(
            width: page.width * 2.0,
            height: page.height * 2.0,
            format: PdfPageImageFormat.png,
          );

          await page.close();
          if (img != null) _previewPages.add(img.bytes);
        }

        await doc.close();

        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      // 2) Imagen -> mostrarla directo (como “1 página”)
      if (_isImage) {
        final bytes = await local.readAsBytes();
        if (!mounted) return;
        setState(() {
          _singleImageBytes = bytes;
          _loading = false;
        });
        return;
      }

      // 3) Texto -> mostrar extracto legible
      if (_isText) {
        final bytes = await local.readAsBytes();
        String txt;
        try {
          txt = utf8.decode(bytes);
        } catch (_) {
          txt = latin1.decode(bytes, allowInvalid: true);
        }

        // limitamos tamaño para no reventar UI/memoria
        if (txt.length > 30000) {
          txt = '${txt.substring(0, 30000)}\n\n…(vista previa recortada)…';
        }

        if (!mounted) return;
        setState(() {
          _textPreview = txt;
          _loading = false;
        });
        return;
      }

      // 4) Otros tipos (DOCX/XLSX/PPTX/RTF/etc)
      // Comprado: usar viewer web con downloadURL
      final downloadUrl = await ref.getDownloadURL();
      final viewer = _isOffice
          ? _officeViewerUrl(downloadUrl)
          : _googleViewerUrl(downloadUrl);

      await _initWebViewer(viewer);

      if (!mounted) return;
      setState(() {
        _viewerUrl = viewer;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openFullIfPurchased() async {
    if (!widget.isPurchased) return;
    final f = _localFile;
    if (f == null) return;
    await OpenFilex.open(f.path);
  }

  Widget _legendCard() {
    final limited = !widget.isPurchased;
    final isPdf = _isPdf;

    final msg = limited
        ? (isPdf
            ? 'Vista previa limitada a ${widget.maxPreviewPages} páginas.\nPara consultar el documento completo y editarlo, realiza la compra.'
            : 'Vista previa limitada.\nPara consultar el archivo completo y editarlo, realiza la compra.')
        : 'Documento comprado ✅\nPuedes abrir el archivo completo para editarlo.';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _CapColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            limited ? Icons.lock_outline : Icons.verified,
            color: _CapColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: _CapColors.text,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctaButton() {
    if (widget.isPurchased) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: ElevatedButton.icon(
          onPressed: _openFullIfPurchased,
          style: ElevatedButton.styleFrom(
            backgroundColor: _CapColors.gold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text(
            'Abrir archivo completo',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    // 👇 Regresa "true" a Biblioteca para que dispare la compra
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: ElevatedButton.icon(
        onPressed: () => Navigator.of(context).pop(true),
        style: ElevatedButton.styleFrom(
          backgroundColor: _CapColors.gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.shopping_cart_checkout),
        label: const Text(
          'Consultar completo (Comprar)',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _whiteViewerContainer({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.white,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shownPdf = _previewPages.length;
    final hasPdfPages = shownPdf > 0;

    final pageLabel = hasPdfPages ? 'Página ${_pageIndex + 1}/$shownPdf' : '';

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
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: _CapColors.text),
          title: const Text(
            'Vista previa',
            style: TextStyle(
              color: _CapColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            if (pageLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    pageLabel,
                    style: const TextStyle(
                      color: _CapColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_CapColors.gold),
                ),
              )
            : (_error != null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No se pudo cargar la vista previa:\n$_error',
                        style: const TextStyle(color: _CapColors.text),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: () {
                          // A) PDF: páginas renderizadas
                          if (hasPdfPages) {
                            return PageView.builder(
                              itemCount: shownPdf,
                              onPageChanged: (i) =>
                                  setState(() => _pageIndex = i),
                              itemBuilder: (_, i) {
                                return _whiteViewerContainer(
                                  child: InteractiveViewer(
                                    minScale: 1.0,
                                    maxScale: 4.0,
                                    child: Center(
                                      child: Image.memory(
                                        _previewPages[i],
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }

                          // B) Imagen/Thumb: 1 “página”
                          if (_singleImageBytes != null) {
                            return _whiteViewerContainer(
                              child: InteractiveViewer(
                                minScale: 1.0,
                                maxScale: 4.0,
                                child: Center(
                                  child: Image.memory(
                                    _singleImageBytes!,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            );
                          }

                          // C) Texto
                          if (_textPreview != null) {
                            return _whiteViewerContainer(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(14),
                                child: SelectableText(
                                  _textPreview!,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    height: 1.25,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }

                          // D) Visor web (comprado)
                          if (_viewerUrl != null && _webCtrl != null) {
                            return _whiteViewerContainer(
                              child: WebViewWidget(controller: _webCtrl!),
                            );
                          }

                          // E) No hay preview posible
                          return const Center(
                            child: Text(
                              'Sin vista previa para mostrar.\n(Agrega un thumbnail en docs_thumbs para este archivo)',
                              style: TextStyle(color: _CapColors.textMuted),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }(),
                      ),
                      _legendCard(),
                      _ctaButton(),
                    ],
                  ),
      ),
    );
  }
}
