import 'dart:ui';
import 'package:flutter/material.dart';
import '../widget/youtube_web_player.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../widget/toast.dart';
import '../widget/login_prompt.dart';
import 'actors.dart';

class SeriesPage extends StatefulWidget {
  final int tvId;

  const SeriesPage({super.key, required this.tvId});

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  String _currentCountryCode = 'US'; // Default
  Map<String, dynamic>? _tvDetails;
  Map<String, dynamic>? _providers;
  List<dynamic>? _cast;
  List<dynamic>? _crew;
  bool _isInWatchlist = false;
  bool _isWatched = false;
  bool _isLiked = false;

  // New state for watched progress
  int? _watchedSeason;
  int? _watchedEpisode;
  bool _isUpdatingWatched = false;

  String? _trailerId;
  final Map<int, List<dynamic>> _seasonEpisodes = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    // Fetch user location for accurate streaming providers
    try {
      final countryCode = await LocationService.getCurrentCountryCode();
      if (countryCode != null) {
        _currentCountryCode = countryCode;
      }
    } catch (e) {
      debugPrint('Error fetching location: $e');
    }

    try {
      final details = await _tmdbService.getTVDetails(widget.tvId);

      List<dynamic> videos = [];
      try {
        videos = await _tmdbService.getTVVideos(widget.tvId);
      } catch (e) {
        debugPrint('Error fetching videos: $e');
      }

      Map<String, dynamic>? providers;
      try {
        providers = await _tmdbService.getWatchProviders(widget.tvId, false);
      } catch (e) {
        debugPrint('Error fetching providers: $e');
      }

      Map<String, dynamic>? credits;
      try {
        credits = await _tmdbService.getTVCredits(widget.tvId);
      } catch (e) {
        debugPrint('Error fetching credits: $e');
      }

      final inWatchlist = await SupabaseService.isInWatchlist(widget.tvId);

      // Fetch watched status
      final watchedItem = await SupabaseService.getWatchedItem(widget.tvId);
      final isWatched = watchedItem != null;
      final isLiked = watchedItem != null && watchedItem['rating'] == 1;

      int? wSeason;
      int? wEpisode;

      if (watchedItem != null) {
        wSeason = watchedItem['watched_season'];
        wEpisode = watchedItem['watched_episode'];
      }

      String? trailerId;
      final trailer = videos.firstWhere(
        (v) => v['site'] == 'YouTube' && v['type'] == 'Trailer',
        orElse: () => null,
      );

      if (trailer != null) {
        trailerId = trailer['key'];
      } else if (videos.isNotEmpty && videos.first['site'] == 'YouTube') {
        trailerId = videos.first['key'];
      }

      if (trailerId != null) {
        _trailerId = trailerId;
      }

      if (mounted) {
        setState(() {
          _tvDetails = details;
          _providers = providers;
          _cast = credits?['cast'];
          _crew = credits?['crew'];
          _isInWatchlist = inWatchlist;
          _isWatched = isWatched;
          _isLiked = isLiked;
          _watchedSeason = wSeason;
          _watchedEpisode = wEpisode;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching TV data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSeasonDetails(int seasonNumber) async {
    if (_seasonEpisodes.containsKey(seasonNumber)) return;

    try {
      final seasonData = await _tmdbService.getSeasonDetails(
        widget.tvId,
        seasonNumber,
      );
      if (mounted) {
        setState(() {
          _seasonEpisodes[seasonNumber] = seasonData['episodes'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching season $seasonNumber: $e');
    }
  }

  Future<void> _handleMainAction() async {
    if (_tvDetails == null) return;

    if (SupabaseService.currentUser() == null) {
      showLoginPrompt(context, message: 'Please sign in to add titles to your watchlist or mark them as watched.');
      return;
    }

    try {
      if (_isWatched) {
        // Remove from watched
        final runtime = _calculateRuntimeFor(_watchedSeason, _watchedEpisode);
        await SupabaseService.removeFromWatched(
          widget.tvId,
          isMovie: false,
          runtime: runtime,
        );
        setState(() {
          _isWatched = false;
          _isLiked = false;
        });
        if (mounted) Toast.show(context, 'Removed from watched');
      } else if (_isInWatchlist) {
        // If in watchlist, "Mark Watched" logic (Mark entire series)
        await SupabaseService.markSeriesAsWatched(_tvDetails!, _tvDetails!);
        await SupabaseService.removeFromWatchlist(widget.tvId);

        setState(() {
          _isInWatchlist = false;
          _isWatched = true;
        });

        if (mounted) Toast.show(context, 'Marked series as watched');
        if (mounted) _promptLike();
      } else {
        // If not in watchlist, "Add to Watchlist" logic
        await SupabaseService.addToWatchlist(_tvDetails!, false);
        setState(() => _isInWatchlist = true);

        if (mounted) Toast.show(context, 'Added to Watchlist');
      }
    } catch (e) {
      if (mounted) Toast.show(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _promptLike() async {
    if (!mounted) return;

    final liked = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Did you like this series?',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (liked == true) {
      if (!_isLiked) {
        _toggleLike();
      }
    }
  }

  int _calculateRuntimeFor(int? season, int? episode) {
    if (_tvDetails == null || season == null || episode == null) return 0;

    final seasons = _tvDetails!['seasons'] as List<dynamic>;
    final runtimes = _tvDetails!['episode_run_time'] as List<dynamic>?;

    int avgRuntime = 45;
    if (runtimes != null && runtimes.isNotEmpty) {
      final sum = runtimes.fold<int>(0, (p, c) => p + (c as int));
      avgRuntime = (sum / runtimes.length).round();
    }

    int totalEpisodes = 0;
    for (var s in seasons) {
      final sNum = s['season_number'] as int;
      final epCount = s['episode_count'] as int;

      if (sNum < season && sNum > 0) {
        totalEpisodes += epCount;
      } else if (sNum == season) {
        totalEpisodes += episode;
      }
    }

    return totalEpisodes * avgRuntime;
  }

  Future<void> _toggleLike() async {
    if (_tvDetails == null) return;

    if (SupabaseService.currentUser() == null) {
      showLoginPrompt(context, message: 'Please sign in to add titles to your favorites.');
      return;
    }

    final newLikeState = !_isLiked;
    setState(() => _isLiked = newLikeState);

    try {
      if (newLikeState) {
        if (!_isWatched) {
          await SupabaseService.markSeriesAsWatched(_tvDetails!, _tvDetails!);
          setState(() => _isWatched = true);
          if (_isInWatchlist) {
            await SupabaseService.removeFromWatchlist(widget.tvId);
            setState(() => _isInWatchlist = false);
          }
        }

        await SupabaseService.updateRating(widget.tvId, 1);

        final genres = (_tvDetails!['genres'] as List)
            .map((g) => g['name'])
            .join(',');

        await SupabaseService.addLikedTVGenres(genres);

        if (mounted) Toast.show(context, 'Added to your interests');
      } else {
        await SupabaseService.updateRating(widget.tvId, 0);
        if (mounted) Toast.show(context, 'Removed from interests');
      }
    } catch (e) {
      setState(() => _isLiked = !newLikeState);
      if (mounted) Toast.show(context, 'Error updating like: $e', isError: true);
    }
  }

  Future<void> _handleEpisodeTap(int season, int episode) async {
    if (SupabaseService.currentUser() == null) {
      showLoginPrompt(context, message: 'Please sign in to track your watched progress.');
      return;
    }

    if (season == _watchedSeason && episode == _watchedEpisode) {
      // Unmarking the current progress
      if (episode > 1) {
        await _updateProgress(season, episode - 1);
      } else {
        // First episode of the season
        // Find previous season
        final seasons = _tvDetails!['seasons'] as List;
        int maxPrevSeason = 0;
        int maxPrevEpisode = 0;

        for (var s in seasons) {
          final sNum = s['season_number'] as int;
          if (sNum < season && sNum > maxPrevSeason && sNum != 0) {
            maxPrevSeason = sNum;
            maxPrevEpisode = s['episode_count'] as int;
          }
        }

        if (maxPrevSeason > 0) {
          // Move to end of previous season
          await _updateProgress(maxPrevSeason, maxPrevEpisode);
        } else {
          // No previous season (e.g. S1E1), so remove from watched entirely
          // This explicitly removes the row from the DB
          await _removeSeriesFromWatched();
        }
      }
    } else {
      // Setting progress forward or backward directly
      await _updateProgress(season, episode);
    }
  }

  Future<void> _removeSeriesFromWatched() async {
    if (!_isWatched) return;

    final runtime = _calculateRuntimeFor(_watchedSeason, _watchedEpisode);

    // Optimistic
    setState(() {
      _isWatched = false;
      _isLiked = false;
      _watchedSeason = null;
      _watchedEpisode = null;
    });

    try {
      await SupabaseService.removeFromWatched(
        widget.tvId,
        isMovie: false,
        runtime: runtime,
      );
      if (mounted) Toast.show(context, 'Removed from watched');
    } catch (e) {
      // Revert is tough here without storing previous state deeply,
      // but usually errors are network, so strict revert might not be consistent.
      // We'll leave UI as is or could reload.
      debugPrint('Error removing from watched: $e');
    }
  }

  Future<void> _updateProgress(int seasonNumber, int episodeNumber) async {
    if (_isUpdatingWatched) return;
    setState(() => _isUpdatingWatched = true);

    final oldSeason = _watchedSeason;
    final oldEpisode = _watchedEpisode;

    // Calculate runtime difference
    final oldRuntime = _calculateRuntimeFor(oldSeason, oldEpisode);
    final newRuntime = _calculateRuntimeFor(seasonNumber, episodeNumber);
    final diff = newRuntime - oldRuntime;

    // Optimistic update
    setState(() {
      _watchedSeason = seasonNumber;
      _watchedEpisode = episodeNumber;
    });

    try {
      // Ensure it's in the watched table first (if not already)
      final isWatched = await SupabaseService.isWatched(widget.tvId);
      if (!isWatched && _tvDetails != null) {
        await SupabaseService.addToWatched(
          _tvDetails!,
          false,
          watchedSeason: seasonNumber,
          watchedEpisode: episodeNumber,
          runtime: diff > 0 ? diff : null,
        );
        setState(() => _isWatched = true);
      } else {
        await SupabaseService.updateWatchedProgress(
          _tvDetails!,
          seasonNumber,
          episodeNumber,
          runtimeAdded: diff > 0 ? diff : null,
        );
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _watchedSeason = oldSeason;
        _watchedEpisode = oldEpisode;
      });
      if (mounted) Toast.show(context, 'Error updating progress: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdatingWatched = false);
    }
  }

  bool _isEpisodeWatched(int season, int episode) {
    if (_watchedSeason == null || _watchedEpisode == null) return false;
    if (season < _watchedSeason!) return true;
    if (season == _watchedSeason! && episode <= _watchedEpisode!) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        extendBodyBehindAppBar: _trailerId == null,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: theme.colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero/Youtube Loading Placeholder
              Container(
                height: 400,
                width: double.infinity,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 
                  0.2,
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Loading
                    Container(
                      height: 32,
                      width: 250,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Meta Loading (Rating, Seasons, Genres)
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 20,
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 80,
                          height: 20,
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            height: 20,
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Buttons Loading
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Content Sections Loading
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(
                        3,
                        (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 24,
                                width: 100,
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 12),
                              if (index == 2) // Horizontal list for Cast
                                SizedBox(
                                  height: 120,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: 4,
                                    itemBuilder: (_, __) => Container(
                                      width: 80,
                                      margin: const EdgeInsets.only(right: 12),
                                      child: Column(
                                        children: [
                                          CircleAvatar(
                                            radius: 35,
                                            backgroundColor: theme
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.3),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            height: 10,
                                            width: 60,
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else // Text block
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 14,
                                      width: double.infinity,
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      height: 14,
                                      width: double.infinity,
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      height: 14,
                                      width: 200,
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_tvDetails == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Failed to load series',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final posterPath = _tvDetails!['poster_path'];
    final backdropPath = _tvDetails!['backdrop_path'];
    final title = _tvDetails!['name'];
    final overview = _tvDetails!['overview'];
    final firstAirDate = _tvDetails!['first_air_date'] ?? '';
    final year = firstAirDate.length >= 4 ? firstAirDate.substring(0, 4) : '';
    final rating =
        (_tvDetails!['vote_average'] as num?)?.toStringAsFixed(1) ?? 'N/A';
    final genres = (_tvDetails!['genres'] as List)
        .map((g) => g['name'])
        .join(', ');
    final numberOfSeasons = _tvDetails!['number_of_seasons'];
    final seasons = _tvDetails!['seasons'] as List;

    final usProviders =
        _providers?[_currentCountryCode] ??
        _providers?['US'] ??
        _providers?.values.firstOrNull;
    final flatrate = usProviders?['flatrate'] as List?;
    final rent = usProviders?['rent'] as List?;
    final buy = usProviders?['buy'] as List?;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: _trailerId == null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_trailerId != null)
              Container(
                color: Colors.black,
                child: YoutubeWebPlayer(
                  videoId: _trailerId!,
                  height: 250,
                ),
              )
            else
              Container(
                height: 400,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      'https://image.tmdb.org/t/p/w500${backdropPath ?? posterPath}',
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        backgroundColor.withValues(alpha: 0.8),
                        backgroundColor,
                      ],
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title ($year)',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'BitcountGridSingle',
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        rating,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$numberOfSeasons Seasons',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          genres,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _buildFrostedButton(
                          icon: _isWatched
                              ? Icons.check_circle
                              : (_isInWatchlist
                                    ? Icons.check_circle_outline
                                    : Icons.add),
                          label: _isWatched
                              ? 'Remove Watched'
                              : (_isInWatchlist ? 'Mark Watched' : 'Watchlist'),
                          onTap: _handleMainAction,
                          isActive: _isInWatchlist || _isWatched,
                          activeColor: _isWatched ? Colors.green : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFrostedButton(
                          icon: _isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          label: 'Like',
                          onTap: _toggleLike,
                          isActive: _isLiked,
                          activeColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Overview',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overview ?? 'No description available.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (flatrate != null && flatrate.isNotEmpty) ...[
                    Text(
                      'Stream On',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: flatrate.map((provider) {
                        return Tooltip(
                          message: provider['provider_name'],
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              'https://image.tmdb.org/t/p/original${provider['logo_path']}',
                              width: 50,
                              height: 50,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (rent != null && rent.isNotEmpty) ...[
                    Text(
                      'Rent',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: rent.map((provider) {
                        return Tooltip(
                          message: provider['provider_name'],
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              'https://image.tmdb.org/t/p/original${provider['logo_path']}',
                              width: 50,
                              height: 50,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (buy != null && buy.isNotEmpty) ...[
                    Text(
                      'Buy',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: buy.map((provider) {
                        return Tooltip(
                          message: provider['provider_name'],
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              'https://image.tmdb.org/t/p/original${provider['logo_path']}',
                              width: 50,
                              height: 50,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (_cast != null && _cast!.isNotEmpty) ...[
                    Text(
                      'Cast',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _cast!.length,
                        itemBuilder: (context, index) {
                          final actor = _cast![index];
                          final profilePath = actor['profile_path'];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ActorsPage(personId: actor['id']),
                                ),
                              );
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(50),
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: profilePath != null
                                          ? Image.network(
                                              'https://image.tmdb.org/t/p/w200$profilePath',
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                    Icons.person,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            )
                                          : Icon(
                                              Icons.person,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    actor['name'],
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    actor['character'] ?? '',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (_crew != null && _crew!.isNotEmpty) ...[
                    Text(
                      'Crew',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _crew!.length,
                        itemBuilder: (context, index) {
                          final member = _crew![index];
                          final profilePath = member['profile_path'];
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: profilePath != null
                                        ? Image.network(
                                            'https://image.tmdb.org/t/p/w200$profilePath',
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.person,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          )
                                        : Icon(
                                            Icons.person,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  member['name'],
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  member['job'] ?? '',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  Text(
                    'Seasons',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...seasons
                      .where((season) {
                        final seasonNum = season['season_number'];
                        final name = season['name'].toString();
                        return seasonNum != 0 && !name.contains('Special');
                      })
                      .map((season) {
                        final seasonNum = season['season_number'];
                        final episodeCount = season['episode_count'];
                        final episodes = _seasonEpisodes[seasonNum];

                        return Card(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                          child: ExpansionTile(
                            title: Text(
                              season['name'],
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '$episodeCount Episodes',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            iconColor: theme.colorScheme.onSurface,
                            collapsedIconColor:
                                theme.colorScheme.onSurfaceVariant,
                            onExpansionChanged: (expanded) {
                              if (expanded) {
                                _fetchSeasonDetails(seasonNum);
                              }
                            },
                            children: [
                              if (episodes == null)
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                )
                              else
                                ...episodes.map<Widget>((episode) {
                                  final epNum = episode['episode_number'];
                                  final isWatched = _isEpisodeWatched(
                                    seasonNum,
                                    epNum,
                                  );

                                  return Dismissible(
                                    key: Key('S${seasonNum}E$epNum'),
                                    background: Container(
                                      color: theme.colorScheme.primaryContainer,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 20),
                                      child: Icon(
                                        Icons.check,
                                        color: theme
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    secondaryBackground: Container(
                                      color: theme.colorScheme.errorContainer,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      child: Icon(
                                        Icons.close,
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                    confirmDismiss: (direction) async {
                                      if (direction ==
                                          DismissDirection.startToEnd) {
                                        // Mark as watched (and previous) or unmark if already watched
                                        await _handleEpisodeTap(
                                          seasonNum,
                                          epNum,
                                        );
                                        return false; // Don't dismiss the tile
                                      } else {
                                        // Swipe left - maybe unmark?
                                        // For now, let's just treat it as unmark current?
                                        // Or maybe just do nothing for now as per plan
                                        return false;
                                      }
                                    },
                                    child: ListTile(
                                      title: Text(
                                        '${episode['episode_number']}. ${episode['name']}',
                                        style: TextStyle(
                                          color: isWatched
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurface,
                                          fontWeight: isWatched
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (episode['overview'] != null &&
                                              episode['overview'].isNotEmpty)
                                            Text(
                                              episode['overview'],
                                              style: TextStyle(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.7),
                                                fontSize: 12,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          isWatched
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          color: isWatched
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                        onPressed: () =>
                                            _handleEpisodeTap(seasonNum, epNum),
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        );
                      })
                      ,
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrostedButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    final effectiveActiveColor =
        activeColor ?? Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isActive
                          ? effectiveActiveColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
