import 'search_models.dart';

class SearchUrlCodec {
  const SearchUrlCodec._();

  static Map<String, String> toQueryParams(SearchState state) {
    final params = <String, String>{};

    final q = state.queryText.trim();
    if (q.isNotEmpty) params['q'] = q;

    final tabName = state.tab.name;
    if (tabName != MediaTabType.allMedia.name) {
      params['tab'] = tabName;
    }

    if (state.formats.isNotEmpty) {
      final formats = state.formats.map((f) => f.name).toList()..sort();
      params['formats'] = formats.join(',');
    }

    if (state.categories.isNotEmpty) {
      final cats = state.categories.map((c) => c.trim()).where((c) => c.isNotEmpty).toList()
        ..sort();
      if (cats.isNotEmpty) params['cats'] = cats.join('|');
    }

    if (state.excludeCategories.isNotEmpty) {
      final cats = state.excludeCategories.map((c) => c.trim()).where((c) => c.isNotEmpty).toList()
        ..sort();
      if (cats.isNotEmpty) params['catsExclude'] = cats.join('|');
    }

    if (state.depictsInclude.isNotEmpty) {
      final entries = state.depictsInclude.map((d) => '${d.qid}~${d.label}').toList()..sort();
      params['depictsIn'] = entries.join('|');
    }

    if (state.depictsExclude.isNotEmpty) {
      final entries = state.depictsExclude.map((d) => '${d.qid}~${d.label}').toList()..sort();
      params['depictsEx'] = entries.join('|');
    }

    if (state.deepCategoryMode) params['deepcat'] = '1';
    if (state.titleOnly) params['titleOnly'] = '1';
    if (state.localOnly) params['local'] = '1';

    final lang = state.languageCode?.trim() ?? '';
    if (lang.isNotEmpty) params['lang'] = lang;

    final model = state.contentModel?.trim() ?? '';
    if (model.isNotEmpty) params['model'] = model;

    final createdFrom = state.createdDate?.from?.trim() ?? '';
    if (createdFrom.isNotEmpty) params['createdFrom'] = createdFrom;
    final createdTo = state.createdDate?.to?.trim() ?? '';
    if (createdTo.isNotEmpty) params['createdTo'] = createdTo;

    final editedFrom = state.editedDate?.from?.trim() ?? '';
    if (editedFrom.isNotEmpty) params['editedFrom'] = editedFrom;
    final editedTo = state.editedDate?.to?.trim() ?? '';
    if (editedTo.isNotEmpty) params['editedTo'] = editedTo;

    if (state.sortMode != SortMode.relevance) {
      params['sort'] = state.sortMode.name;
    }

    if (state.licensePreset != LicensePreset.any) {
      params['license'] = state.licensePreset.name;
    }

    if (state.qualityFilter != QualityFilter.any) {
      params['quality'] = state.qualityFilter.name;
    }

    if (state.minWidth != null && state.minWidth! > 0) {
      params['minW'] = state.minWidth.toString();
    }

    if (state.minHeight != null && state.minHeight! > 0) {
      params['minH'] = state.minHeight.toString();
    }

    if (state.nearCoord != null) {
      final coord = state.nearCoord!;
      params['lat'] = coord.lat.toString();
      params['lng'] = coord.lng.toString();
      params['radius'] = coord.radiusKm.toString();
    }

    if (state.excludeTerms.isNotEmpty) {
      final terms = state.excludeTerms.map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        ..sort();
      if (terms.isNotEmpty) params['exclude'] = terms.join('|');
    }

    return params;
  }


  static SearchState fromQueryParams(
    Map<String, String> params,
    SearchState base,
  ) {
    final tabParam = params['tab'];
    final tab = tabParam == null
        ? base.tab
        : MediaTabType.values.firstWhere(
            (t) => t.name == tabParam,
            orElse: () => base.tab,
          );

    final formatsParam = params['formats'];
    final formats = (formatsParam == null || formatsParam.isEmpty)
        ? <FileFormat>{}
        : formatsParam
            .split(',')
            .map((name) {
              try {
                return FileFormat.values.firstWhere((f) => f.name == name);
              } catch (_) {
                return null;
              }
            })
            .whereType<FileFormat>()
            .toSet();

    final catsParam = params['cats'];
    final categories = (catsParam == null || catsParam.isEmpty)
        ? <String>{}
        : catsParam.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toSet();

    final catsExcludeParam = params['catsExclude'];
    final excludeCategories = (catsExcludeParam == null || catsExcludeParam.isEmpty)
        ? <String>{}
        : catsExcludeParam.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toSet();

    Set<DepictsEntity> parseDepicts(String? raw) {
      if (raw == null || raw.isEmpty) return <DepictsEntity>{};
      return raw.split('|').where((e) => e.isNotEmpty).map((entry) {
        final sep = entry.indexOf('~');
        if (sep < 0) return DepictsEntity(qid: entry, label: entry);
        return DepictsEntity(
          qid: entry.substring(0, sep),
          label: entry.substring(sep + 1),
        );
      }).toSet();
    }

    final depictsInclude = parseDepicts(params['depictsIn']);
    final depictsExclude = parseDepicts(params['depictsEx']);

    final createdFrom = params['createdFrom'];
    final createdTo = params['createdTo'];
    final createdDate = (createdFrom == null && createdTo == null)
        ? null
        : DateFilter(from: createdFrom, to: createdTo);

    final editedFrom = params['editedFrom'];
    final editedTo = params['editedTo'];
    final editedDate = (editedFrom == null && editedTo == null)
        ? null
        : DateFilter(from: editedFrom, to: editedTo);

    final sortParam = params['sort'];
    final sortMode = sortParam == null
        ? SortMode.relevance
        : SortMode.values.firstWhere(
            (s) => s.name == sortParam,
            orElse: () => SortMode.relevance,
          );

    final licenseParam = params['license'];
    final licensePreset = licenseParam == null
        ? base.licensePreset
        : LicensePreset.values.firstWhere(
            (l) => l.name == licenseParam,
            orElse: () => base.licensePreset,
          );

    final qualityParam = params['quality'];
    final qualityFilter = qualityParam == null
        ? base.qualityFilter
        : QualityFilter.values.firstWhere(
            (q) => q.name == qualityParam,
            orElse: () => base.qualityFilter,
          );

    final minWidth = int.tryParse(params['minW'] ?? '');
    final minHeight = int.tryParse(params['minH'] ?? '');

    final lat = double.tryParse(params['lat'] ?? '');
    final lng = double.tryParse(params['lng'] ?? '');
    final radius = double.tryParse(params['radius'] ?? '') ?? 10.0;
    final nearCoord = (lat != null && lng != null)
        ? NearCoordFilter(lat: lat, lng: lng, radiusKm: radius)
        : null;

    final excludeParam = params['exclude'];
    final excludeTerms = (excludeParam == null || excludeParam.isEmpty)
        ? <String>{}
        : excludeParam.split('|').map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();

    return base.copyWith(
      queryText: params['q'] ?? base.queryText,
      tab: tab,
      formats: formats,
      categories: categories,
      excludeCategories: excludeCategories,
      depictsInclude: depictsInclude,
      depictsExclude: depictsExclude,
      deepCategoryMode: params['deepcat'] == '1',
      titleOnly: params['titleOnly'] == '1',
      localOnly: params['local'] == '1',
      languageCode: params['lang'],
      contentModel: params['model'],
      createdDate: createdDate,
      editedDate: editedDate,
      sortMode: sortMode,
      licensePreset: licensePreset,
      qualityFilter: qualityFilter,
      minWidth: minWidth,
      clearMinWidth: minWidth == null,
      minHeight: minHeight,
      clearMinHeight: minHeight == null,
      nearCoord: nearCoord,
      clearNearCoord: nearCoord == null,
      excludeTerms: excludeTerms,
    );
  }

  static bool hasSearchContext(Map<String, String> params) {
    return (params['q'] ?? '').trim().isNotEmpty;
  }
}
