class DandanplayService {
  static const String appId = "nipaplayv1";
  static bool get isLoggedIn => false;
  static String? get userName => null;
  static String? get screenName => null;

  static Future<void> initialize() async {}
  static Future<void> preloadRecentAnimes() async {}
  static Future<void> loadToken() async {}
  static Future<void> saveLoginInfo(String token, String username, String screenName) async {}
  static Future<void> clearLoginInfo() async {}
  static Future<void> saveToken(String token) async {}
  static Future<void> clearToken() async {}
  static Future<Map<String, dynamic>?> getCachedVideoInfo(String fileHash) async => null;
  static Future<void> saveVideoInfoToCache(String fileHash, Map<String, dynamic> videoInfo) async {}
  static Future<String> getAppSecret() async => '';
  static String generateSignature(String appId, int timestamp, String apiPath, String appSecret) => '';
  static Future<Map<String, dynamic>> login(String username, String password) async => {'success': false, 'message': 'Web not supported'};
  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async => {'success': false, 'message': 'Web not supported'};
  static Future<Map<String, dynamic>> getDanmaku(String episodeId, int animeId) async => {'comments': [], 'count': 0};
  static Future<Map<String, dynamic>> getUserPlayHistory({DateTime? fromDate, DateTime? toDate}) async => {'success': false, 'playHistoryAnimes': []};
  static Future<Map<String, dynamic>> addPlayHistory({required List<int> episodeIdList, bool addToFavorite = false, int rating = 0}) async => {'success': false, 'message': 'Web not supported'};
  static Future<Map<String, dynamic>> getBangumiDetails(int bangumiId) async => {'success': false, 'message': 'Web not supported'};
  static Future<Map<int, bool>> getEpisodesWatchStatus(List<int> episodeIds) async => {};
  static Future<Map<String, dynamic>> getUserFavorites({bool onlyOnAir = false}) async => {'success': false, 'favorites': []};
  static Future<Map<String, dynamic>> addFavorite({required int animeId, String? favoriteStatus, int rating = 0, String? comment}) async => {'success': false, 'message': 'Web not supported'};
  static Future<Map<String, dynamic>> removeFavorite(int animeId) async => {'success': false, 'message': 'Web not supported'};
  static Future<bool> isAnimeFavorited(int animeId) async => false;
  static Future<int> getUserRatingForAnime(int animeId) async => 0;
  static Future<Map<String, dynamic>> submitUserRating({required int animeId, required int rating}) async => {'success': false, 'message': 'Web not supported'};
  static Future<Map<String, dynamic>> sendDanmaku({required int episodeId, required double time, required int mode, required int color, required String comment}) async => {'success': false, 'message': 'Web not supported'};
} 