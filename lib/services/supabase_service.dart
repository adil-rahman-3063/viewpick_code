import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'cache_service.dart';

final SupabaseClient supabase = Supabase.instance.client;

class SupabaseService {
  // Language name to TMDB code mapping
  static final Map<String, String> _languageCodeMap = {
    'English': 'en-US',
    'Hindi': 'hi-IN',
    'Tamil': 'ta-IN',
    'Telugu': 'te-IN',
    'Malayalam': 'ml-IN',
    'Kannada': 'kn-IN',
    'Mandarin': 'zh-CN',
    'Japanese': 'ja-JP',
    'Korean': 'ko-KR',
    'French': 'fr-FR',
    'Spanish': 'es-ES',
    'Portuguese': 'pt-BR',
    'Italian': 'it-IT',
    'German': 'de-DE',
    'Russian': 'ru-RU',
    'Persian': 'fa-IR',
    'Turkish': 'tr-TR',
  };

  // Getter for supported language codes
  static List<String> get supportedLanguageCodes =>
      _languageCodeMap.values.toList();

  // Sign in with email + password
  static Future<AuthResponse> signIn(String email, String password) async {
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign in with Google
  static Future<AuthResponse?> signInWithGoogle() async {
    // Dynamically build redirectTo from the current browser URL.
    // This ensures OAuth returns to localhost:3000 in dev and
    // viewpick.vercel.com in production — not always the Supabase Site URL.
    String? redirectTo;
    if (kIsWeb) {
      final uri = Uri.base;
      final port = (uri.port == 80 || uri.port == 443 || uri.port == 0)
          ? ''
          : ':${uri.port}';
      redirectTo = '${uri.scheme}://${uri.host}$port/';
    }
    await supabase.auth.signInWithOAuth(
      Provider.google,
      redirectTo: redirectTo,
    );
    return null; // Will redirect on web
  }


  // Sign out
  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // Reset password
  static Future<void> resetPassword(String email) async {
    await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: 'viewpick://reset-password',
    );
  }

  // Get current user
  static User? currentUser() => supabase.auth.currentUser;

  // Get user's language preferences from metadata and return TMDB codes
  static List<String> getUserLanguages() {
    final user = supabase.auth.currentUser;
    if (user == null) return ['en-US'];

    final metadata = user.userMetadata;
    final languages = metadata?['languages'] as List?;

    if (languages == null || languages.isEmpty) {
      return ['en-US'];
    }

    // Convert language names to TMDB codes
    return languages
        .map((lang) => _languageCodeMap[lang as String])
        .where((code) => code != null)
        .cast<String>()
        .toList();
  }

  // Get a random language from user preferences (backward compatibility)
  static String getUserLanguage() {
    final languages = getUserLanguages();
    if (languages.isEmpty) return 'en-US';
    return languages[Random().nextInt(languages.length)];
  }

  // Update user metadata (name, age, languages)
  static Future<UserResponse> updateUserMetadata(
    Map<String, dynamic> data,
  ) async {
    return await supabase.auth.updateUser(UserAttributes(data: data));
  }

  // Update password
  static Future<UserResponse> updatePassword(String newPassword) async {
    return await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // Check if user has agreed to terms
  static Future<bool> hasAgreedToTerms() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return true; // Fail-safe if not logged in

    try {
      final result = await supabase
          .from('profiles')
          .select('agreed_to_terms')
          .eq('id', userId)
          .maybeSingle();

      if (result == null) return false;
      return result['agreed_to_terms'] == true;
    } catch (e) {
      debugPrint('Error checking terms agreement: $e');
      return true; // Fail-safe on error
    }
  }

  // Set agreed to terms
  static Future<void> agreeToTerms() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'agreed_to_terms': true})
          .eq('id', userId);
    } catch (e) {
      debugPrint('Error agreeing to terms: $e');
    }
  }

  // Example: fetch a list from 'titles' table
  static Future<PostgrestResponse> fetchTitles({int limit = 20}) async {
    return await supabase.from('titles').select().limit(limit);
  }

  // Insert liked movie genres
  static Future<void> addLikedMovieGenres(String genreString) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Split genres by comma
      final genres = genreString
          .split(',')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty);

      for (final genre in genres) {
        // Check if this genre already exists for this user
        final existing = await supabase
            .from('liked_movies')
            .select('genre')
            .eq('user_id', userId)
            .eq('genre', genre);

        // Only insert if it doesn't exist
        if (existing.isEmpty) {
          await supabase.from('liked_movies').insert({
            'user_id': userId,
            'genre': genre,
          });
        }
      }
    } catch (e) {
      debugPrint('Error adding liked genres: $e');
    }
  }

  // Insert liked TV genres
  static Future<void> addLikedTVGenres(String genreString) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final genres = genreString
          .split(',')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty);

      for (final genre in genres) {
        final existing = await supabase
            .from('liked_series')
            .select('genre')
            .eq('user_id', userId)
            .eq('genre', genre);

        if (existing.isEmpty) {
          await supabase.from('liked_series').insert({
            'user_id': userId,
            'genre': genre,
          });
        }
      }
    } catch (e) {
      debugPrint('Error adding liked TV genres: $e');
    }
  }

  // Get liked movie genres
  static Future<List<String>> getLikedMovieGenres() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final data = await supabase
          .from('liked_movies')
          .select<List<Map<String, dynamic>>>('genre')
          .eq('user_id', userId);

      if (data.isEmpty) return [];

      final genres = data.map((e) => e['genre'] as String).toSet().toList();
      return genres;
    } catch (e) {
      debugPrint(
        'An unexpected error occurred while fetching liked genres: $e',
      );
      return [];
    }
  }

  // Get liked TV genres
  static Future<List<String>> getLikedTVGenres() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final data = await supabase
          .from('liked_series')
          .select<List<Map<String, dynamic>>>('genre')
          .eq('user_id', userId);

      if (data.isEmpty) return [];

      return data.map((e) => e['genre'] as String).toSet().toList();
    } catch (e) {
      debugPrint('Error fetching liked TV genres: $e');
      return [];
    }
  }

  // Check if user has any liked content
  static Future<bool> hasLikedContent(bool isMovie) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final table = isMovie ? 'liked_movies' : 'liked_series';

    try {
      final result = await supabase
          .from(table)
          .select('genre')
          .eq('user_id', userId)
          .limit(1);

      return (result as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Watchlist methods
  static Future<void> addToWatchlist(
    Map<String, dynamic> item,
    bool isMovie,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('watchlist').insert({
        'user_id': userId,
        'item_id': item['id'],
        'item_type': isMovie ? 'movie' : 'tv',
        'title': item['title'] ?? item['name'],
        'poster_path': item['poster_path'],
        'release_date': item['release_date'] ?? item['first_air_date'],
        'overview': item['overview'],
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      });
      // Invalidate cache so ListPage fetches fresh data immediately
      CacheService.clear('list_page_full_watchlist');
    } catch (e) {
      debugPrint('Error adding to watchlist: $e');
    }
  }

  static Future<void> removeFromWatchlist(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watchlist')
          .delete()
          .eq('user_id', userId)
          .eq('item_id', itemId);
      // Invalidate cache so ListPage fetches fresh data immediately
      CacheService.clear('list_page_full_watchlist');
    } catch (e) {
      debugPrint('Error removing from watchlist: $e');
    }
  }

  static Future<void> updateWatchlistTimestamp(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watchlist')
          .update({'last_updated': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      debugPrint('Error updating watchlist timestamp: $e');
    }
  }

  static Future<bool> isInWatchlist(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final result = await supabase
          .from('watchlist')
          .select('item_id')
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .limit(1);

      return (result as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getWatchlist() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      // Order by last_updated descending
      final result = await supabase
          .from('watchlist')
          .select()
          .eq('user_id', userId)
          .order('last_updated', ascending: false);

      return (result as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('Error fetching watchlist: $e');
      try {
        final result = await supabase
            .from('watchlist')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        return (result as List)
            .map((item) => item as Map<String, dynamic>)
            .toList();
      } catch (e2) {
        return [];
      }
    }
  }

  // Watched methods
  static Future<void> addToWatched(
    Map<String, dynamic> item,
    bool isMovie, {
    int? rating,
    int? watchedSeason,
    int? watchedEpisode,
    int? runtime,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Ensure we have an ID
    final itemId = item['id'];

    // Update watchlist timestamp if item exists there (e.g. starting a series)
    if (itemId != null) {
      await updateWatchlistTimestamp(itemId);
    }

    try {
      await supabase.from('watched').upsert({
        'user_id': userId,
        'item_id': item['id'],
        'item_type': isMovie ? 'movie' : 'tv',
        'title': item['title'] ?? item['name'],
        'poster_path': item['poster_path'],
        'release_date': item['release_date'] ?? item['first_air_date'],
        'overview': item['overview'],
        'rating': rating,
        'watched_date': DateTime.now().toIso8601String().split('T')[0],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'watched_season': watchedSeason,
        'watched_episode': watchedEpisode,
      }, onConflict: 'user_id, item_id');

      if (runtime != null) {
        await _updateWatchStats(runtime, isMovie, true);
      }
    } catch (e) {
      debugPrint('Error adding to watched: $e');
    }
  }

  static Future<void> removeFromWatched(
    int itemId, {
    bool isMovie = true,
    int? runtime,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watched')
          .delete()
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .eq('item_type', isMovie ? 'movie' : 'tv');

      if (runtime != null) {
        await _updateWatchStats(runtime, isMovie, false);
      }
    } catch (e) {
      debugPrint('Error removing from watched: $e');
    }
  }

  static Future<Map<String, dynamic>?> getWatchedItem(int itemId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final result = await supabase
          .from('watched')
          .select()
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .maybeSingle();

      return result;
    } catch (e) {
      debugPrint('Error checking watched status: $e');
      return null;
    }
  }

  static Future<bool> isWatched(int itemId) async {
    final item = await getWatchedItem(itemId);
    return item != null;
  }

  static Future<List<Map<String, dynamic>>> getWatched() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final result = await supabase
          .from('watched')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      return (result as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('Error fetching watched: $e');
      // Fallback: fetch with watched_date order if updated_at column is missing
      try {
        final result = await supabase
            .from('watched')
            .select()
            .eq('user_id', userId)
            .order('watched_date', ascending: false);
        return (result as List)
            .map((item) => item as Map<String, dynamic>)
            .toList();
      } catch (e2) {
        return [];
      }
    }
  }

  static Future<void> updateRating(int itemId, int rating) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('watched')
          .update({'rating': rating})
          .eq('user_id', userId)
          .eq('item_id', itemId);
    } catch (e) {
      debugPrint('Error updating rating: $e');
    }
  }

  // Update watched progress for TV series
  // Update watched progress for TV series
  static Future<void> updateWatchedProgress(
    Map<String, dynamic> item, // Changed from int itemId to Map item
    int season,
    int episode, {
    int? runtimeAdded,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Ensure we have an ID
    final itemId = item['id'];
    if (itemId == null) return;

    // Update watchlist timestamp so it moves to top of list
    await updateWatchlistTimestamp(itemId);

    try {
      // Try to update existing record first
      final response = await supabase
          .from('watched')
          .update({
            'watched_season': season,
            'watched_episode': episode,
            'watched_date': DateTime.now().toIso8601String().split('T')[0],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('item_id', itemId)
          .select(); // Select to check if row was returned

      if (response.isEmpty) {
        // No row updated, so we need to insert it
        await addToWatched(
          item,
          false, // isMovie is false for series progress updates
          watchedSeason: season,
          watchedEpisode: episode,
          runtime: runtimeAdded,
        );
      } else {
        // Update succeeded, handle stats separately if needed
        if (runtimeAdded != null) {
          await _updateWatchStats(runtimeAdded, false, true);
        }
      }
    } catch (e) {
      debugPrint('Error updating watched progress: $e');
    }
  }

  // Helper to mark an entire series as watched
  static Future<void> markSeriesAsWatched(
    Map<String, dynamic> show,
    Map<String, dynamic> details, {
    int? totalRuntime,
    int? rating,
  }) async {
    try {
      final seasons = details['seasons'] as List<dynamic>;

      // Find the last season (ignoring season 0 if possible, or just taking max season number)
      int maxSeason = 0;
      int maxEpisode = 0;

      for (var season in seasons) {
        final seasonNum = season['season_number'] as int;
        final episodeCount = season['episode_count'] as int;

        if (seasonNum > 0 && seasonNum >= maxSeason) {
          maxSeason = seasonNum;
          maxEpisode = episodeCount;
        }
      }

      // Calculate runtime if not provided
      if (totalRuntime == null) {
        final runtimes = details['episode_run_time'] as List<dynamic>?;
        int avgRuntime = 45; // Default fallback
        if (runtimes != null && runtimes.isNotEmpty) {
          final sum = runtimes.fold<int>(0, (p, c) => p + (c as int));
          avgRuntime = (sum / runtimes.length).round();
        }

        int totalEpisodes = 0;
        for (var season in seasons) {
          final seasonNum = season['season_number'] as int;
          final episodeCount = season['episode_count'] as int;

          if (seasonNum > 0 && seasonNum <= maxSeason) {
            totalEpisodes += episodeCount;
          }
        }
        totalRuntime = totalEpisodes * avgRuntime;
      }

      if (maxSeason > 0 && maxEpisode > 0) {
        await addToWatched(
          show,
          false,
          watchedSeason: maxSeason,
          watchedEpisode: maxEpisode,
          runtime: totalRuntime,
          rating: rating,
        );
      }
    } catch (e) {
      debugPrint('Error marking series as watched: $e');
      rethrow;
    }
  }

  static Future<void> _updateWatchStats(
    int minutes,
    bool isMovie,
    bool add,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata ?? {};
    final key = isMovie ? 'total_movie_minutes' : 'total_series_minutes';
    int current = metadata[key] ?? 0;

    if (add) {
      current += minutes;
    } else {
      current -= minutes;
      if (current < 0) current = 0;
    }

    await supabase.auth.updateUser(
      UserAttributes(data: {...metadata, key: current}),
    );
  }

  // Dislike methods
  static Future<void> addDislike({
    required int itemId,
    required bool isMovie,
    required String reason,
    Map<String, dynamic>? details,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('dislikes').insert({
        'user_id': userId,
        'item_id': itemId,
        'item_type': isMovie ? 'movie' : 'tv',
        'reason': reason,
        'details': details,
      });
    } catch (e) {
      debugPrint('Error adding dislike: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getDislikes() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final data = await supabase
          .from('dislikes')
          .select()
          .eq('user_id', userId);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Error fetching dislikes: $e');
      return [];
    }
  }

  // NOTE: Language preference support can be added later by:
  // 1. Adding a user_preferences table or extending auth.users metadata
  // 2. Storing language preference and using it in TMDB queries
  // Currently, all movies are filtered by language=en-US via the proxy server
  // Get all IDs from watchlist and watched to exclude from recommendations
  static Future<Set<int>> getExcludedIds() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return {};

    try {
      final responses = await Future.wait([
        supabase.from('watchlist').select('item_id').eq('user_id', userId),
        supabase.from('watched').select('item_id').eq('user_id', userId),
      ]);

      final watchlistIds = (responses[0] as List)
          .map((e) => e['item_id'] as int)
          .toSet();
      final watchedIds = (responses[1] as List)
          .map((e) => e['item_id'] as int)
          .toSet();

      return {...watchlistIds, ...watchedIds};
    } catch (e) {
      debugPrint('Error fetching excluded IDs: $e');
      return {};
    }
  }
}
