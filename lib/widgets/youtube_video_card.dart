import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class YouTubeVideoCard extends StatefulWidget {
  const YouTubeVideoCard({
    super.key,
    required this.youtubeId,
    required this.title,
    required this.description,
    this.onClose,
  });

  final String youtubeId;
  final String title;
  final String description;
  final VoidCallback? onClose;

  @override
  State<YouTubeVideoCard> createState() => _YouTubeVideoCardState();
}

class _YouTubeVideoCardState extends State<YouTubeVideoCard> {
  late final YoutubePlayerController _yt;

  @override
  void initState() {
    super.initState();
    _yt = YoutubePlayerController.fromVideoId(
      videoId: widget.youtubeId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        enableCaption: true,
        showControls: true,
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maroon = Color(0xFF6B1A1A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Player en 16:9 y con bordes redondeados (no se sale del marco)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: YoutubePlayer(controller: _yt),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: maroon,
              ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE7E7E7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.description,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        if (widget.onClose != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              label: const Text('Cerrar'),
            ),
          ),
        ],
      ],
    );
  }
}
