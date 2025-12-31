class WebPlaybackItem {
  const WebPlaybackItem({
    required this.uri,
    required this.title,
    this.subtitle,
  });

  final Uri uri;
  final String title;
  final String? subtitle;
}

