import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../services/tmdb_service.dart';
import '../widget/responsive_layout.dart';
import '../widget/toast.dart';
import 'settings.dart';
import 'movies_watched.dart';
import 'series_watched.dart';
import '../main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TMDBService _tmdbService = TMDBService();

  String _name = 'User';
  String _email = '';
  String? _avatarUrl;

  int? _watchlistMovies;
  int? _watchlistSeries;
  int? _watchedMovies;
  int? _watchedSeries;

  Duration? _totalMovieTime;
  Duration? _totalSeriesTime;

  // bool _isLoading = true; // Removed

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    // Reset to loading state
    setState(() {
      _watchlistMovies = null;
      _watchlistSeries = null;
      _watchedMovies = null;
      _watchedSeries = null;
      _totalMovieTime = null;
      _totalSeriesTime = null;
    });

    try {
      final user = SupabaseService.currentUser();
      if (user != null) {
        _email = user.email ?? '';
        _name = user.userMetadata?['name'] ?? 'User';
        _avatarUrl = user.userMetadata?['avatar_url'];
      }

      // Fetch lists in parallel for speed
      final results = await Future.wait([
        SupabaseService.getWatchlist(),
        SupabaseService.getWatched(),
      ]);

      final watchlist = results[0];
      final watched = results[1];

      final watchlistMoviesCount = watchlist
          .where((i) => i['item_type'] == 'movie')
          .length;
      final watchlistSeriesCount = watchlist
          .where((i) => i['item_type'] == 'tv')
          .length;

      final watchedMoviesList = watched
          .where((i) => i['item_type'] == 'movie')
          .toList();
      final watchedSeriesList = watched
          .where((i) => i['item_type'] == 'tv')
          .toList();

      final watchedMoviesCount = watchedMoviesList.length;
      final watchedSeriesCount = watchedSeriesList.length;

      if (mounted) {
        setState(() {
          _watchlistMovies = watchlistMoviesCount;
          _watchlistSeries = watchlistSeriesCount;
          _watchedMovies = watchedMoviesCount;
          _watchedSeries = watchedSeriesCount;
        });
      }

      // Check for cached stats
      final movieMins = user?.userMetadata?['total_movie_minutes'];
      final seriesMins = user?.userMetadata?['total_series_minutes'];

      if (movieMins != null && seriesMins != null) {
        if (mounted) {
          setState(() {
            _totalMovieTime = Duration(minutes: movieMins as int);
            _totalSeriesTime = Duration(minutes: seriesMins as int);
          });
        }
      } else {
        // Calculate stats in background and save them
        await _calculateAndSaveStats(watchedMoviesList, watchedSeriesList);
      }
    } catch (e) {
      debugPrint('Error fetching profile data: $e');
      if (mounted) {
        Toast.show(context, 'Error loading profile', isError: true);
        // Ensure not stuck in loading if error
        setState(() {
          _watchlistMovies ??= 0;
          _watchlistSeries ??= 0;
          _watchedMovies ??= 0;
          _watchedSeries ??= 0;
          _totalMovieTime ??= Duration.zero;
          _totalSeriesTime ??= Duration.zero;
        });
      }
    }
  }

  Future<void> _calculateAndSaveStats(
    List<Map<String, dynamic>> movies,
    List<Map<String, dynamic>> series,
  ) async {
    int totalMovieMinutes = 0;
    int totalSeriesMinutes = 0;

    // Calculate Movie Time
    for (var movie in movies) {
      try {
        final details = await _tmdbService.getMovieDetails(movie['item_id']);
        final runtime = details['runtime'] as int?;
        if (runtime != null) {
          totalMovieMinutes += runtime;
        }
      } catch (e) {
        debugPrint('Error fetching movie details for stats: $e');
      }
    }

    // Calculate Series Time
    for (var show in series) {
      try {
        final details = await _tmdbService.getTVDetails(show['item_id']);
        final seasons = details['seasons'] as List<dynamic>;
        final runtimes = details['episode_run_time'] as List<dynamic>?;

        // Calculate average runtime
        int avgRuntime = 45; // Default fallback
        if (runtimes != null && runtimes.isNotEmpty) {
          final sum = runtimes.fold<int>(0, (p, c) => p + (c as int));
          avgRuntime = (sum / runtimes.length).round();
        }

        final watchedSeason = show['watched_season'] as int? ?? 0;
        final watchedEpisode = show['watched_episode'] as int? ?? 0;

        int episodesWatched = 0;

        for (var season in seasons) {
          final sNum = season['season_number'] as int;
          final epCount = season['episode_count'] as int;

          if (sNum < watchedSeason && sNum > 0) {
            episodesWatched += epCount;
          } else if (sNum == watchedSeason) {
            episodesWatched += watchedEpisode;
          }
        }

        totalSeriesMinutes += episodesWatched * avgRuntime;
      } catch (e) {
        debugPrint('Error fetching series details for stats: $e');
      }
    }

    if (mounted) {
      setState(() {
        _totalMovieTime = Duration(minutes: totalMovieMinutes);
        _totalSeriesTime = Duration(minutes: totalSeriesMinutes);
      });
    }

    // Save to Supabase metadata for future fast loading
    try {
      await SupabaseService.updateUserMetadata({
        'total_movie_minutes': totalMovieMinutes,
        'total_series_minutes': totalSeriesMinutes,
      });
    } catch (e) {
      debugPrint('Error saving stats to metadata: $e');
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return ''; // Should not happen if we handle null in build
    }
    if (duration == Duration.zero) return '0m';

    final years = duration.inDays ~/ 365;
    final remainingDaysAfterYears = duration.inDays % 365;
    final months = remainingDaysAfterYears ~/ 30;
    final days = remainingDaysAfterYears % 30;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    List<String> parts = [];
    if (years > 0) parts.add('${years}y');
    if (months > 0) parts.add('${months}m');
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}min');

    if (parts.isEmpty) return '0min';
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedIndex: 4,
      child: SafeArea(
        bottom: false, // Allow content to go behind navbar
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 120.0),
          child: Column(
            children: [
              // Header Section
              Stack(
                alignment: Alignment.center,
                children: [
                  // Settings & Theme Icons (Top Right)
                  Align(
                    alignment: Alignment.topRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: themeNotifier,
                          builder: (context, currentMode, child) {
                            final isDark = currentMode == ThemeMode.dark;
                            return IconButton(
                              icon: Icon(
                                isDark ? Icons.dark_mode : Icons.light_mode,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              onPressed: () {
                                themeNotifier.value = isDark
                                    ? ThemeMode.light
                                    : ThemeMode.dark;
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.settings,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingsPage(),
                              ),
                            ).then(
                              (_) => _fetchProfileData(),
                            ); // Refresh data on return
                          },
                        ),
                      ],
                    ),
                  ),

                  // Profile Info
                  Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.shadow.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          backgroundImage: _avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: _avatarUrl == null
                              ? Text(
                                  _name.isNotEmpty
                                      ? _name[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'BitcountGridSingle',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _email,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Stats Grid
              Column(
                children: [
                  // Row 1: Movies
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Movies Watchlist',
                          value: _watchlistMovies?.toString(),
                          icon: Icons.bookmark_border,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MoviesWatchedPage(),
                              ),
                            ).then((_) => _fetchProfileData());
                          },
                          child: _buildStatCard(
                            title: 'Movies Watched',
                            value: _watchedMovies?.toString(),
                            icon: Icons.movie_outlined,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 2: Series
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Series Watchlist',
                          value: _watchlistSeries?.toString(),
                          icon: Icons.playlist_play,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SeriesWatchedPage(),
                              ),
                            ).then((_) => _fetchProfileData());
                          },
                          child: _buildStatCard(
                            title: 'Series Watched',
                            value: _watchedSeries?.toString(),
                            icon: Icons.tv,
                            color: Colors.purpleAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 3: Watch Time
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Movie Time',
                          value: _totalMovieTime != null
                              ? _formatDuration(_totalMovieTime)
                              : null,
                          icon: Icons.timer,
                          color: Colors.cyanAccent,
                          isSmallText: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Series Time',
                          value: _totalSeriesTime != null
                              ? _formatDuration(_totalSeriesTime)
                              : null,
                          icon: Icons.history,
                          color: Colors.pinkAccent,
                          isSmallText: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Donation Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showDonationDialog(context),
                  icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
                  label: const Text('Make Donation to Developer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sign Out Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await SupabaseService.signOut();
                    if (mounted) {
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onErrorContainer,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDonationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Support the Developer',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'If you like this app, consider buying me a coffee! ❤️',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/donation.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 200,
                    height: 200,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.qr_code, size: 60)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'adilrahman3063-1@okicici',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: 'adilrahman3063-1@okicici'));
                        Toast.show(context, 'UPI ID copied to clipboard!');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String? value,
    required IconData icon,
    required Color color,
    bool isSmallText = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 160, // Square-ish shape, increased from 140 to prevent overflow
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 12),
              if (value == null)
                SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              else
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: isSmallText ? 16 : 28,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
