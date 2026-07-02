import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import 'search_models.dart';
import 'router.dart';
import 'search_service.dart';
import 'search_url_codec.dart';

/// How this viewer instance got its gallery data.
enum _ViewerMode {
  /// Opened in-app from the search grid: gallery + pagination are already
  /// live in memory via [AssetViewer.searchResultsNotifier].
  gallery,

  /// Reached via a URL that carries full search context (q + filters) but
  /// no in-memory gallery.
  query,

  /// A bare `/view?id=...` link with no search context at all.
  standalone,
}

class AssetViewer extends StatefulWidget {
  final ValueNotifier<List<SearchItem>>? searchResultsNotifier;
  final int initialIndex;
  final VoidCallback? onLoadMore;

  final String? explicitFileId;
  final SearchState? searchState;
  final _ViewerMode mode;

  const AssetViewer({
    Key? key,
    required this.searchResultsNotifier,
    required this.initialIndex,
    required this.onLoadMore,
    this.explicitFileId,
    this.searchState,
  })  : mode = _ViewerMode.gallery,
        super(key: key);

  const AssetViewer.standalone({
    Key? key,
    required String fileId,
  })  : searchResultsNotifier = null,
        initialIndex = 0,
        onLoadMore = null,
        explicitFileId = fileId,
        searchState = null,
        mode = _ViewerMode.standalone,
        super(key: key);

  const AssetViewer.fromQuery({
    Key? key,
    required String fileId,
    required SearchState searchState,
  })  : searchResultsNotifier = null,
        initialIndex = 0,
        onLoadMore = null,
        explicitFileId = fileId,
        searchState = searchState,
        mode = _ViewerMode.query,
        super(key: key);

  @override
  State<AssetViewer> createState() => _AssetViewerState();
}

class _QueryGalleryController {
  _QueryGalleryController(this._service, this._searchState);

  final SearchService _service;
  final SearchState _searchState;
  Map<String, dynamic>? continueParams;
  bool hasMore = true;
  bool _loadingMore = false;

  Future<void> loadMore(ValueNotifier<List<SearchItem>> notifier) async {
    if (_loadingMore || !hasMore) return;

    _loadingMore = true;
    final more =
        await _service.fetchPage(_searchState, continueParams: continueParams);
    _loadingMore = false;
    if (more == null) return;

    final existingUrls = notifier.value.map((e) => e.url).toSet();
    notifier.value = [
      ...notifier.value,
      ...more.items.where((it) => !existingUrls.contains(it.url)),
    ];
    continueParams = more.continueParams;
    hasMore = more.continueParams != null;
  }
}

class _AssetViewerState extends State<AssetViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showMobileInfo = false;

  late ValueNotifier<List<SearchItem>> _activeNotifier;
  bool _isLoading = false;
  bool _suppressUrlSync = false;

  late FocusNode _focusNode;

  final SearchService _service = SearchService();
  _QueryGalleryController? _queryController;

  bool get _hasGallery => widget.mode != _ViewerMode.standalone;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    switch (widget.mode) {
      case _ViewerMode.gallery:
        _activeNotifier = widget.searchResultsNotifier!;
        break;
      case _ViewerMode.standalone:
        _activeNotifier = ValueNotifier([]);
        _isLoading = true;
        _fetchStandaloneAsset();
        break;
      case _ViewerMode.query:
        _activeNotifier = ValueNotifier([]);
        _queryController =
            _QueryGalleryController(_service, widget.searchState!);
        _isLoading = true;
        _fetchQueryGallery();
        break;
    }
  }

  @override
  void didUpdateWidget(covariant AssetViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newFileId = _normalizedTitle(widget.explicitFileId ?? '');
    final oldFileId = _normalizedTitle(oldWidget.explicitFileId ?? '');

    if (newFileId.isEmpty || newFileId == oldFileId) return;
    if (_isLoading || _activeNotifier.value.isEmpty) return;

    final newIndex = _activeNotifier.value.indexWhere(
      (it) => _normalizedTitle(it.title) == newFileId,
    );

    if (newIndex == -1 || newIndex == _currentIndex) return;

    _suppressUrlSync = true;
    _currentIndex = newIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        _suppressUrlSync = false;
        return;
      }

      _pageController.jumpToPage(newIndex);
      setState(() {});
    });
  }

  String _normalizedTitle(String title) =>
      title.replaceFirst('File:', '').trim().toLowerCase();

  Future<void> _fetchStandaloneAsset() async {
    final fileId = widget.explicitFileId ?? '';
    final item = fileId.isEmpty ? null : await _service.fetchSingleItem(fileId);

    if (!mounted) return;
    setState(() {
      _activeNotifier.value = item != null ? [item] : [];
      _isLoading = false;
    });
  }

  Future<void> _fetchQueryGallery() async {
    final searchState = widget.searchState!;
    final controller = _queryController!;
    final targetTitle = _normalizedTitle(widget.explicitFileId ?? '');

    var result = await _service.fetchPage(searchState, continueParams: null);
    if (!mounted) return;

    if (result == null) {
      await _fetchStandaloneAsset();
      return;
    }

    var items = result.items;
    controller.continueParams = result.continueParams;
    controller.hasMore = result.continueParams != null;

    int foundIndex =
        items.indexWhere((it) => _normalizedTitle(it.title) == targetTitle);

    int attempts = 0;
    while (foundIndex == -1 && controller.hasMore && attempts < 4) {
      final more = await _service.fetchPage(
        searchState,
        continueParams: controller.continueParams,
      );
      if (more == null) break;

      final existingUrls = items.map((e) => e.url).toSet();
      items = [
        ...items,
        ...more.items.where((it) => !existingUrls.contains(it.url)),
      ];
      controller.continueParams = more.continueParams;
      controller.hasMore = more.continueParams != null;
      foundIndex =
          items.indexWhere((it) => _normalizedTitle(it.title) == targetTitle);
      attempts++;
    }

    if (foundIndex == -1 && targetTitle.isNotEmpty) {
      final single = await _service.fetchSingleItem(widget.explicitFileId!);
      if (single != null) {
        items = [single, ...items.where((it) => it.url != single.url)];
        foundIndex = 0;
      }
    }

    if (!mounted) return;

    final safeIndex = items.isEmpty ? 0 : foundIndex.clamp(0, items.length - 1);
    setState(() {
      _activeNotifier.value = items;
      _currentIndex = safeIndex;
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _suppressUrlSync = true;
        _pageController.jumpToPage(safeIndex);
      }
    });
  }

  void _triggerLoadMore() {
    switch (widget.mode) {
      case _ViewerMode.gallery:
        widget.onLoadMore?.call();
        break;
      case _ViewerMode.query:
        _queryController?.loadMore(_activeNotifier);
        break;
      case _ViewerMode.standalone:
        break;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPageChanged(int index, int totalLength) {
    setState(() => _currentIndex = index);

    if (_suppressUrlSync) {
      _suppressUrlSync = false;
      return;
    }

    if (index >= totalLength - 3) {
      _triggerLoadMore();
    }

    if (_hasGallery) {
      final currentItem = _activeNotifier.value[index];
      final params = {
        'id': currentItem.title,
        if (widget.searchState != null)
          ...SearchUrlCodec.toQueryParams(widget.searchState!),
      };

      final notifier = _activeNotifier;
      final queryController = _queryController;
      final VoidCallback onLoadMore = widget.mode == _ViewerMode.gallery
          ? widget.onLoadMore!
          : () => queryController?.loadMore(notifier);

      context.replace(
        Uri(path: '/view', queryParameters: params).toString(),
        extra: ViewerState(
          notifier: notifier,
          index: index,
          onLoadMore: onLoadMore,
          searchState: widget.searchState,
        ),
      );
    }
  }

  void _navigateToPage(int index, int totalLength) {
    if (index >= 0 && index < totalLength) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _launchCommonsUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070707),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3D7EFF)),
        ),
      );
    }

    return ValueListenableBuilder<List<SearchItem>>(
      valueListenable: _activeNotifier,
      builder: (context, results, child) {
        if (_currentIndex >= results.length) {
          _currentIndex = results.isNotEmpty ? results.length - 1 : 0;
        }

        if (results.isEmpty) {
          return Scaffold(
            backgroundColor: const Color(0xFF070707),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
            ),
            body: const Center(
              child: Text(
                'Media not found or still loading.',
                style: TextStyle(color: Color(0xFF555555)),
              ),
            ),
          );
        }

        final currentItem = results[_currentIndex];
        final hasPrevious = _currentIndex > 0;
        final hasNext = _currentIndex < results.length - 1;

        return Scaffold(
          backgroundColor: const Color(0xFF070707),
          appBar: AppBar(
            backgroundColor: const Color(0xFF070707),
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            ),
            title: Text(
              _hasGallery ? '${_currentIndex + 1} OF ${results.length}' : 'DIRECT LINK',
              style: const TextStyle(
                color: Color(0xFF7A7A7A),
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (MediaQuery.of(context).size.width < 800) {
                    return IconButton(
                      icon: Icon(
                        _showMobileInfo ? Icons.info : Icons.info_outline,
                        color: _showMobileInfo
                            ? const Color(0xFF3D7EFF)
                            : Colors.white,
                      ),
                      onPressed: () =>
                          setState(() => _showMobileInfo = !_showMobileInfo),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: KeyboardListener(
              focusNode: _focusNode,
              onKeyEvent: (KeyEvent event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _navigateToPage(_currentIndex - 1, results.length);
                  } else if (event.logicalKey ==
                      LogicalKeyboardKey.arrowRight) {
                    _navigateToPage(_currentIndex + 1, results.length);
                  }
                }
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 800;

                  return Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: Stack(
                          children: [
                            PageView.builder(
                              controller: _pageController,
                              physics: _hasGallery
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              itemCount: results.length,
                              onPageChanged: (index) =>
                                  _onPageChanged(index, results.length),
                              itemBuilder: (context, index) {
                                return _NativeMediaRenderer(item: results[index]);
                              },
                            ),
                            if (hasPrevious && isDesktop && _hasGallery)
                              Positioned(
                                left: 24,
                                top: 0,
                                bottom: 0,
                                child: _NavigationButton(
                                  icon: Icons.arrow_back_ios_new,
                                  onTap: () => _navigateToPage(
                                    _currentIndex - 1,
                                    results.length,
                                  ),
                                ),
                              ),
                            if (hasNext && isDesktop && _hasGallery)
                              Positioned(
                                right: 24,
                                top: 0,
                                bottom: 0,
                                child: _NavigationButton(
                                  icon: Icons.arrow_forward_ios,
                                  onTap: () => _navigateToPage(
                                    _currentIndex + 1,
                                    results.length,
                                  ),
                                ),
                              ),
                            if (!isDesktop && _showMobileInfo)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxHeight: constraints.maxHeight * 0.6,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF111111),
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                    border: Border(
                                      top: BorderSide(color: Color(0xFF222222)),
                                    ),
                                  ),
                                  child: _MetadataInspector(
                                    item: currentItem,
                                    onLaunchCommons: () => _launchCommonsUrl(
                                      currentItem.commonsUrl,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isDesktop)
                        Container(
                          width: 380,
                          decoration: const BoxDecoration(
                            color: Color(0xFF111111),
                            border: Border(
                              left: BorderSide(color: Color(0xFF1E1E1E)),
                            ),
                          ),
                          child: _MetadataInspector(
                            item: currentItem,
                            onLaunchCommons: () =>
                                _launchCommonsUrl(currentItem.commonsUrl),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NativeMediaRenderer extends StatefulWidget {
  final SearchItem item;

  const _NativeMediaRenderer({required this.item});

  @override
  State<_NativeMediaRenderer> createState() => _NativeMediaRendererState();
}

class _NativeMediaRendererState extends State<_NativeMediaRenderer> {
  late final String _viewId;
  bool _isNativeHtml = false;

  @override
  void initState() {
    super.initState();
    _viewId =
        'media-view-${widget.item.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';

    final isPdf = widget.item.mediaKind == MediaKind.document &&
        widget.item.extension.toLowerCase() == 'pdf';
    final isVideo = widget.item.mediaKind == MediaKind.video;
    final isAudio = widget.item.mediaKind == MediaKind.audio;

    if (isVideo || isAudio || isPdf) {
      _isNativeHtml = true;

      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        if (isVideo) {
          return html.VideoElement()
            ..src = widget.item.url
            ..controls = true
            ..autoplay = false
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor = '#070707'
            ..style.outline = 'none';
        } else if (isAudio) {
          final container = html.DivElement()
            ..style.display = 'flex'
            ..style.alignItems = 'center'
            ..style.justifyContent = 'center'
            ..style.width = '100%'
            ..style.height = '100%';

          final audio = html.AudioElement()
            ..src = widget.item.url
            ..controls = true
            ..autoplay = false
            ..style.width = '80%'
            ..style.outline = 'none';

          container.append(audio);
          return container;
        } else {
          return html.IFrameElement()
            ..src = widget.item.url
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.border = 'none'
            ..style.backgroundColor = '#323639';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.mediaKind == MediaKind.image ||
        widget.item.mediaKind == MediaKind.vector) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 6.0,
        child: Center(
          child: Image.network(
            widget.item.url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFF3D7EFF),
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          (progress.expectedTotalBytes ?? 1)
                      : null,
                ),
              );
            },
            errorBuilder: (_, __, ___) => _buildFallbackUI(widget.item),
          ),
        ),
      );
    }

    if (_isNativeHtml) {
      final isDesktop = MediaQuery.of(context).size.width >= 800;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 80.0 : 0.0),
        child: HtmlElementView(viewType: _viewId),
      );
    }

    return _buildFallbackUI(widget.item);
  }

  Widget _buildFallbackUI(SearchItem item) {
    IconData icon;
    String typeLabel;

    switch (item.mediaKind) {
      case MediaKind.vector:
        icon = Icons.polyline_outlined;
        typeLabel = 'VECTOR GRAPHIC';
        break;
      case MediaKind.document:
        icon = Icons.description_outlined;
        typeLabel = 'DOCUMENT (${item.extension.toUpperCase()})';
        break;
      default:
        icon = Icons.insert_drive_file_outlined;
        typeLabel = 'FILE';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.thumb.isNotEmpty) Image.network(item.thumb, fit: BoxFit.cover),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withOpacity(0.65),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.white60),
              const SizedBox(height: 16),
              Text(
                typeLabel,
                style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(item.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.open_in_browser, size: 20),
                label: const Text(
                  'Open Media / Download',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetadataInspector extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onLaunchCommons;

  const _MetadataInspector({
    required this.item,
    required this.onLaunchCommons,
  });

  String _cleanHtml(String html) {
    if (html.isEmpty) return '';
    final exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final cleanArtist = _cleanHtml(item.artistHtml);
    final dimensions =
        (item.width > 0 && item.height > 0) ? '${item.width} × ${item.height} px' : '';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SelectableText(
          item.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 24),
        _DownloadSection(
          item: item,
          onLaunchCommons: onLaunchCommons,
        ),
        const SizedBox(height: 32),
        _buildPropertyRow('FILE TYPE', item.mime.toUpperCase()),
        _buildPropertyRow('EXTENSION', item.extension.toUpperCase()),
        _buildPropertyRow('DIMENSIONS', dimensions),
        _buildPropertyRow('AUTHOR / CREATOR', cleanArtist),
        _buildPropertyRow('DATE ORIGINAL', item.dateTimeOriginal),
        _buildPropertyRow('UPLOADER', item.uploader),
        _buildPropertyRow('UPLOAD TIMESTAMP', item.timestamp ?? ''),
        _buildPropertyRow('LICENSE', _cleanHtml(item.licenseShortName)),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFF222222)),
        const SizedBox(height: 24),
        const Text(
          'DESCRIPTION',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          item.snippet.isEmpty
              ? 'No description provided by the archivist.'
              : _cleanHtml(item.snippet),
          style: const TextStyle(
            color: Color(0xFFB0B0B0),
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onLaunchCommons;

  const _DownloadSection({
    required this.item,
    required this.onLaunchCommons,
  });

  Future<void> _handleDownload(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _getResizedUrl(int width) {
    if (item.thumb.isEmpty) return item.url;
    final regExp = RegExp(r'\/(\d+)px-([^/]+)$');
    if (regExp.hasMatch(item.thumb)) {
      return item.thumb.replaceAllMapped(
        regExp,
        (m) => '/${width}px-${m.group(2)}',
      );
    }
    return item.url;
  }

  @override
  Widget build(BuildContext context) {
    final isScalable =
        item.mediaKind == MediaKind.image || item.mediaKind == MediaKind.vector;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _handleDownload(item.url),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3D7EFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.download, size: 18),
          label: const Text(
            'Download Original',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (isScalable) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SizeButton(
                  label: 'SMALL',
                  onTap: () => _handleDownload(_getResizedUrl(640)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'MEDIUM',
                  onTap: () => _handleDownload(_getResizedUrl(1280)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'LARGE',
                  onTap: () => _handleDownload(_getResizedUrl(1920)),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onLaunchCommons,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFAAAAAA),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text(
            'View Source Page',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SizeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SizeButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: const Color(0xFFCCCCCC),
        padding: const EdgeInsets.symmetric(vertical: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavigationButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<_NavigationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withOpacity(0.15)
                : Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isHovered ? Colors.white : const Color(0xFFCCCCCC),
            size: 20,
          ),
        ),
      ),
    );
  }
}