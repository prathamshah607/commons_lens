// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'search_components.dart'; // <-- Your single UI file

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _contentModelController = TextEditingController();
  final TextEditingController _createdFromController = TextEditingController();
  final TextEditingController _createdToController = TextEditingController();
  final TextEditingController _editedFromController = TextEditingController();
  final TextEditingController _editedToController = TextEditingController();

  bool _urlHydrated = false;
  bool _showQueryPreview = false;

  static const _examples = [
    'Apollo 11',
    'Black hole',
    'Colosseum',
    'DNA helix',
    'Hokusai',
    'Solar system'
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

    _scrollController.dispose();
    _categoryController.dispose();
    _languageController.dispose();
    _contentModelController.dispose();
    _createdFromController.dispose();
    _createdToController.dispose();
    _editedFromController.dispose();
    _editedToController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
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
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((current) {
      if (chip.id.startsWith('format:')) {
        final formatName = chip.id.split(':').last;
        return current.copyWith(
            formats: Set<FileFormat>.from(current.formats)
              ..removeWhere((f) => f.name == formatName));
      } else if (chip.id.startsWith('category:')) {
        final categoryName = chip.id.substring('category:'.length);
        return current.copyWith(
            categories: Set<String>.from(current.categories)
              ..remove(categoryName));
      } else if (chip.id == 'titleOnly')
        return current.copyWith(titleOnly: false);
      else if (chip.id == 'language')
        return current.copyWith(clearLanguageCode: true);
      else if (chip.id == 'contentModel')
        return current.copyWith(clearContentModel: true);
      else if (chip.id == 'localOnly')
        return current.copyWith(localOnly: false);
      else if (chip.id == 'createdFrom' || chip.id == 'createdTo')
        return current.copyWith(clearCreatedDate: true);
      else if (chip.id == 'editedFrom' || chip.id == 'editedTo')
        return current.copyWith(clearEditedDate: true);
      return current;
    });
  }

  Future<void> _openAdvancedFilters() async {
    final currentState = ref.read(searchControllerProvider).filterState;
    _categoryController.text = currentState.categories.join(', ');
    _languageController.text = currentState.languageCode ?? '';
    _contentModelController.text = currentState.contentModel ?? '';
    _createdFromController.text = currentState.createdDate?.from ?? '';
    _createdToController.text = currentState.createdDate?.to ?? '';
    _editedFromController.text = currentState.editedDate?.from ?? '';
    _editedToController.text = currentState.editedDate?.to ?? '';

    bool titleOnly = currentState.titleOnly;
    bool deepCategoryMode = currentState.deepCategoryMode;
    bool localOnly = currentState.localOnly;

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
                                  hint: 'Maps, Astronomy, Diagrams'),
                              const SizedBox(height: 14),
                              SwitchListTile(
                                  value: deepCategoryMode,
                                  onChanged: (v) =>
                                      setModalState(() => deepCategoryMode = v),
                                  title: const Text('Include subcategories'),
                                  activeColor: const Color(0xFF3D7EFF)),
                              SwitchListTile(
                                  value: titleOnly,
                                  onChanged: (v) =>
                                      setModalState(() => titleOnly = v),
                                  title: const Text('Search title only'),
                                  activeColor: const Color(0xFF3D7EFF)),
                              SwitchListTile(
                                  value: localOnly,
                                  onChanged: (v) =>
                                      setModalState(() => localOnly = v),
                                  title: const Text('Local only'),
                                  activeColor: const Color(0xFF3D7EFF)),
                              const SizedBox(height: 12),
                              _buildDrawerTextField(
                                  controller: _languageController,
                                  label: 'Language code',
                                  hint: 'en, fr, ja'),
                              const SizedBox(height: 12),
                              _buildDrawerTextField(
                                  controller: _contentModelController,
                                  label: 'Content model',
                                  hint: 'json'),
                              const SizedBox(height: 18),
                              const Text('Created date',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                      child: _buildDrawerTextField(
                                          controller: _createdFromController,
                                          label: 'From',
                                          hint: '2024 or 2024-01')),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: _buildDrawerTextField(
                                          controller: _createdToController,
                                          label: 'To',
                                          hint: '2025 or 2025-12')),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Text('Edited date',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                      child: _buildDrawerTextField(
                                          controller: _editedFromController,
                                          label: 'From',
                                          hint: '2024 or today-1y')),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: _buildDrawerTextField(
                                          controller: _editedToController,
                                          label: 'To',
                                          hint: '2025 or today')),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _buildDrawerActions(
                          context,
                          onApply: () {
                            ref
                                .read(searchControllerProvider.notifier)
                                .applyFilterUpdate((current) {
                              final categories = _categoryController.text
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toSet();
                              return current.copyWith(
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
                                            : _createdToController.text.trim()),
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
                                            : _editedToController.text.trim()),
                              );
                            });
                            Navigator.of(context).pop();
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

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: Column(
        children: [
          SearchTopBar(
            initialQuery: filterState.queryText,
            onSearch: _search,
            onAdvanced: _openAdvancedFilters,
          ),
          _buildTabBar(filterState),
          _buildFormatChips(filterState),
          _buildActiveChipsBar(viewState.lastBuiltQuery),
          _buildQueryPreviewBar(viewState.lastBuiltQuery, session.hasSearched),
          Expanded(
              child: session.hasSearched
                  ? _buildResults(session, filterState)
                  : _buildLanding()),
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
              const WikiLogo(),
              const SizedBox(height: 28),
              const Text('Search all media from Wikimedia Commons',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.4,
                      height: 1.3)),
              const SizedBox(height: 10),
              const Text(
                  'Images, vectors, audio, video, and documents — with format filters and advanced search controls.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF505050), fontSize: 14, height: 1.6)),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _examples
                    .map((q) => ExampleChip(label: q, onTap: () => _search(q)))
                    .toList(),
              ),
            ],
          ),
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
                maxCrossAxisExtent: 210,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
                childAspectRatio: 1.25),
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

  Widget _buildDrawerHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E)))),
      child: Row(
        children: [
          const Expanded(
              child: Text('Advanced filters',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600))),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Color(0xFF8A8A8A))),
        ],
      ),
    );
  }

  Widget _buildDrawerTextField(
      {required TextEditingController controller,
      required String label,
      required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF9A9A9A),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF3D7EFF), width: 1)),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerActions(BuildContext context,
      {required VoidCallback onApply}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E1E1E)))),
      child: Row(
        children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2A2A2A)),
                      foregroundColor: const Color(0xFFB0B0B0),
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('Cancel'))),
          const SizedBox(width: 10),
          Expanded(
              child: ElevatedButton(
                  onPressed: onApply,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D7EFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('Apply'))),
        ],
      ),
    );
  }
}
