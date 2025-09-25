import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineNote {
  OfflineNote({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OfflineNote.fromJson(Map<String, dynamic> json) {
    return OfflineNote(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class OfflineNotesRepository {
  static const _storageKey = 'offline_notes_v1';

  Future<List<OfflineNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => OfflineNote.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveNotes(List<OfflineNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(notes.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, payload);
  }
}

class OfflineNotesScreen extends StatefulWidget {
  const OfflineNotesScreen({super.key});

  @override
  State<OfflineNotesScreen> createState() => _OfflineNotesScreenState();
}

class _OfflineNotesScreenState extends State<OfflineNotesScreen> {
  final OfflineNotesRepository _repository = OfflineNotesRepository();
  List<OfflineNote> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await _repository.loadNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _save(List<OfflineNote> notes) async {
    await _repository.saveNotes(notes);
    if (!mounted) return;
    setState(() {
      _notes = notes;
    });
  }

  Future<void> _createNote() async {
    final result = await showModalBottomSheet<_NoteDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return const _NoteEditorSheet();
      },
    );
    if (result == null) return;

    final note = OfflineNote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: result.title,
      body: result.body,
      createdAt: DateTime.now(),
    );
    final updated = [note, ..._notes];
    await _save(updated);
  }

  Future<void> _deleteNote(String id) async {
    final updated = _notes.where((note) => note.id != id).toList();
    await _save(updated);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      appBar: AppBar(
        title: const Text('Notas guardadas'),
        backgroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNote,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text('Nueva nota'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const _EmptyNotes()
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (_, index) {
                    final note = _notes[index];
                    return Dismissible(
                      key: ValueKey(note.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.redAccent,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteNote(note.id),
                      child: _NoteTile(
                        note: note,
                        subtitle: _formatDate(note.createdAt),
                        onDelete: () => _deleteNote(note.id),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: _notes.length,
                ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.subtitle,
    required this.onDelete,
  });

  final OfflineNote note;
  final String subtitle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                note.body,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.note_alt_outlined, size: 72, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Todavía no registras notas offline.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Crea tu primera nota para guardar pendientes o recordatorios importantes.',
              style: TextStyle(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft({required this.title, required this.body});

  final String title;
  final String body;
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet();

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _NoteDraft(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          shrinkWrap: true,
          children: [
            const Text(
              'Nueva nota offline',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Título',
                counterText: '',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Escribe un título corto';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Contenido',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Completa tu nota';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar nota'),
            ),
          ],
        ),
      ),
    );
  }
}
