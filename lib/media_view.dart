import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:file_magic_number/file_magic_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie_audio/chewie_audio.dart';
import 'package:chewie/chewie.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:files3/utils/hybrid_image_provider.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/models.dart';

class GalleryProps {
  final String? key;
  final String? title;
  final String? url;
  String? path;
  final String? cachePath;

  GalleryProps({this.key, this.title, this.url, this.path, this.cachePath})
    : assert(
        path != null || url != null,
        'At least path or url must be provided',
      ),
      assert(
        key != null || title != null,
        'At least key or title must be provided',
      );
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
  final String? path;
  final String? cachePath;
  final String? url;
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
  }) : assert(
         path != null || url != null,
         'At least path or url must be provided',
       );

  @override
  AudioVideoInteractiveMediaState createState() =>
      AudioVideoInteractiveMediaState();
}

class AudioVideoInteractiveMediaState
    extends State<AudioVideoInteractiveMedia> {
  bool _pathExists = false;
  bool _cacheExists = false;

  late ChewieAudioController _chewieAudioController;
  late ChewieController _chewieController;
  late VideoPlayerController _videoController;
  late Future<bool> _loader;

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

  Future<bool> _loadAudio() async {
    _pathExists = widget.path != null && await File(widget.path!).exists();
    _cacheExists =
        widget.cachePath != null && await File(widget.cachePath!).exists();
    if (_pathExists) {
      _videoController = VideoPlayerController.file(File(widget.path!));
    } else if (_cacheExists) {
      _videoController = VideoPlayerController.file(File(widget.cachePath!));
    } else if (widget.url != null) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url!),
      );
    } else {
      return false;
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
    return true;
  }

  Future<bool> _loadVideo() async {
    _pathExists = widget.path != null && await File(widget.path!).exists();
    _cacheExists =
        widget.cachePath != null && await File(widget.cachePath!).exists();
    if (_pathExists) {
      _videoController = VideoPlayerController.file(File(widget.path!));
    } else if (_cacheExists) {
      _videoController = VideoPlayerController.file(File(widget.cachePath!));
    } else if (widget.url != null) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url!),
      );
    } else {
      return false;
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
    return true;
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
            if (snapshot.data != true) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 64),
                    SizedBox(height: 16),
                    Text('Failed to load media'),
                  ],
                ),
              );
            }
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
  final String? path;
  final String? cachePath;
  final String? url;
  final String? heroTag;
  final bool showControls;
  final Function(bool paging)? setPaging;
  final Function()? onCached;
  const PdfInteractiveMedia({
    super.key,
    this.path,
    this.cachePath,
    this.url,
    this.heroTag,
    this.showControls = true,
    this.setPaging,
    this.onCached,
  }) : assert(
         path != null || url != null,
         'At least path or url must be provided',
       );

  @override
  PdfInteractiveMediaState createState() => PdfInteractiveMediaState();
}

class PdfInteractiveMediaState extends State<PdfInteractiveMedia> {
  final TextEditingController _searchController = TextEditingController();

  bool _pathExists = false;
  bool _cacheExists = false;

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

      if (!_pathExists && !_cacheExists && widget.cachePath != null) {
        final encodedPdf = await document.encodePdf();
        File(widget.cachePath!).writeAsBytes(encodedPdf);
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
    _pathExists = widget.path != null && await File(widget.path!).exists();
    _cacheExists =
        widget.cachePath != null && await File(widget.cachePath!).exists();
    if (_pdfPath == null && _pathExists) {
      _pdfPath = widget.path;
    } else if (_pdfPath == null && _cacheExists) {
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
  final String? path;
  final String? cachePath;
  final String? url;
  final String? heroTag;
  const TextInteractiveMedia({
    super.key,
    required this.path,
    required this.cachePath,
    required this.url,
    this.heroTag,
  }) : assert(
         path != null || url != null,
         'At least path or url must be provided',
       );

  @override
  TextInteractiveMediaState createState() => TextInteractiveMediaState();
}

class TextInteractiveMediaState extends State<TextInteractiveMedia> {
  bool _pathExists = false;
  bool _cacheExists = false;
  late Future<String?> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _loadText();
  }

  Future<String?> _loadText() async {
    _pathExists = widget.path != null && await File(widget.path!).exists();
    _cacheExists =
        widget.cachePath != null && await File(widget.cachePath!).exists();
    if (_pathExists) {
      return await File(widget.path!).readAsString();
    } else if (_cacheExists) {
      return await File(widget.cachePath!).readAsString();
    } else if (widget.url != null) {
      final uri = Uri.parse(widget.url!);
      final response = await HttpClient().getUrl(uri);
      final res = await response.close();
      return await res.transform(const Utf8Decoder()).join();
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _loader,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading text'));
        }
        if (snapshot.data != null) {
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
  final String? url;
  final String? path;
  final String? cachePath;
  final String? heroTag;
  final bool showControls;
  final Function(bool paging)? setPaging;
  final Function(bool dragging)? setDragging;
  final bool isActive;
  final Function()? onCached;
  final Function(String path)? onPathChanged;

  const InteractiveMediaView({
    super.key,
    this.remoteKey,
    this.url,
    this.path,
    this.cachePath,
    this.heroTag,
    this.showControls = true,
    this.setPaging,
    this.setDragging,
    this.isActive = false,
    this.onCached,
    this.onPathChanged,
  }) : assert(
         path != null || url != null,
         'At least path or url must be provided',
       );

  @override
  InteractiveMediaViewState createState() => InteractiveMediaViewState();
}

class InteractiveMediaViewState extends State<InteractiveMediaView> {
  bool _loading = false;
  String mediaType = 'application/octet-stream';
  String? _path;

  final ValueNotifier<double> _progress = ValueNotifier<double>(0.0);
  final PhotoViewController _photoViewController = PhotoViewController();

  Widget fallback(_, String mediaType) => Icon(mediaTypeIcon(mediaType));

  Future<void> updateMediaType() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      if (widget.path != null || widget.cachePath != null) {
        mediaType =
            getMediaType(widget.path ?? widget.cachePath!) ??
            await FileMagicNumber.detectFileTypeFromPathOrBlob(
              widget.path ?? widget.cachePath!,
            ).then(
              (type) => type != FileMagicNumberType.unknown
                  ? mimeTypeFromMagic(type)
                  : 'application/octet-stream',
            );
      } else if (widget.url != null) {
        _path = (await uriToFile(
          widget.url!,
          onProgress: (d, t) => _progress.value = d / t,
        )).path;
        widget.onPathChanged?.call(_path!);
        mediaType = await FileMagicNumber.detectFileTypeFromPathOrBlob(_path!)
            .then(
              (type) => type != FileMagicNumberType.unknown
                  ? mimeTypeFromMagic(type)
                  : 'application/octet-stream',
            );
      }
    } catch (e) {
      mediaType = 'application/octet-stream';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    _path = widget.path;
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
    _progress.dispose();
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
              path: _path,
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
              tag: widget.heroTag ?? widget.remoteKey ?? _path ?? widget.url!,
            ),
            basePosition: Alignment.center,
            enableRotation: true,
            scaleStateChangedCallback: (value) {
              widget.setPaging?.call(value == PhotoViewScaleState.initial);
            },
          )
        : mediaType.toLowerCase() == 'application/pdf'
        ? PdfInteractiveMedia(
            path: _path,
            cachePath: widget.cachePath,
            url: widget.url,
            heroTag: widget.heroTag ?? widget.remoteKey ?? _path ?? widget.url,
            showControls: widget.showControls,
            setPaging: widget.setPaging,
            onCached: widget.onCached,
          )
        : mediaType.startsWith('audio/')
        ? AudioVideoInteractiveMedia(
            path: _path,
            cachePath: widget.cachePath,
            url: widget.url,
            mediaType: mediaType,
            heroTag: widget.heroTag ?? widget.remoteKey ?? _path ?? widget.url,
            staypaused: !widget.isActive,
          )
        : mediaType.startsWith('video/')
        ? AudioVideoInteractiveMedia(
            path: _path,
            cachePath: widget.cachePath,
            url: widget.url,
            mediaType: mediaType,
            heroTag: widget.heroTag ?? widget.remoteKey ?? _path ?? widget.url,
            staypaused: !widget.isActive,
          )
        : mediaType.startsWith('text/')
        ? TextInteractiveMedia(
            path: _path,
            cachePath: widget.cachePath,
            url: widget.url,
            heroTag: widget.heroTag ?? widget.remoteKey ?? _path,
          )
        : Hero(
            tag: widget.heroTag ?? widget.remoteKey ?? _path ?? widget.url!,
            child: _loading
                ? Center(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _progress,
                      builder: (context, value, child) {
                        return CircularProgressIndicator(
                          value: 0 < value && value < 1 ? value : null,
                        );
                      },
                    ),
                  )
                : fallback(context, mediaType),
          );
  }
}

class Gallery extends StatefulWidget {
  final List<GalleryProps> files;
  final int initialIndex;
  final Map<String, double> keysOffsetMap;
  final ScrollController? scrollController;
  final Widget Function(BuildContext, int)? buildContextMenu;
  final Function()? rebuildContext;

  const Gallery({
    super.key,
    required this.files,
    this.initialIndex = 0,
    this.keysOffsetMap = const {},
    this.scrollController,
    this.buildContextMenu,
    this.rebuildContext,
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
    if (_contextMenuSheetController.isAttached) {
      _contextMenuSheetController.animateTo(
        _defaultBottomSheetSize,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _hideBottomSheet() {
    if (_contextMenuSheetController.isAttached) {
      _contextMenuSheetController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeIn,
      );
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void initState() {
    _currentIndex.value = widget.initialIndex;

    _pageController = PageController(
      initialPage: widget.initialIndex,
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

  void popWithCurrentKey() {
    _chromeVisible.value = false;
    if (widget.scrollController != null &&
        widget.keysOffsetMap.containsKey(
          widget.files[_currentIndex.value].key,
        )) {
      widget.scrollController!.jumpTo(
        max(
          0,
          widget.keysOffsetMap[widget.files[_currentIndex.value].key]! -
              MediaQuery.of(context).size.height / 3,
        ),
      );
    }
    Navigator.of(context).pop(widget.files[_currentIndex.value].key);
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
    return PopScope<String>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_contextMenuSheetController.size <= _defaultBottomSheetSize) {
            popWithCurrentKey();
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
                        popWithCurrentKey();
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
                          heroTag: widget.files[index].key,
                          remoteKey: widget.files[index].key,
                          url: widget.files[index].url,
                          path: widget.files[index].path,
                          cachePath: widget.files[index].cachePath,
                          showControls: _chromeVisible.value,
                          setPaging: _setPaging,
                          setDragging: _setDragging,
                          isActive: index == _currentIndex.value,
                          onCached: widget.rebuildContext,
                          onPathChanged: (path) {
                            widget.files[index].path = path;
                            widget.rebuildContext?.call();
                          },
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
                        "${(_currentIndex.value + 1)} / ${widget.files.length}",
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
            if (widget.buildContextMenu != null &&
                widget.files[_currentIndex.value].key != null)
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
                          child: widget.buildContextMenu!(
                            context,
                            _currentIndex.value,
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
  final FileProps? item;
  final String? path;
  final double? width;
  final double? height;

  const MediaPreview({super.key, this.item, this.path, this.width, this.height})
    : assert(
        item != null || path != null,
        'Either item or path must be provided',
      );
  @override
  MediaPreviewState createState() => MediaPreviewState();
}

class MediaPreviewState extends State<MediaPreview> {
  Widget fallback(String mediaType) => Icon(mediaTypeIcon(mediaType));

  Future<void> setImageProvider() async {
    final String? key = widget.item?.key;
    if (getMediaType(key ?? widget.path!)?.startsWith('image/') ?? false) {
      thumbnailCache[key ?? widget.path!] ??= HybridImageProvider(
        url: widget.item?.url,
        path: key != null ? Main.pathFromKey(key) : widget.path!,
        cachePath: key != null ? Main.cachePathFromKey(key) : null,
        thumbPath: key != null ? Main.thumbPathFromKey(key) : null,
        thumbnail: true,
        maxWidth: widget.width?.toInt(),
        maxHeight: widget.height?.toInt(),
        cacheKey: widget.item?.key ?? widget.path!,
      );
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.item?.key ?? oldWidget.path) !=
        (widget.item?.key ?? widget.path)) {
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
    return thumbnailCache[widget.item?.key ?? widget.path!] == null
        ? fallback(
            getMediaType(widget.item?.key ?? widget.path!) ??
                'application/octet-stream',
          )
        : Image(
            image: thumbnailCache[widget.item?.key ?? widget.path!]!,
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
              getMediaType(widget.item?.key ?? widget.path!) ??
                  'application/octet-stream',
            ),
          );
  }
}
