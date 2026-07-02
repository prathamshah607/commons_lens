import 'package:commonslens/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  // Use clean path-based URLs (e.g. /view?id=...) instead of the default
  // hash-based ones (e.g. /#/view?id=...), so URLs are shareable and
  // predictable while still fully supporting deep links and reloads.
  usePathUrlStrategy();
  runApp(const WikiSearchApp());
}

class WikiSearchApp extends StatelessWidget {
  const WikiSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter, // <-- The router completely replaces 'home'
      title: 'Wiki Media Search',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0B0B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3D7EFF),
          surface: Color(0xFF161616),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E1E1E),
          contentTextStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          behavior: SnackBarBehavior.floating,
          width: 280,
        ),
      ),
    );
  }
}