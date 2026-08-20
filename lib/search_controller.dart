import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_models.dart';
import 'search_service.dart';
import 'search_view_state.dart';
import 'search_url_codec.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchViewState>(SearchController.new);

class SearchController extends Notifier<SearchViewState> {
  final SearchService _service = SearchService();
  final Map<SearchSessionKey, SearchSession> _sessions = {};

  SearchSessionKey? _cachedSessionKey;
  int _searchGeneration = 0;

  @override
  SearchViewState build() {
    const initialFilter = SearchState();
    return SearchViewState(
      filterState: initialFilter,
      activeSession: const SearchSession(),
      lastBuiltQuery: _service.buildQuery(initialFilter),
    );
  }

  void _invalidateSessionKey() {
    _cachedSessionKey = null;
  }

  SearchSessionKey _currentSessionKey(SearchState filter) {
    return _cachedSessionKey ??= SearchSessionKey(
      tab: filter.tab,
      querySignature: _service.buildQuerySignature(filter),
    );
  }

  SearchSession _getSession(SearchState filter) {
    return _sessions[_currentSessionKey(filter)] ?? const SearchSession();
  }

  void _updateSession(SearchState filter, SearchSession session) {
    _sessions[_currentSessionKey(filter)] = session;
    state = state.copyWith(activeSession: session);
  }

  void hydrateFromUrl(Map<String, String> params) {
    if (params.isEmpty) return;

    final nextFilter =
        SearchUrlCodec.fromQueryParams(params, const SearchState());
    _invalidateSessionKey();

    final built = _service.buildQuery(nextFilter);
    state = state.copyWith(
      filterState: nextFilter,
      lastBuiltQuery: built,
    );

    if (built.srsearch.trim().isNotEmpty) {
      search(nextFilter.queryText);
    } else {
      state = state.copyWith(activeSession: _getSession(nextFilter));
    }
  }

  Future<void> search(String query, {SearchState? overrideState}) async {
    if (overrideState != null) {
      state = state.copyWith(filterState: overrideState);
    }

    final cleanQuery = query.trim();
    final generation = ++_searchGeneration;
    final nextFilter = state.filterState.copyWith(queryText: cleanQuery);
    final built = _service.buildQuery(nextFilter);

    // A search with no free-text query is still valid if filters alone
    // (depicts, category, license, etc.) produce a non-empty CirrusSearch
    // query — e.g. just "haswbstatement:P180=Q123" for depicts-only.
    if (built.srsearch.trim().isEmpty) return;

    _invalidateSessionKey();

    final loadingSession = const SearchSession().copyWith(
      hasSearched: true,
      loading: true,
      items: [],
      scrollOffset: 0,
    );

    _sessions[_currentSessionKey(nextFilter)] = loadingSession;

    state = state.copyWith(
      filterState: nextFilter,
      lastBuiltQuery: built,
      activeSession: loadingSession,
    );

    final result = await _service.fetchPage(nextFilter, continueParams: null);
    if (generation != _searchGeneration) return;

    if (result == null) {
      _updateSession(
          nextFilter,
          loadingSession.copyWith(
            loading: false,
            error: 'Search failed: Please check your internet connection.',
          ));
      return;
    }

    final sortedItems = nextFilter.sortMode == SortMode.relevance
        ? result.items
        : _service.applyClientSort(result.items, nextFilter.sortMode);

    _updateSession(
        nextFilter,
        loadingSession.copyWith(
          items: sortedItems,
          continueParams: result.continueParams,
          hasMore: result.continueParams != null,
          loading: false,
        ));
  }

  Future<void> loadMore() async {
    final currentSession = state.activeSession;
    if (currentSession.loadingMore || !currentSession.hasMore) {
      return;
    }

    final generation = _searchGeneration;
    _updateSession(
        state.filterState, currentSession.copyWith(loadingMore: true));

    final result = await _service.fetchPage(
      state.filterState,
      continueParams: currentSession.continueParams,
    );

    if (generation != _searchGeneration) return;

    if (result == null) {
      _updateSession(
          state.filterState, currentSession.copyWith(loadingMore: false));
      return;
    }

    final existingUrls = currentSession.items.map((e) => e.url).toSet();
    final merged = [
      ...currentSession.items,
      ...result.items.where((item) => !existingUrls.contains(item.url)),
    ];

    final sortedItems = state.filterState.sortMode == SortMode.relevance
        ? merged
        : _service.applyClientSort(merged, state.filterState.sortMode);

    _updateSession(
        state.filterState,
        currentSession.copyWith(
          items: sortedItems,
          continueParams: result.continueParams,
          hasMore: result.continueParams != null,
          loadingMore: false,
        ));
  }

  void applyFilterUpdate(SearchState Function(SearchState current) updater) {
    final nextFilter = updater(state.filterState);
    if (nextFilter == state.filterState) return;

    _invalidateSessionKey();
    final built = _service.buildQuery(nextFilter);
    state = state.copyWith(
      filterState: nextFilter,
      lastBuiltQuery: built,
      activeSession: _getSession(nextFilter),
    );

    if (built.srsearch.trim().isNotEmpty) {
      search(nextFilter.queryText);
    }
  }

  void saveScrollOffset(double offset) {
    _updateSession(
        state.filterState, state.activeSession.copyWith(scrollOffset: offset));
  }
}

/// Paginated session for a single uploader's portfolio (list=allimages),
/// keyed by username. Deliberately kept separate from [SearchController]:
/// it's not a CirrusSearch session, has no SearchState/filters, and its
/// own continuation tokens — but it reuses the exact same [SearchSession]
/// shape, so it drops into the same grid/pagination UI unchanged.
final authorPortfolioProvider =
    NotifierProvider.family<AuthorPortfolioController, SearchSession, String>(
        AuthorPortfolioController.new);

class AuthorPortfolioController extends FamilyNotifier<SearchSession, String> {
  final SearchService _service = SearchService();
  int _generation = 0;

  @override
  SearchSession build(String username) {
    _loadInitial(username);
    return const SearchSession(hasSearched: true, loading: true);
  }

  Future<void> _loadInitial(String username) async {
    final generation = ++_generation;
    final result = await _service.fetchAuthorImages(username);
    if (generation != _generation) return;

    if (result == null) {
      state = state.copyWith(
        loading: false,
        error: 'Could not load this uploader\'s portfolio.',
      );
      return;
    }

    state = state.copyWith(
      items: result.items,
      continueParams: result.continueParams,
      hasMore: result.continueParams != null,
      loading: false,
    );
  }

  Future<void> loadMore(String username) async {
    if (state.loadingMore || !state.hasMore) return;

    final generation = _generation;
    state = state.copyWith(loadingMore: true);

    final result = await _service.fetchAuthorImages(
      username,
      continueParams: state.continueParams,
    );

    if (generation != _generation) return;

    if (result == null) {
      state = state.copyWith(loadingMore: false);
      return;
    }

    final existingUrls = state.items.map((e) => e.url).toSet();
    final merged = [
      ...state.items,
      ...result.items.where((item) => !existingUrls.contains(item.url)),
    ];

    state = state.copyWith(
      items: merged,
      continueParams: result.continueParams,
      hasMore: result.continueParams != null,
      loadingMore: false,
    );
  }
}
