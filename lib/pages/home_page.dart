import 'package:flutter/material.dart';

import 'movies.dart';
import 'series.dart';
import '../services/supabase_service.dart';
import '../services/tmdb_service.dart';
import '../widget/responsive_layout.dart';
import '../widget/movie_series_toggle.dart';
import '../widget/frosted_card.dart';
import '../services/cache_service.dart';

import 'dart:math';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isMovieMode = true; // For toggle widget

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedIndex: 1,
      child: Stack(
        children: [
          // Page Content (HomeTab handles its own scrolling)
          HomeTab(isMovieMode: _isMovieMode),

          // Static Title
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'VIEWPICK',
                style: TextStyle(
                  fontFamily: 'BitcountGridSingle',
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),

          // Floating Movie/Series Toggle
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Center(
              child: MovieSeriesToggle(
                isMovieMode: _isMovieMode,
                onToggle: (isMovie) {
                  if (!mounted) return;
                  setState(() {
                    _isMovieMode = isMovie;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  final bool isMovieMode;
  const HomeTab({super.key, required this.isMovieMode});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

// ... (existing imports)

class _HomeTabState extends State<HomeTab> {
  final TMDBService _tmdbService = TMDBService();

  List<Map<String, dynamic>> _youMayLike = [];
  List<Map<String, dynamic>> _newlyReleased = [];
  List<Map<String, dynamic>> _watchlist = [];
  List<Map<String, dynamic>> _trending = [];

  // To handle initial loading state if cache is empty
  bool _isLoadingYouMayLike = true;
  bool _isLoadingNewlyReleased = true;
  bool _isLoadingWatchlist = true;
  bool _isLoadingTrending = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMovieMode != widget.isMovieMode) {
      // Clear current data to avoid showing wrong type while loading
      setState(() {
        _youMayLike = [];
        _newlyReleased = [];
        _watchlist = [];
        _trending = [];
        _isLoadingYouMayLike = true;
        _isLoadingNewlyReleased = true;
        _isLoadingWatchlist = true;
        _isLoadingTrending = true;
      });
      _loadData();
    }
  }

  void _loadData() {
    final mode = widget.isMovieMode ? 'movie' : 'tv';

    // Helper to get language
    String getFetchLanguage() {
      if (widget.isMovieMode) {
        return SupabaseService.getUserLanguage();
      } else {
        final allLangs = List<String>.from(
          SupabaseService.supportedLanguageCodes,
        );
        allLangs.addAll(['en-US', 'en-US', 'en-US']);
        return allLangs[Random().nextInt(allLangs.length)];
      }
    }

    final lang = getFetchLanguage();

    // internal helper to handle cache + fetch
    Future<void> loadSection(
      String keySuffix,
      Function(List<Map<String, dynamic>>) onUpdate,
      Function(bool) setLoading,
      Future<List<Map<String, dynamic>>> Function() fetcher,
    ) async {
      final key = 'home_${keySuffix}_$mode';

      // 1. Load Cache
      final cached = await CacheService.load(key);
      if (cached != null && mounted) {
        onUpdate(List<Map<String, dynamic>>.from(cached));
        setLoading(false);
      }

      // 2. Fetch Network
      try {
        final fresh = await fetcher();
        if (mounted) {
          onUpdate(fresh);
          setLoading(false);
          if (fresh.isNotEmpty) {
            CacheService.save(key, fresh);
          }
        }
      } catch (e) {
        debugPrint('Error loading $key: $e');
        if (mounted) setLoading(false);
      }
    }

    loadSection(
      'you_may_like',
      (l) => setState(() => _youMayLike = l),
      (b) => setState(() => _isLoadingYouMayLike = b),
      () => _fetchYouMayLike(),
    );
    loadSection(
      'newly_released',
      (l) => setState(() => _newlyReleased = l),
      (b) => setState(() => _isLoadingNewlyReleased = b),
      () => _fetchNewlyReleased(lang),
    );
    loadSection(
      'watchlist',
      (l) => setState(() => _watchlist = l),
      (b) => setState(() => _isLoadingWatchlist = b),
      () => _fetchWatchlist(),
    );
    loadSection(
      'trending',
      (l) => setState(() => _trending = l),
      (b) => setState(() => _isLoadingTrending = b),
      () => _fetchTrending(lang),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchYouMayLike() async {
    try {
      // 1. Get Liked Genres
      final likedGenres = widget.isMovieMode
          ? await SupabaseService.getLikedMovieGenres()
          : await SupabaseService.getLikedTVGenres();

      // 2. Get User Languages
      final userLanguages = SupabaseService.getUserLanguages();

      // 3. Map Genres to IDs
      final genreMap = widget.isMovieMode
          ? await _tmdbService.getGenreList()
          : await _tmdbService.getTVGenreList();

      final likedGenreIds = <int>[];
      for (final likedGenre in likedGenres) {
        for (final entry in genreMap.entries) {
          if (entry.value.toLowerCase().trim() ==
              likedGenre.toLowerCase().trim()) {
            likedGenreIds.add(entry.key);
            break;
          }
        }
      }

      // 4. Determine Languages to fetch from
      List<String> targetLanguages = [];
      if (widget.isMovieMode) {
        if (userLanguages.isEmpty) {
          targetLanguages = ['en-US'];
        } else {
          targetLanguages = List.from(userLanguages)..shuffle();
          if (targetLanguages.length > 3) {
            targetLanguages = targetLanguages.take(3).toList();
          }
        }
      } else {
        // Series mode: Random languages with English bias
        final allLangs = List<String>.from(
          SupabaseService.supportedLanguageCodes,
        );
        allLangs.addAll(['en-US', 'en-US', 'en-US']);
        allLangs.shuffle();
        targetLanguages = allLangs.take(3).toList();
      }

      List<dynamic> allRawItems = [];

      // 5. Fetch content for each language
      final futures = targetLanguages.map((language) async {
        // Extract language code (e.g. 'ml' from 'ml-IN') for strict filtering
        final langCode = language.split('-')[0];

        if (likedGenreIds.isNotEmpty) {
          // If we have liked genres, pick a random one for this language
          final randomGenreId =
              likedGenreIds[Random().nextInt(likedGenreIds.length)];
          return widget.isMovieMode
              ? await _tmdbService.getMoviesByGenre(
                  randomGenreId,
                  language: language,
                  withOriginalLanguage: langCode,
                )
              : await _tmdbService.getTVByGenre(
                  randomGenreId,
                  language: language,
                  withOriginalLanguage: langCode,
                );
        } else {
          // If no liked genres, fetch popular/trending for this language
          return widget.isMovieMode
              ? await _tmdbService.getMoviesByOriginalLanguage(
                  langCode,
                  language: language,
                )
              : await _tmdbService.getTVByOriginalLanguage(
                  langCode,
                  language: language,
                );
        }
      });

      final results = await Future.wait(futures);
      for (var list in results) {
        allRawItems.addAll(list);
      }

      // 6. Deduplicate and Shuffle
      final uniqueItems = <int, Map<String, dynamic>>{};
      for (var item in allRawItems) {
        if (item['id'] != null) {
          uniqueItems[item['id']] = _formatItem(item);
        }
      }

      final finalList = uniqueItems.values.toList()..shuffle();

      return finalList.take(10).toList();
    } catch (e) {
      debugPrint('Error in _fetchYouMayLike: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNewlyReleased(
    String language,
  ) async {
    try {
      final items = widget.isMovieMode
          ? await _tmdbService.getNowPlayingMovies(language: language)
          : await _tmdbService.getOnTheAirTV(language: language);

      // Filter for items released in the last 3 months (approx 90 days)
      final now = DateTime.now();
      final threeMonthsAgo = now.subtract(const Duration(days: 90));

      final recentItems = items.where((item) {
        final dateStr = item['release_date'] ?? item['first_air_date'];
        if (dateStr == null || dateStr.isEmpty) return false;
        try {
          final date = DateTime.parse(dateStr);
          return date.isAfter(threeMonthsAgo) &&
              date.isBefore(
                now.add(const Duration(days: 7)),
              ); // Allow slightly future releases (e.g. this week)
        } catch (e) {
          return false;
        }
      }).toList();

      // Sort by release date descending (newest first)
      recentItems.sort((a, b) {
        final dateA = a['release_date'] ?? a['first_air_date'] ?? '';
        final dateB = b['release_date'] ?? b['first_air_date'] ?? '';
        return dateB.compareTo(dateA);
      });

      return recentItems.take(10).map((item) => _formatItem(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchWatchlist() async {
    try {
      final watchlist = await SupabaseService.getWatchlist();

      // Filter based on current mode
      final filteredItems = watchlist.where((item) {
        final isMovie = item['item_type'] == 'movie';
        return isMovie == widget.isMovieMode;
      }).toList();

      // Fetch details in parallel
      final futures = filteredItems.map((item) async {
        try {
          final int id = item['item_id'];
          final bool isMovie = item['item_type'] == 'movie';

          Map<String, dynamic> details;
          if (isMovie) {
            details = await _tmdbService.getMovieDetails(id);
          } else {
            details = await _tmdbService.getTVDetails(id);
          }

          final name = details['title'] ?? details['name'] ?? 'No Title';
          final releaseDate =
              details['release_date'] ?? details['first_air_date'] ?? '';
          final year = releaseDate.length >= 4
              ? releaseDate.substring(0, 4)
              : '';
          final overview = details['overview'] ?? 'No description';

          return {
            'id': id,
            'title': name,
            'year': year,
            'image': 'https://image.tmdb.org/t/p/w500${details['poster_path']}',
            'subtitle': overview.length > 50
                ? overview.substring(0, 50) + '...'
                : overview,
          };
        } catch (e) {
          // debugPrint(
          //   'Error fetching details for watchlist item ${item['item_id']}: $e',
          // );
          // Fallback to Supabase data
          return {
            'id': item['item_id'],
            'title': item['title'],
            'year': (item['release_date'] != null && (item['release_date'] as String).length >= 4) ? (item['release_date'] as String).substring(0, 4) : '',
            'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
            'subtitle': item['overview'] ?? 'No description',
          };
        }
      });

      final results = await Future.wait(futures);
      return results;
    } catch (e) {
      debugPrint('Error fetching watchlist: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTrending(String language) async {
    try {
      final items = widget.isMovieMode
          ? await _tmdbService.getTrendingMovies(language: language)
          : await _tmdbService.getTrendingTV(language: language);

      return items.take(10).map((item) => _formatItem(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Map<String, dynamic> _formatItem(dynamic item) {
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
    final subtitle = (item['overview'] as String?) ?? 'No description';

    return {
      'id': item['id'],
      'title': name,
      'year': year,
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
      'subtitle': subtitle.length > 50
          ? '${subtitle.substring(0, 50)}...'
          : subtitle,
    };
  }

  Widget _buildSection(
    String title,
    List<Map<String, dynamic>> items,
    bool isLoading,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: isLoading && items.isEmpty
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 140,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  },
                )
              : items.isEmpty
              ? (title == 'From Watchlist'
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Your watchlist is empty',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink())
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return GestureDetector(
                      onTap: () async {
                        if (widget.isMovieMode) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MoviePage(movieId: item['id']),
                            ),
                          );
                        } else {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SeriesPage(tvId: item['id']),
                            ),
                          );
                        }
                        // Refresh watchlist on return if needed
                        if (title == 'From Watchlist') {
                          // re-trigger watchlist fetch logic manually if strictly needed,
                          // or just rely on next periodic/init update.
                          // Simplest is nothing or a targeted refresh.
                          // For now, let's leave it to keep it simple as user didn't ask for auto-refresh on back.
                        }
                      },
                      child: FrostedCard(
                        imageUrl: item['image'] ?? '',
                        title: item['title'] ?? 'No Title',
                        year: item['year'] ?? '',
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('You May Like', _youMayLike, _isLoadingYouMayLike),
          _buildSection(
            'Newly Released',
            _newlyReleased,
            _isLoadingNewlyReleased,
          ),
          _buildSection('From Watchlist', _watchlist, _isLoadingWatchlist),
          _buildSection('Trending This Week', _trending, _isLoadingTrending),
          const SizedBox(height: 100), // For bottom nav bar
        ],
      ),
    );
  }
}
