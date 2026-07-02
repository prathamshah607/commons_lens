import 'search_models.dart';

/// Converts a [SearchState] to/from URL query parameters so that:
///  - every distinct query + filter combination maps to a distinct URL, and
///  - that URL alone (no in-memory state) is enough to reconstruct the
///    exact same [SearchState] on a fresh page load.
class SearchUrlCodec {
  const SearchUrlCodec._();

  static Map<String, String> toQueryParams(SearchState state) {
    final params = <String, String>{};

    final q = state.queryText.trim();
    if (q.isNotEmpty) params['q'] = q;

    final tabName = state.tab.name;
    if (tabName != MediaTabType.allMedia.name) {
      params['tab'] = tabName;
    }

    if (state.formats.isNotEmpty) {
      final formats = state.formats.map((f) => f.name).toList()..sort();
      params['formats'] = formats.join(',');
    }

    if (state.categories.isNotEmpty) {
      final cats = state.categories.map((c) => c.trim()).where((c) => c.isNotEmpty).toList()
        ..sort();
      if (cats.isNotEmpty) params['cats'] = cats.join('|');
    }

    if (state.deepCategoryMode) params['deepcat'] = '1';
    if (state.titleOnly) params['titleOnly'] = '1';
    if (state.localOnly) params['local'] = '1';

    final lang = state.languageCode?.trim() ?? '';
    if (lang.isNotEmpty) params['lang'] = lang;

    final model = state.contentModel?.trim() ?? '';
    if (model.isNotEmpty) params['model'] = model;

    final createdFrom = state.createdDate?.from?.trim() ?? '';
    if (createdFrom.isNotEmpty) params['createdFrom'] = createdFrom;
    final createdTo = state.createdDate?.to?.trim() ?? '';
    if (createdTo.isNotEmpty) params['createdTo'] = createdTo;

    final editedFrom = state.editedDate?.from?.trim() ?? '';
    if (editedFrom.isNotEmpty) params['editedFrom'] = editedFrom;
    final editedTo = state.editedDate?.to?.trim() ?? '';
    if (editedTo.isNotEmpty) params['editedTo'] = editedTo;

    if (state.sortMode != SortMode.relevance) {
      params['sort'] = state.sortMode.name;
    }

    return params;
  }

  /// Rebuilds a [SearchState] from URL query parameters, layered on top of
  /// [base] (normally `const SearchState()`) so anything absent from the URL
  /// simply falls back to the default.
  static SearchState fromQueryParams(
    Map<String, String> params,
    SearchState base,
  ) {
    final tabParam = params['tab'];
    final tab = tabParam == null
        ? base.tab
        : MediaTabType.values.firstWhere(
            (t) => t.name == tabParam,
            orElse: () => base.tab,
          );

    final formatsParam = params['formats'];
    final formats = (formatsParam == null || formatsParam.isEmpty)
        ? <FileFormat>{}
        : formatsParam
            .split(',')
            .map((name) {
              try {
                return FileFormat.values.firstWhere((f) => f.name == name);
              } catch (_) {
                return null;
              }
            })
            .whereType<FileFormat>()
            .toSet();

    final catsParam = params['cats'];
    final categories = (catsParam == null || catsParam.isEmpty)
        ? <String>{}
        : catsParam.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toSet();

    final createdFrom = params['createdFrom'];
    final createdTo = params['createdTo'];
    final createdDate = (createdFrom == null && createdTo == null)
        ? null
        : DateFilter(from: createdFrom, to: createdTo);

    final editedFrom = params['editedFrom'];
    final editedTo = params['editedTo'];
    final editedDate = (editedFrom == null && editedTo == null)
        ? null
        : DateFilter(from: editedFrom, to: editedTo);

    final sortParam = params['sort'];
    final sortMode = sortParam == null
        ? SortMode.relevance
        : SortMode.values.firstWhere(
            (s) => s.name == sortParam,
            orElse: () => SortMode.relevance,
          );

    return base.copyWith(
      queryText: params['q'] ?? base.queryText,
      tab: tab,
      formats: formats,
      categories: categories,
      deepCategoryMode: params['deepcat'] == '1',
      titleOnly: params['titleOnly'] == '1',
      localOnly: params['local'] == '1',
      languageCode: params['lang'],
      contentModel: params['model'],
      createdDate: createdDate,
      editedDate: editedDate,
      sortMode: sortMode,
    );
  }

  /// True if the params carry enough context (a query) to rebuild a
  /// full search gallery rather than treating this as a bare single-file link.
  static bool hasSearchContext(Map<String, String> params) {
    return (params['q'] ?? '').trim().isNotEmpty;
  }
}
