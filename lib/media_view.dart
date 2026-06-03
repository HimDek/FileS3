import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:files3/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:chewie/chewie.dart';
import 'package:photo_view/photo_view.dart';
import 'package:chewie_audio/chewie_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:files3/utils/hybrid_image_provider.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

class GalleryProps {
  final RemoteFile file;
  final String title;
  final String? description;
  final String url;
  final String path;
  final String cachePath;

  GalleryProps({
    required this.file,
    required this.title,
    this.description,
    required this.url,
    required this.path,
    required this.cachePath,
  });
}

enum DragDirection { none, vertical, horizontal }

class PointerGestureRouter extends StatefulWidget {
  final Widget child;

  /// Whether tap should be accepted
  final bool Function() allowTap;

  /// Whether vertical drag should be intercepted
  final bool Function() allowVerticalDrag;

  final VoidCallback? onTap;

  /// Per-frame vertical delta
  final ValueChanged<double>? onVerticalDrag;

  /// Called when finger is released, total signed dy
  final ValueChanged<double>? onVerticalDragEnd;

  final ValueChanged<DragDirection>? onDragStart;

  const PointerGestureRouter({
    required this.child,
    required this.allowTap,
    required this.allowVerticalDrag,
    this.onTap,
    this.onVerticalDrag,
    this.onVerticalDragEnd,
    this.onDragStart,
    super.key,
  });

  @override
  State<PointerGestureRouter> createState() => _PointerGestureRouterState();
}

class _PointerGestureRouterState extends State<PointerGestureRouter> {
  static const double _tapSlop = 12; // same as Flutter
  static const double _dragStart = 18; // when direction locks

  Offset _start = Offset.zero;
  Offset _last = Offset.zero;

  int _pointers = 0;
  bool _moved = false;
  bool _dragging = false;

  double _totalDy = 0;
  DragDirection _direction = DragDirection.none;

  DateTime _downTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,

      onPointerDown: (e) {
        _pointers++;
        if (_pointers == 1) {
          _start = e.position;
          _last = e.position;
          _downTime = DateTime.now();
          _moved = false;
          _dragging = false;
          _totalDy = 0;
          _direction = DragDirection.none;
        }
      },

      onPointerMove: (e) {
        if (_pointers != 1) return;

        final total = e.position - _start;
        final delta = e.position - _last;

        // Lock direction once movement exceeds threshold
        if (_direction == DragDirection.none && total.distance > _dragStart) {
          _direction = total.dy.abs() > total.dx.abs()
              ? DragDirection.vertical
              : DragDirection.horizontal;
          widget.onDragStart?.call(_direction);
        }

        if (_direction == DragDirection.vertical &&
            widget.allowVerticalDrag()) {
          _dragging = true;
          _totalDy += delta.dy;
          widget.onVerticalDrag?.call(delta.dy);
        } else if (total.distance > _tapSlop) {
          _moved = true;
        }

        _last = e.position;
      },

      onPointerUp: (e) {
        _pointers--;
        if (_pointers == 0) {
          final elapsed = DateTime.now().difference(_downTime).inMilliseconds;

          if (_dragging) {
            widget.onVerticalDragEnd?.call(_totalDy);
          } else if (!_moved && elapsed < 220 && widget.allowTap()) {
            widget.onTap?.call();
          }
        }
      },

      onPointerCancel: (_) {
        _pointers = 0;
        _dragging = false;
        _moved = false;
        _direction = DragDirection.none;
      },

      child: widget.child,
    );
  }
}

class AudioVideoInteractiveMedia extends StatefulWidget {
  final String path;
  final String cachePath;
  final String url;
  final String mediaType;
  final String? heroTag;
  final bool staypaused;
  const AudioVideoInteractiveMedia({
    super.key,
    required this.path,
    required this.cachePath,
    required this.url,
    required this.mediaType,
    this.heroTag,
    this.staypaused = false,
  });

  @override
  AudioVideoInteractiveMediaState createState() =>
      AudioVideoInteractiveMediaState();
}

class AudioVideoInteractiveMediaState
    extends State<AudioVideoInteractiveMedia> {
  late ChewieAudioController _chewieAudioController;
  late ChewieController _chewieController;
  late VideoPlayerController _videoController;
  late Future<dynamic> _loader;

  @override
  void initState() {
    super.initState();
    _loader = widget.mediaType.toLowerCase().startsWith('audio/')
        ? _loadAudio()
        : _loadVideo();
  }

  @override
  void dispose() {
    _chewieAudioController.dispose();
    _chewieController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  Future<ChewieAudioController> _loadAudio() async {
    if (await File(widget.path).exists()) {
      _videoController = VideoPlayerController.file(File(widget.path));
    } else if (await File(widget.cachePath).exists()) {
      _videoController = VideoPlayerController.file(File(widget.cachePath));
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
    }
    await _videoController.initialize();
    _chewieAudioController = ChewieAudioController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
    );
    _videoController.addListener(() {
      if (widget.staypaused && _videoController.value.isPlaying) {
        _videoController.pause();
      }
    });
    _chewieAudioController.addListener(() {
      if (widget.staypaused && _videoController.value.isPlaying) {
        _chewieAudioController.pause();
      }
    });
    return _chewieAudioController;
  }

  Future<VideoPlayerController> _loadVideo() async {
    if (await File(widget.path).exists()) {
      _videoController = VideoPlayerController.file(File(widget.path));
    } else if (await File(widget.cachePath).exists()) {
      _videoController = VideoPlayerController.file(File(widget.cachePath));
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
    }
    await _videoController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
      // Try playing around with some of these other options:

      // showControls: false,
      // materialProgressColors: ChewieProgressColors(
      //   playedColor: Colors.red,
      //   handleColor: Colors.blue,
      //   backgroundColor: Colors.grey,
      //   bufferedColor: Colors.lightGreen,
      // ),
      // placeholder: Container(
      //   color: Colors.grey,
      // ),
      // autoInitialize: true,
    );
    //_videoController.addListener(() => setState(() {}));
    _videoController.addListener(() {
      if (widget.staypaused && _videoController.value.isPlaying) {
        _videoController.pause();
      }
    });
    _chewieController.addListener(() {
      if (widget.staypaused && _videoController.value.isPlaying) {
        _chewieController.pause();
      }
    });
    return _videoController;
  }

  @override
  void didUpdateWidget(covariant AudioVideoInteractiveMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.staypaused && oldWidget.staypaused) return;

    if (widget.staypaused) {
      _videoController.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loader,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
          case ConnectionState.active:
            return Center(child: CircularProgressIndicator());
          case ConnectionState.done:
            return widget.mediaType.toLowerCase().startsWith('audio/')
                ? _buildAudioPlayer()
                : _buildVideo();
        }
      },
    );
  }

  Widget _buildAudioPlayer() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Hero(
          tag: widget.heroTag ?? widget.key.hashCode,
          child: ChewieAudio(controller: _chewieAudioController),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Hero(
          tag: widget.heroTag ?? widget.key.hashCode,
          child: Chewie(controller: _chewieController),
        ),
      ),
    );
  }
}

class PdfInteractiveMedia extends StatefulWidget {
  final String path;
  final String cachePath;
  final String url;
  final String? heroTag;
  final bool showControls;
  final Function(bool paging)? setPaging;
  const PdfInteractiveMedia({
    super.key,
    required this.path,
    required this.cachePath,
    required this.url,
    this.heroTag,
    this.showControls = true,
    this.setPaging,
  });

  @override
  PdfInteractiveMediaState createState() => PdfInteractiveMediaState();
}

class PdfInteractiveMediaState extends State<PdfInteractiveMedia> {
  final ValueNotifier<double> _pdfscale = ValueNotifier<double>(1);

  int _viewerInstance = 0;

  bool _pdfReady = false;
  int _pageCount = 0;
  Size _thumbSize = Size(40, 32);

  String? _pdfPath;
  String? _pdfUrl;

  PdfViewerController? _pdfViewerController;
  PdfTextSearcher? _pdfTextSearcher;

  PdfViewerParams _pdfViewerParams() => PdfViewerParams(
    margin: 0,
    textSelectionParams: PdfTextSelectionParams(
      enabled: true,
      enableSelectionHandles: true,
      showContextMenuAutomatically: true,
    ),
    onViewerReady: (document, controller) {
      if (!mounted || !controller.isReady) return;

      _pdfReady = true;
      _pageCount = controller.pageCount;
      _thumbSize = Size('$_pageCount/$_pageCount'.length * 8.0, 32);

      _pdfTextSearcher ??= PdfTextSearcher(controller)..addListener(_update);

      setState(() {});
    },
    onInteractionUpdate: (details) {
      widget.setPaging?.call(details.scale <= 1.0);
      _pdfscale.value = details.scale;
    },
    pagePaintCallbacks: [
      if (_pdfTextSearcher != null)
        _pdfTextSearcher!.pageTextMatchPaintCallback,
    ],
    viewerOverlayBuilder: (context, size, handleLinkTap) => [
      AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: widget.showControls && _pdfscale.value <= 1.0 ? 1.0 : 0.0,
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
          ),
          onPressed: () async {
            String? query = await showDialog<String>(
              context: context,
              builder: (context) {
                String query = '';
                return AlertDialog(
                  title: Text('Search Document'),
                  content: TextField(
                    keyboardType: TextInputType.text,
                    onChanged: (value) {
                      query = value;
                    },
                    decoration: InputDecoration(hintText: 'Enter search query'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(query);
                      },
                      child: Text('Search'),
                    ),
                  ],
                );
              },
            );
            if (query != null && query.isNotEmpty) {
              _pdfTextSearcher?.startTextSearch(query);
            }
          },
          icon: Icon(Icons.search),
        ),
      ),
      PdfViewerScrollThumb(
        key: const ValueKey('pdf-scroll-thumb'),
        margin: 0,
        controller: _pdfViewerController!,
        orientation: ScrollbarOrientation.right,
        thumbSize: _thumbSize,
        thumbBuilder: (context, thumbSize, pageNumber, controller) =>
            RepaintBoundary(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity:
                    widget.showControls &&
                        _pdfReady &&
                        _pdfscale.value <= 1.0 &&
                        pageNumber != null
                    ? 1.0
                    : 0.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: Center(
                      child: Text(
                        _pdfReady && pageNumber != null
                            ? '$pageNumber/$_pageCount'
                            : '',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    ],
  );

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPdf() async {
    _viewerInstance++;
    if (_pdfPath == null && File(widget.path).existsSync()) {
      _pdfPath = widget.path;
    } else if (_pdfPath == null && File(widget.cachePath).existsSync()) {
      _pdfPath = widget.cachePath;
    } else {
      _pdfUrl = widget.url;
    }

    setState(() {});
  }

  @override
  void initState() {
    _pdfViewerController = PdfViewerController();
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _pdfPath = null;
    _pdfUrl = null;
    _pdfViewerController = null;
    _pdfTextSearcher?.removeListener(_update);
    _pdfTextSearcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.heroTag ?? widget.key.hashCode,
      child: _pdfPath != null
          ? PdfViewer.file(
              key: ValueKey('pdf-$_pdfPath-$_viewerInstance'),
              _pdfPath!,
              controller: _pdfViewerController,
              params: _pdfViewerParams(),
            )
          : _pdfUrl != null
          ? PdfViewer.uri(
              key: ValueKey('pdf-$_pdfUrl-$_viewerInstance'),
              Uri.parse(_pdfUrl!),
              controller: _pdfViewerController,
              params: _pdfViewerParams(),
            )
          : Icon(Icons.picture_as_pdf),
    );
  }
}

class TextInteractiveMedia extends StatefulWidget {
  final String path;
  final String cachePath;
  final String url;
  final String? heroTag;
  const TextInteractiveMedia({
    super.key,
    required this.path,
    required this.cachePath,
    required this.url,
    this.heroTag,
  });

  @override
  TextInteractiveMediaState createState() => TextInteractiveMediaState();
}

class TextInteractiveMediaState extends State<TextInteractiveMedia> {
  late Future<String> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _loadText();
  }

  Future<String> _loadText() async {
    if (await File(widget.path).exists()) {
      return await File(widget.path).readAsString();
    } else if (await File(widget.cachePath).exists()) {
      return await File(widget.cachePath).readAsString();
    } else {
      final uri = Uri.parse(widget.url);
      final response = await HttpClient().getUrl(uri);
      final res = await response.close();
      return await res.transform(const Utf8Decoder()).join();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loader,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading text'));
        }
        if (snapshot.hasData) {
          return Hero(
            tag: widget.heroTag ?? widget.key.hashCode,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Material(
                type: MaterialType.transparency,
                child: SelectableText(snapshot.data!),
              ),
            ),
          );
        }
        return Center(child: Text('No data'));
      },
    );
  }
}

class InteractiveMediaView extends StatefulWidget {
  final String remoteKey;
  final String url;
  final String path;
  final String cachePath;
  final String? heroTag;
  final bool showControls;
  final Function(bool paging)? setPaging;
  final bool isActive;

  const InteractiveMediaView({
    super.key,
    required this.remoteKey,
    required this.url,
    required this.path,
    required this.cachePath,
    this.heroTag,
    this.showControls = true,
    this.setPaging,
    this.isActive = false,
  });

  @override
  InteractiveMediaViewState createState() => InteractiveMediaViewState();
}

class InteractiveMediaViewState extends State<InteractiveMediaView> {
  String get mediaType =>
      getMediaType(widget.remoteKey) ?? 'application/octet-stream';

  final PhotoViewController _photoViewController = PhotoViewController();

  Widget fallback(_, String mediaType) => Icon(
    mediaType.startsWith('image/')
        ? Icons.image
        : mediaType.startsWith('video/')
        ? Icons.videocam
        : mediaType.startsWith('audio/')
        ? Icons.audiotrack
        : mediaType.startsWith('text/')
        ? Icons.description
        : mediaType.startsWith('font/')
        ? Icons.font_download
        : mediaType.startsWith('message/')
        ? Icons.message
        : mediaType.startsWith('model/')
        ? Icons.model_training
        : mediaType.startsWith('application/')
        ? mediaType.toLowerCase() == 'application/pdf'
              ? Icons.picture_as_pdf
              : Icons.apps
        : Icons.insert_drive_file,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mediaType.startsWith('image/')) {
        widget.setPaging?.call(true);
      } else if (mediaType.toLowerCase() == 'application/pdf') {
        widget.setPaging?.call(true);
      } else {
        widget.setPaging?.call(true);
      }
    });
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return mediaType.startsWith('image/')
        ? PhotoView(
            controller: _photoViewController,
            imageProvider: HybridImageProvider(
              url: widget.url,
              path: widget.path,
              cachePath: widget.cachePath,
              cacheKey: widget.remoteKey,
            ),
            loadingBuilder: (context, event) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                () {
                  if (thumbnailCache[widget.remoteKey] != null) {
                    try {
                      return Image(
                        image: thumbnailCache[widget.remoteKey]!,
                        fit: BoxFit.contain,
                      );
                    } catch (e) {
                      // pass
                    }
                  }
                  return SizedBox.shrink();
                }(),
                if (event != null)
                  Center(
                    child: CircularProgressIndicator(
                      value: event.expectedTotalBytes != null
                          ? event.cumulativeBytesLoaded /
                                event.expectedTotalBytes!
                          : null,
                    ),
                  ),
              ],
            ),
            heroAttributes: PhotoViewHeroAttributes(
              tag: widget.heroTag ?? widget.remoteKey,
            ),
            basePosition: Alignment.center,
            enableRotation: true,
            scaleStateChangedCallback: (value) {
              widget.setPaging?.call(value == PhotoViewScaleState.initial);
            },
          )
        : mediaType.toLowerCase() == 'application/pdf'
        ? PdfInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            heroTag: widget.heroTag ?? widget.remoteKey,
            showControls: widget.showControls,
            setPaging: widget.setPaging,
          )
        : mediaType.startsWith('audio/')
        ? AudioVideoInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            mediaType: mediaType,
            heroTag: widget.heroTag ?? widget.remoteKey,
            staypaused: !widget.isActive,
          )
        : mediaType.startsWith('video/')
        ? AudioVideoInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            mediaType: mediaType,
            heroTag: widget.heroTag ?? widget.remoteKey,
            staypaused: !widget.isActive,
          )
        : mediaType.startsWith('text/')
        ? TextInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            heroTag: widget.heroTag ?? widget.remoteKey,
          )
        : Hero(
            tag: widget.heroTag ?? widget.remoteKey,
            child: fallback(context, mediaType),
          );
  }
}

class Gallery extends StatefulWidget {
  final List<GalleryProps> files;
  final int initialIndex;
  final Map<String, double> keysOffsetMap;
  final ScrollController scrollController;
  final Widget Function(BuildContext, RemoteFile) buildContextMenu;

  const Gallery({
    super.key,
    required this.files,
    this.initialIndex = 0,
    required this.keysOffsetMap,
    required this.scrollController,
    required this.buildContextMenu,
  });

  @override
  GalleryState createState() => GalleryState();
}

class GalleryState extends State<Gallery> {
  late PageController _pageController;
  late int _currentIndex;
  double dismissOffset = 0.0;

  final DraggableScrollableController contextMenuSheetController =
      DraggableScrollableController();

  final ValueNotifier<bool> _allowPaging = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(false);

  void _showContextMenu() {
    _chromeVisible.value = true;
    contextMenuSheetController.animateTo(
      0.7,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setPaging(bool paging) {
    _allowPaging.value = paging;
    _chromeVisible.value = _allowPaging.value ? _chromeVisible.value : false;
  }

  @override
  void initState() {
    _currentIndex = widget.initialIndex;
    _pageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: 1,
    );
    super.initState();
    _chromeVisible.addListener(() {
      if (_chromeVisible.value) {
        contextMenuSheetController.animateTo(
          0.13,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        contextMenuSheetController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeIn,
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeVisible.value = true;
    });
  }

  void popWithCurrentIndex() {
    _chromeVisible.value = false;
    widget.scrollController.jumpTo(
      max(
        0,
        widget.keysOffsetMap[widget.files[_currentIndex].file.key]! -
            MediaQuery.of(context).size.height / 3,
      ),
    );
    Navigator.of(context).pop(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _allowPaging.dispose();
    _chromeVisible.dispose();
    contextMenuSheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<int>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          popWithCurrentIndex();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([_allowPaging, _chromeVisible]),
              builder: (context, _) => AnimatedPadding(
                padding: _chromeVisible.value
                    ? EdgeInsets.only(
                        top:
                            kToolbarHeight + MediaQuery.of(context).padding.top,
                        bottom:
                            kToolbarHeight +
                            MediaQuery.of(context).padding.bottom,
                      )
                    : EdgeInsets.zero,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: PageView.builder(
                  controller: _pageController,
                  allowImplicitScrolling: false,
                  physics: _allowPaging.value
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: widget.files.length,
                  onPageChanged: (i) {
                    setState(() => _currentIndex = i);
                  },
                  itemBuilder: (context, index) => PointerGestureRouter(
                    allowTap: () => _allowPaging.value,
                    allowVerticalDrag: () => _allowPaging.value,
                    onTap: () {
                      _chromeVisible.value = !_chromeVisible.value;
                    },
                    onVerticalDrag: (dy) {
                      dismissOffset += dy * 0.7; // resistance
                      dismissOffset = dismissOffset.clamp(-200, 300);
                      setState(() {});
                    },
                    onVerticalDragEnd: (totalDy) {
                      if (totalDy > 100) {
                        dismissOffset = 0;
                        popWithCurrentIndex();
                      } else if (totalDy < -100) {
                        dismissOffset = 0;
                        _showContextMenu();
                      } else {
                        dismissOffset = 0;
                        setState(() {});
                      }
                    },
                    child: Transform.translate(
                      offset: Offset(0, dismissOffset),
                      child: Transform.scale(
                        scale: 1 - (dismissOffset.abs() / 1000).clamp(0, 0.5),
                        child: InteractiveMediaView(
                          heroTag: widget.files[index].file.key,
                          remoteKey: widget.files[index].file.key,
                          url: widget.files[index].url,
                          path: widget.files[index].path,
                          cachePath: Main.cachePathFromKey(
                            widget.files[index].file.key,
                          ),
                          showControls: _chromeVisible.value,
                          setPaging: _setPaging,
                          isActive: index == _currentIndex,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: _chromeVisible,
              builder: (context, _) => SizedBox(
                height: kToolbarHeight + MediaQuery.of(context).padding.top,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  offset: _chromeVisible.value
                      ? Offset.zero
                      : const Offset(0, -1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _chromeVisible.value ? 1.0 : 0.0,
                    child: AppBar(
                      backgroundColor: Theme.of(
                        context,
                      ).appBarTheme.backgroundColor,
                      title: Text(
                        "${(_currentIndex) + 1} / ${widget.files.length}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded),
                          onPressed: () {
                            _showContextMenu();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: _chromeVisible,
              builder: (context, _) => DraggableScrollableSheet(
                controller: contextMenuSheetController,
                initialChildSize: _chromeVisible.value ? 0.13 : 0.0,
                minChildSize: 0,
                maxChildSize: 0.7,
                snap: true,
                snapSizes: const [0.13, 0.7],
                snapAnimationDuration: const Duration(milliseconds: 100),
                builder: (context, scrollController) {
                  return Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: Theme.of(context).canvasColor,
                      borderRadius:
                          Theme.of(context).bottomSheetTheme.shape
                              is RoundedRectangleBorder
                          ? (Theme.of(context).bottomSheetTheme.shape
                                    as RoundedRectangleBorder)
                                .borderRadius
                          : const BorderRadius.only(
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
                            ),
                    ),
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        PinnedHeaderSliver(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            color: Theme.of(context).colorScheme.surface,
                            alignment: Alignment.center,
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurface,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: widget.buildContextMenu(
                            context,
                            widget.files[_currentIndex].file,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MediaPreview extends StatefulWidget {
  final FileProps item;
  final double? width;
  final double? height;

  const MediaPreview({super.key, required this.item, this.width, this.height});
  @override
  MediaPreviewState createState() => MediaPreviewState();
}

class MediaPreviewState extends State<MediaPreview> {
  Widget fallback(String mediaType) => Icon(
    mediaType.startsWith('image/')
        ? Icons.image
        : mediaType.startsWith('video/')
        ? Icons.videocam
        : mediaType.startsWith('audio/')
        ? Icons.audiotrack
        : mediaType.startsWith('text/')
        ? Icons.description
        : mediaType.startsWith('font/')
        ? Icons.font_download
        : mediaType.startsWith('message/')
        ? Icons.message
        : mediaType.startsWith('model/')
        ? Icons.model_training
        : mediaType.startsWith('application/')
        ? mediaType.toLowerCase() == 'application/pdf'
              ? Icons.picture_as_pdf
              : Icons.apps
        : Icons.insert_drive_file,
  );

  void setImageProvider() {
    thumbnailCache[widget.item.key] ??= HybridImageProvider(
      url: widget.item.url,
      path: Main.pathFromKey(widget.item.key),
      cachePath: Main.cachePathFromKey(widget.item.key),
      thumbPath: Main.cachePathFromKey(
        widget.item.key,
      ).replaceFirst(RegExp(r'(\.[^./\\]+)$'), '_thumb'),
      maxWidth: widget.width?.toInt(),
      maxHeight: widget.height?.toInt(),
      cacheKey: widget.item.key,
    );
  }

  @override
  void didUpdateWidget(covariant MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.key != widget.item.key) {
      setImageProvider();
    }
  }

  @override
  void initState() {
    super.initState();
    setImageProvider();
  }

  @override
  Widget build(BuildContext context) {
    return getMediaType(widget.item.key) != null &&
            getMediaType(widget.item.key)!.startsWith('image/')
        ? Image(
            image: thumbnailCache[widget.item.key]!,
            width: widget.width ?? 256,
            height: widget.height ?? 256,
            fit: BoxFit.cover,
          )
        : fallback(getMediaType(widget.item.key) ?? 'application/octet-stream');
  }
}
