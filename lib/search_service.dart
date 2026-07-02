import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_models.dart';

class SearchService {
  static const int pageSize = 50;
  
  // OPTIMIZATION 1: Persistent HTTP Client for connection pooling.
  // Reuses TCP/TLS handshakes across Scatter-Gather streams and pagination.
  static final http.Client _client = http.Client();

  // OPTIMIZATION 2: Pre-compiled Regex.
  // Prevents recompiling the pattern 30+ times per network response.
  static final RegExp _htmlTagRegex = RegExp(r'<[^>]*>');

  // --- NEW: STANDALONE DIRECT FETCH ---
  // Fetches a single specific piece of media by its exact title for deep linking.
  Future<SearchItem?> fetchSingleItem(String filename) async {
    try {
      // Wikimedia requires the 'File:' prefix for explicit title lookups
      final title = filename.startsWith('File:') ? filename : 'File:$filename';
      
      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': title,
        'prop': 'info|imageinfo',
        'inprop': 'url',
        'iiprop': 'url|size|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      
      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      if (pages.isEmpty) return null;

      // Extract the exact page
      final page = pages.values.first;
      
      // If the page has "missing": "", it means the file doesn't exist
      if (page.containsKey('missing')) return null;

      final infoList = page['imageinfo'] as List?;
      if (infoList == null || infoList.isEmpty) return null;

      final info = infoList.first as Map<String, dynamic>;
      final mime = (info['mime'] as String? ?? '').toLowerCase();
      final isSvg = mime == 'image/svg+xml';

      final thumburl = info['thumburl'] as String? ?? '';
      final originalUrl = info['url'] as String? ?? '';
      final descriptionUrl = page['fullurl'] as String?;
      final thumb = thumburl.isNotEmpty ? thumburl : originalUrl;

      if (originalUrl.isEmpty) return null;

      final rawTitle = page['title'] as String? ?? '';
      
      // Extended Metadata Parsing
      final ext = info['extmetadata'] as Map<String, dynamic>? ?? {};
      final artistHtml = ext['Artist']?['value']?.toString() ?? '';
      final licenseShort = ext['LicenseShortName']?['value']?.toString() ?? '';
      final licenseUrl = ext['LicenseUrl']?['value']?.toString() ?? '';
      final dateTimeOriginal = ext['DateTimeOriginal']?['value']?.toString() ?? '';
      
      final uploader = info['user']?.toString() ?? '';
      final width = info['width'] as int? ?? 0;
      final height = info['height'] as int? ?? 0;

      return SearchItem(
        title: rawTitle.replaceFirst('File:', ''),
        url: originalUrl,
        thumb: thumb,
        commonsUrl: 'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(rawTitle)}',
        // In direct title lookups, the snippet isn't returned natively by 'prop=info', 
        // so we gracefully fall back to the title as the description header.
        snippet: rawTitle, 
        mime: mime,
        isSvg: isSvg,
        timestamp: page['timestamp'] as String?,
        descriptionUrl: descriptionUrl,
        artistHtml: artistHtml,
        licenseShortName: licenseShort,
        licenseUrl: licenseUrl,
        dateTimeOriginal: dateTimeOriginal,
        uploader: uploader,
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  // --- QUERY BUILDER ---
  QueryBuildResult buildQuery(SearchState state, {FileFormat? overrideFormat}) {
    final parts = <String>[];
    final chips = <QueryChipData>[];

    if (state.localOnly) {
      parts.add('local:');
      chips.add(const QueryChipData(id: 'localOnly', label: 'Local only'));
    }

    final queryText = state.queryText.trim();
    if (queryText.isNotEmpty) {
      if (state.titleOnly) {
        parts.add('intitle:"$queryText"');
        chips.add(const QueryChipData(id: 'titleOnly', label: 'Title only'));
      } else {
        parts.add(queryText);
      }
    }

    // 1. Tab Macro Filters
    switch (state.tab) {
      case MediaTabType.allMedia:
        chips.add(const QueryChipData(id: 'tab', label: 'All media'));
        break;
      case MediaTabType.images:
        chips.add(const QueryChipData(id: 'tab', label: 'Images'));
        parts.add('filetype:bitmap');
        break;
      case MediaTabType.vectors:
        chips.add(const QueryChipData(id: 'tab', label: 'SVG / Diagrams'));
        parts.add('filetype:drawing');
        break;
      case MediaTabType.audio:
        chips.add(const QueryChipData(id: 'tab', label: 'Audio'));
        parts.add('filetype:audio');
        break;
      case MediaTabType.video:
        chips.add(const QueryChipData(id: 'tab', label: 'Video'));
        parts.add('filetype:video');
        break;
      case MediaTabType.documents:
        chips.add(const QueryChipData(id: 'tab', label: 'Docs'));
        parts.add('filetype:office');
        break;
    }

    // Generate chips for the UI regardless of override
    for (final format in state.formats.toList()
      ..sort((a, b) => a.name.compareTo(b.name))) {
      chips.add(
        QueryChipData(
          id: 'format:${format.name}',
          label: fileFormatLabel(format),
        ),
      );
    }

    // 2. The Micro Filter: Apply exact CirrusSearch filemime for Scatter-Gather
    if (overrideFormat != null) {
      parts.add('filemime:"${_getMimeString(overrideFormat)}"');
    }

    for (final category in state.categories.toList()..sort()) {
      final safe = category.trim();
      if (safe.isEmpty) continue;

      if (state.deepCategoryMode) {
        parts.add('deepcat:"$safe"');
        chips.add(QueryChipData(id: 'category:$safe', label: 'Deep category: $safe'));
      } else {
        parts.add('incategory:"$safe"');
        chips.add(QueryChipData(id: 'category:$safe', label: 'Category: $safe'));
      }
    }

    if (state.languageCode != null && state.languageCode!.trim().isNotEmpty) {
      final lang = state.languageCode!.trim();
      parts.add('inlanguage:$lang');
      chips.add(QueryChipData(id: 'language', label: 'Language: $lang'));
    }

    if (state.contentModel != null && state.contentModel!.trim().isNotEmpty) {
      final model = state.contentModel!.trim();
      parts.add('contentmodel:$model');
      chips.add(QueryChipData(id: 'contentModel', label: 'Model: $model'));
    }

    if (state.createdDate != null) {
      final created = state.createdDate!;
      if (created.from != null && created.from!.trim().isNotEmpty) {
        final from = created.from!.trim();
        parts.add('creationdate:>=$from');
        chips.add(QueryChipData(id: 'createdFrom', label: 'Created ≥ $from'));
      }
      if (created.to != null && created.to!.trim().isNotEmpty) {
        final to = created.to!.trim();
        parts.add('creationdate:<$to');
        chips.add(QueryChipData(id: 'createdTo', label: 'Created < $to'));
      }
    }

    if (state.editedDate != null) {
      final edited = state.editedDate!;
      if (edited.from != null && edited.from!.trim().isNotEmpty) {
        final from = edited.from!.trim();
        parts.add('lasteditdate:>=$from');
        chips.add(QueryChipData(id: 'editedFrom', label: 'Edited ≥ $from'));
      }
      if (edited.to != null && edited.to!.trim().isNotEmpty) {
        final to = edited.to!.trim();
        parts.add('lasteditdate:<$to');
        chips.add(QueryChipData(id: 'editedTo', label: 'Edited < $to'));
      }
    }

    final srsearch = parts.join(' ').trim();

    return QueryBuildResult(
      srsearch: srsearch,
      chips: chips,
      debugPreview: srsearch,
    );
  }

  String buildQuerySignature(SearchState state) {
    final built = buildQuery(state);
    final formats = state.formats.map((f) => f.name).toList()..sort();
    final categories = state.categories.toList()..sort();

    return [
      built.srsearch,
      'formats=${formats.join(",")}',
      'categories=${categories.join(",")}',
      'deep=${state.deepCategoryMode}',
      'titleOnly=${state.titleOnly}',
      'localOnly=${state.localOnly}',
      'lang=${state.languageCode ?? ""}',
      'model=${state.contentModel ?? ""}',
      'createdFrom=${state.createdDate?.from ?? ""}',
      'createdTo=${state.createdDate?.to ?? ""}',
      'editedFrom=${state.editedDate?.from ?? ""}',
      'editedTo=${state.editedDate?.to ?? ""}',
      'sort=${state.sortMode.name}',
    ].join('|');
  }

  // --- THE SCATTER-GATHER ORCHESTRATOR ---
  Future<SearchResponse?> fetchPage(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    // Phase 1: No specific chips selected -> Do a normal macro fetch.
    if (state.formats.isEmpty) {
      return _fetchSingle(state, continueParams: continueParams, overrideFormat: null);
    }

    // Phase 2: Fan-Out (Scatter) to multiple parallel streams.
    final streams = <FileFormat, List<SearchItem>>{};
    final newMultiContinue = <String, dynamic>{};
    bool anySuccess = false;

    // Unpack the multi-cursor dictionary
    final multiTokens = continueParams?['_multi'] as Map<String, dynamic>?;

    final futures = <Future<void>>[];

    for (final format in state.formats) {
      final formatKey = format.name;

      // If we are paging, and this format's stream is empty, skip it.
      if (continueParams != null && multiTokens != null && !multiTokens.containsKey(formatKey)) {
        continue;
      }

      final formatContinue = multiTokens?[formatKey] as Map<String, dynamic>?;

      futures.add(() async {
        final result = await _fetchSingle(state, continueParams: formatContinue, overrideFormat: format);
        if (result != null) {
          anySuccess = true;
          streams[format] = result.items;
          if (result.continueParams != null) {
            newMultiContinue[formatKey] = result.continueParams;
          }
        }
      }());
    }

    await Future.wait(futures);

    if (!anySuccess && streams.isEmpty) return null;

    // Phase 3: Fan-In & Arrange
    final sortedItems = _multiSort(streams, state.sortMode);

    return SearchResponse(
      items: sortedItems,
      // Repack the multi-cursor dictionary
      continueParams: newMultiContinue.isNotEmpty ? {'_multi': newMultiContinue} : null,
    );
  }

  Future<SearchResponse?> _fetchSingle(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    FileFormat? overrideFormat,
  }) async {
    try {
      final built = buildQuery(state, overrideFormat: overrideFormat);

      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'uselang': 'en',
        'generator': 'search',
        'gsrsearch': built.srsearch,
        'gsrlimit': '$pageSize',
        'gsrinfo': 'totalhits|suggestion',
        'gsrprop': 'size|wordcount|timestamp|snippet',
        'prop': 'info|imageinfo',
        'inprop': 'url',
        'gsrnamespace': '6',
        // EXTENDED PAYLOAD: Added extmetadata, user, and dimensions
        'iiprop': 'url|size|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      switch (state.sortMode) {
        case SortMode.relevance:
        case SortMode.titleMatch:
          break;
        case SortMode.newestEdited:
          params['gsrsort'] = 'last_edit_desc';
          break;
        case SortMode.oldestEdited:
          params['gsrsort'] = 'last_edit_asc';
          break;
        case SortMode.newestCreated:
          params['gsrsort'] = 'create_timestamp_desc';
          break;
        case SortMode.oldestCreated:
          params['gsrsort'] = 'create_timestamp_asc';
          break;
      }

      if (continueParams != null) {
        for (final entry in continueParams.entries) {
          params[entry.key] = entry.value.toString();
        }
      }

      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      
      // OPTIMIZATION: Reusing the persistent HTTP client
      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final nextContinue = data['continue'] as Map<String, dynamic>?;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      final items = <SearchItem>[];
      for (final page in pages.values) {
        final infoList = page['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) continue;

        final info = infoList.first as Map<String, dynamic>;
        final mime = (info['mime'] as String? ?? '').toLowerCase();
        final isSvg = mime == 'image/svg+xml';

        final thumburl = info['thumburl'] as String? ?? '';
        final originalUrl = info['url'] as String? ?? '';
        final descriptionUrl = page['fullurl'] as String?;
        final thumb = thumburl.isNotEmpty ? thumburl : originalUrl;

        if (originalUrl.isEmpty) continue;

        final rawTitle = page['title'] as String? ?? '';
        
        // NEW: Extended Metadata Parsing
        final ext = info['extmetadata'] as Map<String, dynamic>? ?? {};
        final artistHtml = ext['Artist']?['value']?.toString() ?? '';
        final licenseShort = ext['LicenseShortName']?['value']?.toString() ?? '';
        final licenseUrl = ext['LicenseUrl']?['value']?.toString() ?? '';
        final dateTimeOriginal = ext['DateTimeOriginal']?['value']?.toString() ?? '';
        
        final uploader = info['user']?.toString() ?? '';
        final width = info['width'] as int? ?? 0;
        final height = info['height'] as int? ?? 0;

        items.add(
          SearchItem(
            title: rawTitle.replaceFirst('File:', ''),
            url: originalUrl,
            thumb: thumb,
            commonsUrl: 'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(rawTitle)}',
            snippet: _stripHtml(page['snippet'] as String? ?? rawTitle),
            mime: mime,
            isSvg: isSvg,
            timestamp: page['timestamp'] as String?,
            descriptionUrl: descriptionUrl,
            // New fields injected into the model
            artistHtml: artistHtml,
            licenseShortName: licenseShort,
            licenseUrl: licenseUrl,
            dateTimeOriginal: dateTimeOriginal,
            uploader: uploader,
            width: width,
            height: height,
          ),
        );
      }

      // If we aren't enforcing a strict format, run the safety filter
      final filteredItems = overrideFormat == null
          ? items.where((item) => _matchesMacroFormat(item, state.formats)).toList()
          : items;

      return SearchResponse(items: filteredItems, continueParams: nextContinue);
    } catch (_) {
      return null;
    }
  }

  // --- THE MERGER & ARRANGER ---
  List<SearchItem> _multiSort(Map<FileFormat, List<SearchItem>> streams, SortMode mode) {
    final result = <SearchItem>[];

    if (mode == SortMode.relevance) {
      // Relevance Round-Robin: Preserves Wikipedia's internal scoring by taking the top result of each stream sequentially
      bool added = true;
      int i = 0;
      while (added) {
        added = false;
        for (final list in streams.values) {
          if (i < list.length) {
            result.add(list[i]);
            added = true;
          }
        }
        i++;
      }
    } else {
      // Dump all and apply hard sorts
      for (final list in streams.values) {
        result.addAll(list);
      }

      if (mode == SortMode.titleMatch) {
        result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      } else {
        // Date strings are ISO8601 so standard string comparison works perfectly
        result.sort((a, b) {
          final tA = a.timestamp ?? '';
          final tB = b.timestamp ?? '';
          final cmp = tA.compareTo(tB);
          if (mode == SortMode.newestCreated || mode == SortMode.newestEdited) {
            return -cmp; 
          }
          return cmp; 
        });
      }
    }

    return result;
  }

  String _getMimeString(FileFormat format) {
    switch (format) {
      case FileFormat.jpg:
      case FileFormat.jpeg: return 'image/jpeg';
      case FileFormat.png: return 'image/png';
      case FileFormat.svg: return 'image/svg+xml';
      case FileFormat.gif: return 'image/gif';
      case FileFormat.tif:
      case FileFormat.tiff: return 'image/tiff';
      case FileFormat.webp: return 'image/webp';
      case FileFormat.pdf: return 'application/pdf';
      case FileFormat.djvu: return 'image/vnd.djvu'; 
      case FileFormat.ogg:
      case FileFormat.oga: return 'audio/ogg';
      case FileFormat.wav: return 'audio/wav';
      case FileFormat.webm: return 'video/webm';
      case FileFormat.mp4: return 'video/mp4';
    }
  }

  bool _matchesMacroFormat(SearchItem item, Set<FileFormat> formats) {
    if (formats.isEmpty) return true;
    final ext = item.extension;
    final mime = item.mime.toLowerCase();

    for (final format in formats) {
      switch (format) {
        case FileFormat.jpg: if (ext == 'jpg' || mime == 'image/jpeg') return true; break;
        case FileFormat.jpeg: if (ext == 'jpeg' || mime == 'image/jpeg') return true; break;
        case FileFormat.png: if (ext == 'png' || mime == 'image/png') return true; break;
        case FileFormat.svg: if (ext == 'svg' || mime == 'image/svg+xml') return true; break;
        case FileFormat.gif: if (ext == 'gif' || mime == 'image/gif') return true; break;
        case FileFormat.tif: if (ext == 'tif' || mime == 'image/tiff') return true; break;
        case FileFormat.tiff: if (ext == 'tiff' || mime == 'image/tiff') return true; break;
        case FileFormat.webp: if (ext == 'webp' || mime == 'image/webp') return true; break;
        case FileFormat.pdf: if (ext == 'pdf' || mime == 'application/pdf') return true; break;
        case FileFormat.djvu: if (ext == 'djvu') return true; break;
        case FileFormat.ogg: if (ext == 'ogg' || mime.contains('ogg')) return true; break;
        case FileFormat.oga: if (ext == 'oga' || mime.contains('ogg')) return true; break;
        case FileFormat.wav: if (ext == 'wav' || mime.contains('wav')) return true; break;
        case FileFormat.webm: if (ext == 'webm' || mime.contains('webm')) return true; break;
        case FileFormat.mp4: if (ext == 'mp4' || mime.contains('mp4')) return true; break;
      }
    }
    return false;
  }

  List<SearchItem> applyClientSort(List<SearchItem> items, SortMode sortMode) {
    if (sortMode != SortMode.titleMatch) return items;
    final sorted = List<SearchItem>.from(items);
    sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return sorted;
  }

  // OPTIMIZATION: Uses the static pre-compiled Regex.
  static String _stripHtml(String s) {
    return s.replaceAll(_htmlTagRegex, '').trim();
  }
}