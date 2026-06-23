// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

class YoutubeWebPlayer extends StatefulWidget {
  final String videoId;
  final double height;

  const YoutubeWebPlayer({
    super.key,
    required this.videoId,
    this.height = 250,
  });

  @override
  State<YoutubeWebPlayer> createState() => _YoutubeWebPlayerState();
}

class _YoutubeWebPlayerState extends State<YoutubeWebPlayer> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'yt-${widget.videoId}-${DateTime.now().millisecondsSinceEpoch}';

    // Register an IFrame element as a platform view
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src =
            'https://www.youtube.com/embed/${widget.videoId}?autoplay=0&rel=0&modestbranding=1'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture'
        ..setAttribute('allowfullscreen', 'true');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
