import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

/// How a work's page presents what its sources say: which provider each
/// field is taken from, which ratings show and in what order, and which
/// sections the page lays out below its episodes.
///
/// One rule is kept for every work of this device (`media_presentation`,
/// id `global`) and one may be kept for a single work (`media_overrides`,
/// field `presentation`, so it follows the work through merges). A part a
/// rule leaves out keeps the default; the work's rule wins over the global
/// one part by part.
final class PresentationRule {
  const PresentationRule(
      {this.sources = const {},
      this.ratings,
      this.sections,
      this.limits = const {}});

  static const providers = ['tmdb', 'bangumi', 'dandanplay', 'https://sources.nipaplay.app'];

  /// Where each field whose source can be chosen is shown.
  static const fields = {
    'title': 'hero.title',
    'originalTitle': 'hero.originalTitle',
    'overview': 'copy.overview',
    'year': 'hero.meta',
    'studio': 'hero.meta',
    'runtimeMs': 'hero.meta',
    'episodeCount': 'hero.meta',
    'genres': 'section.facts',
    'tags': 'section.facts',
    'people': 'section.cast, section.crew',
  };

  /// Sections below the episodes, in their default order.
  static const sectionIds = [
    'characters',
    'cast',
    'crew',
    'gallery',
    'facts',
    'links'
  ];

  static const defaultLimits = {
    'characters': 24,
    'cast': 24,
    'crew': 16,
    'gallery': 12
  };

  /// The order a field takes its providers in when no rule names one: the
  /// order the library has always used.
  static List<String> defaultSources(String field) => switch (field) {
        'title' || 'infobox' || 'tags' => const [
            'bangumi',
            'tmdb',
            'dandanplay'
          ],
        'people' => const ['tmdb', 'bangumi'],
        _ => const ['tmdb', 'bangumi', 'dandanplay'],
      };

  /// Per field, providers in the order they are taken; providers left out
  /// come after them.
  final Map<String, List<String>> sources;

  /// Ratings shown, by provider and in this order; null shows every rating
  /// in the default order. Providers left out are not shown.
  final List<String>? ratings;

  /// Sections shown, in this order; null is the default order (where
  /// characters, when a work has them, stand for its cast).
  final List<String>? sections;

  /// How many entries a section shows at most.
  final Map<String, int> limits;

  bool get isEmpty =>
      sources.isEmpty && ratings == null && sections == null && limits.isEmpty;

  List<String> sourcesFor(String field) =>
      sources[field] ?? defaultSources(field);

  int limit(String section) => limits[section] ?? defaultLimits[section] ?? 24;

  /// [this] over [base]: each part this rule names replaces the base's.
  PresentationRule over(PresentationRule? base) => base == null
      ? this
      : PresentationRule(
          sources: {...base.sources, ...sources},
          ratings: ratings ?? base.ratings,
          sections: sections ?? base.sections,
          limits: {...base.limits, ...limits});

  JsonMap toJson() => {
        if (sources.isNotEmpty) 'sources': sources,
        if (ratings != null) 'ratings': ratings,
        if (sections != null) 'sections': sections,
        if (limits.isNotEmpty) 'limits': limits,
      };

  /// The defaults, as a rule naming every part.
  static JsonMap defaults() => {
        'sources': {
          for (final field in fields.keys) field: defaultSources(field)
        },
        'ratings': null,
        'sections': sectionIds,
        'limits': defaultLimits,
      };

  /// A stored or submitted rule; throws [Failure] for anything it cannot
  /// honour, so a bad rule is refused rather than half applied.
  static PresentationRule parse(Object? value) {
    Never bad(String message) =>
        throw Failure(FailureCode.invalidInput, message);
    if (value is! Map) bad('A presentation rule is a JSON object.');
    List<String> names(Object? list, List<String> allowed, String what) {
      if (list is! List) bad('$what is a list.');
      final out = <String>[];
      for (final item in list) {
        if (item is! String || !allowed.contains(item)) {
          bad('$what may name only ${allowed.join(', ')}; not $item.');
        }
        if (!out.contains(item)) out.add(item);
      }
      return out;
    }

    for (final key in value.keys) {
      if (!const ['sources', 'ratings', 'sections', 'limits'].contains(key)) {
        bad('Unknown part "$key"; a rule has sources, ratings, sections and limits.');
      }
    }
    final sources = <String, List<String>>{};
    if (value['sources'] case final Object raw) {
      if (raw is! Map) bad('sources maps a field to its providers.');
      for (final entry in raw.entries) {
        final field = entry.key as String;
        if (!fields.containsKey(field)) {
          bad('sources may name only ${fields.keys.join(', ')}; not $field.');
        }
        final allowed =
            field == 'people' ? const ['tmdb', 'bangumi', 'https://sources.nipaplay.app'] : providers;
        final order = names(entry.value, allowed, 'sources.$field');
        if (order.isEmpty) bad('sources.$field names no provider.');
        sources[field] = order;
      }
    }
    final limits = <String, int>{};
    if (value['limits'] case final Object raw) {
      if (raw is! Map) bad('limits maps a section to a count.');
      for (final entry in raw.entries) {
        final section = entry.key as String;
        final count = entry.value;
        if (!defaultLimits.containsKey(section)) {
          bad('limits may name only ${defaultLimits.keys.join(', ')}; not $section.');
        }
        if (count is! int || count < 1 || count > 100) {
          bad('limits.$section is a whole number from 1 to 100.');
        }
        limits[section] = count;
      }
    }
    return PresentationRule(
      sources: sources,
      ratings: value['ratings'] == null
          ? null
          : names(value['ratings'], providers, 'ratings'),
      sections: value['sections'] == null
          ? null
          : names(value['sections'], sectionIds, 'sections'),
      limits: limits,
    );
  }

  /// Like [parse], but a stored rule that no longer parses is ignored.
  static PresentationRule? tryParse(Object? value) {
    if (value == null) return null;
    try {
      return parse(value is String ? jsonDecode(value) : value);
    } on Failure {
      return null;
    } on FormatException {
      return null;
    }
  }
}
