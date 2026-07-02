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

  // --- CACHE MANAGEMENT ---

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

  // --- ACTIONS ---

  void hydrateFromUrl(Map<String, String> params) {
    if (params.isEmpty) return;
    
    final nextFilter = SearchUrlCodec.fromQueryParams(params, const SearchState());
    _invalidateSessionKey();
    
    state = state.copyWith(
      filterState: nextFilter,
      lastBuiltQuery: _service.buildQuery(nextFilter),
    );

    if (nextFilter.queryText.isNotEmpty) {
      search(nextFilter.queryText);
    } else {
      state = state.copyWith(activeSession: _getSession(nextFilter));
    }
  }

  Future<void> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    final generation = ++_searchGeneration;
    final nextFilter = state.filterState.copyWith(queryText: cleanQuery);
    
    _invalidateSessionKey();
    
    // Set loading state
    final loadingSession = const SearchSession().copyWith(
      hasSearched: true,
      loading: true,
      items: [],
      scrollOffset: 0,
    );
    
    _sessions[_currentSessionKey(nextFilter)] = loadingSession;
    
    state = state.copyWith(
      filterState: nextFilter,
      lastBuiltQuery: _service.buildQuery(nextFilter),
      activeSession: loadingSession,
    );

    final result = await _service.fetchPage(nextFilter, continueParams: null);
    if (generation != _searchGeneration) return; // Prevent race conditions

    if (result == null) {
      _updateSession(nextFilter, loadingSession.copyWith(
        loading: false,
        error: 'Search failed — check your connection.',
      ));
      return;
    }

    final sortedItems = nextFilter.sortMode == SortMode.relevance
        ? result.items
        : _service.applyClientSort(result.items, nextFilter.sortMode);

    _updateSession(nextFilter, loadingSession.copyWith(
      items: sortedItems,
      continueParams: result.continueParams,
      hasMore: result.continueParams != null,
      loading: false,
    ));
  }

  Future<void> loadMore() async {
    final currentSession = state.activeSession;
    if (currentSession.loadingMore || !currentSession.hasMore || state.filterState.queryText.isEmpty) {
      return;
    }

    final generation = _searchGeneration;
    _updateSession(state.filterState, currentSession.copyWith(loadingMore: true));

    final result = await _service.fetchPage(
      state.filterState,
      continueParams: currentSession.continueParams,
    );
    
    if (generation != _searchGeneration) return;

    if (result == null) {
      _updateSession(state.filterState, currentSession.copyWith(loadingMore: false));
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

    _updateSession(state.filterState, currentSession.copyWith(
      items: sortedItems,
      continueParams: result.continueParams,
      hasMore: result.continueParams != null,
      loadingMore: false,
    ));
  }

  // --- FILTER MUTATIONS ---

  void applyFilterUpdate(SearchState Function(SearchState current) updater) {
    final nextFilter = updater(state.filterState);
    if (nextFilter == state.filterState) return;

    _invalidateSessionKey();
    state = state.copyWith(
      filterState: nextFilter,
      lastBuiltQuery: _service.buildQuery(nextFilter),
      activeSession: _getSession(nextFilter), // Pull from cache if it exists
    );

    if (nextFilter.queryText.trim().isNotEmpty) {
      search(nextFilter.queryText);
    }
  }

  void saveScrollOffset(double offset) {
    _updateSession(state.filterState, state.activeSession.copyWith(scrollOffset: offset));
  }
}