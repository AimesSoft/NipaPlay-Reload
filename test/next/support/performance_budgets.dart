// Wall-clock scheduling gaps and millisecond budgets vary across shared
// runners. Keep functional assertions on every run; opt into timing gates on
// a dedicated machine with --dart-define=NIPAPLAY_PERFORMANCE_TESTS=true.
const enforcePerformanceBudgets =
    bool.fromEnvironment('NIPAPLAY_PERFORMANCE_TESTS');
