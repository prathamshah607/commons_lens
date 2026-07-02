import 'search_models.dart';

class SearchViewState {
  final SearchState filterState;
  final SearchSession activeSession;
  final QueryBuildResult? lastBuiltQuery;

  const SearchViewState({
    required this.filterState,
    required this.activeSession,
    this.lastBuiltQuery,
  });

  SearchViewState copyWith({
    SearchState? filterState,
    SearchSession? activeSession,
    QueryBuildResult? lastBuiltQuery,
  }) {
    return SearchViewState(
      filterState: filterState ?? this.filterState,
      activeSession: activeSession ?? this.activeSession,
      lastBuiltQuery: lastBuiltQuery ?? this.lastBuiltQuery,
    );
  }
}