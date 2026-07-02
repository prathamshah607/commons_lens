import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'search_page.dart';
import 'asset_viewer.dart';
import 'search_models.dart';
import 'search_url_codec.dart';

// A simple wrapper class to pass our gallery state in-memory so repeated
// swipes inside the viewer don't have to re-hit the network. It's a fast
// path only — every navigation is also fully described by the URL itself,
// so losing this object (fresh tab, hard refresh, pasted link) never loses
// content, it just costs one extra fetch to rebuild the gallery.

class ViewerState {
  final ValueNotifier<List<SearchItem>> notifier;
  final int index;
  final VoidCallback onLoadMore;
  final SearchState? searchState;
  final String returnUrl;

  ViewerState({
    required this.notifier,
    required this.index,
    required this.onLoadMore,
    this.searchState,
    required this.returnUrl,
  });
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // 1. THE MAIN SEARCH ROUTE
    // Every distinct query + filter combination lives at its own URL
    // (see SearchUrlCodec / SearchPage._syncUrl), and SearchPage hydrates
    // itself from `state.uri.queryParameters` on first build.
    GoRoute(
      path: '/',
      builder: (context, state) {
        return const SearchPage();
      },
    ),

    // 2. THE UNIQUE MEDIA ROUTE
    GoRoute(
      path: '/view',
      builder: (context, state) {
        final params = state.uri.queryParameters;
        final fileId = params['id'] ?? '';

        // Check if we navigated here from inside the app (memory contains
        // the gallery already, so we can skip re-fetching).
        final viewerState = state.extra as ViewerState?;

        if (viewerState != null) {
          return AssetViewer(
            searchResultsNotifier: viewerState.notifier,
            initialIndex: viewerState.index,
            onLoadMore: viewerState.onLoadMore,
            explicitFileId: fileId,
            searchState: viewerState.searchState,
            returnUrl: viewerState.returnUrl,
          );
        }

        // FRESH ENTRY: no in-memory gallery — either a hard refresh, a
        // browser back/forward after reload, or a pasted URL.
        //
        // If the URL carries search context (q/filters), rebuild the whole
        // gallery from scratch so paging, load-more, and further URL sync
        // keep working exactly like an in-app navigation would.
        if (SearchUrlCodec.hasSearchContext(params)) {
          final searchState =
              SearchUrlCodec.fromQueryParams(params, const SearchState());
          return AssetViewer.fromQuery(
            fileId: fileId,
            searchState: searchState,
            returnUrl: Uri(
              path: '/',
              queryParameters: SearchUrlCodec.toQueryParams(searchState).isEmpty
                  ? null
                  : SearchUrlCodec.toQueryParams(searchState),
            ).toString(),
          );
        }

        // BARE DIRECT LINK: no search context at all, just a single file id
        // (e.g. a link copied straight from a media card). Fetch just that
        // one file.
        return AssetViewer.standalone(fileId: fileId, returnUrl: '/');
      },
    ),
  ],
);
