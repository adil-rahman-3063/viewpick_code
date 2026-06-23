import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/responsive_layout.dart';
import '../widget/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'movies.dart';
import 'series.dart';

class SwipePage extends StatefulWidget {
  const SwipePage({super.key});

  @override
  State<SwipePage> createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage> {
  final CardSwiperController controller = CardSwiperController();
  final FocusNode _keyboardFocus = FocusNode();
  final TMDBService _tmdbService = TMDBService();
  Map<int, String> _genreMap = {};
  Map<int, String> _tvGenreMap = {};

  List<Map<String, dynamic>> _movies = [];
  bool _isLoading = true;


  @override
  void initState() {
    super.initState();
    _initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstTime();
      _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_isLoading || _movies.isEmpty) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        controller.swipeRight();
        break;
      case LogicalKeyboardKey.arrowLeft:
        controller.swipeLeft();
        break;
      case LogicalKeyboardKey.arrowUp:
        controller.swipeTop();
        break;
      default:
        break;
    }
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_swipe_instructions') ?? false;
    if (!seen) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'How to Swipe',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InstructionRow(Icons.swipe_right,   '→  Swipe Right / Arrow Right', Theme.of(context).colorScheme.primary),
                const SizedBox(height: 10),
                _InstructionRow(Icons.swipe_left,    '←  Swipe Left / Arrow Left',  Theme.of(context).colorScheme.error),
                const SizedBox(height: 10),
                _InstructionRow(Icons.swipe_up,      '↑  Swipe Up / Arrow Up — Skip', Theme.of(context).colorScheme.secondary),
                const SizedBox(height: 10),
                _InstructionRow(Icons.touch_app,     'Tap card to open details',     Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  prefs.setBool('seen_swipe_instructions', true);
                },
                child: Text(
                  'Got it!',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _initialize() async {
    try {
      try {
        _genreMap = await _tmdbService.getGenreList();
      } catch (e) {
        debugPrint('Error loading movie genres: $e');
      }

      try {
        _tvGenreMap = await _tmdbService.getTVGenreList();
      } catch (e) {
        debugPrint('Error loading TV genres: $e');
      }

      // Ensure we have at least some genres or handle empty map later
      if (_tvGenreMap.isEmpty) {
        debugPrint('Warning: TV Genre map is empty. Retrying...');
        try {
          _tvGenreMap = await _tmdbService.getTVGenreList();
        } catch (e) {
          debugPrint('Retry failed: $e');
        }
      }

      // Initial fetch (small batch for speed)
      await _fetchMovies(count: 6);
    } catch (e) {
      debugPrint('Error initializing page: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isFetchingMore = false;

  Future<void> _fetchMovies({int count = 6}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final newContent = await _fetchContentBatch(targetCount: count);

      if (mounted) {
        setState(() {
          _movies = newContent;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching content: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchContentBatch({
    int targetCount = 6,
  }) async {
    final List<Map<String, dynamic>> batchResult = [];
    int attempts = 0;

    // Fetch user preferences and history once outside the loop for efficiency
    List<Map<String, dynamic>> dislikes = [];
    List<String> likedMovieGenres = [];
    List<String> likedTVGenres = [];
    Set<int> excludedIds = {};
    List<Map<String, dynamic>> watchedList = [];
    List<Map<String, dynamic>> watchlist = [];
    List<String> userLanguages = [];

    try {
      final results = await Future.wait([
        SupabaseService.getDislikes(),
        SupabaseService.getLikedMovieGenres(),
        SupabaseService.getLikedTVGenres(),
        SupabaseService.getExcludedIds(),
        SupabaseService.getWatched(),
        SupabaseService.getWatchlist(),
      ]);

      dislikes = results[0] as List<Map<String, dynamic>>;
      likedMovieGenres = results[1] as List<String>;
      likedTVGenres = results[2] as List<String>;
      excludedIds = results[3] as Set<int>;
      watchedList = results[4] as List<Map<String, dynamic>>;
      watchlist = results[5] as List<Map<String, dynamic>>;
      userLanguages = SupabaseService.getUserLanguages();
    } catch (e) {
      debugPrint('Error fetching preferences: $e');
    }

    // We try to fill the batch until we reach target count or max attempts
    while (batchResult.length < targetCount && attempts < targetCount + 5) {
      attempts++;
      try {
        bool isDisliked(Map<String, dynamic> item, bool isMovie) {
          // Check local batch duplicates
          if (batchResult.any((b) => b['id'] == item['id'])) return true;

          if (excludedIds.contains(item['id'])) return true;

          final dateStr = (item['release_date'] ?? item['first_air_date'] ?? '')
              .toString();
          final itemYear = dateStr.length >= 4
              ? int.tryParse(dateStr.substring(0, 4)) ?? 0
              : 0;
          final activeGenreMap = isMovie ? _genreMap : _tvGenreMap;
          final itemGenres = (item['genre_ids'] as List<dynamic>? ?? [])
              .map((id) => activeGenreMap[id])
              .where((name) => name != null)
              .toList();

          for (final dislike in dislikes) {
            final reason = dislike['reason'];
            final details = dislike['details'];

            if (reason == 'genre') {
              if (itemGenres.contains(details['genre'])) return true;
            } else if (reason == 'year_exact') {
              if (itemYear == details['year']) return true;
            } else if (reason == 'year_before') {
              if (itemYear < details['year']) return true;
            } else if (reason == 'language') {
              if (item['original_language'] == details['language_code']) {
                return true;
              }
            }
          }
          return false;
        }

        // Randomly decide between Movie and Series for this attempt
        final bool fetchMovie = Random().nextBool();
        bool actualFetchMovie = fetchMovie;
        final activeGenreMap = fetchMovie ? _genreMap : _tvGenreMap;
        final currentLikedGenres = fetchMovie ? likedMovieGenres : likedTVGenres;

        // Strategies:
        // 0-39: Recommendations / Similar (if user has watched/watchlist history)
        // 40-79: Genre / You May Like (liked genres & languages)
        // 80-99: Popular / Trending Fallback
        int strategy = Random().nextInt(100);

        List<dynamic> content = [];

        // Strategy 1: Recommendations / Similar (if user has watched/watchlist history)
        if (strategy < 40 && (watchedList.isNotEmpty || watchlist.isNotEmpty)) {
          final targetType = fetchMovie ? 'movie' : 'tv';
          final eligibleItems = <Map<String, dynamic>>[];

          eligibleItems.addAll(watchedList.where((item) => item['item_type'] == targetType));
          eligibleItems.addAll(watchlist.where((item) => item['item_type'] == targetType));

          // If no items of target type, try the other type
          if (eligibleItems.isEmpty) {
            final otherType = fetchMovie ? 'tv' : 'movie';
            eligibleItems.addAll(watchedList.where((item) => item['item_type'] == otherType));
            eligibleItems.addAll(watchlist.where((item) => item['item_type'] == otherType));
          }

          if (eligibleItems.isNotEmpty) {
            final randomItem = eligibleItems[Random().nextInt(eligibleItems.length)];
            final int tmdbId = randomItem['item_id'];
            actualFetchMovie = randomItem['item_type'] == 'movie';

            final randomPage = Random().nextInt(3) + 1;
            final useRecommendations = Random().nextBool();

            try {
              if (actualFetchMovie) {
                content = useRecommendations
                    ? await _tmdbService.getMovieRecommendations(tmdbId, page: randomPage)
                    : await _tmdbService.getSimilarMovies(tmdbId, page: randomPage);
              } else {
                content = useRecommendations
                    ? await _tmdbService.getTVRecommendations(tmdbId, page: randomPage)
                    : await _tmdbService.getSimilarTV(tmdbId, page: randomPage);
              }
            } catch (e) {
              debugPrint('Error fetching recommendations for item $tmdbId: $e');
            }
          }
        }

        // Strategy 2: Genre/You May Like (liked genres & languages)
        if (content.isEmpty && (currentLikedGenres.isNotEmpty || userLanguages.isNotEmpty)) {
          final hasLikedThisTypeContent = currentLikedGenres.isNotEmpty;

          // If we have liked genres, fetch by genre
          if (hasLikedThisTypeContent && Random().nextDouble() < 0.7) {
            final dislikedGenreNames = dislikes
                .where((d) => d['reason'] == 'genre')
                .map((d) => d['details']['genre'])
                .toSet();

            final validGenreIds = activeGenreMap.entries
                .where((entry) =>
                    currentLikedGenres.contains(entry.value) &&
                    !dislikedGenreNames.contains(entry.value))
                .map((entry) => entry.key)
                .toList();

            if (validGenreIds.isNotEmpty) {
              final randomGenreId = validGenreIds[Random().nextInt(validGenreIds.length)];
              final randomPage = Random().nextInt(15) + 1;

              String language = 'en-US';
              String? langCode;
              if (userLanguages.isNotEmpty) {
                language = userLanguages[Random().nextInt(userLanguages.length)];
                langCode = language.split('-')[0];
              }

              try {
                if (fetchMovie) {
                  content = await _tmdbService.getMoviesByGenre(
                    randomGenreId,
                    page: randomPage,
                    language: language,
                    withOriginalLanguage: langCode,
                  );
                } else {
                  content = await _tmdbService.getTVByGenre(
                    randomGenreId,
                    page: randomPage,
                    language: language,
                    withOriginalLanguage: langCode,
                  );
                }
              } catch (_) {}
            }
          }

          // Fetch by original language
          if (content.isEmpty && userLanguages.isNotEmpty) {
            final dislikedLanguages = dislikes
                .where((d) => d['reason'] == 'language')
                .map((d) => d['details']['language_code'])
                .toSet();

            final availableLanguages = userLanguages.where((lang) {
              final code = lang.split('-')[0];
              return !dislikedLanguages.contains(code);
            }).toList();

            if (availableLanguages.isNotEmpty) {
              final targetLanguage = availableLanguages[Random().nextInt(availableLanguages.length)];
              final targetCode = targetLanguage.split('-')[0];
              final randomPage = Random().nextInt(15) + 1;

              try {
                content = fetchMovie
                    ? await _tmdbService.getMoviesByOriginalLanguage(
                        targetCode,
                        language: targetLanguage,
                        page: randomPage,
                      )
                    : await _tmdbService.getTVByOriginalLanguage(
                        targetCode,
                        language: targetLanguage,
                        page: randomPage,
                      );
              } catch (_) {}
            }
          }
        }

        // Fallback / Strategy 3: Random/Popular (Fallback)
        if (content.isEmpty) {
          final randomPage = Random().nextInt(20) + 1;
          String language = 'en-US';
          String? langCode;
          if (userLanguages.isNotEmpty) {
            language = userLanguages[Random().nextInt(userLanguages.length)];
            langCode = language.split('-')[0];
          }

          try {
            if (Random().nextBool()) {
              content = fetchMovie
                  ? await _tmdbService.getMoviesByOriginalLanguage(
                      langCode ?? 'en',
                      language: language,
                      page: randomPage,
                    )
                  : await _tmdbService.getTVByOriginalLanguage(
                      langCode ?? 'en',
                      language: language,
                      page: randomPage,
                    );
            } else {
              content = fetchMovie
                  ? await _tmdbService.getPopularMovies(
                      language: language,
                      page: randomPage,
                    )
                  : await _tmdbService.getPopularTV(
                      language: language,
                      page: randomPage,
                    );
            }
          } catch (e) {
            try {
              content = fetchMovie
                  ? await _tmdbService.getPopularMovies(page: 1)
                  : await _tmdbService.getPopularTV(page: 1);
            } catch (_) {}
          }
        }

        content.shuffle();

        // Filter and format
        for (var item in content) {
          if (!isDisliked(item, actualFetchMovie)) {
            batchResult.add(_formatData(item, actualFetchMovie));
            if (batchResult.length >= targetCount) break;
          }
        }
      } catch (e) {
        debugPrint('Error in single fetch attempt: $e');
      }
    }
    return batchResult;
  }

  Future<void> _loadMoreContent({int count = 15}) async {
    if (_isFetchingMore) return;

    _isFetchingMore = true;
    debugPrint('Fetching more content...');

    // Append loading card if not present and we are running low
    if (_movies.isEmpty || _movies.last['id'] != -1) {
      setState(() {
        _movies.add({
          'id': -1,
          'name': 'Loading...',
          'image': '',
          'description': 'Fetching more content...',
          'genre': '',
          'year': '',
        });
      });
    }

    int retryCount = 0;
    bool addedContent = false;

    try {
      while (!addedContent && retryCount < 3) {
        if (retryCount > 0) {
          debugPrint('Retrying fetch (attempt ${retryCount + 1})...');
          await Future.delayed(const Duration(milliseconds: 500));
        }

        final newContent = await _fetchContentBatch(targetCount: count);
        if (newContent.isNotEmpty && mounted) {
          // Filter out duplicates
          final uniqueContent = newContent.where((newItem) {
            return !_movies.any(
              (existingItem) => existingItem['id'] == newItem['id'],
            );
          }).toList();

          if (mounted) {
            setState(() {
              // Remove loading card
              final loadingIndex = _movies.indexWhere((m) => m['id'] == -1);
              if (loadingIndex != -1) {
                _movies.removeAt(loadingIndex);
                // Insert new content at the position of the loading card
                _movies.insertAll(loadingIndex, uniqueContent);
              } else {
                _movies.addAll(uniqueContent);
              }
            });
            debugPrint(
              'Added ${uniqueContent.length} new items. Total: ${_movies.length}',
            );
            addedContent = true;
          }
        } else {
          debugPrint('Fetched content was empty or all duplicates.');
        }
        retryCount++;
      }
    } catch (e) {
      debugPrint('Error loading more content: $e');
      // Remove loading card on error
      if (mounted) {
        setState(() {
          _movies.removeWhere((m) => m['id'] == -1);
        });
      }
    } finally {
      _isFetchingMore = false;
    }
  }

  Map<String, dynamic> _formatData(dynamic item, bool isMovie) {
    final activeGenreMap = isMovie ? _genreMap : _tvGenreMap;
    final genreIds = item['genre_ids'] as List<dynamic>? ?? [];
    final genres = genreIds
        .map((id) => activeGenreMap[id])
        .where((name) => name != null)
        .join(', ');

    // Handle movies vs TV series (different field names)
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

    return {
      'id': item['id'],
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
      'name': name,
      'year': year,
      'genre': genres,
      'description': item['overview'],
      'original_language': item['original_language'],
      'is_movie': isMovie,
    };
  }

  void _swipeUp() {
    controller.swipeTop();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocus,
      onKeyEvent: _handleKeyEvent,
      child: ResponsiveLayout(
      selectedIndex: 0,
      child: Column(
        children: [
          // Card area - shows loading or content
          // Card area - shows loading or content
          Expanded(
            child: _isLoading
                ? Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: MediaQuery.of(context).size.height * 0.68,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : _movies.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'Could not load content. Please check your internet connection.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _fetchMovies,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.68,
                      width: MediaQuery.of(context).size.width * 0.9,
                      child: CardSwiper(
                        controller: controller,
                        cardsCount: _movies.length,
                        onSwipe: _onSwipe,
                        onUndo: _onUndo,
                        isLoop: false,
                        allowedSwipeDirection: const AllowedSwipeDirection.only(left: true, right: true, up: true),
                        numberOfCardsDisplayed: _movies.length < 3
                            ? _movies.length
                            : 3,
                        backCardOffset: const Offset(40, 40),
                        padding: const EdgeInsets.all(24.0),
                        cardBuilder:
                            (
                              context,
                              index,
                              horizontalThresholdPercentage,
                              verticalThresholdPercentage,
                            ) {
                              final movie = _movies[index];
                              return _buildMovieCard(
                                movie,
                                horizontalThresholdPercentage,
                              );
                            },
                      ),
                    ),
                  ),
          ),
          // Control buttons - only show when not loading and has movies
          if (!_isLoading && _movies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(Icons.undo, () => controller.undo()),
                  _buildControlButton(Icons.arrow_upward, _swipeUp),
                ],
              ),
            ),
        ],
      ),
    ));
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: IconButton(
            icon: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildMovieCard(
    Map<String, dynamic> movie, [
    int horizontalThresholdPercentage = 0,
  ]) {
    if (movie['id'] == -1) {
      return _buildLoadingCard();
    }

    Color? overlayColor;
    double opacity = 0.0;

    if (horizontalThresholdPercentage != 0) {
      if (horizontalThresholdPercentage > 0) {
        // Swiping Right - Green (Like)
        overlayColor = Theme.of(context).colorScheme.primary;
      } else {
        // Swiping Left - Red (Dislike)
        overlayColor = Theme.of(context).colorScheme.error;
      }

      // Calculate opacity based on swipe distance
      // Assuming threshold percentage goes up to 100 or more
      // We want visible hue starting early but maxing out around 0.5 opacity
      opacity = (horizontalThresholdPercentage.abs() / 100.0).clamp(0.0, 0.5);
    }

    return GestureDetector(
      onTap: () {
        if (movie['is_movie'] == true) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MoviePage(movieId: movie['id']),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SeriesPage(tvId: movie['id']),
            ),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            movie['image'] ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                                  child: Icon(
                                    Icons.movie,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    size: 50,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        movie['name'] ?? 'No Title',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            movie['year'] ?? '',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              movie['genre'] ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        movie['description'] ?? 'No Description',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (overlayColor != null)
                  Container(
                    decoration: BoxDecoration(
                      color: overlayColor.withValues(alpha: opacity),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading more content...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    debugPrint(
      'The card $previousIndex was swiped to the ${direction.name}. Now the card $currentIndex is on top',
    );

    // Prevent swiping the loading card
    if (_movies[previousIndex]['id'] == -1) {
      return false;
    }

    if (direction == CardSwiperDirection.right) {
      // Handle 'like'
      final movie = _movies[previousIndex];
      _saveLikedMovie(movie);

      // Show action dialog after a short delay to allow swipe animation to complete
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _showActionDialog(movie);
        }
      });
    } else if (direction == CardSwiperDirection.left) {
      // Handle 'dislike'
      final movie = _movies[previousIndex];
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _showDislikeReasonDialog(movie);
        }
      });
    } else if (direction == CardSwiperDirection.top) {
      // Swipe up = skip silently (no action saved)
      if (mounted) Toast.show(context, 'Skipped');
    }

    // Infinite scroll trigger: Fetch more items frequently
    // If we have fewer than 5 cards left ahead (excluding loading card), fetch more.
    final remaining = _movies.length - 1 - currentIndex!;
    if (remaining <= 5) {
      _loadMoreContent(count: 5);
    } else if ((previousIndex + 1) % 3 == 0) {
      _loadMoreContent(count: 3);
    }

    return true;
  }

  void _showDislikeReasonDialog(Map<String, dynamic> movie) {
    String currentView = 'main'; // 'main', 'genre', 'language', 'year'

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget content;
            void navigateTo(String view) {
              setSheetState(() => currentView = view);
            }

            switch (currentView) {
              case 'genre':
                content = _buildGenreView(movie, navigateTo);
                break;
              case 'language':
                content = _buildLanguageView(movie, navigateTo);
                break;
              case 'year':
                content = _buildYearView(movie, navigateTo);
                break;
              default:
                content = _buildMainDislikeView(movie, navigateTo);
            }

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    content,
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDislikeOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainDislikeView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Why did you dislike this?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        _buildDislikeOption(
          icon: Icons.category,
          label: 'Genre',
          onTap: () => onNavigate('genre'),
        ),
        const SizedBox(height: 16),
        _buildDislikeOption(
          icon: Icons.language,
          label: 'Language',
          onTap: () => onNavigate('language'),
        ),
        const SizedBox(height: 16),
        _buildDislikeOption(
          icon: Icons.calendar_today,
          label: 'Year',
          onTap: () => onNavigate('year'),
        ),
        const SizedBox(height: 16),
        _buildDislikeOption(
          icon: Icons.close,
          label: 'None',
          onTap: () {
            SupabaseService.addDislike(
              itemId: movie['id'],
              isMovie: movie['is_movie'] ?? true,
              reason: 'none',
            );
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildGenreView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    final genres = (movie['genre'] as String).split(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => onNavigate('main'),
            ),
            Expanded(
              child: Text(
                'Hide a Genre',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48), // Balance back button
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Select a genre to stop seeing recommendations for it.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ...genres.map(
          (genre) => ListTile(
            leading: Icon(
              Icons.block,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Hide $genre',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              SupabaseService.addDislike(
                itemId: movie['id'],
                isMovie: movie['is_movie'] ?? true,
                reason: 'genre',
                details: {'genre': genre},
              );
              Navigator.pop(context);
              Toast.show(context, 'Hidden $genre from future recommendations');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    final language = movie['original_language'] ?? 'en';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => onNavigate('main'),
            ),
            Expanded(
              child: Text(
                'Hide Language',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Do you want to hide all content in this language ($language)?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () {
                SupabaseService.addDislike(
                  itemId: movie['id'],
                  isMovie: movie['is_movie'] ?? true,
                  reason: 'language',
                  details: {'language_code': language},
                );
                Navigator.pop(context);
                Toast.show(context, 'Hidden content in $language');
              },
              child: const Text('Yes, Hide It'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildYearView(
    Map<String, dynamic> movie,
    Function(String) onNavigate,
  ) {
    final year = int.tryParse(movie['year'] ?? '') ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => onNavigate('main'),
            ),
            Expanded(
              child: Text(
                'Hide by Year',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Filter out content based on release year.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: Icon(
            Icons.calendar_today,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Hide content from $year',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Only hide items released exactly in $year',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () {
            SupabaseService.addDislike(
              itemId: movie['id'],
              isMovie: movie['is_movie'] ?? true,
              reason: 'year_exact',
              details: {'year': year},
            );
            Navigator.pop(context);
            Toast.show(context, 'Hidden content from $year');
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(
            Icons.history,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Hide everything before $year',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Hide all items released in $year or earlier',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () {
            SupabaseService.addDislike(
              itemId: movie['id'],
              isMovie: movie['is_movie'] ?? true,
              reason: 'year_before',
              details: {'year': year},
            );
            Navigator.pop(context);
            Toast.show(context, 'Hidden all content older than $year');
          },
        ),
      ],
    );
  }

  void _showRateDialog(Map<String, dynamic> item, Function(int rating) onRate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Did you like it?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Would you recommend "${item['name']}" to others?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton.icon(
            icon: Icon(
              Icons.thumb_down_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              'No',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              onRate(0);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.thumb_up_rounded),
            label: const Text('Yes'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: () {
              Navigator.pop(context);
              onRate(1);
            },
          ),
        ],
      ),
    );
  }

  void _showActionDialog(Map<String, dynamic> movie) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  movie['name'],
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Add to...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: (movie['is_movie'] ?? true)
                            ? Icons.bookmark_add_outlined
                            : Icons.playlist_play, // Changed icon for Series
                        label: (movie['is_movie'] ?? true) ? 'Watchlist' : 'Watched Till',
                        onTap: () async {
                          Navigator.pop(context);
                          if (movie['is_movie'] ?? true) {
                            await SupabaseService.addToWatchlist(
                              movie,
                              movie['is_movie'] ?? true,
                            );
                            if (!context.mounted) return;
                            Toast.show(
                              context,
                              'Added ${movie['name']} to Watchlist',
                            );
                          } else {
                            // Series: "Watchlist" button now triggers "Watched Till"
                            _showWatchedTillDialog(movie);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.check_circle_outline,
                        label: (movie['is_movie'] ?? true) ? 'Watched' : 'Watched All',
                        onTap: () {
                          Navigator.pop(context);
                          _showRateDialog(movie, (rating) async {
                            // If user liked it, save for recommendations
                            if (rating == 1) {
                              await _saveLikedMovie(movie);
                            }

                            if (movie['is_movie'] ?? true) {
                              // Fetch details to get runtime
                              int? runtime;
                              try {
                                final details = await _tmdbService
                                    .getMovieDetails(movie['id']);
                                runtime = details['runtime'] as int?;
                              } catch (e) {
                                debugPrint('Error fetching runtime: $e');
                              }

                              await SupabaseService.addToWatched(
                                movie,
                                true,
                                runtime: runtime,
                                rating: rating,
                              );
                              await SupabaseService.removeFromWatchlist(
                                movie['id'],
                              );
                              if (!context.mounted) return;
                              Toast.show(
                                context,
                                'Marked ${movie['name']} as Watched',
                              );
                            } else {
                              // Series: "Watched" button now marks ALL as watched
                              _markAllWatched(movie, rating);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _markAllWatched(Map<String, dynamic> show, int rating) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    try {
      final details = await _tmdbService.getTVDetails(show['id']);

      if (!mounted) return;
      Navigator.pop(context); // Pop loading

      await SupabaseService.markSeriesAsWatched(show, details, rating: rating);
      await SupabaseService.removeFromWatchlist(show['id']);

      if (mounted) {
        Toast.show(context, 'Marked ${show['name']} as fully watched');
      }
    } catch (e) {
      debugPrint('Error marking all as watched: $e');
      if (mounted) {
        Navigator.pop(context);
        Toast.show(context, 'Failed to mark as watched', isError: true);
      }
    }
  }

  Future<void> _showWatchedTillDialog(Map<String, dynamic> show) async {
    debugPrint('Fetching details for TV Show ID: ${show['id']}');
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    try {
      // Fetch details to get seasons
      final details = await _tmdbService.getTVDetails(show['id']);
      final seasons = details['seasons'] as List<dynamic>;
      // Sort seasons by season_number
      seasons.sort(
        (a, b) =>
            (a['season_number'] as int).compareTo(b['season_number'] as int),
      );

      if (!mounted) return;

      // Pop the loading dialog
      if (Navigator.canPop(context)) Navigator.pop(context);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Watched till...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: seasons.length + 1, // +1 for "None"
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // "None" option
                          return ListTile(
                            title: Text(
                              'None (Watched All / Clear)',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              // Maybe clear progress or mark all as watched?
                              // For now, let's assume it means "I watched everything"
                              // Or maybe just close the dialog.
                              // Based on user request "1st option none", let's just close it for now
                              // or maybe mark as watched without specific episode?
                              // Let's just close it as a "Cancel" or "No specific episode" option.
                            },
                          );
                        }

                        final season = seasons[index - 1];
                        final seasonNum = season['season_number'];
                        final episodeCount = season['episode_count'];

                        if (seasonNum == 0) {
                          return const SizedBox.shrink(); // Skip specials if desired
                        }

                        return Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            title: Text(
                              season['name'],
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              '$episodeCount Episodes',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            iconColor: Theme.of(context).colorScheme.onSurface,
                            collapsedIconColor: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            children: [
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 5,
                                      childAspectRatio: 1.5,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: episodeCount,
                                itemBuilder: (context, epIndex) {
                                  final epNum = epIndex + 1;
                                  return InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      _markWatchedTill(
                                        show,
                                        details,
                                        seasonNum,
                                        epNum,
                                      );
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Text(
                                        '$epNum',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Error fetching seasons: $e');
      if (mounted) {
        // Pop the loading dialog
        Navigator.pop(context);
        Toast.show(
          context,
          'Failed to load seasons. Please check your connection.',
          isError: true,
        );
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurface,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markWatchedTill(
    Map<String, dynamic> show,
    Map<String, dynamic> showDetails,
    int seasonNum,
    int episodeNum,
  ) async {
    // Use addToWatched to ensure it handles both insert (new) and update (existing)
    await SupabaseService.addToWatched(
      show,
      false, // isMovie = false for TV shows
      watchedSeason: seasonNum,
      watchedEpisode: episodeNum,
    );

    if (mounted) {
      Toast.show(context, 'Marked as watched');
    }
  }

  Future<void> _saveLikedMovie(Map<String, dynamic> movie) async {
    final genre = movie['genre'] as String?;
    if (genre != null && genre.isNotEmpty) {
      try {
        if (movie['is_movie'] == true) {
          await SupabaseService.addLikedMovieGenres(genre);
        } else {
          await SupabaseService.addLikedTVGenres(genre);
        }
        debugPrint(
          'Saved liked ${movie['is_movie'] == true ? "movie" : "TV"} genres: $genre',
        );
      } catch (e) {
        debugPrint('Error saving liked content: $e');
      }
    }
  }

  bool _onUndo(
    int? previousIndex,
    int currentIndex,
    CardSwiperDirection direction,
  ) {
    debugPrint('The card $currentIndex was undod from the ${direction.name}.');
    return true;
  }
}

// Helper widget for the instructions dialog rows
class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InstructionRow(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
