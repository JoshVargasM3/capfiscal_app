// lib/screens/chat.dart
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../widgets/custom_drawer.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_bottom_nav.dart';

/// Entrada FAQ reutilizable para mantener la lógica desacoplada de la UI.
class FaqEntry {
  const FaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    required this.keywords,
    this.requiresEscalation = false,
    this.preferSpecialist = false,
  });

  final String id;
  final String question;
  final String answer;
  final List<String> keywords;
  final bool requiresEscalation;
  final bool preferSpecialist;
}

enum ChatAuthor { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.author,
    required this.text,
    this.timestamp,
    this.escalation,
  });

  final ChatAuthor author;
  final String text;
  final DateTime? timestamp;
  final ChatEscalation? escalation;

  ChatMessage copyWith({ChatEscalation? escalation}) => ChatMessage(
        author: author,
        text: text,
        timestamp: timestamp,
        escalation: escalation ?? this.escalation,
      );
}

class ChatEscalation {
  const ChatEscalation({
    required this.topic,
    this.preferSpecialist = false,
  });

  final String topic;
  final bool preferSpecialist;
}

class AssistantReply {
  const AssistantReply({
    required this.text,
    this.requiresEscalation = false,
    this.preferSpecialist = false,
  });

  final String text;
  final bool requiresEscalation;
  final bool preferSpecialist;
}

/// Pequeño motor de FAQ para mantener testable la lógica de respuestas.
class ChatAssistant {
  ChatAssistant({required List<FaqEntry> faqs})
      : _faqs = List<FaqEntry>.from(faqs);

  final List<FaqEntry> _faqs;

  AssistantReply reply(String question) {
    final normalized = question.toLowerCase().trim();
    final match = _faqs.firstWhere(
      (faq) => faq.keywords.any(normalized.contains),
      orElse: () => const FaqEntry(
        id: 'default',
        question: 'default',
        answer:
            'Puedo ayudarte con preguntas frecuentes como pagos, facturación y acceso a cursos.',
        keywords: <String>[],
        requiresEscalation: true,
      ),
    );

    return AssistantReply(
      text: match.answer,
      requiresEscalation: match.requiresEscalation,
      preferSpecialist: match.preferSpecialist,
    );
  }
}

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

  final List<ChatMessage> _messages = <ChatMessage>[
    ChatMessage(
      author: ChatAuthor.assistant,
      text:
          '¡Hola! Soy tu asistente CAPFISCAL. Pregunta por pagos, facturación o cursos y te responderé al instante.',
      timestamp: DateTime.now(),
    ),
  ];

  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final ChatAssistant _assistant;

  @override
  void initState() {
    super.initState();
    _assistant = ChatAssistant(faqs: _faqEntries);
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

  Future<void> _sendMessage() async {
    final txt = _textCtrl.text.trim();
    if (txt.isEmpty) return;

    final userMessage = ChatMessage(
      author: ChatAuthor.user,
      text: txt,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _textCtrl.clear();
    });

    Future.delayed(const Duration(milliseconds: 80), _animateToEnd);

    final reply = _assistant.reply(txt);
    final response = ChatMessage(
      author: ChatAuthor.assistant,
      text: reply.text,
      timestamp: DateTime.now(),
      escalation: reply.requiresEscalation
          ? ChatEscalation(
              topic: txt,
              preferSpecialist: reply.preferSpecialist,
            )
          : null,
    );

    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    setState(() {
      _messages.add(response);
    });
    Future.delayed(const Duration(milliseconds: 120), _animateToEnd);
  }

  Future<void> _openSpecialistSheet(String topic) async {
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: topic);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _CapColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Comparte tus datos y te enlazamos con un especialista.',
                style: TextStyle(
                  color: _CapColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _SpecialistField(
                controller: nameCtrl,
                hint: 'Nombre completo',
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 8),
              _SpecialistField(
                controller: contactCtrl,
                hint: 'Teléfono o correo',
                icon: Icons.phone_outlined,
              ),
              const SizedBox(height: 8),
              _SpecialistField(
                controller: noteCtrl,
                hint: 'Tema a tratar',
                icon: Icons.note_alt_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _CapColors.gold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    final composed =
                        'Tema: ${noteCtrl.text}\nNombre: ${nameCtrl.text}\nContacto: ${contactCtrl.text}';
                    _sendEscalationEmail(composed);
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Compartir con especialista'),
                ),
              ),
            ],
          ),
        );
      },
    );
    nameCtrl.dispose();
    contactCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _sendEscalationEmail(String topic) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'capfiscal.app@gmail.com',
      queryParameters: {
        'subject': 'Asistencia CAPFISCAL',
        'body': 'Hola equipo CAPFISCAL, necesito ayuda con:\n$topic\n\nEnviado desde la app.',
      },
    );
    try {
      final launched = await launchUrl(uri);
      if (!mounted) return;
      if (launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abrimos tu app de correo.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No pudimos abrir el correo, escríbenos a capfiscal.app@gmail.com.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar el correo: $e')),
      );
    }
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    final didPop = await navigator.maybePop();
    if (!mounted || didPop || !navigator.mounted) return;
    navigator.pushReplacementNamed('/home');
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
                      ),
                    ),
                  ],
                ),
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
                  final isAssistant = msg.author == ChatAuthor.assistant;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MessageBubble(
                        text: msg.text,
                        isCapfiscal: isAssistant,
                      ),
                      if (msg.escalation != null && isAssistant)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ChatEscalationCard(
                            escalation: msg.escalation!,
                            onContactSpecialist: _openSpecialistSheet,
                            onSendEmail: _sendEscalationEmail,
                          ),
                        ),
                    ],
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

class ChatEscalationCard extends StatelessWidget {
  const ChatEscalationCard({
    required this.escalation,
    required this.onContactSpecialist,
    required this.onSendEmail,
  });

  final ChatEscalation escalation;
  final Future<void> Function(String topic) onContactSpecialist;
  final Future<void> Function(String topic) onSendEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _CapColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                escalation.preferSpecialist
                    ? Icons.support_agent
                    : Icons.outgoing_mail,
                color: _CapColors.gold,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  escalation.preferSpecialist
                      ? 'Necesitamos un especialista para este tema.'
                      : '¿Quieres que lo revise alguien de nuestro equipo?',
                  style: const TextStyle(
                    color: _CapColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onContactSpecialist(escalation.topic),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Contactar especialista'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _CapColors.gold,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => onSendEmail(escalation.topic),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Enviar correo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpecialistField extends StatelessWidget {
  const _SpecialistField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: _CapColors.text),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _CapColors.textMuted),
        hintText: hint,
        hintStyle: const TextStyle(color: _CapColors.textMuted),
        filled: true,
        fillColor: _CapColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _CapColors.gold),
        ),
      ),
    );
  }
}

final List<FaqEntry> _faqEntries = <FaqEntry>[
  const FaqEntry(
    id: 'suscripcion_estado',
    question: '¿Mi suscripción está activa?',
    answer:
        'Puedes revisar el estado y la fecha de renovación en tu Perfil > Datos de la suscripción. Si aparece "Expira pronto" te avisaremos con 3 días de anticipación.',
    keywords: <String>['suscripción', 'estado', 'vigencia', 'renovación'],
  ),
  const FaqEntry(
    id: 'metodos_pago',
    question: '¿Cómo actualizo mi tarjeta?',
    answer:
        'Desde tu Perfil ahora puedes editar el método principal o agregar una tarjeta alterna. Usamos Stripe para resguardar los datos.',
    keywords: <String>['método', 'tarjeta', 'pago', 'actualizar'],
  ),
  const FaqEntry(
    id: 'facturacion',
    question: 'Necesito una factura',
    answer:
        'Envíanos tu RFC y uso de CFDI respondiendo este chat o por correo a capfiscal.app@gmail.com para emitir la factura en menos de 24h.',
    keywords: <String>['factura', 'facturación', 'cfdi', 'rfc'],
    requiresEscalation: true,
    preferSpecialist: true,
  ),
  const FaqEntry(
    id: 'asesoria',
    question: 'Requiero asesoría personalizada',
    answer:
        'Con gusto te enlazamos con un especialista fiscal. Compártenos tu tema y medio de contacto.',
    keywords: <String>['asesoría', 'especialista', 'ayuda'],
    requiresEscalation: true,
    preferSpecialist: true,
  ),
];
