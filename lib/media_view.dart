import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:file_magic_number/file_magic_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie_audio/chewie_audio.dart';
import 'package:chewie/chewie.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:files3/utils/hybrid_image_provider.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
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
  final Function()? onCached;
  const PdfInteractiveMedia({
    super.key,
    required this.path,
    required this.cachePath,
    required this.url,
    this.heroTag,
    this.showControls = true,
    this.setPaging,
    this.onCached,
  });

  @override
  PdfInteractiveMediaState createState() => PdfInteractiveMediaState();
}

class PdfInteractiveMediaState extends State<PdfInteractiveMedia> {
  final TextEditingController _searchController = TextEditingController();

  bool _pdfReady = false;
  int _pageCount = 0;
  double _initialZoom = 1.0;
  double _currentZoom = 1.0;
  Size _thumbSize = Size(40, 72);

  String? _pdfPath;
  String? _pdfUrl;
  String _selectedText = '';

  PdfViewerController? _pdfViewerController;
  PdfTextSearcher? _pdfTextSearcher;

  void _updatePaging() {
    if (_currentZoom <= _initialZoom && _selectedText.isEmpty) {
      widget.setPaging?.call(true);
    } else {
      widget.setPaging?.call(false);
    }
  }

  PdfViewerParams _pdfViewerParams() => PdfViewerParams(
    margin: 0,
    textSelectionParams: PdfTextSelectionParams(
      enabled: true,
      enableSelectionHandles: true,
      showContextMenuAutomatically: true,
      onTextSelectionChange: (textSelection) async {
        _selectedText = await textSelection.getSelectedText();
        _updatePaging();
      },
    ),
    onViewerReady: (document, controller) async {
      if (!mounted || !controller.isReady) return;

      _pdfReady = true;
      _pageCount = controller.pageCount;
      _thumbSize = Size('$_pageCount/$_pageCount'.length * 8.0, 72);

      _pdfTextSearcher ??= PdfTextSearcher(controller)..addListener(_update);

      _initialZoom = controller.currentZoom;
      _currentZoom = controller.currentZoom;
      setState(() {});

      if (!(await File(widget.path).exists()) &&
          !(await File(widget.cachePath).exists())) {
        final encodedPdf = await document.encodePdf();
        File(widget.cachePath).writeAsBytes(encodedPdf);
        widget.onCached?.call();
      }
    },
    onInteractionUpdate: (details) {
      _currentZoom = _pdfViewerController?.currentZoom ?? 1.0;
      _updatePaging();
    },
    pagePaintCallbacks: [
      if (_pdfTextSearcher != null)
        _pdfTextSearcher!.pageTextMatchPaintCallback,
    ],
    backgroundColor: Colors.black,
    loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            value: totalBytes != null ? bytesDownloaded / totalBytes : null,
          ),
          SizedBox(height: 16),
          Text(
            totalBytes != null
                ? 'Loading PDF... ${(bytesDownloaded / totalBytes * 100).toStringAsFixed(0)}%'
                : 'Loading PDF...',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    ),
    // linkHandlerParams: PdfLinkHandlerParams(
    //   onLinkTap: (pdfLink) {
    //     if (pdfLink.url != null) {
    //       launchUrlString(pdfLink.url!);
    //     }
    //   }
    // ),
    errorBannerBuilder: (context, error, stackTrace, documentRef) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          SizedBox(height: 16),
          Text(
            'Failed to load PDF',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          // GestureDetector(
          //   onTap: () {
          //     _instance++;
          //     setState(() {});
          //   },
          //   child: Container(
          //     margin: const EdgeInsets.only(top: 16),
          //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          //     decoration: BoxDecoration(
          //       color: Theme.of(context).colorScheme.primary,
          //       borderRadius: BorderRadius.circular(8),
          //     ),
          //     child: Text(
          //       'Retry',
          //       style: TextStyle(
          //         color: Theme.of(context).colorScheme.onPrimary,
          //       ),
          //     ),
          //   ),
          // ),
        ],
      ),
    ),
    viewerOverlayBuilder: (context, size, handleLinkTap) => [
      AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: widget.showControls && _currentZoom <= _initialZoom
            ? 1.0
            : 0.0,
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
          ),
          onPressed: () async {
            await showDialog<String>(
              context: context,
              builder: (context) {
                return StatefulBuilder(
                  builder: (context, setState) {
                    return AlertDialog(
                      title: Text('Search Document'),
                      content: TextField(
                        controller: _searchController,
                        keyboardType: TextInputType.text,
                        onChanged: (value) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Enter search query',
                          prefixIcon: Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _pdfTextSearcher?.resetTextSearch();
                                  },
                                )
                              : null,
                        ),
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
                            Navigator.of(context).pop(_searchController.text);
                          },
                          child: Text('Search'),
                        ),
                      ],
                    );
                  },
                );
              },
            );
            if (_searchController.text.isNotEmpty) {
              _pdfTextSearcher?.startTextSearch(_searchController.text);
            }
          },
          icon: Icon(Icons.search),
        ),
      ),
      PdfViewerScrollThumb(
        margin: 0,
        controller: _pdfViewerController!,
        orientation: ScrollbarOrientation.right,
        thumbSize: _thumbSize,
        thumbBuilder: (context, thumbSize, pageNumber, controller) =>
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity:
                  widget.showControls &&
                      _pdfReady &&
                      _currentZoom <= _initialZoom &&
                      pageNumber != null
                  ? 1.0
                  : 0.0,
              child: Padding(
                padding: const EdgeInsets.only(top: 2.0, bottom: 40),
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
    ],
  );

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPdf() async {
    if (_pdfPath == null && File(widget.path).existsSync()) {
      _pdfPath = widget.path;
    } else if (_pdfPath == null && File(widget.cachePath).existsSync()) {
      _pdfPath = widget.cachePath;
    } else {
      _pdfUrl = widget.url;
    }

    setState(() {});
  }

  Future<String?> _passwordProvider() async {
    TextEditingController controller = TextEditingController();
    bool obscure = true;

    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Password Required'),
              content: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: TextInputType.text,
                onChanged: (value) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Enter password',
                  prefixIcon: Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(controller.text);
                  },
                  child: Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    _pdfViewerController = PdfViewerController();
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pdfPath = null;
    _pdfUrl = null;
    _pdfViewerController = null;
    _pdfTextSearcher?.removeListener(_update);
    _pdfTextSearcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Hero(
          tag: widget.heroTag ?? widget.key.hashCode,
          child: Icon(Icons.picture_as_pdf),
        ),
        _pdfPath != null
            ? PdfViewer.file(
                key: ValueKey('$_pdfPath'),
                _pdfPath!,
                controller: _pdfViewerController,
                passwordProvider: _passwordProvider,
                params: _pdfViewerParams(),
              )
            : _pdfUrl != null
            ? PdfViewer.uri(
                key: ValueKey('$_pdfUrl'),
                Uri.parse(_pdfUrl!),
                controller: _pdfViewerController,
                passwordProvider: _passwordProvider,
                params: _pdfViewerParams(),
              )
            : Icon(Icons.picture_as_pdf),
      ],
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
  final String? remoteKey;
  final String url;
  final String path;
  final String cachePath;
  final String? heroTag;
  final bool showControls;
  final Function(bool paging)? setPaging;
  final Function(bool dragging)? setDragging;
  final bool isActive;
  final Function()? onCached;

  const InteractiveMediaView({
    super.key,
    this.remoteKey,
    required this.url,
    required this.path,
    required this.cachePath,
    this.heroTag,
    this.showControls = true,
    this.setPaging,
    this.setDragging,
    this.isActive = false,
    this.onCached,
  });

  @override
  InteractiveMediaViewState createState() => InteractiveMediaViewState();
}

class InteractiveMediaViewState extends State<InteractiveMediaView> {
  String mediaType = 'application/octet-stream';

  final PhotoViewController _photoViewController = PhotoViewController();

  Widget fallback(_, String mediaType) => Icon(mediaTypeIcon(mediaType));

  Future<void> updateMediaType() async {
    if (mounted) {
      mediaType =
          getMediaType(widget.path) ??
          await FileMagicNumber.detectFileTypeFromPathOrBlob(widget.path).then(
            (type) => type != FileMagicNumberType.unknown
                ? mimeTypeFromMagic(type)
                : 'application/octet-stream',
          );
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    updateMediaType();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mediaType.startsWith('image/')) {
        widget.setDragging?.call(true);
      } else if (mediaType.toLowerCase() == 'application/pdf') {
        widget.setDragging?.call(false);
      } else {
        widget.setDragging?.call(true);
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
              onCached: widget.onCached,
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
              tag: widget.heroTag ?? widget.remoteKey ?? widget.path,
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
            heroTag: widget.heroTag ?? widget.remoteKey ?? widget.path,
            showControls: widget.showControls,
            setPaging: widget.setPaging,
            onCached: widget.onCached,
          )
        : mediaType.startsWith('audio/')
        ? AudioVideoInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            mediaType: mediaType,
            heroTag: widget.heroTag ?? widget.remoteKey ?? widget.path,
            staypaused: !widget.isActive,
          )
        : mediaType.startsWith('video/')
        ? AudioVideoInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            mediaType: mediaType,
            heroTag: widget.heroTag ?? widget.remoteKey ?? widget.path,
            staypaused: !widget.isActive,
          )
        : mediaType.startsWith('text/')
        ? TextInteractiveMedia(
            path: widget.path,
            cachePath: widget.cachePath,
            url: widget.url,
            heroTag: widget.heroTag ?? widget.remoteKey ?? widget.path,
          )
        : Hero(
            tag: widget.heroTag ?? widget.remoteKey ?? widget.path,
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
  final Function() rebuildContext;

  const Gallery({
    super.key,
    required this.files,
    this.initialIndex = 0,
    required this.keysOffsetMap,
    required this.scrollController,
    required this.buildContextMenu,
    required this.rebuildContext,
  });

  @override
  GalleryState createState() => GalleryState();
}

class GalleryState extends State<Gallery> {
  double dismissOffset = 0.0;

  static const double _defaultBottomSheetSize = 0.13;
  static const double _maxBottomSheetSize = 0.7;

  late PageController _pageController;
  final DraggableScrollableController _contextMenuSheetController =
      DraggableScrollableController();
  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> _allowPaging = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _allowDragging = ValueNotifier<bool>(true);

  void _setPaging(bool paging) {
    _allowPaging.value = paging;
    _chromeVisible.value = _allowPaging.value ? _chromeVisible.value : false;
  }

  void _setDragging(bool dragging) {
    _allowDragging.value = dragging;
  }

  void _expandBottomSheet() {
    _chromeVisible.value = true;
    _contextMenuSheetController.animateTo(
      _maxBottomSheetSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _collapseBottomSheet() {
    _contextMenuSheetController.animateTo(
      _defaultBottomSheetSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _hideBottomSheet() {
    _contextMenuSheetController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeIn,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void initState() {
    _currentIndex.value = widget.initialIndex;
    _pageController = PageController(
      initialPage: _currentIndex.value,
      viewportFraction: 1,
    );
    super.initState();

    _chromeVisible.addListener(() {
      if (_chromeVisible.value) {
        _collapseBottomSheet();
      } else {
        _hideBottomSheet();
      }
    });

    _contextMenuSheetController.addListener(() {
      if (_contextMenuSheetController.size <= 0) {
        _chromeVisible.value = false;
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
        widget.keysOffsetMap[widget.files[_currentIndex.value].file.key]! -
            MediaQuery.of(context).size.height / 3,
      ),
    );
    Navigator.of(context).pop(_currentIndex.value);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _contextMenuSheetController.dispose();
    _currentIndex.dispose();
    _allowPaging.dispose();
    _chromeVisible.dispose();
    _allowDragging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<int>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_contextMenuSheetController.size <= _defaultBottomSheetSize) {
            popWithCurrentIndex();
          } else {
            _chromeVisible.value = true;
          }
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([
                _allowPaging,
                _chromeVisible,
                _allowDragging,
              ]),
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
                    setState(() => _currentIndex.value = i);
                  },
                  itemBuilder: (context, index) => PointerGestureRouter(
                    allowTap: () => _allowPaging.value,
                    allowVerticalDrag: () =>
                        _allowPaging.value && _allowDragging.value,
                    onTap: () {
                      _chromeVisible.value = !_chromeVisible.value;
                    },
                    onVerticalDrag: (dy) {
                      dismissOffset += dy * _maxBottomSheetSize; // resistance
                      dismissOffset = dismissOffset.clamp(-200, 300);
                      setState(() {});
                    },
                    onVerticalDragEnd: (totalDy) {
                      if (totalDy > 100) {
                        dismissOffset = 0;
                        popWithCurrentIndex();
                      } else if (totalDy < -100) {
                        dismissOffset = 0;
                        _expandBottomSheet();
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
                          setDragging: _setDragging,
                          isActive: index == _currentIndex.value,
                          onCached: widget.rebuildContext,
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
                      backgroundColor: Colors.black,
                      title: Text(
                        "${(_currentIndex.value) + 1} / ${widget.files.length}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded),
                          onPressed: _expandBottomSheet,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DraggableScrollableSheet(
              controller: _contextMenuSheetController,
              initialChildSize: _chromeVisible.value && _allowDragging.value
                  ? _defaultBottomSheetSize
                  : 0.0,
              minChildSize: 0,
              maxChildSize: _maxBottomSheetSize,
              snap: true,
              snapSizes: const [_defaultBottomSheetSize, _maxBottomSheetSize],
              snapAnimationDuration: const Duration(milliseconds: 100),
              builder: (context, scrollController) {
                return Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: Colors.black,
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
                          color: Colors.black,
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
                          widget.files[_currentIndex.value].file,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        backgroundColor: Colors.black,
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
  Widget fallback(String mediaType) => Icon(mediaTypeIcon(mediaType));

  Future<void> setImageProvider() async {
    thumbnailCache[widget.item.key] ??= HybridImageProvider(
      url: widget.item.url,
      path: Main.pathFromKey(widget.item.key),
      cachePath: Main.cachePathFromKey(widget.item.key),
      thumbPath: "${Main.cachePathFromKey(widget.item.key)}_thumb",
      thumbnail: true,
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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: () async {
        if (getMediaType(widget.item.key) != null &&
            getMediaType(widget.item.key)!.startsWith('image/') &&
            thumbnailCache[widget.item.key] == null) {
          await setImageProvider();
        }
      }(),
      builder: (context, snapshot) =>
          snapshot.connectionState != ConnectionState.done ||
              thumbnailCache[widget.item.key] == null
          ? fallback(
              getMediaType(widget.item.key) ?? 'application/octet-stream',
            )
          : Image(
              image: thumbnailCache[widget.item.key]!,
              width: widget.width ?? 256,
              height: widget.height ?? 256,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                if (loadingProgress.expectedTotalBytes != null &&
                    loadingProgress.cumulativeBytesLoaded >=
                        loadingProgress.expectedTotalBytes!) {
                  return child;
                }
                return Stack(
                  fit: StackFit.loose,
                  alignment: Alignment.center,
                  children: [
                    child,
                    CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ],
                );
              },
              errorBuilder: (context, error, stackTrace) => fallback(
                getMediaType(widget.item.key) ?? 'application/octet-stream',
              ),
            ),
    );
  }
}

class ExternalFileView extends StatefulWidget {
  final String path;
  final void Function()? upload;

  const ExternalFileView({super.key, required this.path, this.upload});

  @override
  State<ExternalFileView> createState() => ExternalFileViewState();
}

class ExternalFileViewState extends State<ExternalFileView> {
  static const double _defaultBottomSheetSize = 0.13;
  static const double _maxBottomSheetSize = 0.5;

  final DraggableScrollableController _contextMenuSheetController =
      DraggableScrollableController();
  final ValueNotifier<bool> _allowPaging = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _chromeVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _allowDragging = ValueNotifier<bool>(true);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);
  final ValueNotifier<String?> _path = ValueNotifier<String?>(null);

  String? _mediaType;

  void _setPaging(bool paging) {
    _allowPaging.value = paging;
    _chromeVisible.value = _allowPaging.value ? _chromeVisible.value : false;
  }

  void _setDragging(bool dragging) {
    _allowDragging.value = dragging;
  }

  void _expandBottomSheet() {
    _chromeVisible.value = true;
    _contextMenuSheetController.animateTo(
      _maxBottomSheetSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _collapseBottomSheet() {
    _contextMenuSheetController.animateTo(
      _defaultBottomSheetSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _hideBottomSheet() {
    _contextMenuSheetController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeIn,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  void _uriToPath() async {
    if (RegExp(r'^[a-zA-Z]+://').hasMatch(widget.path)) {
      _path.value = (await uriToFile(
        widget.path,
        onProgress: (d, t) => _progress.value = d / t,
      )).path;
    }
  }

  @override
  void initState() {
    _uriToPath();
    super.initState();

    _mediaType = getMediaType(widget.path);

    _chromeVisible.addListener(() {
      if (_chromeVisible.value &&
          _contextMenuSheetController.size <= _defaultBottomSheetSize) {
        _collapseBottomSheet();
      } else if (!_chromeVisible.value &&
          _contextMenuSheetController.size > 0) {
        _hideBottomSheet();
      }
    });

    _contextMenuSheetController.addListener(() {
      if (_contextMenuSheetController.size <= 0 && _chromeVisible.value) {
        _chromeVisible.value = false;
      }
    });
  }

  @override
  void dispose() {
    _contextMenuSheetController.dispose();
    _allowPaging.dispose();
    _chromeVisible.dispose();
    _allowDragging.dispose();
    _progress.dispose();
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([
              _allowPaging,
              _chromeVisible,
              _path,
              _progress,
            ]),
            builder: (context, _) => AnimatedPadding(
              padding: _chromeVisible.value
                  ? EdgeInsets.only(
                      top: kToolbarHeight + MediaQuery.of(context).padding.top,
                      bottom:
                          kToolbarHeight +
                          MediaQuery.of(context).padding.bottom,
                    )
                  : EdgeInsets.zero,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: PointerGestureRouter(
                allowTap: () => _allowPaging.value,
                allowVerticalDrag: () => false,
                onTap: () {
                  _chromeVisible.value = !_chromeVisible.value;
                },
                child: Center(
                  child: _path.value != null
                      ? InteractiveMediaView(
                          url: RegExp(r'^[a-zA-Z]+://').hasMatch(widget.path)
                              ? widget.path
                              : "file://${widget.path}",
                          path: _path.value!,
                          cachePath: _path.value!,
                          showControls: _chromeVisible.value,
                          setPaging: _setPaging,
                          setDragging: _setDragging,
                        )
                      : CircularProgressIndicator(value: _progress.value),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_chromeVisible, _path]),
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
                    backgroundColor: Colors.black,
                    title: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(p.basename(_path.value ?? widget.path)),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: _expandBottomSheet,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _contextMenuSheetController,
            initialChildSize: _chromeVisible.value && _allowDragging.value
                ? _defaultBottomSheetSize
                : 0.0,
            minChildSize: 0,
            maxChildSize: _maxBottomSheetSize,
            snap: true,
            snapSizes: const [_defaultBottomSheetSize, _maxBottomSheetSize],
            snapAnimationDuration: const Duration(milliseconds: 100),
            builder: (context, scrollController) {
              return ListenableBuilder(
                listenable: _path,
                builder: (context, _) => Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: Colors.black,
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
                          color: Colors.black,
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
                        child: Column(
                          children: [
                            ListTile(
                              visualDensity: VisualDensity.comfortable,
                              leading: Icon(mediaTypeIcon(_mediaType)),
                              title: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(widget.path),
                              ),
                              subtitle: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    if (_path.value != null) ...[
                                      Text(
                                        bytesToReadable(
                                          File(_path.value!).lengthSync(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      p.extension(_path.value ?? widget.path),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ListTile(
                              visualDensity: VisualDensity.comfortable,
                              leading: const Icon(Icons.open_in_new),
                              title: const Text('Open with...'),
                              subtitle: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(_path.value ?? widget.path),
                              ),
                              onTap: _path.value != null
                                  ? () {
                                      OpenFile.open(_path.value!);
                                    }
                                  : null,
                            ),
                            ListTile(
                              visualDensity: VisualDensity.comfortable,
                              leading: const Icon(Icons.share),
                              title: const Text('Share'),
                              onTap: _path.value != null
                                  ? () {
                                      SharePlus.instance.share(
                                        ShareParams(
                                          files: <XFile>[XFile(_path.value!)],
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                            if (widget.upload != null)
                              ListTile(
                                visualDensity: VisualDensity.comfortable,
                                leading: const Icon(Icons.upload),
                                title: const Text('Upload'),
                                onTap: _path.value != null
                                    ? widget.upload
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: Colors.black,
    );
  }
}
