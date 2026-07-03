import 'package:go_router/go_router.dart';

import 'search_page.dart';
import 'asset_viewer.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: '/view',
      builder: (context, state) {
        final params = state.uri.queryParameters;
        final fileId = params['id'] ?? '';

        final returnParams = Map<String, String>.from(params)..remove('id');
        final returnUrl = Uri(
          path: '/',
          queryParameters: returnParams.isEmpty ? null : returnParams,
        ).toString();

        return AssetViewer(fileId: fileId, returnUrl: returnUrl);
      },
    ),
  ],
);