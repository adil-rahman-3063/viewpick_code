import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../widget/toast.dart';
import 'actors.dart';

class MoviePage extends StatefulWidget {
  final int movieId;

  const MoviePage({super.key, required this.movieId});

  @override
  State<MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends State<MoviePage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  String _currentCountryCode = 'US';
  Map<String, dynamic>? _movieDetails;
  Map<String, dynamic>? _providers;
  List<dynamic>? _cast;
  List<dynamic>? _crew;
  List<dynamic>? _collectionMovies;
  bool _isInWatchlist = false;
  bool _isWatched = false;
  bool _isLiked = false;
  YoutubePlayerController? _youtubeController;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
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
      final details = await _tmdbService.getMovieDetails(widget.movieId);

      List<dynamic> videos = [];
      try {
        videos = await _tmdbService.getMovieVideos(widget.movieId);
      } catch (e) {
        debugPrint('Error fetching videos: $e');
      }

      Map<String, dynamic>? providers;
      try {
        providers = await _tmdbService.getWatchProviders(widget.movieId, true);
      } catch (e) {
        debugPrint('Error fetching providers: $e');
      }

      Map<String, dynamic>? credits;
      try {
        credits = await _tmdbService.getMovieCredits(widget.movieId);
      } catch (e) {
        debugPrint('Error fetching credits: $e');
      }

      List<dynamic>? collectionMovies;
      if (details['belongs_to_collection'] != null) {
        try {
          final collectionId = details['belongs_to_collection']['id'];
          final collection = await _tmdbService.getCollectionDetails(
            collectionId,
          );
          collectionMovies = collection['parts'];
          // Sort by release date
          collectionMovies?.sort((a, b) {
            final dateA = a['release_date'] ?? '';
            final dateB = b['release_date'] ?? '';
            return dateA.compareTo(dateB);
          });
        } catch (e) {
          debugPrint('Error fetching collection: $e');
        }
      }

      final inWatchlist = await SupabaseService.isInWatchlist(widget.movieId);
      final watchedItem = await SupabaseService.getWatchedItem(widget.movieId);
      final isWatched = watchedItem != null;
      final isLiked = watchedItem != null && watchedItem['rating'] == 1;

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
        _youtubeController = YoutubePlayerController(
          initialVideoId: trailerId,
          flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
        );
      }

      if (mounted) {
        setState(() {
          _movieDetails = details;
          _providers = providers;
          _cast = credits?['cast'];
          _crew = credits?['crew'];
          _collectionMovies = collectionMovies;
          _isInWatchlist = inWatchlist;
          _isWatched = isWatched;
          _isLiked = isLiked;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching movie data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleMainAction() async {
    if (_movieDetails == null) return;

    try {
      final runtime = _movieDetails!['runtime'] as int?;

      if (_isWatched) {
        // Remove from watched
        await SupabaseService.removeFromWatched(
          widget.movieId,
          isMovie: true,
          runtime: runtime,
        );
        setState(() {
          _isWatched = false;
          _isLiked = false; // Also reset like status
        });
        if (mounted) Toast.show(context, 'Removed from watched');
      } else if (_isInWatchlist) {
        // Mark as watched
        await SupabaseService.addToWatched(
          _movieDetails!,
          true,
          runtime: runtime,
        );
        await SupabaseService.removeFromWatchlist(widget.movieId);

        setState(() {
          _isInWatchlist = false;
          _isWatched = true;
        });

        if (mounted) Toast.show(context, 'Marked as watched');
        if (mounted) _promptLike();
      } else {
        // Add to watchlist
        await SupabaseService.addToWatchlist(_movieDetails!, true);
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
          'Did you like this movie?',
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

  Future<void> _toggleLike() async {
    if (_movieDetails == null) return;

    final newLikeState = !_isLiked;
    setState(() => _isLiked = newLikeState);

    try {
      if (newLikeState) {
        // Like logic
        if (!_isWatched) {
          // If liking, it implies watched
          final runtime = _movieDetails!['runtime'] as int?;
          await SupabaseService.addToWatched(
            _movieDetails!,
            true,
            rating: 1,
            runtime: runtime,
          );
          if (_isInWatchlist) {
            await SupabaseService.removeFromWatchlist(widget.movieId);
            setState(() => _isInWatchlist = false);
          }
          setState(() => _isWatched = true);
        } else {
          await SupabaseService.updateRating(widget.movieId, 1);
        }

        final genres = (_movieDetails!['genres'] as List)
            .map((g) => g['name'])
            .join(',');

        await SupabaseService.addLikedMovieGenres(genres);

        if (mounted) Toast.show(context, 'Added to your interests');
      } else {
        // Unlike logic
        await SupabaseService.updateRating(widget.movieId, 0);
        if (mounted) Toast.show(context, 'Removed from interests');
      }
    } catch (e) {
      // Revert on error
      setState(() => _isLiked = !newLikeState);
      if (mounted) Toast.show(context, 'Error updating like: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        extendBodyBehindAppBar: _youtubeController == null,
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
                    // Meta Loading
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
                        const SizedBox(width: 16),
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
                              if (index == 2) // Horizontal list for Cast/Crew
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

    if (_movieDetails == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Failed to load movie',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final posterPath = _movieDetails!['poster_path'];
    final backdropPath = _movieDetails!['backdrop_path'];
    final title = _movieDetails!['title'];
    final overview = _movieDetails!['overview'];
    final releaseDate = _movieDetails!['release_date'] ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
    final rating =
        (_movieDetails!['vote_average'] as num?)?.toStringAsFixed(1) ?? 'N/A';
    final genres = (_movieDetails!['genres'] as List)
        .map((g) => g['name'])
        .join(', ');
    final runtime = _movieDetails!['runtime'] != null
        ? '${_movieDetails!['runtime']} min'
        : '';

    final usProviders =
        _providers?[_currentCountryCode] ??
        _providers?['US'] ??
        _providers?.values.firstOrNull;
    final flatrate = usProviders?['flatrate'] as List?;
    final rent = usProviders?['rent'] as List?;
    final buy = usProviders?['buy'] as List?;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: _youtubeController == null,
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
            if (_youtubeController != null)
              Container(
                height: 250,
                width: double.infinity,
                color: Colors.black,
                child: YoutubePlayer(
                  controller: _youtubeController!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: Colors.red,
                  progressColors: const ProgressBarColors(
                    playedColor: Colors.red,
                    handleColor: Colors.redAccent,
                  ),
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
                        runtime,
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
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildFrostedButton(
                          icon: _isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          label: 'Like',
                          onTap: _toggleLike,
                          isActive: _isLiked,
                          activeColor: Colors.pink,
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

                  if (_collectionMovies != null &&
                      _collectionMovies!.isNotEmpty) ...[
                    Text(
                      'Collection',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200, // Adjusted height for posters
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _collectionMovies!.length,
                        itemBuilder: (context, index) {
                          final movie = _collectionMovies![index];
                          // Skip current movie if desired, or keep to show position in collection
                          // if (movie['id'] == widget.movieId) return SizedBox.shrink();

                          final posterPath = movie['poster_path'];
                          final releaseDate = movie['release_date'] ?? '';
                          final year = releaseDate.length >= 4
                              ? releaseDate.substring(0, 4)
                              : '';

                          return GestureDetector(
                            onTap: () {
                              // Prevent navigating to current page again if clicking same movie
                              if (movie['id'] == widget.movieId) return;

                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      MoviePage(movieId: movie['id']),
                                ),
                              );
                            },
                            child: Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                border: movie['id'] == widget.movieId
                                    ? Border.all(
                                        color: theme.colorScheme.primary,
                                        width: 2,
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: posterPath != null
                                          ? Image.network(
                                              'https://image.tmdb.org/t/p/w200$posterPath',
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                    color: theme
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.movie,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: theme
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              child: Center(
                                                child: Icon(
                                                  Icons.movie,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    movie['title'] ?? 'No Title',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    year,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
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
