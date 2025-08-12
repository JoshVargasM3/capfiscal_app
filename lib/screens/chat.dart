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

class _ChatScreenState extends State<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Mensajes de ejemplo. Integra tu backend cuando gustes.
  final List<Map<String, String>> _messages = <Map<String, String>>[
    {'sender': 'capfiscal', 'text': '¡Hola! ¿En qué puedo ayudarte?'},
    {'sender': 'user', 'text': 'Quiero saber sobre mi suscripción.'},
  ];

  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  static const _brand = Color(0xFF6B1A1A);

  void _sendMessage() {
    final txt = _textCtrl.text.trim();
    if (txt.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': txt});
      _textCtrl.clear();
    });

    // Desplaza la lista al final para ver el mensaje nuevo
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const CustomDrawer(),

      // Top bar unificado
      appBar: CapfiscalTopBar(
        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
        onRefresh: () => setState(() {}), // aquí puedes recargar mensajes
        onProfile: () => Navigator.of(context).pushNamed('/perfil'),
      ),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                  ),
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
            child: Text(
              'CHAT',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: _brand,
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

          // Caja de texto + enviar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0x11000000)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      minLines: 1,
                      maxLines: 5,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        filled: true,
                        fillColor: const Color(0xFFE7E7E7),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    width: 44,
                    child: Ink(
                      decoration: const ShapeDecoration(
                        color: _brand,
                        shape: CircleBorder(),
                      ),
                      child: IconButton(
                        tooltip: 'Enviar',
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom nav unificado
      bottomNavigationBar: CapfiscalBottomNav(
        currentIndex: 3, // Chat
        onTap: (i) {
          switch (i) {
            case 0:
              Navigator.pushReplacementNamed(context, '/biblioteca');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/video');
              break;
            case 2:
              // Si tienes Home, ve a Home. De momento regresamos a biblioteca.
              Navigator.pushReplacementNamed(context, '/biblioteca');
              break;
            case 3:
              // Ya estás en chat
              break;
          }
        },
      ),
    );
  }
}

/// Burbuja de mensaje con estilos de la app
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isCapfiscal,
  });

  final String text;
  final bool isCapfiscal;

  static const _brand = Color(0xFF6B1A1A);

  @override
  Widget build(BuildContext context) {
    final bg = isCapfiscal ? _brand : const Color(0xFFE7E7E7);
    final fg = isCapfiscal ? Colors.white : Colors.black87;
    final align = isCapfiscal ? Alignment.centerLeft : Alignment.centerRight;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft:
          isCapfiscal ? const Radius.circular(2) : const Radius.circular(14),
      bottomRight:
          isCapfiscal ? const Radius.circular(14) : const Radius.circular(2),
    );

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border:
              isCapfiscal ? null : Border.all(color: _brand.withOpacity(.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Text(text, style: TextStyle(color: fg, fontSize: 15)),
      ),
    );
  }
}
