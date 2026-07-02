import 'package:flutter/foundation.dart';

enum MediaTabType {
  allMedia,
  images,
  vectors,
  audio,
  video,
  documents,
}

enum FileFormat {
  jpg,
  jpeg,
  png,
  svg,
  gif,
  tif,
  tiff,
  webp,
  pdf,
  djvu,
  ogg,
  oga,
  wav,
  webm,
  mp4,
}

enum SortMode {
  relevance,
  newestEdited,
  oldestEdited,
  newestCreated,
  oldestCreated,
  titleMatch,
}

enum MediaKind {
  image,
  vector,
  audio,
  video,
  document,
  unknown,
}

class DateFilter {
  final String? from;
  final String? to;

  const DateFilter({this.from, this.to});

  bool get isEmpty =>
      (from == null || from!.trim().isEmpty) &&
      (to == null || to!.trim().isEmpty);

  DateFilter copyWith({
    String? from,
    String? to,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return DateFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
    );
  }
}

class SearchState {
  final String queryText;
  final MediaTabType tab;
  final Set<FileFormat> formats;
  final Set<String> categories;
  final bool deepCategoryMode;
  final bool titleOnly;
  final bool localOnly;
  final String? languageCode;
  final String? contentModel;
  final DateFilter? createdDate;
  final DateFilter? editedDate;
  final SortMode sortMode;

  const SearchState({
    this.queryText = '',
    this.tab = MediaTabType.allMedia,
    this.formats = const {},
    this.categories = const {},
    this.deepCategoryMode = false,
    this.titleOnly = false,
    this.localOnly = false,
    this.languageCode,
    this.contentModel,
    this.createdDate,
    this.editedDate,
    this.sortMode = SortMode.relevance,
  });

  SearchState copyWith({
    String? queryText,
    MediaTabType? tab,
    Set<FileFormat>? formats,
    Set<String>? categories,
    bool? deepCategoryMode,
    bool? titleOnly,
    bool? localOnly,
    String? languageCode,
    String? contentModel,
    DateFilter? createdDate,
    DateFilter? editedDate,
    SortMode? sortMode,
    bool clearLanguageCode = false,
    bool clearContentModel = false,
    bool clearCreatedDate = false,
    bool clearEditedDate = false,
  }) {
    return SearchState(
      queryText: queryText ?? this.queryText,
      tab: tab ?? this.tab,
      formats: formats ?? this.formats,
      categories: categories ?? this.categories,
      deepCategoryMode: deepCategoryMode ?? this.deepCategoryMode,
      titleOnly: titleOnly ?? this.titleOnly,
      localOnly: localOnly ?? this.localOnly,
      languageCode:
          clearLanguageCode ? null : (languageCode ?? this.languageCode),
      contentModel:
          clearContentModel ? null : (contentModel ?? this.contentModel),
      createdDate:
          clearCreatedDate ? null : (createdDate ?? this.createdDate),
      editedDate:
          clearEditedDate ? null : (editedDate ?? this.editedDate),
      sortMode: sortMode ?? this.sortMode,
    );
  }
}

class MediaTabConfig {
  final MediaTabType type;
  final String label;
  final Set<FileFormat> allowedFormats;
  final String emptyMessage;

  const MediaTabConfig({
    required this.type,
    required this.label,
    required this.allowedFormats,
    required this.emptyMessage,
  });
}

const mediaTabs = [
  MediaTabConfig(
    type: MediaTabType.allMedia,
    label: 'All',
    allowedFormats: {
      FileFormat.jpg,
      FileFormat.jpeg,
      FileFormat.png,
      FileFormat.svg,
      FileFormat.gif,
      FileFormat.tif,
      FileFormat.tiff,
      FileFormat.webp,
      FileFormat.pdf,
      FileFormat.djvu,
      FileFormat.ogg,
      FileFormat.oga,
      FileFormat.wav,
      FileFormat.webm,
      FileFormat.mp4,
    },
    emptyMessage: 'No media found.',
  ),
  MediaTabConfig(
    type: MediaTabType.images,
    label: 'Images',
    allowedFormats: {
      FileFormat.jpg,
      FileFormat.jpeg,
      FileFormat.png,
      FileFormat.gif,
      FileFormat.webp,
      FileFormat.tif,
      FileFormat.tiff,
    },
    emptyMessage: 'No images found.',
  ),
  MediaTabConfig(
    type: MediaTabType.vectors,
    label: 'SVG / Diagrams',
    allowedFormats: {
      FileFormat.svg,
    },
    emptyMessage: 'No vector files found.',
  ),
  MediaTabConfig(
    type: MediaTabType.audio,
    label: 'Audio',
    allowedFormats: {
      FileFormat.ogg,
      FileFormat.oga,
      FileFormat.wav,
    },
    emptyMessage: 'No audio found.',
  ),
  MediaTabConfig(
    type: MediaTabType.video,
    label: 'Video',
    allowedFormats: {
      FileFormat.webm,
      FileFormat.mp4,
    },
    emptyMessage: 'No videos found.',
  ),
  MediaTabConfig(
    type: MediaTabType.documents,
    label: 'Docs',
    allowedFormats: {
      FileFormat.pdf,
      FileFormat.djvu,
    },
    emptyMessage: 'No documents found.',
  ),
];

MediaTabConfig configForTab(MediaTabType type) {
  return mediaTabs.firstWhere((tab) => tab.type == type);
}

String fileFormatLabel(FileFormat format) {
  switch (format) {
    case FileFormat.jpg:
      return 'JPG';
    case FileFormat.jpeg:
      return 'JPEG';
    case FileFormat.png:
      return 'PNG';
    case FileFormat.svg:
      return 'SVG';
    case FileFormat.gif:
      return 'GIF';
    case FileFormat.tif:
      return 'TIF';
    case FileFormat.tiff:
      return 'TIFF';
    case FileFormat.webp:
      return 'WEBP';
    case FileFormat.pdf:
      return 'PDF';
    case FileFormat.djvu:
      return 'DJVU';
    case FileFormat.ogg:
      return 'OGG';
    case FileFormat.oga:
      return 'OGA';
    case FileFormat.wav:
      return 'WAV';
    case FileFormat.webm:
      return 'WEBM';
    case FileFormat.mp4:
      return 'MP4';
  }
}

MediaKind mediaKindFromFormat(FileFormat format) {
  switch (format) {
    case FileFormat.jpg:
    case FileFormat.jpeg:
    case FileFormat.png:
    case FileFormat.gif:
    case FileFormat.tif:
    case FileFormat.tiff:
    case FileFormat.webp:
      return MediaKind.image;
    case FileFormat.svg:
      return MediaKind.vector;
    case FileFormat.ogg:
    case FileFormat.oga:
    case FileFormat.wav:
      return MediaKind.audio;
    case FileFormat.webm:
    case FileFormat.mp4:
      return MediaKind.video;
    case FileFormat.pdf:
    case FileFormat.djvu:
      return MediaKind.document;
  }
}

class QueryChipData {
  final String id;
  final String label;

  const QueryChipData({
    required this.id,
    required this.label,
  });
}

class QueryBuildResult {
  final String srsearch;
  final List<QueryChipData> chips;
  final String debugPreview;

  const QueryBuildResult({
    required this.srsearch,
    required this.chips,
    required this.debugPreview,
  });
}

class SearchItem {
  final String title;
  final String url;
  final String thumb;
  final String commonsUrl;
  final String snippet;
  final String mime;
  final bool isSvg;
  final String? timestamp;
  final String? descriptionUrl;
  
  // NEW ExtMetadata fields
  final String artistHtml;
  final String licenseShortName;
  final String licenseUrl;
  final String dateTimeOriginal;
  final String uploader;
  final int width;
  final int height;

  const SearchItem({
    required this.title,
    required this.url,
    required this.thumb,
    required this.commonsUrl,
    required this.snippet,
    required this.mime,
    required this.isSvg,
    this.timestamp,
    this.descriptionUrl,
    this.artistHtml = '',
    this.licenseShortName = '',
    this.licenseUrl = '',
    this.dateTimeOriginal = '',
    this.uploader = '',
    this.width = 0,
    this.height = 0,
  });

  String get extension {
    final lower = url.toLowerCase();
    final parts = lower.split('.');
    if (parts.length > 1) {
      return parts.last;
    }
    return '';
  }

  MediaKind get mediaKind {
    final m = mime.toLowerCase();
    if (m.startsWith('image/')) {
      if (m.contains('svg')) return MediaKind.vector;
      return MediaKind.image;
    }
    if (m.startsWith('video/') || extension == 'webm' || extension == 'mp4') {
      return MediaKind.video;
    }
    if (m.startsWith('audio/') || extension == 'ogg' || extension == 'wav') {
      return MediaKind.audio;
    }
    if (m == 'application/pdf' || extension == 'djvu') return MediaKind.document;
    return MediaKind.unknown;
  }
}

class SearchResponse {
  final List<SearchItem> items;
  final Map<String, dynamic>? continueParams;

  const SearchResponse({
    required this.items,
    required this.continueParams,
  });
}

@immutable
class SearchSessionKey {
  final MediaTabType tab;
  final String querySignature;

  const SearchSessionKey({
    required this.tab,
    required this.querySignature,
  });

  @override
  bool operator ==(Object other) {
    return other is SearchSessionKey &&
        other.tab == tab &&
        other.querySignature == querySignature;
  }

  @override
  int get hashCode => Object.hash(tab, querySignature);
}

class SearchSession {
  final List<SearchItem> items;
  final Map<String, dynamic>? continueParams;
  final bool hasMore;
  final bool hasSearched;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final double scrollOffset;

  const SearchSession({
    this.items = const [],
    this.continueParams,
    this.hasMore = false,
    this.hasSearched = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.scrollOffset = 0,
  });

  SearchSession copyWith({
    List<SearchItem>? items,
    Map<String, dynamic>? continueParams,
    bool? hasMore,
    bool? hasSearched,
    bool? loading,
    bool? loadingMore,
    String? error,
    double? scrollOffset,
    bool clearContinueParams = false,
    bool clearError = false,
  }) {
    return SearchSession(
      items: items ?? this.items,
      continueParams:
          clearContinueParams ? null : (continueParams ?? this.continueParams),
      hasMore: hasMore ?? this.hasMore,
      hasSearched: hasSearched ?? this.hasSearched,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      scrollOffset: scrollOffset ?? this.scrollOffset,
    );
  }
}