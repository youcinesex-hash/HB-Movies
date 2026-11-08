/// TMDB API configuration.
///
/// Pass the key at build time instead of committing it to the repository:
/// flutter run --dart-define=TMDB_API_KEY=YOUR_NEW_TMDB_KEY
///
/// For a release build, use the same define with `flutter build apk`.
const String tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

bool get hasTmdbApiKey => tmdbApiKey.isNotEmpty;
