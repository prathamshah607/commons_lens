import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'search_models.dart';
import 'search_url_codec.dart';

// -----------------------------------------------------------------------------
// Top Bar
// -----------------------------------------------------------------------------

class SearchTopBar extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdvanced;

  const SearchTopBar({
    super.key,
    required this.initialQuery,
    required this.onSearch,
    required this.onAdvanced,
  });

  @override
  State<SearchTopBar> createState() => _SearchTopBarState();
}

class _SearchTopBarState extends State<SearchTopBar> {
  late TextEditingController _controller;
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _listener = () => setState(() {});
    _controller.addListener(_listener!);
  }
  
  @override
  void didUpdateWidget(SearchTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery && _controller.text != widget.initialQuery) {
      _controller.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    if (_listener != null) _controller.removeListener(_listener!);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text('WIKI\nMEDIA', style: TextStyle(color: Color(0xFF3D7EFF), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2.5, height: 1.5)),
            ),
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  keyboardType: TextInputType.url, textInputAction: TextInputAction.search, autocorrect: false, enableSuggestions: false, spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
                  controller: _controller,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search media…', hintStyle: const TextStyle(color: Color(0xFF3A3A3A), fontSize: 14),
                    filled: true, fillColor: const Color(0xFF181818),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3D7EFF), width: 1)),
                    suffixIcon: _controller.text.isNotEmpty ? GestureDetector(
                      onTap: () {
                        _controller.clear();
                        widget.onSearch('');
                      }, 
                      child: const Icon(Icons.close, size: 15, color: Color(0xFF3A3A3A))) : null,
                  ),
                  onSubmitted: widget.onSearch,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF2A2A2A)), foregroundColor: const Color(0xFFB0B0B0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: widget.onAdvanced,
                child: const Text('Filters', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3D7EFF), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), padding: const EdgeInsets.symmetric(horizontal: 18)),
                onPressed: () => widget.onSearch(_controller.text),
                child: const Text('Search', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Landing / Empty State UI
// -----------------------------------------------------------------------------

class WikiLogo extends StatelessWidget {
  const WikiLogo({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E1E1E)), color: const Color(0xFF141414)),
      child: const Icon(Icons.perm_media_rounded, size: 26, color: Color(0xFF3D7EFF)),
    );
  }
}

class ExampleChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const ExampleChip({super.key, required this.label, required this.onTap});
  @override
  State<ExampleChip> createState() => _ExampleChipState();
}

class _ExampleChipState extends State<ExampleChip> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true), onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: _hovered ? const Color(0xFF191919) : const Color(0xFF141414), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF242424))),
          child: Text(widget.label, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Media Card Ecosystem
// -----------------------------------------------------------------------------

class MediaCard extends StatefulWidget {
  final SearchItem item;
  final ValueNotifier<List<SearchItem>> searchResultsNotifier;
  final VoidCallback onLoadMore;
  final int index;
  final SearchState searchState;

  const MediaCard({
    super.key,
    required this.item,
    required this.searchResultsNotifier,
    required this.onLoadMore,
    required this.index,
    required this.searchState,
  });
  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;

  Future<void> _handleTap() async {
    final params = <String, String>{'id': widget.item.title, ...SearchUrlCodec.toQueryParams(widget.searchState)};
    final searchUrl = GoRouterState.of(context).uri.toString();
    final uniqueUrl = Uri(path: '/view', queryParameters: params).toString();
    
    context.go(
      uniqueUrl,
      extra: ViewerState(notifier: widget.searchResultsNotifier, index: widget.index, onLoadMore: widget.onLoadMore, searchState: widget.searchState, returnUrl: searchUrl),
    );
  }

  Future<void> _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: widget.item.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media URL copied'), duration: Duration(seconds: 2)),
      );
    }
  }

  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.image: return Icons.image_outlined;
      case MediaKind.vector: return Icons.polyline_outlined;
      case MediaKind.audio: return Icons.graphic_eq_outlined;
      case MediaKind.video: return Icons.videocam_outlined;
      case MediaKind.document: return Icons.description_outlined;
      case MediaKind.unknown: return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final kind = item.mediaKind;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true), onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _handleTap, onLongPress: _copyUrl,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140), clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFF131313), borderRadius: BorderRadius.circular(8), border: Border.all(color: _hovered ? const Color(0xFF3D7EFF).withOpacity(0.55) : const Color(0xFF202020))),
          child: Stack(
            children: [
              Positioned.fill(child: MediaPreview(item: item, index: widget.index)),
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF2A2A2A))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconForKind(kind), size: 12, color: const Color(0xFFCACACA)),
                      const SizedBox(width: 5),
                      Text(item.extension.isEmpty ? item.mime.toUpperCase() : item.extension.toUpperCase(), style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(_hovered ? 0.08 : 0.0), Colors.black.withOpacity(0.82)])),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25)),
                      const SizedBox(height: 4),
                      Text(item.snippet.isEmpty ? item.mime : item.snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 11, height: 1.35)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaPreview extends StatefulWidget {
  final SearchItem item;
  final int index;
  const MediaPreview({super.key, required this.item, required this.index});
  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  bool _shouldLoad = false;
  @override
  void initState() {
    super.initState();
    final slot = widget.index % 25;
    if (slot == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _shouldLoad = true); });
    } else {
      Future.delayed(Duration(milliseconds: slot * 30), () { if (mounted) setState(() => _shouldLoad = true); });
    }
  }
  @override
  void dispose() {
    if (_shouldLoad) {
      final thumb = widget.item.thumb;
      if (thumb.isNotEmpty) PaintingBinding.instance.imageCache.evict(NetworkImage(thumb));
    }
    super.dispose();
  }
  bool _isSafeImageUrl(String url) {
    if (url.isEmpty) return false;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.gif') || path.endsWith('.webp');
  }
  @override
  Widget build(BuildContext context) {
    if (!_shouldLoad) return const PreviewLoading();
    final item = widget.item;
    final kind = item.mediaKind;
    if (kind == MediaKind.audio || kind == MediaKind.unknown || !_isSafeImageUrl(item.thumb)) return PreviewFallback(item: item);
    return Image.network(item.thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => PreviewFallback(item: item), loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return const PreviewLoading();
    });
  }
}

class PreviewLoading extends StatelessWidget {
  const PreviewLoading({super.key});
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF121212)), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.4, color: Color(0xFF3D7EFF)))));
  }
}

class PreviewFallback extends StatelessWidget {
  final SearchItem item;
  const PreviewFallback({super.key, required this.item});
  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.image: return Icons.image_outlined;
      case MediaKind.vector: return Icons.polyline_outlined;
      case MediaKind.audio: return Icons.graphic_eq_outlined;
      case MediaKind.video: return Icons.videocam_outlined;
      case MediaKind.document: return Icons.description_outlined;
      case MediaKind.unknown: return Icons.insert_drive_file_outlined;
    }
  }
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF101010), Color(0xFF171717)], begin: Alignment.topLeft, end: Alignment.bottomRight)), child: Center(child: Icon(_iconForKind(item.mediaKind), size: 34, color: const Color(0xFF555555))));
  }
}