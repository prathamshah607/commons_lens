import 'dart:html' as html;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'search_models.dart';

class DownloadService {
  // Deliberately NOT sending a custom header (e.g. Api-User-Agent) here.
  // upload.wikimedia.org is the raw media storage layer, not the MediaWiki
  // API — unlike commons.wikimedia.org/w/api.php and
  // www.wikidata.org/w/api.php, it's not confirmed to allow custom headers
  // in its CORS policy. Any custom header turns a "simple" cross-origin GET
  // into one that requires a CORS preflight (OPTIONS) first; if that
  // preflight isn't explicitly allowed, the browser blocks the request
  // before it ever reaches the network — every download fails identically
  // and instantly, with no distinguishing error. Plain http.get with no
  // extra headers is what actually works here.

  static Future<void> downloadSingleFile(String url, String title, String extension) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final cleanTitle = title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll('File:', '')
            .trim();
        final fileName = '$cleanTitle.${extension.toLowerCase()}';

        final blob = html.Blob([response.bodyBytes], response.headers['content-type'] ?? 'application/octet-stream');
        final objectUrl = html.Url.createObjectUrlFromBlob(blob);

        html.AnchorElement(href: objectUrl)
          ..setAttribute("download", fileName)
          ..click();

        html.Url.revokeObjectUrl(objectUrl);
      }
    } catch (e) {
      print('Download failed: $e');
      html.window.open(url, '_blank');
    }
  }

  /// Fetches one file with a timeout and a couple of retries on transient
  /// failure (timeout, dropped connection, 5xx). Does NOT retry on 4xx —
  /// that's a real rejection (e.g. gone/forbidden), not a transient blip.
  static Future<http.Response?> _fetchWithRetry(
    String url, {
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(timeout);

        if (response.statusCode == 200) return response;
        if (response.statusCode >= 400 && response.statusCode < 500) {
          // Real rejection — retrying won't help.
          return null;
        }
        // 5xx or unexpected — fall through to retry.
      } catch (_) {
        // Timeout or network error — fall through to retry.
      }

      if (attempt < maxAttempts) {
        // Backoff before retrying, so a struggling server gets breathing
        // room instead of getting hammered again immediately.
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

  /// Downloads [items] as a single zip. Runs up to [concurrency] fetches in
  /// parallel (bounded, not unlimited — polite to Wikimedia's servers and
  /// avoids opening hundreds of simultaneous connections) instead of one at
  /// a time, which is the main lever for finishing a large batch in a
  /// reasonable window. [onProgress] reports (completed, total, failedTitles)
  /// after every file, so a caller can show real progress instead of a
  /// single silent wait — and so failures are visible instead of only
  /// living in a print() no one sees.
  ///
  /// Honest limits, unchanged by this fix: everything is still held in
  /// memory until the zip is built, and this still only runs while the
  /// browser tab is alive and unthrottled. There's no way to make a
  /// client-side, tab-bound download truly survive the tab being
  /// suspended/discarded overnight — that would need a server-side job
  /// queue, which is a different architecture.
  static Future<void> downloadBulkZip(
    List<SearchItem> items, {
    String zipName = 'commons_export.zip',
    int concurrency = 5,
    void Function(int completed, int total, List<String> failedTitles)? onProgress,
  }) async {
    if (items.isEmpty) return;

    final archive = Archive();
    final failedTitles = <String>[];
    var completed = 0;

    Future<void> fetchOne(SearchItem item) async {
      final response = await _fetchWithRetry(item.url);

      if (response != null) {
        final cleanTitle = item.title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll('File:', '')
            .trim();

        final fileName = '$cleanTitle.${item.extension.toLowerCase()}';
        archive.addFile(
            ArchiveFile(fileName, response.bodyBytes.length, response.bodyBytes));
      } else {
        failedTitles.add(item.title);
      }

      completed++;
      onProgress?.call(completed, items.length, failedTitles);
    }

    // Bounded parallelism: process items in chunks of `concurrency` rather
    // than either "all 500 at once" (too many simultaneous connections) or
    // "one at a time" (the current 30s/image -> 4+ hour problem).
    for (var i = 0; i < items.length; i += concurrency) {
      final chunk = items.skip(i).take(concurrency);
      await Future.wait(chunk.map(fetchOne));
    }

    if (archive.isEmpty) return;

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) return;

    final blob = html.Blob([zipData], 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download", zipName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }
}