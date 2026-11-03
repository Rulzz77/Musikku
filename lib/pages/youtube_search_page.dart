import 'dart:async';

import 'package:flutter/material.dart';

import '../services/search_suggest_service.dart';
import '../widgets/music_design.dart';

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
      YoutubeSearchRequest(query: q, mode: YoutubeSearchMode.music),
    );
  }


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
    const quickSearches = <String>[
      'Pop Indonesia', 'Dangdut', 'Dangdut Koplo', 'Campursari/Jawa',
      'Lagu Inggris', 'DJ Remix', 'K-pop', 'Rock Indonesia', 'Lagu akustik',
    ];

    return Scaffold(
      body: MusicBackdrop(
        child: MusicPageEntrance(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 12, 17, 15),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Kembali',
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MUSIKKU  /  SEARCH', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                            const SizedBox(height: 3),
                            Text('Temukan musik', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.graphic_eq_rounded, color: scheme.onPrimary),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 0, 17, 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _focus.hasFocus ? scheme.primary.withValues(alpha: 0.65) : scheme.outlineVariant.withValues(alpha: 0.75), width: _focus.hasFocus ? 1.4 : 1),
                    ),
                    child: Row(
                      children: [
                        Padding(padding: const EdgeInsets.only(left: 15, right: 9), child: Icon(Icons.search_rounded, color: scheme.primary, size: 23)),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            textInputAction: TextInputAction.search,
                            onSubmitted: _submit,
                            decoration: const InputDecoration(
                              hintText: 'Lagu, artis, album, atau suasana',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.symmetric(vertical: 17),
                            ),
                          ),
                        ),
                        if (typing)
                          IconButton(tooltip: 'Hapus teks', onPressed: _controller.clear, icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant)),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: IconButton.filled(
                            tooltip: 'Cari sekarang',
                            onPressed: () => _submit(_controller.text),
                            style: IconButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!typing && _history.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(19, 2, 19, 9),
                    child: Text('Jelajahi berdasarkan suasana', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(17, 0, 17, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < quickSearches.length; i++)
                          ActionChip(
                            avatar: Icon(i.isEven ? Icons.play_arrow_rounded : Icons.graphic_eq_rounded, size: 16),
                            label: Text(quickSearches[i]),
                            onPressed: () => _submit(quickSearches[i]),
                          ),
                      ],
                    ),
                  ),
                ],
                if (!typing && _history.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(19, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('Pencarian terakhir', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                        TextButton(onPressed: () async { await widget.onDeleteHistory(null); if (mounted) setState(() => _history.clear()); }, child: const Text('Hapus semua')),
                      ],
                    ),
                  ),
                if (typing || _history.isNotEmpty)
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 26),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => Divider(height: 1, indent: 46, color: scheme.outlineVariant.withValues(alpha: 0.55)),
                      itemBuilder: (context, index) {
                        final value = items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          leading: Container(width: 34, height: 34, decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)), child: Icon(typing ? Icons.search_rounded : Icons.history_rounded, color: scheme.onSurfaceVariant, size: 18)),
                          title: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          trailing: Icon(Icons.north_west_rounded, color: scheme.onSurfaceVariant, size: 17),
                          onTap: () => typing ? _submit(value) : _setSuggestion(value),
                          onLongPress: typing ? null : () async { await widget.onDeleteHistory(value); if (mounted) setState(() => _history.remove(value)); },
                        );
                      },
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
