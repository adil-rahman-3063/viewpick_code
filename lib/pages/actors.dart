import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../widget/frosted_card.dart';
import '../widget/movie_series_toggle.dart';
import 'movies.dart';
import 'series.dart';

class ActorsPage extends StatefulWidget {
  final int personId;

  const ActorsPage({super.key, required this.personId});

  @override
  State<ActorsPage> createState() => _ActorsPageState();
}

class _ActorsPageState extends State<ActorsPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  Map<String, dynamic>? _personDetails;
  List<Map<String, dynamic>> _movies = [];
  List<Map<String, dynamic>> _series = [];
  bool _isMovieMode = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final details = await _tmdbService.getPersonDetails(widget.personId);
      final credits = await _tmdbService.getPersonCombinedCredits(
        widget.personId,
      );

      final cast = credits['cast'] as List<dynamic>? ?? [];

      // Filter and format movies
      final movies = cast
          .where((item) => item['media_type'] == 'movie')
          .map((item) => _formatItem(item))
          .toList();

      // Filter and format series
      final series = cast
          .where((item) => item['media_type'] == 'tv')
          .map((item) => _formatItem(item))
          .toList();

      // Sort by popularity or release date if needed, for now let's keep API order or sort by date desc
      movies.sort(
        (a, b) => (b['year'] as String).compareTo(a['year'] as String),
      );
      series.sort(
        (a, b) => (b['year'] as String).compareTo(a['year'] as String),
      );

      if (mounted) {
        setState(() {
          _personDetails = details;
          _movies = movies;
          _series = series;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching actor data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _formatItem(dynamic item) {
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

    return {
      'id': item['id'],
      'title': name,
      'year': year,
      'image': 'https://image.tmdb.org/t/p/w500${item['poster_path']}',
      'type': item['media_type'],
      'character': item['character'] ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    if (_personDetails == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Text(
            'Failed to load actor details',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
        ),
      );
    }

    final name = _personDetails!['name'];
    final biography = _personDetails!['biography'];
    final profilePath = _personDetails!['profile_path'];
    final knownFor = _personDetails!['known_for_department'];
    final placeOfBirth = _personDetails!['place_of_birth'];
    final birthday = _personDetails!['birthday'];

    final currentList = _isMovieMode ? _movies : _series;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
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
            // Actor Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 100, 16, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: profilePath != null
                        ? Image.network(
                            'https://image.tmdb.org/t/p/w500$profilePath',
                            width: 120,
                            height: 180,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 120,
                            height: 180,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              size: 60,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'BitcountGridSingle',
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (knownFor != null)
                          Text(
                            knownFor,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (birthday != null)
                          Text(
                            'Born: $birthday',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        if (placeOfBirth != null)
                          Text(
                            placeOfBirth,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Biography
            if (biography != null && biography.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Biography',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      biography,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.5,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

            // Toggle
            Center(
              child: MovieSeriesToggle(
                isMovieMode: _isMovieMode,
                onToggle: (isMovie) {
                  setState(() {
                    _isMovieMode = isMovie;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: currentList.length,
                itemBuilder: (context, index) {
                  final item = currentList[index];
                  return GestureDetector(
                    onTap: () {
                      if (_isMovieMode) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                MoviePage(movieId: item['id']),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SeriesPage(tvId: item['id']),
                          ),
                        );
                      }
                    },
                    child: Column(
                      children: [
                        Expanded(
                          child: FrostedCard(
                            imageUrl: item['image'] ?? '',
                            title: item['title'] ?? 'No Title',
                            year: item['year'] ?? '',
                          ),
                        ),
                        if (item['character'] != null &&
                            item['character'].isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'as ${item['character']}',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
