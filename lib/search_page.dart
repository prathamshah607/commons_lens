// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'package:commonslens/advanced_filters_drawer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'download_service.dart';
import 'search_models.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'search_components.dart';

final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedItemsProvider = StateProvider<Set<SearchItem>>((ref) => {});

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final double width;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.width,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.width,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF161616) : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? const Color(0xFF3D7EFF).withValues(alpha: 0.5) : const Color(0xFF1E1E1E),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(widget.description,
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final ScrollController _scrollController = ScrollController();

  bool _urlHydrated = false;
  bool _showQueryPreview = false;
  bool? _isFiltersExpanded;

  static const _examples = [
    'Apollo 11',
    'Pride and Prejudice',
    'Berlin',
    'DNA helix',
    'Charlie Chaplin',
    'Mitridate, Re di Ponto'
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_urlHydrated) {
      _urlHydrated = true;
      final params = GoRouterState.of(context).uri.queryParameters;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(searchControllerProvider.notifier).hydrateFromUrl(params);
      });
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      ref
          .read(searchControllerProvider.notifier)
          .saveScrollOffset(_scrollController.position.pixels);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  Widget _buildBulkActionBar(SearchSession session) {
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
        child: Row(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                ref.read(selectionModeProvider.notifier).state = false;
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
              onPressed: selectedItems.isEmpty
                  ? null
                  : () {
                      DownloadService.downloadBulkZip(selectedItems.toList(),
                          zipName: 'selected_commons_media.zip');
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF)),
              icon: const Icon(Icons.download, size: 18, color: Colors.white),
              label: Text('Download (${selectedItems.length})',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _search(String query) =>
      ref.read(searchControllerProvider.notifier).search(query);

  void _selectTab(MediaTabType tab) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((current) {
      final config = configForTab(tab);
      final nextFormats = current.formats
          .where((f) => config.allowedFormats.contains(f))
          .toSet();
      return current.copyWith(tab: tab, formats: nextFormats);
    });
  }

  void _toggleFormat(FileFormat format) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((current) {
      final next = Set<FileFormat>.from(current.formats);
      if (next.contains(format))
        next.remove(format);
      else
        next.add(format);
      return current.copyWith(formats: next);
    });
  }

  void _changeSortMode(SortMode mode) {
    ref
        .read(searchControllerProvider.notifier)
        .applyFilterUpdate((current) => current.copyWith(sortMode: mode));
  }

  void _removeChip(QueryChipData chip) {
    final current = ref.read(searchControllerProvider).filterState;
    SearchState next = current;

    if (chip.id.startsWith('format:')) {
      final formatName = chip.id.split(':').last;
      next = current.copyWith(
          formats: Set<FileFormat>.from(current.formats)
            ..removeWhere((f) => f.name == formatName));
    } else if (chip.id.startsWith('category:')) {
      final categoryName = chip.id.substring('category:'.length);
      next = current.copyWith(
          categories: Set<String>.from(current.categories)
            ..remove(categoryName));
    } else if (chip.id == 'titleOnly') {
      next = current.copyWith(titleOnly: false);
    } else if (chip.id == 'language') {
      next = current.copyWith(clearLanguageCode: true);
    } else if (chip.id == 'contentModel') {
      next = current.copyWith(clearContentModel: true);
    } else if (chip.id == 'localOnly') {
      next = current.copyWith(localOnly: false);
    } else if (chip.id == 'createdFrom' || chip.id == 'createdTo') {
      next = current.copyWith(clearCreatedDate: true);
    } else if (chip.id == 'editedFrom' || chip.id == 'editedTo') {
      next = current.copyWith(clearEditedDate: true);
    } else if (chip.id == 'depicts') {
      next = current.copyWith(clearDepicts: true);
    } else if (chip.id == 'license') {
      next = current.copyWith(licensePreset: LicensePreset.any);
    } else if (chip.id == 'quality') {
      next = current.copyWith(qualityFilter: QualityFilter.any);
    } else if (chip.id == 'minWidth') {
      next = current.copyWith(clearMinWidth: true);
    } else if (chip.id == 'minHeight') {
      next = current.copyWith(clearMinHeight: true);
    } else if (chip.id == 'nearCoord') {
      next = current.copyWith(clearNearCoord: true);
    } else if (chip.id.startsWith('exclude:')) {
      final excludeName = chip.id.substring('exclude:'.length);
      next = current.copyWith(
          excludeTerms: Set<String>.from(current.excludeTerms)
            ..remove(excludeName));
    }

    ref
        .read(searchControllerProvider.notifier)
        .search(next.queryText, overrideState: next);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      searchControllerProvider.select((state) => state.filterState),
      (previous, next) {
        if (previous == next) return;
        final currentUri = GoRouterState.of(context).uri;
        if (currentUri.path != '/') return;
        final params = SearchUrlCodec.toQueryParams(next);
        final newUrl =
            Uri(path: '/', queryParameters: params.isEmpty ? null : params)
                .toString();
        if (currentUri.toString() != newUrl) context.replace(newUrl);
      },
    );

    final viewState = ref.watch(searchControllerProvider);
    final session = viewState.activeSession;
    final filterState = viewState.filterState;

    final isMobile = MediaQuery.of(context).size.width < 600;
    _isFiltersExpanded ??= !isMobile;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      endDrawer: const AdvancedFiltersDrawer(),
      body: Column(
        children: [
          SearchTopBar(
            initialQuery: filterState.queryText,
            onSearch: _search,
          ),

          InkWell(
            onTap: () =>
                setState(() => _isFiltersExpanded = !_isFiltersExpanded!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isFiltersExpanded!
                        ? "Hide FileType Filters"
                        : "Show Filetype Filters",
                    style: const TextStyle(
                        color: Color(0xFF3D7EFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isFiltersExpanded!
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF3D7EFF),
                    size: 16,
                  )
                ],
              ),
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isFiltersExpanded!
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabBar(filterState),
                      _buildFormatChips(filterState),
                      _buildActiveChipsBar(viewState.lastBuiltQuery),
                      _buildQueryPreviewBar(
                          viewState.lastBuiltQuery, session.hasSearched),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
              child: session.hasSearched
                  ? _buildResults(session, filterState)
                  : _buildLanding()),
          if (session.hasSearched) _buildBulkActionBar(session),
        ],
      ),
    );
  }

  Widget _buildLanding() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WikiLogo(),
            const SizedBox(height: 28),
            const Text('CommonsLens Discovery Engine',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1.2)),
            const SizedBox(height: 12),
            const Text(
                'A high-performance media discovery interface for the world\'s largest free media archive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFFAAAAAA), fontSize: 16, height: 1.5)),
            const SizedBox(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _examples
                  .map((q) => ExampleChip(label: q, onTap: () => _search(q)))
                  .toList(),
            ),
            const SizedBox(height: 64),
            
            // THE NEW FEATURE GRID
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  return Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      _FeatureCard(
                        icon: Icons.travel_explore,
                        title: 'Semantic Entity Search',
                        description: 'Leverage Wikidata Q-codes to find conceptual matches and exact subjects, bypassing basic string overlaps. Match Depictions and Categories for powerful searching.',
                        width: isMobile ? double.infinity : 400,
                      ),
                      _FeatureCard(
                        icon: Icons.filter_alt_outlined,
                        title: 'Advanced Metadata',
                        description: 'Filter instantly by Creative Commons licenses, creation times, languages, geographical coordinates, and peer-reviewed quality assessments.',
                        width: isMobile ? double.infinity : 400,
                      ),
                      _FeatureCard(
                        icon: Icons.bolt,
                        title: 'Native Hardware Rendering',
                        description: 'Bypasses standard canvas limits to lazily load and decode massive archival images, videos, audios and documents with zero UI lockup.',
                        width: isMobile ? double.infinity : 400,
                      ),
                      _FeatureCard(
                        icon: Icons.archive_outlined,
                        title: 'Client-Side Bulk Export',
                        description: 'Select subsets of research data and compile in-memory .zip archives directly in the browser without server bottlenecks.',
                        width: isMobile ? double.infinity : 400,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(SearchSession session, SearchState filterState) {
    if (session.loading)
      return const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFF3D7EFF))));
    if (session.error != null)
      return Center(
          child: Text(session.error!,
              style: const TextStyle(color: Color(0xFF484848), fontSize: 14)));
    if (session.items.isEmpty)
      return Center(
          child: Text(configForTab(filterState.tab).emptyMessage,
              style: const TextStyle(color: Color(0xFF404040), fontSize: 14)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Row(
            children: [
              Text(
                  '${session.items.length} RESULTS${session.hasMore ? '+' : ''}',
                  style: const TextStyle(
                      color: Color(0xFF323232),
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              _buildSortMenu(filterState.sortMode),
            ],
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
              if (i == session.items.length)
                return const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Color(0xFF3D7EFF))));
              return RepaintBoundary(
                child: MediaCard(
                  item: session.items[i],
                  searchResultsNotifier: ValueNotifier(session.items),
                  onLoadMore: () =>
                      ref.read(searchControllerProvider.notifier).loadMore(),
                  index: i,
                  searchState: filterState,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(SearchState filterState) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A)))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: mediaTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = mediaTabs[index];
          final selected = filterState.tab == tab.type;
          return Center(
            child: GestureDetector(
              onTap: () => _selectTab(tab.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3D7EFF).withOpacity(0.12)
                        : const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF3D7EFF)
                            : const Color(0xFF242424))),
                child: Text(tab.label,
                    style: TextStyle(
                        color: selected
                            ? const Color(0xFF7AABFF)
                            : const Color(0xFF6A6A6A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormatChips(SearchState filterState) {
    final formats = configForTab(filterState.tab).allowedFormats.toList()
      ..sort((a, b) => fileFormatLabel(a).compareTo(fileFormatLabel(b)));
    if (formats.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          border: Border(bottom: BorderSide(color: Color(0xFF181818)))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: formats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final format = formats[index];
          final selected = filterState.formats.contains(format);
          return Center(
            child: GestureDetector(
              onTap: () => _toggleFormat(format),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3D7EFF).withOpacity(0.14)
                        : const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF3D7EFF)
                            : const Color(0xFF242424))),
                child: Text(fileFormatLabel(format),
                    style: TextStyle(
                        color: selected
                            ? const Color(0xFF7AABFF)
                            : const Color(0xFF6A6A6A),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveChipsBar(QueryBuildResult? lastBuiltQuery) {
    final removable = (lastBuiltQuery?.chips ?? const <QueryChipData>[])
        .where((chip) => chip.id != 'scope' && chip.id != 'tab')
        .toList();
    if (removable.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Color(0xFF0B0B0B),
          border: Border(bottom: BorderSide(color: Color(0xFF171717)))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: removable.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = removable[index];
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF252525))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(chip.label,
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  GestureDetector(
                      onTap: () => _removeChip(chip),
                      child: const Icon(Icons.close,
                          size: 14, color: Color(0xFF666666))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueryPreviewBar(
      QueryBuildResult? lastBuiltQuery, bool hasSearched) {
    if (lastBuiltQuery == null || !hasSearched) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
          color: Color(0xFF0A0A0A),
          border: Border(bottom: BorderSide(color: Color(0xFF151515)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showQueryPreview = !_showQueryPreview),
            child: Row(
              children: [
                const Text('QUERY PREVIEW',
                    style: TextStyle(
                        color: Color(0xFF4E4E4E),
                        fontSize: 10,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Icon(
                    _showQueryPreview
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF5C5C5C)),
              ],
            ),
          ),
          if (_showQueryPreview) ...[
            const SizedBox(height: 8),
            SelectableText(lastBuiltQuery.debugPreview,
                style: const TextStyle(
                    color: Color(0xFF8A8A8A), fontSize: 12, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _buildSortMenu(SortMode currentSort) {
    return PopupMenuButton<SortMode>(
      initialValue: currentSort,
      onSelected: _changeSortMode,
      color: const Color(0xFF161616),
      itemBuilder: (context) => const [
        PopupMenuItem(value: SortMode.relevance, child: Text('Relevance')),
        PopupMenuItem(value: SortMode.titleMatch, child: Text('Title A–Z')),
        PopupMenuItem(
            value: SortMode.newestEdited, child: Text('Recently edited')),
        PopupMenuItem(
            value: SortMode.oldestEdited, child: Text('Least recently edited')),
        PopupMenuItem(
            value: SortMode.newestCreated, child: Text('Recently created')),
        PopupMenuItem(
            value: SortMode.oldestCreated, child: Text('Oldest created')),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF262626))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_sortLabel(currentSort),
                style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 16, color: Color(0xFF777777)),
          ],
        ),
      ),
    );
  }

  String _sortLabel(SortMode mode) {
    switch (mode) {
      case SortMode.relevance:
        return 'Relevance';
      case SortMode.titleMatch:
        return 'Title A–Z';
      case SortMode.newestEdited:
        return 'Recently edited';
      case SortMode.oldestEdited:
        return 'Least edited';
      case SortMode.newestCreated:
        return 'Recently created';
      case SortMode.oldestCreated:
        return 'Oldest created';
    }
  }
}
