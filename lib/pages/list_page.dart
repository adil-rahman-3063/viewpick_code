import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../services/cache_service.dart';

import '../widget/responsive_layout.dart';
import '../widget/movie_series_toggle.dart';
import 'movies.dart';
import 'series.dart';

class ListPage extends StatefulWidget {
  const ListPage({super.key});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  bool _isMovieMode = true;
  List<Map<String, dynamic>> _watchlist = [];

  // Search/Filter state
  final TextEditingController _searchController = TextEditingController();
  bool _isFilterExpanded = false;
  RangeValues _selectedYearRange = RangeValues(1950, DateTime.now().year.toDouble());
  String _searchQuery = '';
  final Set<int> _selectedProviderIds = {};
  List<dynamic> _watchProviders = [];
  bool _providersLoaded = false;

  final Map<int, Timer> _debounceTimers = {};
  final Map<int, Map<String, dynamic>> _pendingUpdates = {};

  @override
  void initState() {
    super.initState();
    _fetchWatchlist();
    _fetchProviders();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstTime());
  }

  Future<void> _fetchProviders() async {
    try {
      final providers = await _tmdbService.getAvailableWatchProviders(watchRegion: 'IN');
      // Deduplicate and filter major ones
      final targetProviderIds = {
        8, // Netflix
        122, // JioHotstar (formerly Hotstar)
        119, // Amazon Prime Video
        220, // JioCinema
        237, // Sony LIV
        232, // Zee5
        283, // Crunchyroll
        337, // Disney+
        15, // Hulu
        1899, // Max
        2, // Apple TV
        350, // Apple TV Plus
        73, // Tubi
        300, // Pluto TV
        284, // MX Player
        319, // ALTBalaji
        309, // Sun NXT
        218, // Eros Now
      };
      
      final filtered = providers.where((p) => targetProviderIds.contains(p['provider_id'])).map((p) {
        // Branding update to JioHotstar
        if (p['provider_id'] == 122) {
          return {...p, 'provider_name': 'JioHotstar'};
        }
        return p;
      }).toList();
      
      if (mounted) {
        setState(() {
          _watchProviders = filtered;
          _providersLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching providers: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Cancel all timers and force update if any pending
    _debounceTimers.forEach((key, timer) => timer.cancel());
    // Note: We can't await here reliably, but we can try to fire and forget
    // the final updates if they haven't been processed.
    _pendingUpdates.forEach((id, update) {
      SupabaseService.updateWatchedProgress(
        update['item'],
        update['season'],
        update['episode'],
        runtimeAdded: update['runtime_added'],
      );
      // SupabaseService.updateWatchlistTimestamp(id); // Already done
    });
    super.dispose();
  }

  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_list_instructions') ?? false;
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
              'Manage List',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Swipe Right to Left to Mark Watched',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.delete, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Swipe Left to Right to Remove',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  prefs.setBool('seen_list_instructions', true);
                },
                child: const Text(
                  'Got it!',
                  style: TextStyle(
                    color: Colors.blueAccent,
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

  // Calculate next episode locally based on details
  Map<String, int>? _calculateNextEpisode(
    Map<String, dynamic> details,
    int currentSeason,
    int currentEpisode,
  ) {
    final seasons = details['seasons'] as List;
    // Filter out specials
    final validSeasons = seasons.where((s) => s['season_number'] != 0).toList();
    validSeasons.sort(
      (a, b) =>
          (a['season_number'] as int).compareTo(b['season_number'] as int),
    );

    final seasonData = validSeasons.firstWhere(
      (s) => s['season_number'] == currentSeason,
      orElse: () => null,
    );

    if (seasonData != null) {
      final episodeCount = seasonData['episode_count'] as int;
      if (currentEpisode < episodeCount) {
        return {'season': currentSeason, 'episode': currentEpisode + 1};
      } else {
        // Next season
        final nextSeason = currentSeason + 1;
        final nextSeasonData = validSeasons.firstWhere(
          (s) => s['season_number'] == nextSeason,
          orElse: () => null,
        );
        if (nextSeasonData != null) {
          return {'season': nextSeason, 'episode': 1};
        } else {
          return null; // Caught up
        }
      }
    } else {
      // Fallback or restart
      if (validSeasons.isNotEmpty) {
        return {'season': validSeasons.first['season_number'], 'episode': 1};
      }
      return {'season': 1, 'episode': 1};
    }
  }

  // Handle local swipe update
  // Handle local swipe update for Series
  // Returns TRUE if series is finished (should dismiss), FALSE if continuing (keep in list)
  bool _handleSeriesSwipe(Map<String, dynamic> item) {
    if (item['is_movie'] == true) return true;

    final int id = item['id'];
    final int justWatchedSeason = item['next_season'] ?? 1;
    final int justWatchedEpisode = item['next_episode'] ?? 1;

    // Calculate runtime
    final details = item['details'] as Map<String, dynamic>?;
    int avgRuntime = 45;
    if (details != null) {
      final runtimes = details['episode_run_time'] as List<dynamic>?;
      if (runtimes != null && runtimes.isNotEmpty) {
        final sum = runtimes.fold<int>(0, (p, c) => p + (c as int));
        avgRuntime = (sum / runtimes.length).round();
      }
    }

    // Determine what the NEXT episode will be
    final nextEpMap = _calculateNextEpisode(
      details ?? {},
      justWatchedSeason,
      justWatchedEpisode,
    );

    if (nextEpMap != null) {
      // Series continues - Update local state and snap back
      final int prevSeason = item['next_season'] ?? 1;
      final int prevEpisode = item['next_episode'] ?? 1;

      setState(() {
        // Update item details
        item['next_season'] = nextEpMap['season'];
        item['next_episode'] = nextEpMap['episode'];
        item['last_updated'] = DateTime.now().toUtc().toIso8601String();

        // Just update cache without reordering the list immediately
        CacheService.save(
          'list_page_full_watchlist',
          _watchlist,
        ); // Update cache
      });
      // Schedule DB update
      _scheduleUpdate(
        id,
        item,
        justWatchedSeason,
        justWatchedEpisode,
        avgRuntime,
      );

      if (mounted) {
        Toast.show(
          context,
          'Marked S${justWatchedSeason}E${justWatchedEpisode} watched',
          onUndo: () {
            _undoSeriesUpdate(id, item, prevSeason, prevEpisode, avgRuntime);
          },
        );
      }

      return false; // Don't dismiss
    } else {
      // Series Finished
      // Store previous state for undo
      item['_prevSeason'] = item['next_season'] ?? 1;
      item['_prevEpisode'] = item['next_episode'] ?? 1;

      // Schedule update for the last watched episode
      _scheduleUpdate(
        id,
        item,
        justWatchedSeason,
        justWatchedEpisode,
        avgRuntime,
      );
      // Return true to allow Dismissible to dismiss
      // onDismissed will handle removal from list
      return true;
    }
  }

  void _undoSeriesUpdate(
    int id,
    Map<String, dynamic> item,
    int prevSeason,
    int prevEpisode,
    int runtimeToRemove,
  ) {
    _debounceTimers[id]?.cancel();
    _debounceTimers.remove(id);
    _pendingUpdates.remove(id);

    setState(() {
      item['next_season'] = prevSeason;
      item['next_episode'] = prevEpisode;
      // We don't easily know the previous 'last_updated', but keeping it at the top is fine
      CacheService.save('list_page_full_watchlist', _watchlist);
    });

    Toast.show(context, 'Update undone');
  }

  void _scheduleUpdate(
    int id,
    Map<String, dynamic> item,
    int season,
    int episode,
    int runtime,
  ) {
    _debounceTimers[id]?.cancel();

    // Update timestamp immediately to preserve list order
    SupabaseService.updateWatchlistTimestamp(id);

    // Accumulate runtime if multiple swipes
    final existingRuntime = _pendingUpdates[id]?['runtime_added'] ?? 0;

    _pendingUpdates[id] = {
      'season': season,
      'episode': episode,
      'runtime_added': existingRuntime + runtime,
      'item': item,
    };

    _debounceTimers[id] = Timer(const Duration(seconds: 5), () async {
      final update = _pendingUpdates.remove(id);
      _debounceTimers.remove(id);
      if (update != null) {
        await SupabaseService.updateWatchedProgress(
          update['item'],
          update['season'],
          update['episode'],
          runtimeAdded: update['runtime_added'],
        );
      }
    });
  }

  Future<void> _fetchWatchlist() async {
    // 1. Try loading from cache first
    try {
      final cached = await CacheService.load('list_page_full_watchlist');
      if (cached != null && mounted && _isLoading) {
        setState(() {
          _watchlist = List<Map<String, dynamic>>.from(cached);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Cache load error: $e');
    }

    // 2. Fetch fresh data
    // setState(() => _isLoading = true); // Don't reset loading if we have cache
    if (_watchlist.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final data = await SupabaseService.getWatchlist();

      final List<Map<String, dynamic>> formattedList = [];

      // Fetch details for each item in parallel
      final futures = data.map((item) async {
        try {
          final int id = item['item_id'];
          final bool isMovie = item['item_type'] == 'movie';

          Map<String, dynamic> details;
          int? nextSeason;
          int? nextEpisode;
          String? watchedTimeStr;

          if (isMovie) {
            details = await _tmdbService.getMovieDetails(id);
          } else {
            details = await _tmdbService.getTVDetails(id);

            // Calculate next episode and get update time for series
            final watchedItem = await SupabaseService.getWatchedItem(id);
            watchedTimeStr = watchedItem?['last_updated'] ?? watchedItem?['updated_at'];
            final currentSeason = watchedItem?['watched_season'] as int? ?? 1;
            final currentEpisode = watchedItem?['watched_episode'] as int? ?? 0;

            // Logic to determine next episode
            // We need to know how many episodes are in the current season
            final seasons = details['seasons'] as List;

            // Filter out specials (Season 0)
            final validSeasons = seasons
                .where((s) => s['season_number'] != 0)
                .toList();
            // Sort by season number to be safe
            validSeasons.sort(
              (a, b) => (a['season_number'] as int).compareTo(
                b['season_number'] as int,
              ),
            );

            final seasonData = validSeasons.firstWhere(
              (s) => s['season_number'] == currentSeason,
              orElse: () => null,
            );

            if (seasonData != null) {
              final episodeCount = seasonData['episode_count'] as int;

              // If current episode is less than total episodes, increment episode
              // Note: If currentEpisode is 0 (not started), this will set it to 1.
              if (currentEpisode < episodeCount) {
                nextSeason = currentSeason;
                nextEpisode = currentEpisode + 1;
              } else {
                // If current episode is equal to (or greater than) episode count,
                // we have finished this season. Move to next season, episode 1.
                nextSeason = currentSeason + 1;
                nextEpisode = 1;

                // Check if next season exists in the data
                final nextSeasonData = validSeasons.firstWhere(
                  (s) => s['season_number'] == nextSeason,
                  orElse: () => null,
                );

                if (nextSeasonData == null) {
                  // No more seasons, user is caught up
                  nextSeason = null;
                  nextEpisode = null;
                }
              }
            } else {
              // Fallback: If current season not found (maybe 0 or error), start from first valid season
              if (validSeasons.isNotEmpty) {
                nextSeason = validSeasons.first['season_number'];
                nextEpisode = 1;
              } else {
                nextSeason = 1;
                nextEpisode = 1;
              }
            }
          }

          // Extract genres
          final genres =
              (details['genres'] as List?)
                  ?.map((g) => g['name'] as String)
                  .take(2)
                  .join(', ') ??
              '';

          // If it's a series and we have no next episode, don't show it
          if (!isMovie && (nextSeason == null || nextEpisode == null)) {
            return null;
          }

          // Get the sorting timestamp based on item type
          final createdAtStr = item['created_at'] ?? item['last_updated'] ?? item['updated_at'];
          DateTime sortTime;
          if (isMovie) {
            sortTime = DateTime.tryParse(createdAtStr?.toString() ?? '') ?? DateTime(0);
          } else {
            final watchedTime = watchedTimeStr != null ? DateTime.tryParse(watchedTimeStr.toString()) : null;
            sortTime = watchedTime ?? DateTime.tryParse(createdAtStr?.toString() ?? '') ?? DateTime(0);
          }

          return {
            'id': id,
            'last_updated': sortTime.toUtc().toIso8601String(),
            'title': details['title'] ?? details['name'] ?? 'No Title',
            'year': () {
              final dateStr = (details['release_date'] ?? details['first_air_date']) as String?;
              return (dateStr != null && dateStr.length >= 4) ? dateStr.substring(0, 4) : '';
            }(),
            'image': 'https://image.tmdb.org/t/p/w200${details['poster_path']}',
            'description': details['overview'] ?? 'No description',
            'genre': genres.isNotEmpty
                ? genres
                : (isMovie ? 'Movie' : 'TV Series'),
            'is_movie': isMovie,
            'next_season': nextSeason,
            'next_episode': nextEpisode,
            'raw_item': item,
            'details': details,
          };
        } catch (e) {
          final isMovieFallback = item['item_type'] == 'movie';
          final createdAtStrFallback = item['created_at'] ?? item['last_updated'] ?? item['updated_at'];
          DateTime sortTimeFallback = DateTime.tryParse((isMovieFallback ? createdAtStrFallback : (item['last_updated'] ?? item['updated_at'] ?? item['created_at']))?.toString() ?? '') ?? DateTime(0);

          return {
            'id': item['item_id'],
            'last_updated': sortTimeFallback.toUtc().toIso8601String(),
            'title': item['title'] ?? 'No Title',
            'year': () {
              final dateStr = item['release_date'] as String?;
              return (dateStr != null && dateStr.length >= 4) ? dateStr.substring(0, 4) : '';
            }(),
            'image': 'https://image.tmdb.org/t/p/w200${item['poster_path']}',
            'description': item['overview'] ?? 'No description',
            'genre': (item['item_type'] == 'tv' ? 'TV Series' : 'Movie'),
            'is_movie': item['item_type'] == 'movie',
            'raw_item': item,
          };
        }
      });

      final results = await Future.wait(futures);
      // Filter out nulls (caught up series)
      formattedList.addAll(results.whereType<Map<String, dynamic>>());

      // Apply pending updates to keep local swiped values from being overwritten by stale DB data
      for (var item in formattedList) {
        final id = item['id'];
        if (_pendingUpdates.containsKey(id)) {
          final pending = _pendingUpdates[id]!;
          final pendingItem = pending['item'];
          item['next_season'] = pendingItem['next_season'];
          item['next_episode'] = pendingItem['next_episode'];
          item['last_updated'] = pendingItem['last_updated'];
        }
      }

      // Sort by the type-specific sortTime (stored in last_updated) descending
      formattedList.sort((a, b) {
        final aTime =
            DateTime.tryParse(a['last_updated']?.toString() ?? '') ??
            DateTime(0);
        final bTime =
            DateTime.tryParse(b['last_updated']?.toString() ?? '') ??
            DateTime(0);
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _watchlist = formattedList;
          _isLoading = false;
        });
        // Save to cache
        CacheService.save('list_page_full_watchlist', formattedList);
      }
    } catch (e) {
      debugPrint('Error fetching watchlist: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  List<Map<String, dynamic>> get _filteredWatchlist {
    return _watchlist.where((item) {
      // 0. Type Mode (Main Toggle)
      if (item['is_movie'] != _isMovieMode) return false;

      // 1. Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final title = (item['title'] ?? '').toString().toLowerCase();
        final description = (item['description'] ?? '').toString().toLowerCase();
        if (!title.contains(_searchQuery) && !description.contains(_searchQuery)) {
          return false;
        }
      }

      // 2. Year & Provider Filters
      if (_searchQuery.isEmpty) {
        // Year Filter
        final int? year = int.tryParse(item['year'] ?? '');
        if (year != null) {
          if (year < _selectedYearRange.start || year > _selectedYearRange.end) {
            return false;
          }
        }

        // Provider Filter
        if (_selectedProviderIds.isNotEmpty) {
          final details = item['details'] as Map<String, dynamic>?;
          final providerData = details?['watch/providers']?['results']?['IN'];
          if (providerData == null) return false;
          
          bool hasProvider = false;
          // Check flatrate, rent, and buy sections
          final sections = ['flatrate', 'rent', 'buy'];
          for (var section in sections) {
            final providers = providerData[section] as List<dynamic>?;
            if (providers != null) {
              for (var p in providers) {
                if (_selectedProviderIds.contains(p['provider_id'])) {
                  hasProvider = true;
                  break;
                }
              }
            }
            if (hasProvider) break;
          }
          if (!hasProvider) return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildProviderChip(Map<String, dynamic> provider) {
    final id = provider['provider_id'];
    final name = provider['provider_name'];
    final logoPath = provider['logo_path'];
    final isSelected = _selectedProviderIds.contains(id);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedProviderIds.remove(id);
          } else {
            _selectedProviderIds.add(id);
          }
        });
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: logoPath != null
              ? Image.network(
                  'https://image.tmdb.org/t/p/original$logoPath',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.tv, size: 20)),
                )
              : Center(child: Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  void _undoRemoval(
    Map<String, dynamic> item,
    int originalIndex, {
    required bool wasWatched,
    int? runtime,
    int? prevSeason,
    int? prevEpisode,
  }) async {
    final int id = item['id'];

    // 1. Revert DB changes
    if (wasWatched) {
      if (item['is_movie'] == true) {
        // For movies, remove from watched
        await SupabaseService.removeFromWatched(
          id,
          isMovie: true,
          runtime: runtime,
        );
      } else {
        // For series, cancel pending update OR revert progress
        if (_debounceTimers.containsKey(id)) {
          _debounceTimers[id]?.cancel();
          _debounceTimers.remove(id);
          _pendingUpdates.remove(id);
        } else if (prevSeason != null && prevEpisode != null) {
          // If update already fired, revert to previous progress
          await SupabaseService.updateWatchedProgress(
            item,
            prevSeason,
            prevEpisode,
          );
        }
      }
      // Re-add to watchlist (since it was removed)
      await SupabaseService.addToWatchlist(
        item['details'] ?? item['raw_item'],
        item['is_movie'],
      );
    } else {
      // If it was just removed, re-add to watchlist
      await SupabaseService.addToWatchlist(
        item['details'] ?? item['raw_item'],
        item['is_movie'],
      );
    }

    // 2. Revert local state
    if (mounted) {
      setState(() {
        // Prevent duplication if clicked multiple times quickly
        if (_watchlist.any((i) => i['id'] == item['id'])) return;

        if (originalIndex >= 0 && originalIndex <= _watchlist.length) {
          _watchlist.insert(originalIndex, item);
        } else {
          _watchlist.insert(0, item);
        }
        CacheService.save('list_page_full_watchlist', _watchlist);
      });
      Toast.show(context, 'Restored ${item['title']}');
    }
  }

  Widget _buildIdCard(Map<String, dynamic> item) {
    return Dismissible(
      key: Key('watchlist_${item['id']}'),
      direction: DismissDirection.horizontal,
      // Swipe Left to Right (Start to End) -> Remove (Red)
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete,
              color: Theme.of(context).colorScheme.onErrorContainer,
              size: 30,
            ),
            const SizedBox(height: 4),
            Text(
              'Remove',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      // Swipe Right to Left (End to Start) -> Mark Watched (Green)
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check, color: Colors.white, size: 30),
            SizedBox(height: 4),
            Text(
              'Mark Watched',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (direction) {
        final int removedIndex = _watchlist.indexOf(item);
        setState(() {
          _watchlist.removeAt(removedIndex);
          CacheService.save('list_page_full_watchlist', _watchlist);
        });

        if (direction == DismissDirection.startToEnd) {
          // Remove from watchlist
          SupabaseService.removeFromWatchlist(item['id']);
          Toast.show(
            context,
            'Removed ${item['title']}',
            onUndo: () {
              _undoRemoval(item, removedIndex, wasWatched: false);
            },
          );
        } else {
          // Mark as watched (Movie or Finished Series)
          if (item['is_movie'] == true) {
            final details = item['details'] as Map<String, dynamic>?;
            final runtime = details?['runtime'] as int?;

            SupabaseService.addToWatched(
              item['details'] ?? item['raw_item'],
              true,
              runtime: runtime,
            );
            SupabaseService.removeFromWatchlist(item['id']);
            Toast.show(
              context,
              'Marked ${item['title']} as watched',
              onUndo: () {
                _undoRemoval(item, removedIndex, wasWatched: true, runtime: runtime);
              },
            );
          } else {
            // Series finished
            Toast.show(
              context,
              'Series completed!',
              onUndo: () {
                _undoRemoval(
                  item,
                  removedIndex,
                  wasWatched: true,
                  prevSeason: item['_prevSeason'],
                  prevEpisode: item['_prevEpisode'],
                );
              },
            );
          }
        }
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          return true;
        } else {
          // Mark as watched
          if (item['is_movie'] == true) {
            return true;
          } else {
            // Series Logic
            return _handleSeriesSwipe(item);
          }
        }
      },
      child: GestureDetector(
        onTap: () async {
          if (item['is_movie'] == true) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MoviePage(movieId: item['id']),
              ),
            );
          } else {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SeriesPage(tvId: item['id']),
              ),
            );
          }
          _fetchWatchlist();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 140,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                child: Image.network(
                  item['image'],
                  width: 100,
                  height: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 100,
                    height: 140,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.error,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        item['title'],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Year | Genre
                      Text(
                        '${item['year']} | ${item['genre']}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Description
                      Flexible(
                        child: Text(
                          item['description'],
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item['is_movie'] == false &&
                          item['next_season'] != null &&
                          item['next_episode'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Up Next: S${item['next_season']} E${item['next_episode']}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _filteredWatchlist;

    return ResponsiveLayout(
      selectedIndex: 3, // List icon index
      child: Column(
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.only(top: 50.0, bottom: 10.0),
            child: Center(
              child: Text(
                'YOUR LIST',
                style: TextStyle(
                  fontFamily: 'BitcountGridSingle',
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),

          // Search and Filter Header (Borrowed from Explore)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search watchlist...',
                      hintStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isFilterExpanded = !_isFilterExpanded;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isFilterExpanded
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isFilterExpanded
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      color: _isFilterExpanded
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter Panel (Borrowed from Explore)
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: _isFilterExpanded ? 240 : 0,
            curve: Curves.easeInOutCubic,
            child: ClipRect(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Year Range
                      Row(
                        children: [
                          Text(
                            'Year Range: ${_selectedYearRange.start.round()} - ${_selectedYearRange.end.round()}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedYearRange = RangeValues(1950, DateTime.now().year.toDouble());
                                _searchController.clear();
                                _searchQuery = '';
                                _selectedProviderIds.clear();
                                // Refresh to clear any stale state
                                _fetchWatchlist();
                              });
                            },
                            icon: Icon(
                              Icons.clear_all_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            label: Text(
                              'Clear',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.errorContainer.withValues(alpha: 0.2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ],
                      ),
                      RangeSlider(
                        values: _selectedYearRange,
                        min: 1950,
                        max: DateTime.now().year.toDouble(),
                        divisions: (DateTime.now().year - 1950),
                        labels: RangeLabels(
                          _selectedYearRange.start.round().toString(),
                          _selectedYearRange.end.round().toString(),
                        ),
                        onChanged: (RangeValues values) {
                          setState(() {
                            _selectedYearRange = values;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // OTT Providers
                      if (_providersLoaded) ...[
                        Text(
                          'Streaming Services',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _watchProviders
                                .map((p) => Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _buildProviderChip(p),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Main Toggle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: MovieSeriesToggle(
              isMovieMode: _isMovieMode,
              onToggle: (isMovie) {
                setState(() {
                  _isMovieMode = isMovie;
                });
              },
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : filteredList.isEmpty
                ? RefreshIndicator(
                    onRefresh: _fetchWatchlist,
                    color: Theme.of(context).colorScheme.primary,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No results found for "$_searchQuery"'
                                      : 'No items match your filters',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchWatchlist,
                    color: Theme.of(context).colorScheme.primary,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final item = filteredList[index];
                        return _buildIdCard(item);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
