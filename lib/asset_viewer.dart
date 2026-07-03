import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:ui';
import 'download_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // <-- Added Riverpod

import 'search_models.dart';
import 'search_service.dart';
import 'search_url_codec.dart';
import 'search_controller.dart'; // <-- Link to the brain

class AssetViewer extends ConsumerStatefulWidget {
  final String fileId;
  final String returnUrl;

  const AssetViewer({
    super.key,
    required this.fileId,
    required this.returnUrl,
  });

  @override
  ConsumerState<AssetViewer> createState() => _AssetViewerState();
}

class _AssetViewerState extends ConsumerState<AssetViewer> {
  late PageController _pageController;
  late int _currentIndex; // Removed the -1
  bool _showMobileInfo = false;

  bool _urlHydrated = false;
  bool _suppressUrlSync = false;

  late FocusNode _focusNode;
  final SearchService _service = SearchService();

  bool _isStandalone = false;
  SearchItem? _injectedTarget;
  bool _isFetchingInjected = false;

  @override
  void initState() {
    super.initState();

    // PRE-CALCULATE THE INDEX FROM THE HOT CACHE
    final session = ref.read(searchControllerProvider).activeSession;
    final targetId = _normalizedTitle(widget.fileId);
    int startIndex = session.items
        .indexWhere((it) => _normalizedTitle(it.title) == targetId);

    // Set the state and page controller immediately
    _currentIndex = startIndex >= 0 ? startIndex : 0;
    _pageController = PageController(initialPage: _currentIndex);

    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_urlHydrated) {
      _urlHydrated = true;
      final params = GoRouterState.of(context).uri.queryParameters;

      if (SearchUrlCodec.hasSearchContext(params)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // THE SIMPLE FIX: Only hydrate if memory is empty!
          // If we tapped an image in-app, the cache is hot, so do nothing.
          if (ref.read(searchControllerProvider).activeSession.items.isEmpty) {
            ref.read(searchControllerProvider.notifier).hydrateFromUrl(params);
          }
        });
      } else {
        _isStandalone = true;
        _fetchInjectedTarget();
      }
    }
  }

  @override
  void didUpdateWidget(covariant AssetViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newFileId = _normalizedTitle(widget.fileId);
    final oldFileId = _normalizedTitle(oldWidget.fileId);

    if (newFileId.isEmpty || newFileId == oldFileId) return;

    // Handle Browser Back/Forward buttons
    final items = _getCombinedItems();
    if (items.isEmpty) return;

    if (_currentIndex >= 0 && _currentIndex < items.length) {
      if (_normalizedTitle(items[_currentIndex].title) == newFileId) {
        return; // URL changed because of our own swipe. Do nothing.
      }
    }

    int found =
        items.indexWhere((it) => _normalizedTitle(it.title) == newFileId);
    if (found != -1) {
      _suppressUrlSync = true;
      _currentIndex = found;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(found);
          setState(() {});
        }
      });
    } else if (!_isFetchingInjected) {
      _fetchInjectedTarget();
    }
  }

  String _normalizedTitle(String title) =>
      title.replaceFirst('File:', '').trim().toLowerCase();

  Future<void> _fetchInjectedTarget() async {
    setState(() => _isFetchingInjected = true);
    final item = await _service.fetchSingleItem(widget.fileId);
    if (mounted) {
      setState(() {
        _injectedTarget = item;
        _isFetchingInjected = false;
      });
    }
  }

  List<SearchItem> _getCombinedItems() {
    final session = ref.watch(searchControllerProvider).activeSession;
    final gallery = _isStandalone ? <SearchItem>[] : session.items;

    List<SearchItem> items = List.from(gallery);

    // Inject the deep-linked item if it's not already in the loaded gallery
    if (_injectedTarget != null) {
      if (!items.any((it) =>
          _normalizedTitle(it.title) ==
          _normalizedTitle(_injectedTarget!.title))) {
        items.insert(0, _injectedTarget!);
      }
    }
    return items;
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

    if (!_isStandalone && index >= totalLength - 3) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }

    // Sync URL without rebuilding the stack
    final items = _getCombinedItems();
    if (items.isNotEmpty) {
      final params = Map<String, String>.from(
          GoRouterState.of(context).uri.queryParameters);
      params['id'] = items[index].title;
      context.replace(Uri(path: '/view', queryParameters: params).toString());
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
    final session = ref.watch(searchControllerProvider).activeSession;
    final items = _getCombinedItems();

    final isLoading = (_isStandalone && _isFetchingInjected) ||
        (!_isStandalone && session.loading && items.isEmpty);

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070707),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF3D7EFF))),
      );
    }

    if (items.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF070707),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              // If they clicked an image to get here, pop it off.
              if (context.canPop()) {
                context.pop();
              } else {
                // If they pasted a link directly into the browser, fallback to go()
                context.go(widget.returnUrl);
              }
            },
          ),
        ),
        body: const Center(
          child: Text('Media not found.',
              style: TextStyle(color: Color(0xFF555555))),
        ),
      );
    }

    // Failsafe bounds
    if (_currentIndex >= items.length || _currentIndex < 0) {
      _currentIndex = 0;
    }

    final currentItem = items[_currentIndex];
    final hasPrevious = _currentIndex > 0;
    final hasNext = _currentIndex < items.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070707),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.go(widget.returnUrl),
        ),
        title: Text(
          !_isStandalone
              ? '${_currentIndex + 1} OF ${items.length}'
              : 'DIRECT LINK',
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
                _navigateToPage(_currentIndex - 1, items.length);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _navigateToPage(_currentIndex + 1, items.length);
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
                          physics: !_isStandalone
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          onPageChanged: (index) =>
                              _onPageChanged(index, items.length),
                          itemBuilder: (context, index) {
                            return _NativeMediaRenderer(item: items[index]);
                          },
                        ),
                        if (hasPrevious && isDesktop && !_isStandalone)
                          Positioned(
                            left: 24,
                            top: 0,
                            bottom: 0,
                            child: _NavigationButton(
                              icon: Icons.arrow_back_ios_new,
                              onTap: () => _navigateToPage(
                                  _currentIndex - 1, items.length),
                            ),
                          ),
                        if (hasNext && isDesktop && !_isStandalone)
                          Positioned(
                            right: 24,
                            top: 0,
                            bottom: 0,
                            child: _NavigationButton(
                              icon: Icons.arrow_forward_ios,
                              onTap: () => _navigateToPage(
                                  _currentIndex + 1, items.length),
                            ),
                          ),
                        if (!isDesktop && _showMobileInfo)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * 0.6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF111111),
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16)),
                                border: Border(
                                    top: BorderSide(color: Color(0xFF222222))),
                              ),
                              child: _MetadataInspector(
                                item: currentItem,
                                onLaunchCommons: () =>
                                    _launchCommonsUrl(currentItem.commonsUrl),
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
                        border:
                            Border(left: BorderSide(color: Color(0xFF1E1E1E))),
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

    // 1. Detect if it's an image or vector
    final isImage = widget.item.mediaKind == MediaKind.image ||
        widget.item.mediaKind == MediaKind.vector;

    // 2. Add 'isImage' to the native HTML condition
    if (isVideo || isAudio || isPdf || isImage) {
      _isNativeHtml = true;

      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        // 3. Render the native HTML <img> tag
        if (isImage) {
          return html.ImageElement()
            ..src = widget.item.url
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain' // Ensures the image isn't squashed
            ..style.backgroundColor = 'transparent'
            ..style.outline = 'none';
        } else if (isVideo) {
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
    // If it's an Image, Video, Audio, or PDF, it drops directly into this native view
    if (_isNativeHtml) {
      final isDesktop = MediaQuery.of(context).size.width >= 800;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 80.0 : 0.0),
        child: HtmlElementView(viewType: _viewId),
      );
    }

    // Otherwise, show the fallback UI (for unknown files)
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
            color: Colors.black.withValues(alpha: 0.65),
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
    final exp = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final cleanArtist = _cleanHtml(item.artistHtml);
    final dimensions = (item.width > 0 && item.height > 0)
        ? '${item.width} × ${item.height} px'
        : '';

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
        _buildLicenseRow(
          context,
          'LICENSE',
          _cleanHtml(item.licenseShortName),
          item.licenseUrl,
        ),
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

  Widget _buildLicenseRow(
    BuildContext context,
    String label,
    String value,
    String? url,
  ) {
    if (value.isEmpty) return const SizedBox.shrink();

    final cleanUrl = (url ?? '').trim();
    final isClickable = cleanUrl.isNotEmpty;

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
          if (isClickable)
            InkWell(
              onTap: () async {
                final uri = Uri.tryParse(cleanUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF7AABFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF7AABFF),
                ),
              ),
            )
          else
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

  Future<void> _handleDownload(BuildContext context, String url) async {
    // Show a quick toast so the user knows the network request started
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading media...'),
        duration: Duration(seconds: 2),
      ),
    );

    // Call our custom forcing function
    await DownloadService.downloadSingleFile(url, item.title, item.extension);
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
          // Passed context here!
          onPressed: () => _handleDownload(context, item.url),
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
                  // Passed context here!
                  onTap: () => _handleDownload(context, _getResizedUrl(640)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'MEDIUM',
                  // Passed context here!
                  onTap: () => _handleDownload(context, _getResizedUrl(1280)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'LARGE',
                  // Passed context here!
                  onTap: () => _handleDownload(context, _getResizedUrl(1920)),
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
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.3)
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
