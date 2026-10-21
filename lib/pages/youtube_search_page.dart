import 'dart:async';

import 'package:flutter/material.dart';

import '../services/search_suggest_service.dart';

/// Mode pencarian MusikKu: katalog lagu saja.
enum YoutubeSearchMode { music }

class YoutubeSearchRequest {
  final String query;
  final YoutubeSearchMode mode;

  const YoutubeSearchRequest({required this.query, required this.mode});
}

/// Pencarian musik: saran kata kunci dan riwayat lokal.
class YoutubeSearchPage extends StatefulWidget {
  final String initialQuery;
  final List<String> history;
  final SearchSuggestService suggestService;
  final Future<void> Function(String? query) onDeleteHistory;

  const YoutubeSearchPage({
    super.key,
    required this.suggestService,
    required this.onDeleteHistory,
    this.initialQuery = '',
    this.history = const [],
  });

  @override
  State<YoutubeSearchPage> createState() => _YoutubeSearchPageState();
}

class _YoutubeSearchPageState extends State<YoutubeSearchPage> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  Timer? _debounce;
  List<String> _suggestions = const [];
  late List<String> _history;
  int _requestId = 0;
  int _mode = 0;

  static const _modes = <({String label, IconData icon})>[
    (label: 'Musik', icon: Icons.music_note_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _history = List<String>.from(widget.history);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _controller.addListener(_onChanged);
    if (widget.initialQuery.isNotEmpty) _onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 240), () async {
      final id = ++_requestId;
      try {
        final result = await widget.suggestService.suggest(text);
        if (!mounted || id != _requestId) return;
        setState(() => _suggestions = result);
      } catch (_) {
        if (mounted && id == _requestId) setState(() => _suggestions = const []);
      }
    });
  }

  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    Navigator.of(context).pop(
      YoutubeSearchRequest(query: q, mode: _modesForIndex(_mode)),
    );
  }

  YoutubeSearchMode _modesForIndex(int _) => YoutubeSearchMode.music;

  void _setSuggestion(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typing = _controller.text.trim().isNotEmpty;
    final items = typing ? _suggestions : _history;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 46,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Cari lagu, artis, album, atau remix',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: typing
                  ? IconButton(
                      tooltip: 'Hapus',
                      onPressed: _controller.clear,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Cari',
            onPressed: () => _submit(_controller.text),
            icon: Icon(Icons.arrow_forward_rounded, color: scheme.primary),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              scrollDirection: Axis.horizontal,
              itemCount: _modes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final mode = _modes[index];
                return ChoiceChip(
                  selected: _mode == index,
                  showCheckmark: false,
                  avatar: Icon(mode.icon, size: 16),
                  label: Text(mode.label),
                  onSelected: (_) {
                    setState(() => _mode = index);
                    if (_controller.text.trim().isNotEmpty) {
                      // Mode adalah affordance discovery; request akhir tetap
                      // dikendalikan oleh Hub agar API usage tidak dobel.
                      _focus.requestFocus();
                    }
                  },
                );
              },
            ),
          ),
          if (!typing && _history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 10, 8),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 17, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Pencarian terakhir', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant))),
                  TextButton(
                    onPressed: () async {
                      setState(() => _history.clear());
                      await widget.onDeleteHistory(null);
                    },
                    child: const Text('Hapus semua'),
                  ),
                ],
              ),
            ),
          if (typing && _suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Saran untuk “${_controller.text.trim()}”', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          Expanded(
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final text = items[index];
                return Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: Icon(typing ? Icons.search_rounded : Icons.history_rounded, size: 18, color: scheme.onPrimaryContainer),
                    ),
                    title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: typing
                        ? IconButton(
                            tooltip: 'Isi pencarian',
                            icon: Icon(Icons.north_west_rounded, size: 18, color: scheme.onSurfaceVariant),
                            onPressed: () => _setSuggestion(text),
                          )
                        : IconButton(
                            tooltip: 'Hapus dari riwayat',
                            icon: Icon(Icons.close_rounded, size: 19, color: scheme.onSurfaceVariant),
                            onPressed: () async {
                              setState(() => _history.removeWhere((item) => item.toLowerCase() == text.toLowerCase()));
                              await widget.onDeleteHistory(text);
                            },
                          ),
                    onTap: () => _submit(text),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
