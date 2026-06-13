import 'package:flutter/material.dart';
import 'dart:async';
import '../services/tmdb_service.dart';
import '../services/supabase_service.dart';
import '../widget/frosted_card.dart';
import '../widget/responsive_layout.dart';
import '../pages/movies.dart';
import '../pages/series.dart';
import '../pages/actors.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final TMDBService _tmdbService = TMDBService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  final List<Map<String, dynamic>> _items = [];

  // Search state
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _searchLogs = [];
  bool _showSearchTimeoutMessage = false;
  String _currentSearchQuery = '';

  // Filter state
  bool _isFilterExpanded = false;
  String _selectedType = 'All'; // 'All', 'Movie', 'TV Series'

  // New Filter States
  RangeValues _selectedYearRange = RangeValues(1950, DateTime.now().year.toDouble());
  final Set<int> _selectedGenreIds = {};
  final Set<int> _selectedProviderIds = {};

  // Data
  Map<int, String> _movieGenres = {};
  List<dynamic> _watchProviders = [];
  bool _genresLoaded = false;
  bool _providersLoaded = false;

  final Set<int> _addedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchGenres();
    _fetchProviders();
    _fetchMixedContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGenres() async {
    try {
      final genres = await _tmdbService.getGenreList();

      if (mounted) {
        setState(() {
          _movieGenres = genres;
          _genresLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching genres: $e');
    }
  }

  Future<void> _fetchProviders() async {
    // Helper to fetch with error swallowing
    Future<List<dynamic>> fetchSafe(String region) async {
      try {
        return await _tmdbService.getAvailableWatchProviders(
          watchRegion: region,
        );
      } catch (e) {
        debugPrint('Error fetching providers for $region: $e');
        return [];
      }
    }

    try {
      // Fetch for both IN and US to cover all requested services
      // We run them in parallel but handle errors individually so one failure doesn't kill all
      final results = await Future.wait([fetchSafe('IN'), fetchSafe('US')]);

      final allProviders = [...results[0], ...results[1]];

      if (allProviders.isEmpty) {
        debugPrint('No providers fetched from any region.');
        // Even if empty, we might want to set loaded to true so UI doesn't break?
        // But better to leave it false so we don't show empty section.
        return;
      }

      // Deduplicate by provider_id
      final uniqueProviders = <int, Map<String, dynamic>>{};
      for (var p in allProviders) {
        uniqueProviders[p['provider_id']] = p;
      }

      // Map of requested providers to their TMDB IDs
      final targetProviderIds = {
        8, // Netflix
        122, // Hotstar
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
        257, // Fubo
        299, // Sling TV
        386, // Peacock
        531, // Paramount+
        73, // Tubi
        300, // Pluto TV
        319, // ALTBalaji
        309, // Sun NXT
        218, // Eros Now
        284, // MX Player
      };

      final filtered = uniqueProviders.values
          .where((p) => targetProviderIds.contains(p['provider_id']))
          .map((p) {
            // Branding update to JioHotstar
            if (p['provider_id'] == 122) {
              return {...p, 'provider_name': 'JioHotstar'};
            }
            return p;
          })
          .toList();

      if (mounted) {
        setState(() {
          _watchProviders = filtered;
          _providersLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error in _fetchProviders: $e');
    }
  }

  Future<void> _fetchMixedContent() async {
    setState(() {
      _isLoading = true;
      _items.clear();
      _addedIds.clear();
    });

    try {
      final excludedIds = await SupabaseService.getExcludedIds();

      // If providers are selected, use DISCOVER API
      if (_selectedProviderIds.isNotEmpty) {
        await _fetchDiscoverContent(excludedIds);
      } else {
        // Otherwise use POPULAR/TRENDING mix
        await _fetchPopularTrendingContent(excludedIds);
      }
    } catch (e) {
      debugPrint('Error fetching explore content: $e');
      if (mounted && _items.isEmpty) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDiscoverContent(Set<int> excludedIds) async {
    final providerString = _selectedProviderIds.join('|'); // OR logic
    final genreString = _selectedGenreIds.isNotEmpty
        ? _selectedGenreIds.join('|')
        : null;
    final dateGte = '${_selectedYearRange.start.round()}-01-01';
    final dateLte = '${_selectedYearRange.end.round()}-12-31';

    // Fetch Movies and TV
    final results = await Future.wait([
      _tmdbService.discoverMovies(
        withWatchProviders: providerString,
        withGenres: genreString,
        releaseDateGte: dateGte,
        releaseDateLte: dateLte,
        page: 1,
      ),
      _tmdbService.discoverMovies(
        withWatchProviders: providerString,
        withGenres: genreString,
        releaseDateGte: dateGte,
        releaseDateLte: dateLte,
        page: 2,
      ),
      _tmdbService.discoverTV(
        withWatchProviders: providerString,
        withGenres: genreString,
        firstAirDateGte: dateGte,
        firstAirDateLte: dateLte,
        page: 1,
      ),
      _tmdbService.discoverTV(
        withWatchProviders: providerString,
        withGenres: genreString,
        firstAirDateGte: dateGte,
        firstAirDateLte: dateLte,
        page: 2,
      ),
    ]);

    await _processAndAddItems(results, excludedIds);
  }

  Future<void> _fetchPopularTrendingContent(Set<int> excludedIds) async {
    // Batch 1: Popular Page 1
    final batch1 = await Future.wait([
      _tmdbService.getPopularMovies(page: 1),
      _tmdbService.getPopularTV(page: 1),
    ]);
    await _processAndAddItems(batch1, excludedIds);

    // Batch 2: Trending
    final batch2 = await Future.wait([
      _tmdbService.getTrendingMovies(),
      _tmdbService.getTrendingTV(),
    ]);
    await _processAndAddItems(batch2, excludedIds);

    // Batch 3: Popular Page 2
    final batch3 = await Future.wait([
      _tmdbService.getPopularMovies(page: 2),
      _tmdbService.getPopularTV(page: 2),
    ]);
    await _processAndAddItems(batch3, excludedIds);

    // Batch 4: Popular Page 3 (ensure we reach 90)
    if (_items.length < 90) {
      final batch4 = await Future.wait([
        _tmdbService.getPopularMovies(page: 3),
        _tmdbService.getPopularTV(page: 3),
      ]);
      await _processAndAddItems(batch4, excludedIds);
    }
  }

  Future<void> _processAndAddItems(
    List<List<dynamic>> results,
    Set<int> excludedIds,
  ) async {
    final List<dynamic> newItems = [];
    for (var list in results) {
      newItems.addAll(list);
    }

    final filtered = newItems
        .where(
          (item) =>
              !excludedIds.contains(item['id']) &&
              !_addedIds.contains(item['id']),
        )
        .toList();

    for (var item in filtered) {
      _addedIds.add(item['id']);
    }

    filtered.shuffle();

    final formatted = filtered.map((item) => _formatItem(item)).toList();

    // Add row by row (3 items per row) for visual engagement
    for (var i = 0; i < formatted.length; i += 3) {
      if (!mounted) return;
      if (_items.length >= 90) break;

      final end = (i + 3 < formatted.length) ? i + 3 : formatted.length;
      final chunk = formatted.sublist(i, end);

      setState(() {
        _items.addAll(chunk);
        _isLoading = false;
      });

      // Short delay to create "row by row" loading effect
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }



  Future<void> _performSearch(String query) async {
    final searchId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentSearchQuery = searchId;

    setState(() {
      _isLoading = true;
      _isSearching = true;
      _searchResults = [];
      _searchLogs = ['Deep search initiated for "$query"...'];
      _showSearchTimeoutMessage = false;
    });

    // Timeout timer to show "Not found yet" message
    Timer(const Duration(seconds: 10), () {
      if (mounted && _currentSearchQuery == searchId && _searchResults.isEmpty) {
        setState(() => _showSearchTimeoutMessage = true);
      }
    });

    try {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) setState(() => _searchLogs.add('Establishing connection...'));

      final uniqueIds = <int>{};
      
      // Search up to 50 pages continuously
      for (int page = 1; page <= 50; page++) {
        // Check if a new search has been started
        if (_currentSearchQuery != searchId) return;

        try {
          final pageResult = await _tmdbService.searchMulti(query, page: page);
          
          if (pageResult.isEmpty && page > 1) {
            if (mounted) setState(() => _searchLogs.add('End of results reached at page $page.'));
            break; 
          }

          final List<Map<String, dynamic>> pageFormatted = [];
          for (var item in pageResult) {
            final id = item['id'];
            if (id != null && (item['media_type'] == 'movie' ||
                    item['media_type'] == 'tv' ||
                    item['media_type'] == 'person') &&
                !uniqueIds.contains(id)) {
              uniqueIds.add(id);
              pageFormatted.add(_formatItem(item));
            }
          }

          if (mounted && _currentSearchQuery == searchId) {
            setState(() {
              _searchResults.addAll(pageFormatted);
              _searchLogs.add('Found ${pageFormatted.length} items on page $page...');
              // If we found something, we can hide the timeout message
              if (_searchResults.isNotEmpty) _showSearchTimeoutMessage = false;
              
              // We keep _isLoading = true to keep showing logs as requested
            });
          }

          // Small delay between pages to keep UI responsive and logs readable
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('Error fetching page $page: $e');
          if (mounted) setState(() => _searchLogs.add('Warning: Page $page skip due to error.'));
        }
      }

      if (mounted && _currentSearchQuery == searchId) {
        setState(() {
          _searchLogs.add('Search completed. Total results: ${_searchResults.length}');
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching: $e');
      if (mounted && _currentSearchQuery == searchId) {
        setState(() {
          _isLoading = false;
          _searchLogs.add('Search stopped due to error.');
        });
      }
    }
  }

  bool _shouldIncludeItem(Map<String, dynamic> item, {bool isSearch = false}) {
    // 1. Type Filter - Keep this for search if user specifically wants just movies/tv
    if (_selectedType == 'Movie' && item['type'] != 'movie') return false;
    if (_selectedType == 'TV Series' && item['type'] != 'tv') return false;
    // Note: If type is 'person', it shows in 'All' but not in specific Movie/TV filters.

    // If searching, we skip Year and Genre filters to allow finding items outside current filters
    if (isSearch) return true;

    // 2. Year Filter
    final int? year = int.tryParse(item['year']);
    // Persons might not have year, so skip year check for them or treat as valid
    if (year != null && item['type'] != 'person') {
      if (year < _selectedYearRange.start || year > _selectedYearRange.end) {
        return false;
      }
    }

    // 3. Genre Filter
    if (_selectedGenreIds.isNotEmpty && item['type'] != 'person') {
      final itemGenres = item['genre_ids'] as List<dynamic>?;
      if (itemGenres == null || itemGenres.isEmpty) return false;

      bool hasGenre = false;
      for (var id in itemGenres) {
        if (_selectedGenreIds.contains(id)) {
          hasGenre = true;
          break;
        }
      }
      if (!hasGenre) return false;
    }

    return true;
  }

  Map<String, dynamic> _formatItem(dynamic item) {
    final name = item['title'] ?? item['name'] ?? 'No Title';
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? '';
    final year = releaseDate.toString().length >= 4 ? releaseDate.toString().substring(0, 4) : '';
    final type = item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv');

    String imagePath;
    if (type == 'person') {
      imagePath = item['profile_path'] != null
          ? 'https://image.tmdb.org/t/p/w500${item['profile_path']}'
          : '';
    } else {
      imagePath = item['poster_path'] != null
          ? 'https://image.tmdb.org/t/p/w500${item['poster_path']}'
          : '';
    }

    String description;
    if (type == 'person') {
      description = 'Known for: ${item['known_for_department'] ?? 'Acting'}';
    } else {
      description = item['overview'] ?? 'No description';
    }

    return {
      'id': item['id'],
      'title': name,
      'year': year,
      'image': imagePath,
      'type': type,
      'description': description,
      'genre_ids': item['genre_ids'],
    };
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where(_shouldIncludeItem).toList();
  }

  List<Map<String, dynamic>> get _filteredSearchResults {
    return _searchResults.where((item) => _shouldIncludeItem(item, isSearch: true)).toList();
  }

  Widget _buildSearchResultCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () {
        if (item['type'] == 'movie') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MoviePage(movieId: item['id']),
            ),
          );
        } else if (item['type'] == 'tv') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SeriesPage(tvId: item['id']),
            ),
          );
        } else if (item['type'] == 'person') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActorsPage(personId: item['id']),
            ),
          );
        }
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
                    // Year | Type
                    Builder(
                      builder: (context) {
                        String typeText;
                        if (item['type'] == 'movie') {
                          typeText = 'Movie';
                        } else if (item['type'] == 'tv') {
                          typeText = 'TV Series';
                        } else if (item['type'] == 'person') {
                          typeText = 'Actor';
                        } else {
                          typeText = 'Content';
                        }

                        final year = item['year'] as String;
                        final label = year.isNotEmpty
                            ? '$year | $typeText'
                            : typeText;

                        return Text(
                          label,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        );
                      },
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedType == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildGenreChip(int id, String label) {
    final isSelected = _selectedGenreIds.contains(id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedGenreIds.remove(id);
          } else {
            _selectedGenreIds.add(id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
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
          // Re-fetch content when provider changes
          _fetchMixedContent();
        });
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: logoPath != null
              ? Image.network(
                  'https://image.tmdb.org/t/p/original$logoPath',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Center(child: Icon(Icons.tv, size: 24)),
                )
              : Center(
                  child: Text(
                    name[0],
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedIndex: 2, // Explore icon is selected
      child: Column(
        children: [
          // VIEWPICK Title
          Padding(
            padding: const EdgeInsets.only(top: 50.0, bottom: 20.0),
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
          // Search bar and Filter Button
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          _isSearching = false;
                          _searchResults = [];
                          _isLoading = false;
                          _searchLogs = [];
                        });
                      }
                    },
                    onSubmitted: _performSearch,
                    decoration: InputDecoration(
                      hintText: 'Search movies and series...',
                      hintStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send_rounded),
                        onPressed: () => _performSearch(_searchController.text),
                        color: Theme.of(context).colorScheme.primary,
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

          // Filter Options Panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: _isFilterExpanded
                ? 350 // Adjusted height
                : 0,
            curve: Curves.easeInOutCubic,
            child: ClipRect(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type Filter
                      Row(
                        children: [
                          _buildFilterChip('All'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Movie'),
                          const SizedBox(width: 8),
                          _buildFilterChip('TV Series'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedType = 'All';
                                _selectedYearRange = RangeValues(
                                  1950,
                                  DateTime.now().year.toDouble(),
                                );
                                _selectedGenreIds.clear();
                                _selectedProviderIds.clear();
                              });
                              _fetchMixedContent();
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Streaming Services Filter
                      if (_providersLoaded) ...[
                        Text(
                          'Streaming Services',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _watchProviders
                                .map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: _buildProviderChip(p),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Year Range Filter
                      Text(
                        'Year Range: ${_selectedYearRange.start.round()} - ${_selectedYearRange.end.round()}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
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

                      // Genre Filter
                      if (_genresLoaded) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Genres',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._movieGenres.entries
                                .take(8)
                                .map((e) => _buildGenreChip(e.key, e.value)),
                            // Combine a few TV genres if needed or just show common ones
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Grid view
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollNotification) {
                if (scrollNotification is ScrollStartNotification) {
                  if (_isFilterExpanded) {
                    setState(() {
                      _isFilterExpanded = false;
                    });
                  }
                }
                return false;
              },
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          if (_searchLogs.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            if (_showSearchTimeoutMessage && _searchResults.isEmpty) ...[
                              Text(
                                'Still searching... No results found yet.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Column(
                                children: _searchLogs.reversed.take(5).toList().asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final log = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      log,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: index == 0 ? 1.0 : 0.5),
                                        fontSize: index == 0 ? 14 : 12,
                                        fontStyle: index == 0 ? FontStyle.normal : FontStyle.italic,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : _items.isEmpty && !_isSearching
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load content',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _fetchMixedContent();
                              if (!_genresLoaded) _fetchGenres();
                              if (!_providersLoaded) _fetchProviders();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _isSearching
                  ? _filteredSearchResults.isEmpty
                       ? Center(
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
                                 'No results found for "${_searchController.text}"',
                                 style: TextStyle(
                                   color: Theme.of(context).colorScheme.onSurfaceVariant,
                                   fontSize: 16,
                                 ),
                               ),
                               if (_selectedType != 'All') ...[
                                 const SizedBox(height: 8),
                                 Text(
                                   '(Filters are active: $_selectedType only)',
                                   style: TextStyle(
                                     color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                     fontSize: 12,
                                   ),
                                 ),
                               ],
                             ],
                           ),
                         )
                       : ListView.builder(
                           padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 100.0),
                           itemCount: _filteredSearchResults.length,
                           itemBuilder: (context, index) {
                             return _buildSearchResultCard(
                               _filteredSearchResults[index],
                             );
                           },
                         )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        16.0,
                        0,
                        16.0,
                        100.0,
                      ), // Added bottom padding for nav bar
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.5,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        return GestureDetector(
                          onTap: () {
                            if (item['type'] == 'movie') {
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
                                  builder: (context) =>
                                      SeriesPage(tvId: item['id']),
                                ),
                              );
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
          ),
        ],
      ),
    );
  }
}
