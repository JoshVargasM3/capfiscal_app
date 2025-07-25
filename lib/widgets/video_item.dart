import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'fullscreen_video_player.dart';

class VideoItem extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoItem({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<VideoItem> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  void _openFullScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPlayer(controller: _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red[900],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _initialized
              ? Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: IconButton(
                          icon: Icon(
                            _controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                            color: Colors.white,
                            size: 40,
                          ),
                          onPressed: _togglePlay,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen, color: Colors.white, size: 30),
                        onPressed: _openFullScreen,
                      ),
                    ),
                  ],
                )
              : const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
