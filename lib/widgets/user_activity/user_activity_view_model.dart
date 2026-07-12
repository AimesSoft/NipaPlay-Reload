import 'package:flutter/widgets.dart';

class UserActivityViewModel {
  const UserActivityViewModel({
    required this.isLoading,
    required this.error,
    required this.recentWatched,
    required this.favorites,
    required this.rated,
    required this.onRefresh,
    required this.onOpenAnimeDetail,
    required this.formatTime,
    required this.ratingText,
    required this.favoriteStatusText,
    required this.processImageUrl,
  });

  final bool isLoading;
  final String? error;
  final List<Map<String, dynamic>> recentWatched;
  final List<Map<String, dynamic>> favorites;
  final List<Map<String, dynamic>> rated;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onOpenAnimeDetail;
  final String Function(String? value) formatTime;
  final String Function(int rating) ratingText;
  final String Function(String? status) favoriteStatusText;
  final String? Function(String? url) processImageUrl;
}
