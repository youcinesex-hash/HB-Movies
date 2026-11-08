# TMDB API configuration

The app's TMDB key must not be committed to source control. Configure it at build time with Dart's compile-time environment define:

```bash
flutter run --dart-define=TMDB_API_KEY=YOUR_NEW_TMDB_KEY
```

For an APK:

```bash
flutter build apk --release --dart-define=TMDB_API_KEY=YOUR_NEW_TMDB_KEY
```

In Dart code, import `tmdb_config.dart` and read `tmdbApiKey`. Check `hasTmdbApiKey` before making TMDB requests and show a setup message if it is false.

A key embedded in a client app can still be extracted from the compiled app. For a publicly distributed app, proxy TMDB requests through a backend and keep the key there.
