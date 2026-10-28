/// Markdown heading navigation over original UTF-16 offsets. Fenced examples
/// are never interpreted as headings. IDs are pinned by the snapshot revision.
final class KnowledgeSection {
  KnowledgeSection(this.id, this.title, this.level, this.start, this.line);
  final String id, title;
  final int level, start, line;
  late int end;
  late int blockEnd;
  Map<String, Object?> toJson() => {
        'sectionId': id,
        'title': title,
        'level': level,
        'startOffset': start,
        'endOffset': end,
        'startLine': line,
      };
}

List<KnowledgeSection> knowledgeSections(String content) {
  final sections = <KnowledgeSection>[];
  var offset = 0, lineNumber = 0;
  String? fence;
  var fenceLength = 0;
  for (final line in content.split('\n')) {
    lineNumber++;
    final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (marker != null) {
      final run = marker[1]!;
      if (fence == null) {
        fence = run[0];
        fenceLength = run.length;
      } else if (run[0] == fence &&
          run.length >= fenceLength &&
          marker[2]!.trim().isEmpty) {
        fence = null;
      }
    } else if (fence == null) {
      final heading =
          RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*)|[ \t]*)$').firstMatch(line);
      if (heading != null) {
        final title = (heading[2] ?? '')
            .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '')
            .trim();
        sections.add(KnowledgeSection(
            'line:$lineNumber', title, heading[1]!.length, offset, lineNumber));
      }
    }
    offset += line.length + 1;
  }
  if (sections.isEmpty || sections.first.start != 0) {
    sections.insert(0, KnowledgeSection('document:start', 'Document', 0, 0, 1));
  }
  for (var i = 0; i < sections.length; i++) {
    sections[i].blockEnd =
        i + 1 < sections.length ? sections[i + 1].start : content.length;
    sections[i].end = content.length;
    for (var j = i + 1; j < sections.length; j++) {
      if (sections[j].level <= sections[i].level) {
        sections[i].end = sections[j].start;
        break;
      }
    }
  }
  return sections;
}
