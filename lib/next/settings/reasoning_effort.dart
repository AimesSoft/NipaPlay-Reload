/// Thinking effort when the person never chose one. 梨花's turns are errands
/// around a media library, not code, so a light effort keeps them quick.
const defaultReasoningEffort = 'low';

/// The saved value (`model.json` `reasoning`) as the settings show it: '' is
/// off, a missing value is the default.
String reasoningChoice(Object? saved) => saved == 'off'
    ? ''
    : saved is String && saved.isNotEmpty
        ? saved
        : defaultReasoningEffort;

/// The effort the runner is asked for; null sends none, as when it is off.
String? reasoningEffort(Object? saved) {
  final choice = reasoningChoice(saved);
  return choice.isEmpty ? null : choice;
}

/// What `model.json` keeps for a choice from the settings. Off is written out,
/// so it stays apart from never having chosen.
String storedReasoning(String choice) => choice.isEmpty ? 'off' : choice;
