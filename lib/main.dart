import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tmdb_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HBMovieApp());
}

class HBMovieApp extends StatelessWidget {
  const HBMovieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HB Movies',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF17191F),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF090A0F),
          foregroundColor: Colors.white,
        ),
      ),
      home: const CatalogScreen(),
    );
  }
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.rating,
    required this.mediaType,
  });

  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final String releaseDate;
  final double rating;
  final String mediaType;

  String get posterUrl => posterPath.isEmpty
      ? ''
      : 'https://image.tmdb.org/t/p/w500$posterPath';
  String get backdropUrl => backdropPath.isEmpty
      ? ''
      : 'https://image.tmdb.org/t/p/w1280$backdropPath';
  String get year => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
  String get favoriteKey => '$mediaType:$id';

  factory CatalogItem.fromJson(Map<String, dynamic> json,
      {String? defaultMediaType}) {
    return CatalogItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? json['name'] ?? 'Sem título').toString(),
      overview: (json['overview'] ?? '').toString(),
      posterPath: (json['poster_path'] ?? '').toString(),
      backdropPath: (json['backdrop_path'] ?? '').toString(),
      releaseDate: (json['release_date'] ?? json['first_air_date'] ?? '').toString(),
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
      mediaType: (json['media_type'] ?? defaultMediaType ?? 'movie').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'release_date': releaseDate,
        'vote_average': rating,
        'media_type': mediaType,
      };
}

class TmdbService {
  static const _baseUrl = 'https://api.themoviedb.org/3';

  static Future<List<CatalogItem>> list(String path,
      {String? defaultMediaType}) async {
    if (!hasTmdbApiKey) throw const TmdbException('missing_key');
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: {
      'api_key': tmdbApiKey,
      'language': 'pt-BR',
      'page': '1',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw TmdbException('HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map((item) => CatalogItem.fromJson(item,
            defaultMediaType: defaultMediaType))
        .where((item) => item.id > 0)
        .toList();
  }

  static Future<List<CatalogItem>> search(String query) =>
      list('/search/multi', defaultMediaType: 'movie').then((_) =>
          throw StateError('Use searchWithQuery for search requests'));

  static Future<List<CatalogItem>> searchWithQuery(String query) async {
    if (!hasTmdbApiKey) throw const TmdbException('missing_key');
    final uri = Uri.parse('$_baseUrl/search/multi').replace(queryParameters: {
      'api_key': tmdbApiKey,
      'language': 'pt-BR',
      'query': query,
      'page': '1',
      'include_adult': 'false',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw TmdbException('HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? const [];
    return results
        .whereType<Map<String, dynamic>>()
        .where((item) => item['media_type'] == 'movie' || item['media_type'] == 'tv')
        .map(CatalogItem.fromJson)
        .toList();
  }

  static Future<Map<String, dynamic>> details(CatalogItem item) async {
    if (!hasTmdbApiKey) throw const TmdbException('missing_key');
    final uri = Uri.parse('$_baseUrl/${item.mediaType}/${item.id}').replace(
      queryParameters: {'api_key': tmdbApiKey, 'language': 'pt-BR'},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw TmdbException('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<String?> trailerKey(CatalogItem item) async {
    final uri = Uri.parse('$_baseUrl/${item.mediaType}/${item.id}/videos')
        .replace(queryParameters: {'api_key': tmdbApiKey, 'language': 'pt-BR'});
    var response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    var results = (jsonDecode(response.body) as Map<String, dynamic>)['results']
        as List<dynamic>? ?? const [];
    var trailer = _findYoutubeTrailer(results);
    if (trailer != null) return trailer;

    // Fall back to English metadata when a localized trailer is unavailable.
    final englishUri = Uri.parse('$_baseUrl/${item.mediaType}/${item.id}/videos')
        .replace(queryParameters: {'api_key': tmdbApiKey, 'language': 'en-US'});
    response = await http.get(englishUri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    results = (jsonDecode(response.body) as Map<String, dynamic>)['results']
        as List<dynamic>? ?? const [];
    trailer = _findYoutubeTrailer(results);
    return trailer;
  }

  static String? _findYoutubeTrailer(List<dynamic> results) {
    for (final entry in results.whereType<Map<String, dynamic>>()) {
      if (entry['site'] == 'YouTube' &&
          (entry['type'] == 'Trailer' || entry['type'] == 'Teaser') &&
          entry['key'] is String) {
        return entry['key'] as String;
      }
    }
    return null;
  }
}

class TmdbException implements Exception {
  const TmdbException(this.message);
  final String message;
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<CatalogItem> _trending = [];
  List<CatalogItem> _popularMovies = [];
  List<CatalogItem> _popularShows = [];
  List<CatalogItem> _favorites = [];
  List<CatalogItem> _searchResults = [];
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadCatalog();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('hb_favorites') ?? const [];
    final items = <CatalogItem>[];
    for (final value in jsonList) {
      try {
        items.add(CatalogItem.fromJson(jsonDecode(value) as Map<String, dynamic>));
      } catch (_) {
        // Ignore an invalid saved item rather than preventing the app from opening.
      }
    }
    if (mounted) setState(() => _favorites = items);
  }

  Future<void> _loadCatalog() async {
    if (!hasTmdbApiKey) {
      setState(() {
        _loading = false;
        _error = 'missing_key';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        TmdbService.list('/trending/all/week'),
        TmdbService.list('/movie/popular', defaultMediaType: 'movie'),
        TmdbService.list('/tv/popular', defaultMediaType: 'tv'),
      ]);
      if (!mounted) return;
      setState(() {
        _trending = results[0];
        _popularMovies = results[1];
        _popularShows = results[2];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _loading = true;
      _error = null;
    });
    try {
      final results = await TmdbService.searchWithQuery(query.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _toggleFavorite(CatalogItem item) async {
    final exists = _favorites.any((saved) => saved.favoriteKey == item.favoriteKey);
    setState(() {
      if (exists) {
        _favorites.removeWhere((saved) => saved.favoriteKey == item.favoriteKey);
      } else {
        _favorites.insert(0, item);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'hb_favorites',
      _favorites.map((saved) => jsonEncode(saved.toJson())).toList(),
    );
  }

  bool _isFavorite(CatalogItem item) =>
      _favorites.any((saved) => saved.favoriteKey == item.favoriteKey);

  void _openDetails(CatalogItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DetailsScreen(
        item: item,
        isFavorite: _isFavorite(item),
        onToggleFavorite: () => _toggleFavorite(item),
      ),
    ));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _tab == 2
        ? _favoritesPage()
        : _tab == 1
            ? _searchPage()
            : _homePage();
    return Scaffold(
      appBar: AppBar(
        title: const Text('HB MOVIES', style: TextStyle(
          color: Color(0xFFE50914), fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        )),
        actions: [
          IconButton(
            tooltip: 'Atualizar catálogo',
            onPressed: _loadCatalog,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark), label: 'Minha lista'),
        ],
      ),
    );
  }

  Widget _homePage() {
    if (_loading && _trending.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _trending.isEmpty) return _errorView();
    final featured = _trending.isEmpty ? null : _trending.first;
    return RefreshIndicator(
      onRefresh: _loadCatalog,
      child: ListView(
        children: [
          if (featured != null)
            _FeaturedBanner(item: featured, onTap: () => _openDetails(featured)),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          _CatalogRow(title: 'Em alta esta semana', items: _trending,
              onTap: _openDetails, isFavorite: _isFavorite),
          _CatalogRow(title: 'Filmes populares', items: _popularMovies,
              onTap: _openDetails, isFavorite: _isFavorite),
          _CatalogRow(title: 'Séries populares', items: _popularShows,
              onTap: _openDetails, isFavorite: _isFavorite),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Text('Informações de filmes e séries fornecidas por TMDB. '
                'Este app não oferece nem transmite filmes completos.',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _searchPage() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Buscar filmes e séries',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _search(_searchController.text),
              ),
              filled: true,
              fillColor: const Color(0xFF17191F),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView()
                  : _searchResults.isEmpty
                      ? const Center(child: Text('Pesquise um título para começar.'))
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _searchResults.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: .52,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                          ),
                          itemBuilder: (_, index) {
                            final item = _searchResults[index];
                            return PosterCard(item: item,
                                onTap: () => _openDetails(item));
                          },
                        ),
        ),
      ]);

  Widget _favoritesPage() => _favorites.isEmpty
      ? const Center(child: Text('Sua lista está vazia. Adicione títulos pelos detalhes.'))
      : GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _favorites.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, childAspectRatio: .52,
            crossAxisSpacing: 10, mainAxisSpacing: 12,
          ),
          itemBuilder: (_, index) {
            final item = _favorites[index];
            return PosterCard(item: item, onTap: () => _openDetails(item));
          },
        );

  Widget _errorView() {
    final missingKey = _error == 'missing_key' || _error?.contains('missing_key') == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 44, color: Colors.white54),
          const SizedBox(height: 12),
          Text(missingKey
              ? 'Configure a chave TMDB para carregar o catálogo.'
              : 'Não foi possível carregar o catálogo. Verifique a conexão e a chave da API.',
              textAlign: TextAlign.center),
          if (!missingKey && _error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
          const SizedBox(height: 14),
          OutlinedButton(onPressed: _loadCatalog, child: const Text('Tentar novamente')),
        ]),
      ),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({required this.item, required this.onTap});
  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 360,
          child: Stack(fit: StackFit.expand, children: [
            if (item.backdropUrl.isNotEmpty)
              Image.network(item.backdropUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _bannerPlaceholder())
            else
              _bannerPlaceholder(),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xFF090A0F)],
              stops: [.25, 1],
            ))),
            Positioned(left: 20, right: 20, bottom: 24, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DESTAQUE', style: TextStyle(color: Color(0xFFE50914),
                    fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 6),
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: onTap,
                    icon: const Icon(Icons.info_outline), label: const Text('Ver detalhes')),
              ],
            )),
          ]),
        ),
      );

  Widget _bannerPlaceholder() => Container(color: const Color(0xFF242631));
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.title, required this.items,
    required this.onTap, required this.isFavorite});
  final String title;
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onTap;
  final bool Function(CatalogItem) isFavorite;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
      SizedBox(height: 205, child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) => SizedBox(width: 128,
          child: PosterCard(item: items[index], onTap: () => onTap(items[index]),
              isFavorite: isFavorite(items[index]))),
      )),
    ]);
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({required this.item, required this.onTap, this.isFavorite = false});
  final CatalogItem item;
  final VoidCallback onTap;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: item.posterUrl.isEmpty
                ? Container(color: const Color(0xFF20222A),
                    child: const Icon(Icons.movie_outlined, color: Colors.white54))
                : Image.network(item.posterUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF20222A),
                      child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                    ))),
            if (isFavorite)
              const Positioned(right: 6, top: 6, child: Icon(Icons.bookmark,
                  color: Color(0xFFE50914), size: 22)),
          ])),
          const SizedBox(height: 5),
          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text('${item.year}${item.year.isNotEmpty ? ' • ' : ''}${item.mediaType == 'tv' ? 'Série' : 'Filme'}',
              maxLines: 1, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
      );
}

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.item,
    required this.isFavorite, required this.onToggleFavorite});
  final CatalogItem item;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late Future<Map<String, dynamic>> _details;
  bool _favorite = false;
  bool _trailerLoading = false;

  @override
  void initState() {
    super.initState();
    _favorite = widget.isFavorite;
    _details = TmdbService.details(widget.item);
  }

  Future<void> _playTrailer() async {
    setState(() => _trailerLoading = true);
    try {
      final key = await TmdbService.trailerKey(widget.item);
      if (!mounted) return;
      if (key == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não há trailer disponível para este título.')));
        return;
      }
      final uri = Uri.parse('https://www.youtube.com/watch?v=$key');
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Não foi possível abrir o YouTube.');
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir o trailer: $error')));
    } finally {
      if (mounted) setState(() => _trailerLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FutureBuilder<Map<String, dynamic>>(
          future: _details,
          builder: (context, snapshot) {
            final details = snapshot.data ?? const <String, dynamic>{};
            final backdrop = (details['backdrop_path'] ?? widget.item.backdropPath).toString();
            final backdropUrl = backdrop.isEmpty ? '' : 'https://image.tmdb.org/t/p/w1280$backdrop';
            final genres = (details['genres'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map((genre) => genre['name'].toString()).join(' • ');
            return CustomScrollView(slivers: [
              SliverAppBar(expandedHeight: 300, pinned: true,
                actions: [IconButton(
                  tooltip: _favorite ? 'Remover da minha lista' : 'Adicionar à minha lista',
                  onPressed: () => setState(() {
                    _favorite = !_favorite;
                    widget.onToggleFavorite();
                  }),
                  icon: Icon(_favorite ? Icons.bookmark : Icons.bookmark_border,
                      color: _favorite ? const Color(0xFFE50914) : Colors.white),
                )],
                flexibleSpace: FlexibleSpaceBar(background: backdropUrl.isEmpty
                    ? Container(color: const Color(0xFF20222A))
                    : Image.network(backdropUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF20222A)))),
              ),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.item.title, style: const TextStyle(fontSize: 27,
                      fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    if (widget.item.year.isNotEmpty) _InfoChip(widget.item.year),
                    _InfoChip(widget.item.mediaType == 'tv' ? 'Série' : 'Filme'),
                    _InfoChip('★ ${widget.item.rating.toStringAsFixed(1)}'),
                    if (genres.isNotEmpty) _InfoChip(genres),
                  ]),
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: _trailerLoading ? null : _playTrailer,
                    icon: _trailerLoading
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: const Text('Assistir trailer oficial'),
                  )),
                  const SizedBox(height: 22),
                  const Text('Sinopse', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text((details['overview'] ?? widget.item.overview).toString().isEmpty
                      ? 'Sinopse indisponível.'
                      : (details['overview'] ?? widget.item.overview).toString(),
                      style: const TextStyle(height: 1.55, color: Colors.white70)),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator())),
                  if (snapshot.hasError)
                    const Padding(padding: EdgeInsets.only(top: 12),
                        child: Text('Alguns detalhes não puderam ser carregados.',
                            style: TextStyle(color: Colors.white54))),
                  const SizedBox(height: 24),
                  const Text('A reprodução de filmes completos não é fornecida pelo TMDB. '
                      'O botão abre somente trailers disponíveis no YouTube.',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                ]),
              )),
            ]);
          },
        ),
      );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF20222A),
        borderRadius: BorderRadius.circular(30)),
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );
}
