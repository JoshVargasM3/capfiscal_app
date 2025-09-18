// lib/screens/chat.dart
import 'package:flutter/material.dart';

import '../widgets/custom_drawer.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// 🎨 Paleta CAPFISCAL
class _CapColors {
  static const bgTop = Color(0xFF0A0A0B);
  static const bgMid = Color(0xFF2A2A2F);
  static const bgBottom = Color(0xFF4A4A50);
  static const surface = Color(0xFF1C1C21);
  static const surfaceAlt = Color(0xFF2A2A2F);
  static const text = Color(0xFFEFEFEF);
  static const textMuted = Color(0xFFBEBEC6);
  static const gold = Color(0xFFE1B85C);
  static const goldDark = Color(0xFFB88F30);
}

class _ChatScreenState extends State<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Mensajes de ejemplo. Integra tu backend cuando gustes.
  final List<Map<String, String>> _messages = <Map<String, String>>[
    {'sender': 'capfiscal', 'text': '¡Hola! ¿En qué puedo ayudarte?'},
    {'sender': 'user', 'text': 'Quiero saber sobre mi suscripción.'},
  ];

  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  void _jumpToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  void _animateToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent + 60,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _sendMessage() {
    final txt = _textCtrl.text.trim();
    if (txt.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': txt});
      _textCtrl.clear();
    });

    Future.delayed(const Duration(milliseconds: 80), _animateToEnd);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Degradado más notorio de gris (abajo) a negro (arriba)
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

        // Top bar unificado
        appBar: CapfiscalTopBar(
          onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          onRefresh: () => setState(() {}),
          onProfile: () => Navigator.of(context).pushNamed('/perfil'),
        ),

        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra "Regresar" oscura
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
                    ),
                  ),
                ],
              ),
            ),

            // Título dorado
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Text(
                'CHAT',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _CapColors.gold,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .6,
                    ),
              ),
            ),

            // Lista de mensajes
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) {
                  final msg = _messages[i];
                  final isCapfiscal = msg['sender'] == 'capfiscal';
                  return _MessageBubble(
                    text: msg['text'] ?? '',
                    isCapfiscal: isCapfiscal,
                  );
                },
              ),
            ),

            // Caja de texto + enviar (oscura + botón dorado)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
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
                        child: TextField(
                          controller: _textCtrl,
                          minLines: 1,
                          maxLines: 5,
                          onSubmitted: (_) => _sendMessage(),
                          cursorColor: _CapColors.gold,
                          style: const TextStyle(color: _CapColors.text),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Escribe un mensaje...',
                            hintStyle: TextStyle(color: _CapColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      width: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
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
                        child: IconButton(
                          tooltip: 'Enviar',
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Bottom nav: ['/biblioteca', '/video', '/home', '/chat']
        bottomNavigationBar: const CapfiscalBottomNav(currentIndex: 3),
      ),
    );
  }
}

/// Burbuja de mensaje con estilos CAPFISCAL
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isCapfiscal,
  });

  final String text;
  final bool isCapfiscal;

  @override
  Widget build(BuildContext context) {
    final align = isCapfiscal ? Alignment.centerLeft : Alignment.centerRight;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft:
          isCapfiscal ? const Radius.circular(4) : const Radius.circular(14),
      bottomRight:
          isCapfiscal ? const Radius.circular(14) : const Radius.circular(4),
    );

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          // Capfiscal (bot) = burbuja oscura; Usuario = dorado
          color: isCapfiscal ? _CapColors.surface : null,
          gradient: isCapfiscal
              ? null
              : const LinearGradient(
                  colors: [_CapColors.gold, _CapColors.goldDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          border: isCapfiscal ? Border.all(color: Colors.white12) : null,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isCapfiscal ? _CapColors.text : Colors.black,
            fontSize: 15,
            fontWeight: isCapfiscal ? FontWeight.w500 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
