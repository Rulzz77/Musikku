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
      'Pop Indonesia',
      'Dangdut',
      'Dangdut Koplo',
      'Campursari/Jawa',
      'Lagu Inggris',
      'DJ Remix',
      'K-pop',
      'Rock Indonesia',
      'Lagu akustik',
    ];

    return Scaffold(
      body: MusicBackdrop(child: MusicPageEntrance(child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 18, 14),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Kembali',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Temukan musik',
                          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.7),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          typing ? 'Pilih saran atau lanjutkan pencarian' : 'Cari lagu, artis, album, atau remix',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.graphic_eq_rounded, color: scheme.onPrimary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _focus.hasFocus ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.55), width: _focus.hasFocus ? 1.4 : 1),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 15, right: 9),
                      child: Icon(Icons.search_rounded, color: scheme.primary, size: 25),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _submit,
                        decoration: const InputDecoration(
                          hintText: 'Lagu atau nama artis…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 17),
                        ),
                      ),
                    ),
                    if (typing)
                      IconButton(
                        tooltip: 'Hapus teks',
                        onPressed: _controller.clear,
                        icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: IconButton.filled(
                        tooltip: 'Cari sekarang',
                        onPressed: () => _submit(_controller.text),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!typing && _history.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text('Mulai dari suasana favoritmu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: scheme.onSurface)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final query in quickSearches)
                      ActionChip(
                        avatar: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(query),
                        onPressed: () => _submit(query),
                      ),
                  ],
                ),
              ),
            ],
            if (!typing && _history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Pencarian terakhir', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
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
            if (typing)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 17, color: scheme.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _suggestions.isEmpty ? 'Mencari saran…' : 'Saran untuk “${_controller.text.trim()}”',
                        style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                    if (_suggestions.isNotEmpty) Text('${_suggestions.length}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(typing ? Icons.search_off_rounded : Icons.headphones_rounded, size: 38, color: scheme.onPrimary),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              typing ? 'Belum ada saran' : 'Musik favoritmu dimulai di sini',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              typing ? 'Coba kata kunci lain atau langsung tekan tombol panah untuk mencari.' : 'Ketik judul lagu atau pilih salah satu ide pencarian di atas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 26),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final text = items[index];
                        return Material(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _submit(text),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(13)),
                                    child: Icon(typing ? Icons.search_rounded : Icons.history_rounded, color: scheme.onPrimaryContainer, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                                  if (typing)
                                    IconButton(
                                      tooltip: 'Isi pencarian',
                                      icon: Icon(Icons.north_west_rounded, size: 19, color: scheme.onSurfaceVariant),
                                      onPressed: () => _setSuggestion(text),
                                    )
                                  else
                                    IconButton(
                                      tooltip: 'Hapus dari riwayat',
                                      icon: Icon(Icons.close_rounded, size: 19, color: scheme.onSurfaceVariant),
                                      onPressed: () async {
                                        setState(() => _history.removeWhere((item) => item.toLowerCase() == text.toLowerCase()));
                                        await widget.onDeleteHistory(text);
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ))),
    );
  }
}
