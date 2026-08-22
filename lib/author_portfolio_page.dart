import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'download_service.dart';
import 'search_models.dart';
import 'search_controller.dart';
import 'search_components.dart';
import 'search_page.dart' show selectionModeProvider, selectedItemsProvider;

class AuthorPortfolioPage extends ConsumerStatefulWidget {
  final String username;

  const AuthorPortfolioPage({super.key, required this.username});

  @override
  ConsumerState<AuthorPortfolioPage> createState() =>
      _AuthorPortfolioPageState();
}

class _AuthorPortfolioPageState extends ConsumerState<AuthorPortfolioPage> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _authorCtrl =
      TextEditingController(text: widget.username);

  bool _isDownloading = false;
  int _downloadCompleted = 0;
  int _downloadTotal = 0;
  List<String> _downloadFailed = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AuthorPortfolioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _authorCtrl.text = widget.username;
      // Switching authors — a bulk selection from the previous grid
      // shouldn't silently carry over into the new one.
      ref.read(selectionModeProvider.notifier).state = false;
      ref.read(selectedItemsProvider.notifier).state = {};
    }
  }

  @override
  void dispose() {
    _authorCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitAuthorSearch() {
    final name = _authorCtrl.text.trim();
    if (name.isEmpty || name == widget.username) return;
    // authorPortfolioProvider is keyed by username, so navigating here just
    // rebuilds this same page watching a different family instance — no
    // extra state plumbing needed, GoRouter + Riverpod already do the work.
    context.go(Uri(path: '/author', queryParameters: {'name': name}).toString());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref
          .read(authorPortfolioProvider(widget.username).notifier)
          .loadMore(widget.username);
    }
  }

  Widget _buildAuthorSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _authorCtrl,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search uploads by author username…',
            hintStyle: const TextStyle(color: Color(0xFF3A3A3A), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF181818),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF3D7EFF), width: 1)),
            prefixIcon: const Icon(Icons.person_search_rounded,
                size: 18, color: Color(0xFF3A3A3A)),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: Color(0xFF3D7EFF)),
              onPressed: _submitAuthorSearch,
            ),
          ),
          onSubmitted: (_) => _submitAuthorSearch(),
        ),
      ),
    );
  }

  Future<void> _startBulkDownload(List<SearchItem> items) async {
    setState(() {
      _isDownloading = true;
      _downloadCompleted = 0;
      _downloadTotal = items.length;
      _downloadFailed = [];
    });

    await DownloadService.downloadBulkZip(
      items,
      zipName: '${widget.username}_portfolio.zip',
      onProgress: (completed, total, failedTitles) {
        if (!mounted) return;
        setState(() {
          _downloadCompleted = completed;
          _downloadTotal = total;
          _downloadFailed = failedTitles;
        });
      },
    );

    if (!mounted) return;
    setState(() => _isDownloading = false);
  }

  Widget _buildBulkActionBar() {
    final isSelectionMode = ref.watch(selectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);
    if (!isSelectionMode) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131313),
        border: Border(top: BorderSide(color: Color(0xFF202020))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _downloadTotal == 0
                      ? null
                      : _downloadCompleted / _downloadTotal,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF2A2A2A),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF3D7EFF)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _downloadFailed.isEmpty
                    ? 'Downloading $_downloadCompleted / $_downloadTotal…'
                    : 'Downloading $_downloadCompleted / $_downloadTotal — '
                        '${_downloadFailed.length} failed',
                style: TextStyle(
                  color: _downloadFailed.isEmpty
                      ? const Color(0xFF888888)
                      : const Color(0xFFFF6B6B),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isDownloading
                      ? null
                      : () {
                          ref.read(selectionModeProvider.notifier).state =
                              false;
                          ref.read(selectedItemsProvider.notifier).state = {};
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: (selectedItems.isEmpty || _isDownloading)
                      ? null
                      : () => _startBulkDownload(selectedItems.toList()),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D7EFF)),
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download,
                          size: 18, color: Colors.white),
                  label: Text(
                    _isDownloading
                        ? 'Downloading…'
                        : 'Download (${selectedItems.length})',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authorPortfolioProvider(widget.username));

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text(
          'AUTHOR PORTFOLIO',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildAuthorSearchBar(),
          Expanded(child: _buildBody(session)),
          _buildBulkActionBar(),
        ],
      ),
    );
  }

  Widget _buildBody(SearchSession session) {
    if (session.loading && session.items.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child:
              CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
        ),
      );
    }
    if (session.error != null && session.items.isEmpty) {
      return Center(
        child: Text(session.error!,
            style: const TextStyle(color: Color(0xFF484848), fontSize: 14)),
      );
    }
    if (session.items.isEmpty) {
      return Center(
        child: Text('No uploads found for "${widget.username}".',
            style: const TextStyle(color: Color(0xFF404040), fontSize: 14)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Text(
            '${session.items.length} UPLOAD${session.items.length == 1 ? '' : 'S'}'
            '${session.hasMore ? '+' : ''}',
            style: const TextStyle(
                color: Color(0xFF323232),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            cacheExtent: 150,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85),
            itemCount: session.items.length + (session.loadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == session.items.length) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
                  ),
                );
              }
              return RepaintBoundary(
                key: ValueKey(session.items[i].url),
                child: MediaCard(
                  item: session.items[i],
                  searchResultsNotifier: ValueNotifier(session.items),
                  onLoadMore: () => ref
                      .read(authorPortfolioProvider(widget.username).notifier)
                      .loadMore(widget.username),
                  index: i,
                  searchState: const SearchState(),
                  extraParams: {'author': widget.username},
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
