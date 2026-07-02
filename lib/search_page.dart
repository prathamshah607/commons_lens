// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'router.dart';
import 'search_models.dart';
import 'search_service.dart';
import 'search_url_codec.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _contentModelController = TextEditingController();
  final TextEditingController _createdFromController = TextEditingController();
  final TextEditingController _createdToController = TextEditingController();
  final TextEditingController _editedFromController = TextEditingController();
  final TextEditingController _editedToController = TextEditingController();

  final SearchService _service = SearchService();

  SearchState _state = const SearchState();
  QueryBuildResult? _lastBuiltQuery;

  final Map<SearchSessionKey, SearchSession> _sessions = {};

  final ValueNotifier<List<SearchItem>> _liveResults = ValueNotifier([]);

  SearchSessionKey? _cachedSessionKey;

  bool _showQueryPreview = false;
  int _searchGeneration = 0;
  
  // NEW: Flag to ensure URL hydration only happens once on boot
  bool _urlHydrated = false;

  static const _examples = [
    'Apollo 11',
    'Black hole',
    'Colosseum',
    'DNA helix',
    'Hokusai',
    'Solar system',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20; // 30 MB
    _lastBuiltQuery = _service.buildQuery(_state);
  }

  // --- URL HYDRATION ---
  // This reads the address bar on cold boots (e.g., direct linking to
  // /?q=Apollo+11&tab=audio&cats=Maps|Astronomy&sort=newestCreated&...).
  // Every filter that _syncUrl writes out is parsed back here, so a pasted
  // or bookmarked URL always reproduces the exact same search.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_urlHydrated) {
      _urlHydrated = true;
      final params = GoRouterState.of(context).uri.queryParameters;

      if (params.isNotEmpty) {
        _state = SearchUrlCodec.fromQueryParams(params, _state);

        _controller.text = _state.queryText;
        _invalidateSessionKey();
        _lastBuiltQuery = _service.buildQuery(_state);

        // If a search query was provided, trigger it automatically
        if (_state.queryText.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _search(_state.queryText);
          });
        }
      }
    }
  }

  // --- URL SERIALIZATION ---
  // Silently updates the address bar whenever state changes, so every
  // unique query + filter combination gets its own unique, shareable URL.
  void _syncUrl() {
  final currentUri = GoRouterState.of(context).uri;
  if (currentUri.path != '/') return;

  final params = SearchUrlCodec.toQueryParams(_state);
  final newUrl =
      Uri(path: '/', queryParameters: params.isEmpty ? null : params).toString();

  if (currentUri.toString() != newUrl) {
    context.replace(newUrl);
  }
}

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _categoryController.dispose();
    _languageController.dispose();
    _contentModelController.dispose();
    _createdFromController.dispose();
    _createdToController.dispose();
    _editedFromController.dispose();
    _editedToController.dispose();
    _liveResults.dispose();
    super.dispose();
  }

  void _invalidateSessionKey() {
    _cachedSessionKey = null;
  }

  SearchSessionKey _currentSessionKey() {
    return _cachedSessionKey ??= SearchSessionKey(
      tab: _state.tab,
      querySignature: _service.buildQuerySignature(_state),
    );
  }

  SearchSession _currentSession() {
    return _sessions[_currentSessionKey()] ?? const SearchSession();
  }

  void _setCurrentSession(SearchSession session) {
    _sessions[_currentSessionKey()] = session;
    _liveResults.value = session.items;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    final session = _currentSession();
    _setCurrentSession(session.copyWith(scrollOffset: pos.pixels));

    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _maybeLoadMore();
    }
  }

  void _maybeLoadMore() {
    final session = _currentSession();
    if (!session.loading && !session.loadingMore && session.hasMore) {
      _loadMore();
    }
  }

  void _checkIfScrollable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final session = _currentSession();
      if (pos.maxScrollExtent < 200 &&
          session.hasMore &&
          !session.loading &&
          !session.loadingMore) {
        _loadMore();
      }
    });
  }

  void _restoreScrollIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final offset = _currentSession().scrollOffset;
      final max = _scrollController.position.maxScrollExtent;
      final target = offset.clamp(0.0, max.toDouble());
      _scrollController.jumpTo(target);
    });
  }

  Future<void> _search(String query) async {
    query = query.trim();
    if (query.isEmpty) return;

    final generation = ++_searchGeneration;

    final nextState = _state.copyWith(queryText: query);
    final built = _service.buildQuery(nextState);

    _invalidateSessionKey();
    setState(() {
      _state = nextState;
      _lastBuiltQuery = built;
      _setCurrentSession(
        const SearchSession().copyWith(
          hasSearched: true,
          loading: true,
          loadingMore: false,
          items: [],
          hasMore: false,
          clearContinueParams: true,
          clearError: true,
          scrollOffset: 0,
        ),
      );
    });

    // Sync state to the browser address bar
    _syncUrl();

    final result = await _service.fetchPage(_state, continueParams: null);
    if (!mounted || generation != _searchGeneration) return;

    if (result == null) {
      setState(() {
        _setCurrentSession(
          _currentSession().copyWith(
            loading: false,
            error: 'Search failed — check your connection.',
          ),
        );
      });
      return;
    }

    final sortedItems = _state.sortMode == SortMode.relevance
        ? result.items
        : _service.applyClientSort(result.items, _state.sortMode);

    setState(() {
      _setCurrentSession(
        _currentSession().copyWith(
          items: sortedItems,
          continueParams: result.continueParams,
          hasMore: result.continueParams != null,
          loading: false,
          loadingMore: false,
          clearError: true,
        ),
      );
    });

    _checkIfScrollable();
    _restoreScrollIfNeeded();
  }

  Future<void> _loadMore() async {
    final session = _currentSession();
    if (session.loadingMore || !session.hasMore || _state.queryText.isEmpty) {
      return;
    }

    final generation = _searchGeneration;

    setState(() {
      _setCurrentSession(session.copyWith(loadingMore: true));
    });

    final result = await _service.fetchPage(
      _state,
      continueParams: session.continueParams,
    );
    if (!mounted || generation != _searchGeneration) return;

    if (result == null) {
      setState(() {
        _setCurrentSession(_currentSession().copyWith(loadingMore: false));
      });
      return;
    }

    final existingUrls = session.items.map((e) => e.url).toSet();
    final merged = [
      ...session.items,
      ...result.items.where((item) => !existingUrls.contains(item.url)),
    ];

    final sortedItems = _state.sortMode == SortMode.relevance
        ? merged
        : _service.applyClientSort(merged, _state.sortMode);

    setState(() {
      _setCurrentSession(
        _currentSession().copyWith(
          items: sortedItems,
          continueParams: result.continueParams,
          hasMore: result.continueParams != null,
          loadingMore: false,
        ),
      );
    });

    final addedCount = sortedItems.length - session.items.length;
    if (addedCount < 5 && result.continueParams != null) {
      _maybeLoadMore();
    } else {
      _checkIfScrollable();
    }
  }

  void _selectTab(MediaTabType tab) {
    if (_state.tab == tab) return;

    final config = configForTab(tab);
    final nextFormats =
        _state.formats.where((f) => config.allowedFormats.contains(f)).toSet();

    final nextState = _state.copyWith(
      tab: tab,
      formats: nextFormats,
    );

    _invalidateSessionKey();
    setState(() {
      _state = nextState;
      _lastBuiltQuery = _service.buildQuery(_state);
    });
    
    // Sync state to the browser address bar
    _syncUrl();

    final session = _currentSession();
    if (!session.hasSearched && _state.queryText.trim().isNotEmpty) {
      _search(_state.queryText);
    } else {
      _restoreScrollIfNeeded();
    }
  }

  List<FileFormat> _visibleFormats() {
    final config = configForTab(_state.tab);
    final formats = config.allowedFormats.toList()
      ..sort((a, b) => fileFormatLabel(a).compareTo(fileFormatLabel(b)));
    return formats;
  }

  void _toggleFormat(FileFormat format) {
    final next = Set<FileFormat>.from(_state.formats);

    if (next.contains(format)) {
      next.remove(format);
    } else {
      next.add(format);
    }

    _invalidateSessionKey();
    setState(() {
      _state = _state.copyWith(formats: next);
      _lastBuiltQuery = _service.buildQuery(_state);
    });
    
    _syncUrl();

    if (_state.queryText.trim().isNotEmpty) {
      _search(_state.queryText);
    }
  }

  void _changeSortMode(SortMode mode) {
    if (_state.sortMode == mode) return;

    _invalidateSessionKey();
    setState(() {
      _state = _state.copyWith(sortMode: mode);
      _lastBuiltQuery = _service.buildQuery(_state);
    });

    _syncUrl();

    if (_state.queryText.trim().isNotEmpty) {
      _search(_state.queryText);
    }
  }

  void _removeChip(QueryChipData chip) {
    if (chip.id.startsWith('format:')) {
      final formatName = chip.id.split(':').last;
      final nextFormats = Set<FileFormat>.from(_state.formats)
        ..removeWhere((f) => f.name == formatName);

      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(formats: nextFormats);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id.startsWith('category:')) {
      final categoryName = chip.id.substring('category:'.length);
      final nextCategories = Set<String>.from(_state.categories)
        ..remove(categoryName);

      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(categories: nextCategories);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id == 'titleOnly') {
      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(titleOnly: false);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id == 'language') {
      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(clearLanguageCode: true);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id == 'contentModel') {
      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(clearContentModel: true);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id == 'localOnly') {
      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(localOnly: false);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id == 'createdFrom' || chip.id == 'createdTo') {
      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(clearCreatedDate: true);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else if (chip.id == 'editedFrom' || chip.id == 'editedTo') {
      _invalidateSessionKey();
      setState(() {
        _state = _state.copyWith(clearEditedDate: true);
        _lastBuiltQuery = _service.buildQuery(_state);
      });
    } else {
      return;
    }

    _syncUrl();

    if (_state.queryText.trim().isNotEmpty) {
      _search(_state.queryText);
    }
  }

  Future<void> _openAdvancedFilters() async {
    _categoryController.text = _state.categories.join(', ');
    _languageController.text = _state.languageCode ?? '';
    _contentModelController.text = _state.contentModel ?? '';
    _createdFromController.text = _state.createdDate?.from ?? '';
    _createdToController.text = _state.createdDate?.to ?? '';
    _editedFromController.text = _state.editedDate?.from ?? '';
    _editedToController.text = _state.editedDate?.to ?? '';

    bool titleOnly = _state.titleOnly;
    bool deepCategoryMode = _state.deepCategoryMode;
    bool localOnly = _state.localOnly;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Advanced filters',
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: const Color(0xFF111111),
                child: SizedBox(
                  width: 420,
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildDrawerHeader(context),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildDrawerTextField(
                                controller: _categoryController,
                                label: 'Categories',
                                hint: 'Maps, Astronomy, Diagrams',
                              ),
                              const SizedBox(height: 14),
                              SwitchListTile(
                                value: deepCategoryMode,
                                onChanged: (v) =>
                                    setModalState(() => deepCategoryMode = v),
                                title: const Text('Include subcategories'),
                                activeColor: const Color(0xFF3D7EFF),
                              ),
                              SwitchListTile(
                                value: titleOnly,
                                onChanged: (v) =>
                                    setModalState(() => titleOnly = v),
                                title: const Text('Search title only'),
                                activeColor: const Color(0xFF3D7EFF),
                              ),
                              SwitchListTile(
                                value: localOnly,
                                onChanged: (v) =>
                                    setModalState(() => localOnly = v),
                                title: const Text('Local only'),
                                activeColor: const Color(0xFF3D7EFF),
                              ),
                              const SizedBox(height: 12),
                              _buildDrawerTextField(
                                controller: _languageController,
                                label: 'Language code',
                                hint: 'en, fr, ja',
                              ),
                              const SizedBox(height: 12),
                              _buildDrawerTextField(
                                controller: _contentModelController,
                                label: 'Content model',
                                hint: 'json',
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Created date',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDrawerTextField(
                                      controller: _createdFromController,
                                      label: 'From',
                                      hint: '2024 or 2024-01',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildDrawerTextField(
                                      controller: _createdToController,
                                      label: 'To',
                                      hint: '2025 or 2025-12',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Edited date',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDrawerTextField(
                                      controller: _editedFromController,
                                      label: 'From',
                                      hint: '2024 or today-1y',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildDrawerTextField(
                                      controller: _editedToController,
                                      label: 'To',
                                      hint: '2025 or today',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _buildDrawerActions(
                          context,
                          onApply: () {
                            final categories = _categoryController.text
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toSet();

                            _invalidateSessionKey();
                            setState(() {
                              _state = _state.copyWith(
                                categories: categories,
                                deepCategoryMode: deepCategoryMode,
                                titleOnly: titleOnly,
                                localOnly: localOnly,
                                languageCode:
                                    _languageController.text.trim().isEmpty
                                        ? null
                                        : _languageController.text.trim(),
                                contentModel:
                                    _contentModelController.text.trim().isEmpty
                                        ? null
                                        : _contentModelController.text.trim(),
                                createdDate: (_createdFromController.text
                                            .trim()
                                            .isEmpty &&
                                        _createdToController.text
                                            .trim()
                                            .isEmpty)
                                    ? null
                                    : DateFilter(
                                        from: _createdFromController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : _createdFromController.text
                                                .trim(),
                                        to: _createdToController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : _createdToController.text.trim(),
                                      ),
                                editedDate: (_editedFromController.text
                                            .trim()
                                            .isEmpty &&
                                        _editedToController.text.trim().isEmpty)
                                    ? null
                                    : DateFilter(
                                        from: _editedFromController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : _editedFromController.text.trim(),
                                        to: _editedToController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : _editedToController.text.trim(),
                                      ),
                              );
                              _lastBuiltQuery = _service.buildQuery(_state);
                            });
                            
                            _syncUrl();

                            Navigator.of(context).pop();

                            if (_state.queryText.trim().isNotEmpty) {
                              _search(_state.queryText);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final session = _currentSession();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: Column(
        children: [
          _TopBar(
            controller: _controller,
            onSearch: _search,
            onAdvanced: _openAdvancedFilters,
          ),
          _buildTabBar(),
          _buildFormatChips(),
          _buildActiveChipsBar(),
          _buildQueryPreviewBar(),
          Expanded(
            child: session.hasSearched ? _buildResults() : _buildLanding(),
          ),
        ],
      ),
    );
  }

  Widget _buildLanding() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _WikiLogo(),
              const SizedBox(height: 28),
              const Text(
                'Search all media from Wikimedia Commons',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.4,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Images, vectors, audio, video, and documents — with format filters and advanced search controls.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF505050),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _examples
                    .map(
                      (q) => _ExampleChip(
                        label: q,
                        onTap: () {
                          _controller.text = q;
                          _search(q);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final session = _currentSession();

    if (session.loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF3D7EFF),
          ),
        ),
      );
    }

    if (session.error != null) {
      return Center(
        child: Text(
          session.error!,
          style: const TextStyle(color: Color(0xFF484848), fontSize: 14),
        ),
      );
    }

    if (session.items.isEmpty) {
      final emptyMessage = configForTab(_state.tab).emptyMessage;
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: Color(0xFF404040), fontSize: 14),
        ),
      );
    }

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
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildSortMenu(),
            ],
          ),
        ),
        if (_lastBuiltQuery != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Text(
              _lastBuiltQuery!.chips.map((c) => c.label).join(' · '),
              style: const TextStyle(
                color: Color(0xFF555555),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            cacheExtent: 150,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: 1.25,
            ),
            itemCount: session.items.length + (session.loadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == session.items.length) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF3D7EFF),
                    ),
                  ),
                );
              }

              return RepaintBoundary(
                child: _MediaCard(
                  item: session.items[i],
                  searchResultsNotifier: _liveResults,
                  onLoadMore: _maybeLoadMore,
                  index: i,
                  searchState: _state,
                  onCopied: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Media URL copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: mediaTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = mediaTabs[index];
          final selected = _state.tab == tab.type;

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
                        : const Color(0xFF242424),
                  ),
                ),
                child: Text(
                  tab.label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF7AABFF)
                        : const Color(0xFF6A6A6A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormatChips() {
    final formats = _visibleFormats();
    if (formats.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(bottom: BorderSide(color: Color(0xFF181818))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: formats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final format = formats[index];
          final selected = _state.formats.contains(format);

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
                        : const Color(0xFF242424),
                  ),
                ),
                child: Text(
                  fileFormatLabel(format),
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF7AABFF)
                        : const Color(0xFF6A6A6A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveChipsBar() {
    final chips = _lastBuiltQuery?.chips ?? const <QueryChipData>[];
    final removable =
        chips.where((chip) => chip.id != 'scope' && chip.id != 'tab').toList();

    if (removable.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B0B),
        border: Border(bottom: BorderSide(color: Color(0xFF171717))),
      ),
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
                border: Border.all(color: const Color(0xFF252525)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chip.label,
                    style: const TextStyle(
                      color: Color(0xFF9A9A9A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _removeChip(chip),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueryPreviewBar() {
    final built = _lastBuiltQuery;
    if (built == null || !_currentSession().hasSearched) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(bottom: BorderSide(color: Color(0xFF151515))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showQueryPreview = !_showQueryPreview;
              });
            },
            child: Row(
              children: [
                const Text(
                  'QUERY PREVIEW',
                  style: TextStyle(
                    color: Color(0xFF4E4E4E),
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _showQueryPreview
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: const Color(0xFF5C5C5C),
                ),
              ],
            ),
          ),
          if (_showQueryPreview) ...[
            const SizedBox(height: 8),
            SelectableText(
              built.debugPreview,
              style: const TextStyle(
                color: Color(0xFF8A8A8A),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<SortMode>(
      initialValue: _state.sortMode,
      onSelected: _changeSortMode,
      color: const Color(0xFF161616),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: SortMode.relevance,
          child: Text('Relevance'),
        ),
        PopupMenuItem(
          value: SortMode.titleMatch,
          child: Text('Title A–Z'),
        ),
        PopupMenuItem(
          value: SortMode.newestEdited,
          child: Text('Recently edited'),
        ),
        PopupMenuItem(
          value: SortMode.oldestEdited,
          child: Text('Least recently edited'),
        ),
        PopupMenuItem(
          value: SortMode.newestCreated,
          child: Text('Recently created'),
        ),
        PopupMenuItem(
          value: SortMode.oldestCreated,
          child: Text('Oldest created'),
        ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sortLabel(_state.sortMode),
              style: const TextStyle(
                color: Color(0xFFB0B0B0),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 16, color: Color(0xFF777777)),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Advanced filters',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Color(0xFF8A8A8A)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9A9A9A),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          controller: controller,
          style: const TextStyle(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF4A4A4A), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF181818),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D7EFF), width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerActions(
    BuildContext context, {
    required VoidCallback onApply,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF2A2A2A)),
                foregroundColor: const Color(0xFFB0B0B0),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D7EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdvanced;

  const _TopBar({
    required this.controller,
    required this.onSearch,
    required this.onAdvanced,
  });

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _listener = () => setState(() {});
    widget.controller.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) {
      widget.controller.removeListener(_listener!);
    }
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
              child: Text(
                'WIKI\nMEDIA',
                style: TextStyle(
                  color: Color(0xFF3D7EFF),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                  height: 1.5,
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  enableSuggestions: false,
                  spellCheckConfiguration:
                      const SpellCheckConfiguration.disabled(),
                  controller: widget.controller,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search media…',
                    hintStyle:
                        const TextStyle(color: Color(0xFF3A3A3A), fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF181818),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Color(0xFF3D7EFF),
                        width: 1,
                      ),
                    ),
                    suffixIcon: widget.controller.text.isNotEmpty
                        ? GestureDetector(
                            onTap: widget.controller.clear,
                            child: const Icon(
                              Icons.close,
                              size: 15,
                              color: Color(0xFF3A3A3A),
                            ),
                          )
                        : null,
                  ),
                  onSubmitted: widget.onSearch,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2A2A2A)),
                  foregroundColor: const Color(0xFFB0B0B0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: widget.onAdvanced,
                child: const Text(
                  'Filters',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: () => widget.onSearch(widget.controller.text),
                child: const Text(
                  'Search',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WikiLogo extends StatelessWidget {
  const _WikiLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E)),
        color: const Color(0xFF141414),
      ),
      child: const Icon(
        Icons.perm_media_rounded,
        size: 26,
        color: Color(0xFF3D7EFF),
      ),
    );
  }
}

class _ExampleChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ExampleChip({
    required this.label,
    required this.onTap,
  });

  @override
  State<_ExampleChip> createState() => _ExampleChipState();
}

class _ExampleChipState extends State<_ExampleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF191919) : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Color(0xFFAAAAAA),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Card
// -----------------------------------------------------------------------------

class _MediaCard extends StatefulWidget {
  final SearchItem item;
  final ValueNotifier<List<SearchItem>> searchResultsNotifier;
  final VoidCallback onLoadMore;
  final int index;
  final VoidCallback onCopied;
  final SearchState searchState;

  const _MediaCard({
    required this.item,
    required this.searchResultsNotifier,
    required this.onLoadMore,
    required this.index,
    required this.onCopied,
    required this.searchState,
  });

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  bool _hovered = false;

  Future<void> _openCommons() async {
    final url = Uri.parse(widget.item.commonsUrl);
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  Future<void> _handleTap() async {

    // Embed the full search context (query + every active filter) into the
    // URL alongside the file id, so this exact URL — pasted fresh, or
    // reached via back/forward after a reload — reconstructs the same
    // gallery and lands on the same item, not just a bare single file.
    final params = <String, String>{
      'id': widget.item.title,
      ...SearchUrlCodec.toQueryParams(widget.searchState),
    };
    final uniqueUrl = Uri(path: '/view', queryParameters: params).toString();

    print('pushing $uniqueUrl');

    context.go(
      uniqueUrl,
      extra: ViewerState(
        notifier: widget.searchResultsNotifier,
        index: widget.index,
        onLoadMore: widget.onLoadMore,
        searchState: widget.searchState,
      ),
    );
  }

  Future<void> _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: widget.item.url));
    widget.onCopied();
  }

  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.image:
        return Icons.image_outlined;
      case MediaKind.vector:
        return Icons.polyline_outlined;
      case MediaKind.audio:
        return Icons.graphic_eq_outlined;
      case MediaKind.video:
        return Icons.videocam_outlined;
      case MediaKind.document:
        return Icons.description_outlined;
      case MediaKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final kind = item.mediaKind;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        onLongPress: _copyUrl,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF131313),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF3D7EFF).withOpacity(0.55)
                  : const Color(0xFF202020),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _MediaPreview(item: item, index: widget.index),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForKind(kind),
                        size: 12,
                        color: const Color(0xFFCACACA),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        item.extension.isEmpty
                            ? item.mime.toUpperCase()
                            : item.extension.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(_hovered ? 0.08 : 0.0),
                        Colors.black.withOpacity(0.82),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.snippet.isEmpty ? item.mime : item.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
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

// -----------------------------------------------------------------------------
// Preview
// -----------------------------------------------------------------------------

class _MediaPreview extends StatefulWidget {
  final SearchItem item;
  final int index;

  const _MediaPreview({required this.item, required this.index});

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  bool _shouldLoad = false;

  @override
  void initState() {
    super.initState();
    final slot = widget.index % 25;
    if (slot == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shouldLoad = true);
      });
    } else {
      Future.delayed(Duration(milliseconds: slot * 30), () {
        if (mounted) setState(() => _shouldLoad = true);
      });
    }
  }

  @override
  void dispose() {
    if (_shouldLoad) {
      final thumb = widget.item.thumb;
      if (thumb.isNotEmpty) {
        PaintingBinding.instance.imageCache.evict(NetworkImage(thumb));
      }
    }
    super.dispose();
  }

  bool _isSafeImageUrl(String url) {
    if (url.isEmpty) return false;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldLoad) return const _PreviewLoading();

    final item = widget.item;
    final kind = item.mediaKind;

    if (kind == MediaKind.audio || kind == MediaKind.unknown) {
      return _PreviewFallback(item: item);
    }

    if (!_isSafeImageUrl(item.thumb)) {
      return _PreviewFallback(item: item);
    }

    return Image.network(
      item.thumb,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _PreviewFallback(item: item),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _PreviewLoading();
      },
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF121212)),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            color: Color(0xFF3D7EFF),
          ),
        ),
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  final SearchItem item;

  const _PreviewFallback({required this.item});

  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.image:
        return Icons.image_outlined;
      case MediaKind.vector:
        return Icons.polyline_outlined;
      case MediaKind.audio:
        return Icons.graphic_eq_outlined;
      case MediaKind.video:
        return Icons.videocam_outlined;
      case MediaKind.document:
        return Icons.description_outlined;
      case MediaKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF101010), Color(0xFF171717)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _iconForKind(item.mediaKind),
          size: 34,
          color: const Color(0xFF555555),
        ),
      ),
    );
  }
}