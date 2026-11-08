# TMDB API configuration

The app's TMDB key must not be committed to source control. Configure it at build time with Dart's compile-time environment define:

```bash
flutter pub get
flutter run --dart-define=TMDB_API_KEY=YOUR_NEW_TMDB_KEY
```

For an APK:

```bash
flutter build apk --release --dart-define=TMDB_API_KEY=YOUR_NEW_TMDB_KEY
```

The app uses TMDB for trending titles, popular movies and series, title search, posters, summaries, ratings, and metadata. Trailer links are retrieved from TMDB and opened in YouTube when available. TMDB does not provide complete movie or series streams, so this app does not stream full titles.

A key embedded in a client app can still be extracted from the compiled app. For a publicly distributed app, proxy TMDB requests through a backend and keep the key there. Since the previously shared key appeared in chat, revoke it and create a replacement before building.
