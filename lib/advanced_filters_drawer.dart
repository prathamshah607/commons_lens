import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_controller.dart';
import 'search_service.dart';

class AdvancedFiltersDrawer extends ConsumerStatefulWidget {
  const AdvancedFiltersDrawer({super.key});

  @override
  ConsumerState<AdvancedFiltersDrawer> createState() =>
      _AdvancedFiltersDrawerState();
}

class _AdvancedFiltersDrawerState extends ConsumerState<AdvancedFiltersDrawer> {
  final SearchService _service = SearchService();

  late TextEditingController _minWidthCtrl;
  late TextEditingController _minHeightCtrl;
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;
  late TextEditingController _radiusCtrl;

  Set<String> _selectedCategories = {};

  late TextEditingController _langCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _createdFromCtrl;
  late TextEditingController _createdToCtrl;
  late TextEditingController _editedFromCtrl;
  late TextEditingController _editedToCtrl;

  @override
  void initState() {
    super.initState();
    final state = ref.read(searchControllerProvider).filterState;

    _minWidthCtrl =
        TextEditingController(text: state.minWidth?.toString() ?? '');
    _minHeightCtrl =
        TextEditingController(text: state.minHeight?.toString() ?? '');
    _latCtrl =
        TextEditingController(text: state.nearCoord?.lat.toString() ?? '');
    _lngCtrl =
        TextEditingController(text: state.nearCoord?.lng.toString() ?? '');
    _radiusCtrl = TextEditingController(
        text: state.nearCoord?.radiusKm.toString() ?? '10');

    _selectedCategories = Set.from(state.categories);

    _langCtrl = TextEditingController(text: state.languageCode ?? '');
    _modelCtrl = TextEditingController(text: state.contentModel ?? '');
    _createdFromCtrl =
        TextEditingController(text: state.createdDate?.from ?? '');
    _createdToCtrl = TextEditingController(text: state.createdDate?.to ?? '');
    _editedFromCtrl = TextEditingController(text: state.editedDate?.from ?? '');
    _editedToCtrl = TextEditingController(text: state.editedDate?.to ?? '');
  }

  @override
  void dispose() {
    _minWidthCtrl.dispose();
    _minHeightCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _langCtrl.dispose();
    _modelCtrl.dispose();
    _createdFromCtrl.dispose();
    _createdToCtrl.dispose();
    _editedFromCtrl.dispose();
    _editedToCtrl.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final w = int.tryParse(_minWidthCtrl.text);
    final h = int.tryParse(_minHeightCtrl.text);
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final rad = double.tryParse(_radiusCtrl.text) ?? 10.0;

    NearCoordFilter? coordFilter;
    if (lat != null && lng != null) {
      coordFilter = NearCoordFilter(lat: lat, lng: lng, radiusKm: rad);
    }

    final cats = _selectedCategories;
    final lang = _langCtrl.text.trim().isEmpty ? null : _langCtrl.text.trim();
    final model =
        _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim();
    final cFrom = _createdFromCtrl.text.trim();
    final cTo = _createdToCtrl.text.trim();
    final eFrom = _editedFromCtrl.text.trim();
    final eTo = _editedToCtrl.text.trim();

    final created = (cFrom.isNotEmpty || cTo.isNotEmpty)
        ? DateFilter(from: cFrom, to: cTo)
        : null;
    final edited = (eFrom.isNotEmpty || eTo.isNotEmpty)
        ? DateFilter(from: eFrom, to: eTo)
        : null;

    final currentState = ref.read(searchControllerProvider).filterState;

    final nextState = currentState.copyWith(
      minWidth: w,
      clearMinWidth: w == null,
      minHeight: h,
      clearMinHeight: h == null,
      nearCoord: coordFilter,
      clearNearCoord: coordFilter == null,
      categories: cats,
      languageCode: lang,
      clearLanguageCode: lang == null,
      contentModel: model,
      clearContentModel: model == null,
      createdDate: created,
      clearCreatedDate: created == null,
      editedDate: edited,
      clearEditedDate: edited == null,
    );

    ref
        .read(searchControllerProvider.notifier)
        .search(nextState.queryText, overrideState: nextState);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider).filterState;

    return Drawer(
      width: 600,
      backgroundColor: const Color(0xFF111111),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'FILTERS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF222222), height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [

                  _buildSectionHeader('DEPICTS (SUBJECT)'),
                  Autocomplete<DepictsEntity>(
                    displayStringForOption: (option) => option.label,
                    initialValue:
                        TextEditingValue(text: state.depicts?.label ?? ''),
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty)
                        return const Iterable<DepictsEntity>.empty();
                      return await _service
                          .searchDepictsEntities(textEditingValue.text);
                    },
                    onSelected: (DepictsEntity selection) {
                      final nextState = state.copyWith(depicts: selection);
                      ref.read(searchControllerProvider.notifier).search(
                          nextState.queryText,
                          overrideState: nextState);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        keyboardType: (kIsWeb &&
                                (defaultTargetPlatform == TargetPlatform.iOS ||
                                    defaultTargetPlatform ==
                                        TargetPlatform.android))
                            ? TextInputType.text
                            : TextInputType.url,
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration().copyWith(
                          hintText: 'e.g. Cat, Eiffel Tower...',
                          suffixIcon: state.depicts != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white54, size: 18),
                                  onPressed: () {
                                    controller.clear();
                                    final nextState =
                                        state.copyWith(clearDepicts: true);
                                    ref
                                        .read(searchControllerProvider.notifier)
                                        .search(nextState.queryText,
                                            overrideState: nextState);
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: const Color(0xFF1E1E1E),
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 200, maxWidth: 300),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option.label,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                  subtitle: option.description != null
                                      ? Text(option.description!,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11))
                                      : null,
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('LICENSE / RIGHTS'),
                  DropdownButtonFormField<LicensePreset>(
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration: _inputDecoration(),
                    value: state.licensePreset,
                    items: LicensePreset.values.map((preset) {
                      return DropdownMenuItem(
                          value: preset,
                          child: Text(licensePresetLabel(preset),
                              style: const TextStyle(color: Colors.white)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final nextState = state.copyWith(licensePreset: val);
                        ref.read(searchControllerProvider.notifier).search(
                            nextState.queryText,
                            overrideState: nextState);
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('QUALITY ASSESSMENT'),
                  DropdownButtonFormField<QualityFilter>(
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration: _inputDecoration(),
                    value: state.qualityFilter,
                    items: QualityFilter.values.map((q) {
                      return DropdownMenuItem(
                          value: q,
                          child: Text(qualityFilterLabel(q),
                              style: const TextStyle(color: Colors.white)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final nextState = state.copyWith(qualityFilter: val);
                        ref.read(searchControllerProvider.notifier).search(
                            nextState.queryText,
                            overrideState: nextState);
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('CATEGORIES'),
                  if (_selectedCategories.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedCategories
                          .map((c) => Chip(
                                label: Text(c,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11)),
                                backgroundColor: const Color(0xFF222222),
                                deleteIconColor: Colors.white54,
                                side: BorderSide.none,
                                onDeleted: () => setState(
                                    () => _selectedCategories.remove(c)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Autocomplete<String>(
                    optionsBuilder: (textEditingValue) async {
                      if (textEditingValue.text.isEmpty)
                        return const Iterable<String>.empty();
                      return await _service
                          .searchCategories(textEditingValue.text);
                    },
                    onSelected: (String selection) {
                      setState(() => _selectedCategories.add(selection));
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        keyboardType: (kIsWeb &&
                                (defaultTargetPlatform == TargetPlatform.iOS ||
                                    defaultTargetPlatform ==
                                        TargetPlatform.android))
                            ? TextInputType.text
                            : TextInputType.url,
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration().copyWith(
                          hintText: 'Search categories...',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add,
                                color: Colors.white54, size: 18),
                            onPressed: () {
                              if (controller.text.isNotEmpty) {
                                setState(() => _selectedCategories
                                    .add(controller.text.trim()));
                                controller.clear();
                              }
                            },
                          ),
                        ),
                        onSubmitted: (val) {
                          if (val.isNotEmpty) {
                            setState(() => _selectedCategories.add(val.trim()));
                            controller.clear();
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: const Color(0xFF1E1E1E),
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 200, maxWidth: 360),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                  onTap: () {
                                    onSelected(option);
                                    FocusScope.of(context).unfocus();
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('LANGUAGE & CONTENT'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _langCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Lang (en)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _modelCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Model (wikitext)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('CREATED DATE (YYYY-MM-DD)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _createdFromCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'From'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _createdToCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'To'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('EDITED DATE (YYYY-MM-DD)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _editedFromCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'From'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _editedToCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'To'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('MINIMUM RESOLUTION'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minWidthCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Width px'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _minHeightCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Height px'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('GEOLOCATION (LAT / LNG)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _latCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Lat'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _lngCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Lng'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF222222))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applyFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D7EFF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Apply Manual Filters',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF7A7A7A),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: Colors.white30),
    );
  }
}
