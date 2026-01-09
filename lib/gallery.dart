import 'package:enough_media/enough_media.dart';
import 'package:files3/helpers.dart';
import 'package:flutter/material.dart';

class GalleryProps {
  final String title;
  final String key;
  final String? description;
  final String url;
  final String path;
  final int? size;

  GalleryProps({
    required this.title,
    required this.key,
    this.description,
    required this.url,
    required this.path,
    this.size,
  });
}

class Gallery extends StatefulWidget {
  final List<GalleryProps> files;
  final int initialIndex;

  const Gallery({super.key, required this.files, this.initialIndex = 0});

  @override
  GalleryState createState() => GalleryState();
}

class GalleryState extends State<Gallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Image ${_currentIndex + 1} of ${widget.files.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.files.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) => InteractiveMediaWidget(
          heroTag: widget.files[index].path,
          mediaProvider: getMediaProvider(
            name: widget.files[index].title,
            mediaType:
                getMediaType(widget.files[index].key) ??
                'application/octet-stream',
            url: widget.files[index].url,
            path: widget.files[index].path,
            size: widget.files[index].size,
            description: widget.files[index].description,
          ),
          fallbackBuilder: (_, media) => Icon(
            media.isImage
                ? Icons.image
                : media.isVideo
                ? Icons.videocam
                : media.isAudio
                ? Icons.audiotrack
                : media.isText
                ? Icons.description
                : media.isFont
                ? Icons.font_download
                : media.isMessage
                ? Icons.message
                : media.isModel
                ? Icons.model_training
                : media.isApplication
                ? media.mediaType.toLowerCase() == 'application/pdf'
                      ? Icons.picture_as_pdf
                      : Icons.apps
                : Icons.insert_drive_file,
          ),
        ),
      ),
    );
  }
}
