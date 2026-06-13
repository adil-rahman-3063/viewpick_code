import 'package:flutter/material.dart';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';

import 'series.dart';

class SeriesWatchedPage extends StatefulWidget {
  const SeriesWatchedPage({super.key});

  @override
  State<SeriesWatchedPage> createState() => _SeriesWatchedPageState();
}

class _SeriesWatchedPageState extends State<SeriesWatchedPage> {
  final TMDBService _tmdbService = TMDBService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _watchedSeries = [];

  @override
  void initState() {
    super.initState();
    _fetchWatchedSeries();
  }

  Future<void> _fetchWatchedSeries() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.getWatched();

      // Filter for TV series only
      final seriesData = data
          .where((item) => item['item_type'] == 'tv')
          .toList();

      final List<Map<String, dynamic>> formattedList = [];

      // Fetch details for each item in parallel
      final futures = seriesData.map((item) async {
        try {
          final int id = item['item_id'];
          final details = await _tmdbService.getTVDetails(id);

          // Extract genres
          final genres =
              (details['genres'] as List?)
                  ?.map((g) => g['name'] as String)
                  .take(2)
                  .join(', ') ??
              '';

          return {
            'id': id,
            'title': details['name'] ?? 'No Title',
            'year': (details['first_air_date'] != null && (details['first_air_date'] as String).length >= 4)
                ? (details['first_air_date'] as String).substring(0, 4)
                : '',
            'image': 'https://image.tmdb.org/t/p/w200${details['poster_path']}',
            'description': details['overview'] ?? 'No description',
            'genre': genres.isNotEmpty ? genres : 'TV Series',
            'is_movie': false,
            'raw_item': item,
            'details': details,
            'watched_date': item['watched_date'],
            'updated_at': item['updated_at'],
            'watched_season': item['watched_season'],
            'watched_episode': item['watched_episode'],
            'rating': item['rating'],
          };
        } catch (e) {
          debugPrint('Error fetching details for series ${item['item_id']}: $e');
          return {
            'id': item['item_id'],
            'title': item['title'] ?? 'No Title',
            'year': (item['release_date'] != null && (item['release_date'] as String).length >= 4)
                ? (item['release_date'] as String).substring(0, 4)
                : '',
            'image': 'https://image.tmdb.org/t/p/w200${item['poster_path']}',
            'description': item['overview'] ?? 'No description',
            'genre': 'TV Series',
            'is_movie': false,
            'raw_item': item,
            'watched_date': item['watched_date'],
            'updated_at': item['updated_at'],
            'watched_season': item['watched_season'],
            'watched_episode': item['watched_episode'],
            'rating': item['rating'],
          };
        }
      });

      final results = await Future.wait(futures);
      formattedList.addAll(results.whereType<Map<String, dynamic>>());
      
      // Sort by updated_at descending
      formattedList.sort((a, b) {
        final aTime = DateTime.tryParse(a['updated_at']?.toString() ?? '') ?? DateTime(0);
        final bTime = DateTime.tryParse(b['updated_at']?.toString() ?? '') ?? DateTime(0);
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _watchedSeries = formattedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching watched series: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSeriesCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SeriesPage(tvId: item['id'])),
        );
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item['watched_season'] != null &&
                        item['watched_episode'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Watched up to: S${item['watched_season']} E${item['watched_episode']}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary,
                          fontSize: 12,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Series Watched',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : _watchedSeries.isEmpty
          ? Center(
              child: Text(
                'No series watched yet',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _watchedSeries.length,
              itemBuilder: (context, index) {
                final item = _watchedSeries[index];
                return _buildSeriesCard(item);
              },
            ),
    );
  }
}
