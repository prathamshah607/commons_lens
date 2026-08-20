import 'package:go_router/go_router.dart';

import 'search_page.dart';
import 'asset_viewer.dart';
import 'author_portfolio_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: '/author',
      builder: (context, state) {
        final name = state.uri.queryParameters['name'] ?? '';
        return AuthorPortfolioPage(username: name);
      },
    ),
    GoRoute(
      path: '/view',
      builder: (context, state) {
        final params = state.uri.queryParameters;
        final fileId = params['id'] ?? '';
        final author = params['author'];

        final String returnUrl;
        if (author != null && author.trim().isNotEmpty) {
          returnUrl =
              Uri(path: '/author', queryParameters: {'name': author}).toString();
        } else {
          final returnParams = Map<String, String>.from(params)..remove('id');
          returnUrl = Uri(
            path: '/',
            queryParameters: returnParams.isEmpty ? null : returnParams,
          ).toString();
        }

        return AssetViewer(fileId: fileId, returnUrl: returnUrl);
      },
    ),
  ],
);