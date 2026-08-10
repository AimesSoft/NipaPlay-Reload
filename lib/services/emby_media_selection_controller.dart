import 'package:flutter/foundation.dart';

import '../models/emby_media_selection.dart';
import 'emby_media_preference_store.dart';
import 'emby_media_selection_resolver.dart';
import 'emby_media_source_catalog.dart';

enum EmbySelectionDimension { source, audio, subtitle }

class EmbyMediaSelectionState {
  EmbyMediaSelectionState({
    List<EmbyMediaSourceDescriptor> sources =
        const <EmbyMediaSourceDescriptor>[],
    this.selectedSourceId,
    this.audio = const EmbyTrackPreference.followDefault(),
    this.subtitle = const EmbyTrackPreference.followDefault(),
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.canPersist = true,
    Set<EmbySelectionDimension> dirtyDimensions =
        const <EmbySelectionDimension>{},
  })  : sources = List<EmbyMediaSourceDescriptor>.unmodifiable(sources),
        dirtyDimensions =
            Set<EmbySelectionDimension>.unmodifiable(dirtyDimensions);

  final List<EmbyMediaSourceDescriptor> sources;
  final String? selectedSourceId;
  final EmbyTrackPreference audio;
  final EmbyTrackPreference subtitle;
  final bool isLoading;
  final bool isSaving;
  final Object? error;
  final bool canPersist;
  final Set<EmbySelectionDimension> dirtyDimensions;
}

abstract class EmbyMediaSelectionController extends ChangeNotifier {
  EmbyMediaSelectionState get state;

  Future<void> load({bool forceRefresh = false});

  void selectSource(String sourceId);

  void selectAudio(EmbyTrackPreference preference);

  void selectSubtitle(EmbyTrackPreference preference);

  Future<bool> apply();

  void cancel();
}

class DefaultEmbyMediaSelectionController extends EmbyMediaSelectionController {
  DefaultEmbyMediaSelectionController({
    required EmbyMediaSourceCatalog catalog,
    required EmbyMediaPreferenceStore store,
    required EmbyMediaSelectionResolver resolver,
    required EmbySelectionContext? context,
    required String catalogScopeKey,
    required String itemId,
  })  : _catalog = catalog,
        _store = store,
        _resolver = resolver,
        _context = context,
        _catalogScopeKey = catalogScopeKey,
        _itemId = itemId,
        _state = EmbyMediaSelectionState(canPersist: context != null),
        _baseline = EmbyMediaSelectionState(canPersist: context != null);

  final EmbyMediaSourceCatalog _catalog;
  final EmbyMediaPreferenceStore _store;
  final EmbyMediaSelectionResolver _resolver;
  final EmbySelectionContext? _context;
  final String _catalogScopeKey;
  final String _itemId;

  EmbyMediaSelectionState _state;
  EmbyMediaSelectionState _baseline;
  EmbyResolutionPlan? _resolution;
  int _loadGeneration = 0;

  @override
  EmbyMediaSelectionState get state => _state;

  @override
  Future<void> load({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    _setState(_buildState(isLoading: true, error: null));
    try {
      final sources = await _catalog.load(
        _catalogScopeKey,
        _itemId,
        forceRefresh: forceRefresh,
      );
      final context = _context;
      final preferences = context == null
          ? const EmbyPreferenceLayers()
          : await _store.load(context);
      if (generation != _loadGeneration) return;
      _resolution = _resolver.resolve(
        sources: sources,
        preferences: preferences,
      );
      final candidate = _resolution!.candidates.firstOrNull;
      _baseline = _stateForCandidate(
        sources: sources,
        candidate: candidate,
        canPersist: _context != null,
      );
      _setState(_baseline);
    } catch (error) {
      if (generation != _loadGeneration) return;
      _setState(_buildState(isLoading: false, error: error));
    }
  }

  @override
  void selectSource(String sourceId) {
    if (_state.isSaving) return;
    final candidate = _candidateFor(sourceId);
    if (candidate == null ||
        candidate.source.source.id == _state.selectedSourceId) {
      return;
    }
    final dirty = <EmbySelectionDimension>{
      ..._state.dirtyDimensions,
      EmbySelectionDimension.source,
    };
    _setState(
      _stateForCandidate(
        sources: _state.sources,
        candidate: candidate,
        canPersist: _state.canPersist,
        dirtyDimensions: dirty,
      ),
    );
  }

  @override
  void selectAudio(EmbyTrackPreference preference) {
    if (_state.isSaving) return;
    if (preference.mode == EmbyTrackPreferenceMode.disabled) return;
    _setState(
      _buildState(
        audio: preference,
        dirtyDimensions: <EmbySelectionDimension>{
          ..._state.dirtyDimensions,
          EmbySelectionDimension.audio,
        },
        error: null,
      ),
    );
  }

  @override
  void selectSubtitle(EmbyTrackPreference preference) {
    if (_state.isSaving) return;
    _setState(
      _buildState(
        subtitle: preference,
        dirtyDimensions: <EmbySelectionDimension>{
          ..._state.dirtyDimensions,
          EmbySelectionDimension.subtitle,
        },
        error: null,
      ),
    );
  }

  @override
  Future<bool> apply() async {
    if (_state.isSaving) return false;
    final context = _context;
    if (context == null) {
      _setState(
        _buildState(
          error: StateError('无法保存 Emby 媒体偏好：账号标识不可用'),
        ),
      );
      return false;
    }
    final draft = _state;
    if (draft.dirtyDimensions.isEmpty) return true;

    final currentSource = _sourceFor(draft.selectedSourceId);
    if (currentSource == null) {
      final error = StateError('无法保存 Emby 媒体偏好：未选择媒体源');
      _setState(_buildState(error: error));
      throw error;
    }

    final dirty = draft.dirtyDimensions;
    final patch = EmbyManualSelectionPatch(
      source:
          dirty.contains(EmbySelectionDimension.source) ? currentSource : null,
      audio: dirty.contains(EmbySelectionDimension.audio) ? draft.audio : null,
      subtitle: dirty.contains(EmbySelectionDimension.subtitle)
          ? draft.subtitle
          : null,
    );
    final savingSnapshot = EmbyMediaSelectionState(
      sources: draft.sources,
      selectedSourceId: draft.selectedSourceId,
      audio: draft.audio,
      subtitle: draft.subtitle,
      isSaving: true,
      canPersist: draft.canPersist,
      dirtyDimensions: draft.dirtyDimensions,
    );
    _setState(savingSnapshot);
    try {
      await _store.saveManualPatch(context, currentSource, patch);
      _baseline = EmbyMediaSelectionState(
        sources: savingSnapshot.sources,
        selectedSourceId: savingSnapshot.selectedSourceId,
        audio: savingSnapshot.audio,
        subtitle: savingSnapshot.subtitle,
        isSaving: false,
        canPersist: savingSnapshot.canPersist,
        dirtyDimensions: const <EmbySelectionDimension>{},
      );
      _setState(_baseline);
      return true;
    } catch (error) {
      _setState(_buildState(isSaving: false, error: error));
      rethrow;
    }
  }

  @override
  void cancel() {
    if (_state.isSaving) return;
    _setState(_baseline);
  }

  EmbyMediaSourceDescriptor? _sourceFor(String? selectedId) {
    if (selectedId == null) return null;
    for (final source in _state.sources) {
      if (source.source.id == selectedId) return source;
    }
    return null;
  }

  EmbySourceCandidate? _candidateFor(String sourceId) {
    final resolution = _resolution;
    if (resolution == null) return null;
    for (final candidate in resolution.candidates) {
      if (candidate.source.source.id == sourceId) return candidate;
    }
    return null;
  }

  EmbyMediaSelectionState _stateForCandidate({
    required List<EmbyMediaSourceDescriptor> sources,
    required EmbySourceCandidate? candidate,
    required bool canPersist,
    Set<EmbySelectionDimension> dirtyDimensions =
        const <EmbySelectionDimension>{},
  }) =>
      EmbyMediaSelectionState(
        sources: sources,
        selectedSourceId: candidate?.source.source.id,
        audio: _preferenceFor(
          candidate?.tracks.audio,
          mediaSourceId: candidate?.source.source.id,
        ),
        subtitle: _preferenceFor(
          candidate?.tracks.subtitle,
          mediaSourceId: candidate?.source.source.id,
        ),
        canPersist: canPersist,
        dirtyDimensions: dirtyDimensions,
      );

  EmbyTrackPreference _preferenceFor(
    EmbyResolvedTrackSelection? selection, {
    required String? mediaSourceId,
  }) {
    if (selection == null ||
        selection.mode == EmbyResolvedTrackMode.followDefault) {
      return const EmbyTrackPreference.followDefault();
    }
    if (selection.mode == EmbyResolvedTrackMode.disabled) {
      return const EmbyTrackPreference.disabled();
    }
    final fingerprint = selection.fingerprint;
    final index = selection.sourceIndex;
    if (mediaSourceId == null || fingerprint == null || index == null) {
      return const EmbyTrackPreference.followDefault();
    }
    return EmbyTrackPreference.track(
      fingerprint,
      sourceIndex: index,
      mediaSourceId: mediaSourceId,
    );
  }

  EmbyMediaSelectionState _buildState({
    List<EmbyMediaSourceDescriptor>? sources,
    String? selectedSourceId,
    EmbyTrackPreference? audio,
    EmbyTrackPreference? subtitle,
    bool? isLoading,
    bool? isSaving,
    Object? error,
    bool? canPersist,
    Set<EmbySelectionDimension>? dirtyDimensions,
  }) =>
      EmbyMediaSelectionState(
        sources: sources ?? _state.sources,
        selectedSourceId: selectedSourceId ?? _state.selectedSourceId,
        audio: audio ?? _state.audio,
        subtitle: subtitle ?? _state.subtitle,
        isLoading: isLoading ?? _state.isLoading,
        isSaving: isSaving ?? _state.isSaving,
        error: error,
        canPersist: canPersist ?? _state.canPersist,
        dirtyDimensions: dirtyDimensions ?? _state.dirtyDimensions,
      );

  void _setState(EmbyMediaSelectionState value) {
    _state = value;
    notifyListeners();
  }
}

extension on List<EmbySourceCandidate> {
  EmbySourceCandidate? get firstOrNull => isEmpty ? null : first;
}
