import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/controllers/user_activity_controller.dart';
import 'package:nipaplay/widgets/user_activity/cupertino_user_activity.dart';
import 'package:nipaplay/widgets/user_activity/desktop_user_activity.dart';
import 'package:nipaplay/widgets/user_activity/user_activity_view_model.dart';

class AdaptiveUserActivity extends StatefulWidget {
  const AdaptiveUserActivity({super.key});

  @override
  State<AdaptiveUserActivity> createState() => _AdaptiveUserActivityState();
}

class _AdaptiveUserActivityState extends State<AdaptiveUserActivity>
    with UserActivityController {
  @override
  Widget build(BuildContext context) {
    final data = UserActivityViewModel(
      isLoading: isLoading,
      error: error,
      recentWatched: recentWatched,
      favorites: favorites,
      rated: rated,
      onRefresh: loadUserActivity,
      onOpenAnimeDetail: openAnimeDetail,
      formatTime: formatTime,
      ratingText: getRatingText,
      favoriteStatusText: getFavoriteStatusText,
      processImageUrl: processImageUrl,
    );
    final surface = AppDisplaySurfaceScope.of(context);
    if (surface == AppDisplaySurface.phone) {
      return CupertinoUserActivity(data: data);
    }
    return DesktopUserActivity(data: data);
  }
}
