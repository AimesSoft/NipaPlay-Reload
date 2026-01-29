class BuildInfoEntry {
  final String label;
  final String value;

  const BuildInfoEntry(this.label, this.value);
}

class BuildInfoSection {
  final String title;
  final List<BuildInfoEntry> entries;

  const BuildInfoSection({
    required this.title,
    required this.entries,
  });
}
