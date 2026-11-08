import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  runApp(const HBMovieApp());
}

class HBMovieApp extends StatelessWidget {
  const HBMovieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HB Movie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0C13),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF141724),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class ChannelItem {
  final String name;
  final String url;

  ChannelItem({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory ChannelItem.fromJson(Map<String, dynamic> json) =>
      ChannelItem(name: json['name'], url: json['url']);
}

class ResolverService {
  static Future<String?> extractVideoStream(String url) async {
    final lower = url.toLowerCase();
    if (lower.endsWith('.m3u8') || lower.endsWith('.mp4')) return url;

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

        final source = document.querySelector('video source');
        if (source != null && source.attributes.containsKey('src')) {
          return Uri.parse(url).resolve(source.attributes['src']!).toString();
        }

        final regex = RegExp(r'https?:\\/\\/[^\\s"\\']+\\.(m3u8|mp4)[^\\s"\\']*');
        final match = regex.firstMatch(response.body);
        if (match != null) return match.group(0);
      }
    } catch (_) {}
    return null;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChannelItem> _channels = [];
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('hb_channels');

    if (!mounted) return;

    setState(() {
      _channels = data == null
          ? [
              ChannelItem(
                name: 'Big Buck Bunny',
                url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
              ),
              ChannelItem(
                name: 'Tears of Steel',
                url:
                    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
              ),
            ]
          : data
              .map((item) => ChannelItem.fromJson(jsonDecode(item) as Map<String, dynamic>))
              .toList();
    });
  }

  Future<void> _saveChannels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'hb_channels',
      _channels.map((channel) => jsonEncode(channel.toJson())).toList(),
    );
  }

  void _addChannelDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141724),
          title: const Text('Adicionar canal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration:
                    const InputDecoration(labelText: 'URL (.m3u8 ou site)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
              onPressed: () {
                final url = _urlCtrl.text.trim();
                if (url.isEmpty) return;

                setState(() {
                  _channels.add(ChannelItem(
                    name: _nameCtrl.text.trim().isEmpty
                        ? 'Fonte ${_channels.length + 1}'
                        : _nameCtrl.text.trim(),
                    url: url,
                  ));
                });

                _saveChannels();
                _nameCtrl.clear();
                _urlCtrl.clear();
                Navigator.pop(ctx);
              },
              child: const Text('Salvar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPlayer(ChannelItem channel) async {
    _isLoading = true;
    setState(() {});

    final stream = await ResolverService.extractVideoStream(channel.url);

    _isLoading = false;
    setState(() {});

    if (!mounted) return;

    if (stream != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(title: channel.name, videoUrl: stream),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Não foi possível carregar o vídeo.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HB MOVIE',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE50914)),
        ),
        backgroundColor: const Color(0xFF0F111A),
        actions: [
          IconButton(icon: const Icon(Icons.add_link), onPressed: _addChannelDialog),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _channels.length,
              itemBuilder: (context, index) {
                final item = _channels[index];
                return Card(
                  color: const Color(0xFF141724),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.play_circle_fill,
                        color: Color(0xFFE50914), size: 36),
                    title: Text(item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item.url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      onPressed: () {
                        setState(() => _channels.removeAt(index));
                        _saveChannels();
                      },
                    ),
                    onTap: () => _openPlayer(item),
                  ),
                );
              },
            ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String title;
  final String videoUrl;

  const PlayerScreen({super.key, required this.title, required this.videoUrl});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _videoPlayerController = controller;

    try {
      await controller.initialize();
      if (!mounted) return;

      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        allowFullScreen: true,
        fullScreenByDefault: true,
      );

      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = 'Falha ao iniciar o vídeo.');
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.title)),
        body: Center(child: Text(_error!)),
      );
    }

    if (_chewieController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: Center(child: Chewie(controller: _chewieController!)),
    );
  }
}
