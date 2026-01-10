import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:files3/models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:chewie_audio/chewie_audio.dart';
import 'package:enough_media/enough_media.dart';
import 'package:files3/helpers.dart';

class GalleryProps {
  final RemoteFile file;
  final String title;
  final String? description;
  final String url;
  final String path;

  GalleryProps({
    required this.file,
    required this.title,
    this.description,
    required this.url,
    required this.path,
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
  final MediaProvider mediaProvider;
  final String? heroTag;
  final bool staypaused;
  const AudioVideoInteractiveMedia({
    super.key,
    required this.mediaProvider,
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
    _loader = widget.mediaProvider.isAudio ? _loadAudio() : _loadVideo();
  }

  @override
  void dispose() {
    _chewieAudioController.dispose();
    _chewieController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  Future<ChewieAudioController> _loadAudio() async {
    final provider = widget.mediaProvider;
    if (provider is FileMediaProvider) {
      _videoController = VideoPlayerController.file(provider.file);
    } else if (provider is UrlMediaProvider) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(provider.url),
      );
    } else if (provider is AssetMediaProvider) {
      _videoController = VideoPlayerController.asset(provider.assetName);
    } else {
      throw StateError('Unsupported media provider $provider');
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
    final provider = widget.mediaProvider;
    if (provider is FileMediaProvider) {
      _videoController = VideoPlayerController.file(provider.file);
    } else if (provider is UrlMediaProvider) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(provider.url),
      );
    } else if (provider is AssetMediaProvider) {
      _videoController = VideoPlayerController.asset(provider.assetName);
    } else {
      throw StateError('Unsupported media provider $provider');
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
            return widget.mediaProvider.isAudio
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
          tag: widget.heroTag ?? widget.mediaProvider.hashCode,
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
          tag: widget.heroTag ?? widget.mediaProvider.hashCode,
          child: Chewie(controller: _chewieController),
        ),
      ),
    );
  }
}

class InteractiveMediaView extends StatefulWidget {
  final MediaProvider mediaProvider;
  final String? heroTag;
  final Function(bool paging)? setPaging;
  final Function(bool contextMenu)? setContextMenu;
  final bool isActive;

  const InteractiveMediaView({
    super.key,
    this.heroTag,
    required this.mediaProvider,
    this.setPaging,
    this.setContextMenu,
    this.isActive = false,
  });

  @override
  InteractiveMediaViewState createState() => InteractiveMediaViewState();
}

class InteractiveMediaViewState extends State<InteractiveMediaView> {
  late MediaProvider _provider;
  bool _loading = true;
  double _progress = 0.0;
  double pdfscale = 1;

  final PhotoViewController _photoViewController = PhotoViewController();
  final PhotoViewScaleStateController _photoViewScaleStateController =
      PhotoViewScaleStateController();
  final PdfViewerController _pdfViewerController = PdfViewerController();

  // Future<void> _loadMedia() async {
  //   if (_provider is MemoryMediaProvider) {
  //     setState(() {
  //       _loading = false;
  //     });
  //     return;
  //   }
  //   if (_provider is MyUrlMediaProvider) {
  //     _provider = await ((_provider as MyUrlMediaProvider)).toMemoryProvider(
  //       onProgress: (int received, int total) {
  //         _progress = total != 0 ? received / total : 0.0;
  //       },
  //     );
  //   } else {
  //     _provider = await _provider.toMemoryProvider();
  //   }
  //   setState(() {
  //     _loading = false;
  //   });
  // }

  Widget fallback(_, MediaProvider media, double progress) => Icon(
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
  );

  @override
  void initState() {
    super.initState();
    _provider = widget.mediaProvider;
    // _loadMedia();
    // Force correct default state when page becomes active
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_provider.isImage) {
        widget.setContextMenu?.call(true);
        widget.setPaging?.call(true);
      } else if (_provider.mediaType == 'application/pdf') {
        widget.setContextMenu?.call(false);
        widget.setPaging?.call(true);
      } else {
        widget.setContextMenu?.call(true);
        widget.setPaging?.call(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return
    // _loading
    //     ? fallback(context, _provider, _progress)
    //     :
    _provider.isImage
        ? PhotoView(
            controller: _photoViewController,
            imageProvider: _provider is UrlMediaProvider
                ? NetworkImage((_provider as UrlMediaProvider).url)
                : FileImage((_provider as FileMediaProvider).file),
            heroAttributes: PhotoViewHeroAttributes(
              tag: widget.heroTag ?? _provider.hashCode,
            ),
            basePosition: Alignment.center,
            enableRotation: true,
            scaleStateChangedCallback: (value) {
              widget.setPaging?.call(value == PhotoViewScaleState.initial);
              widget.setContextMenu?.call(true);
            },
          )
        : _provider.mediaType == 'application/pdf'
        ? Hero(
            tag: widget.heroTag ?? _provider.hashCode,
            child:
                _provider is UrlMediaProvider || _provider is FileMediaProvider
                ? PdfViewer(
                    controller: _pdfViewerController,
                    params: PdfViewerParams(
                      enableTextSelection: true,
                      onInteractionUpdate: (details) {
                        widget.setPaging?.call(details.scale <= 1.0);
                        widget.setContextMenu?.call(false);
                        setState(() {
                          pdfscale = details.scale;
                        });
                      },
                    ),
                    _provider is UrlMediaProvider
                        ? PdfDocumentRefUri(
                            Uri.parse((_provider as UrlMediaProvider).url),
                          )
                        : PdfDocumentRefFile(
                            (_provider as FileMediaProvider).file.path,
                          ),
                  )
                : fallback(context, _provider, _progress),
          )
        : _provider.isAudio
        ? AudioVideoInteractiveMedia(
            mediaProvider: _provider,
            heroTag: widget.heroTag,
            staypaused: !widget.isActive,
          )
        : _provider.isVideo
        ? AudioVideoInteractiveMedia(
            mediaProvider: _provider,
            heroTag: widget.heroTag,
            staypaused: !widget.isActive,
          )
        : _provider.isText
        ? Hero(
            tag: widget.heroTag ?? _provider.hashCode,
            child: TextInteractiveMedia(mediaProvider: _provider),
          )
        : _provider is TextMediaProvider
        ? Hero(
            tag: widget.heroTag ?? _provider.hashCode,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Material(
                type: MaterialType.transparency,
                child: SelectableText((_provider as TextMediaProvider).text),
              ),
            ),
          )
        : Hero(
            tag: widget.heroTag ?? _provider.hashCode,
            child: fallback(context, _provider, _progress),
          );
  }
}

class Gallery extends StatefulWidget {
  final List<GalleryProps> files;
  final int initialIndex;
  final Widget Function(RemoteFile file)? buildContextMenu;

  const Gallery({
    super.key,
    required this.files,
    this.initialIndex = 0,
    this.buildContextMenu,
  });

  @override
  GalleryState createState() => GalleryState();
}

class GalleryState extends State<Gallery> {
  late PageController _pageController;
  final ValueNotifier<bool> chromeVisible = ValueNotifier(false);
  final DraggableScrollableController sheetController =
      DraggableScrollableController();
  late int _currentIndex;
  bool _allowPaging = true;
  bool _allowContextMenu = true;
  double dismissOffset = 0.0;

  void _showContextMenu() {
    sheetController.animateTo(
      0.7,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setPaging(bool paging) {
    setState(() {
      _allowPaging = paging;
      chromeVisible.value = _allowPaging ? chromeVisible.value : false;
    });
  }

  void _setContextMenu(bool allow) {
    setState(() {
      _allowContextMenu = allow;
    });
  }

  Widget _grabHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(12),
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white30,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _itemBuilder(BuildContext context, int index) {
    return InteractiveMediaView(
      heroTag: widget.files[index].file.key,
      mediaProvider: getMediaProvider(
        name: widget.files[index].title,
        mediaType:
            getMediaType(widget.files[index].file.key) ??
            'application/octet-stream',
        url: widget.files[index].url,
        path: widget.files[index].path,
        size: widget.files[index].file.size,
        description: widget.files[index].description,
      ),
      setPaging: _setPaging,
      setContextMenu: _setContextMenu,
      isActive: index == _currentIndex,
    );
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _currentIndex = widget.initialIndex;
    });
    _pageController = PageController(initialPage: _currentIndex);
    chromeVisible.addListener(() {
      if (chromeVisible.value) {
        sheetController.animateTo(
          0.125,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        sheetController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeIn,
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: chromeVisible,
      builder: (context, value, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: AnimatedSlide(
              offset: value ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              child: AppBar(
                backgroundColor: Colors.black,
                title: Text("${_currentIndex + 1} / ${widget.files.length}"),
              ),
            ),
          ),
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                physics: _allowPaging
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: widget.files.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) => PointerGestureRouter(
                  allowTap: () => _allowPaging,
                  allowVerticalDrag: () => _allowPaging && _allowContextMenu,
                  onTap: () {
                    chromeVisible.value = !chromeVisible.value;
                  },
                  onVerticalDrag: (dy) {
                    dismissOffset += dy * 0.7; // resistance
                    dismissOffset = dismissOffset.clamp(-200, 300);
                    setState(() {});
                  },
                  onVerticalDragEnd: (totalDy) {
                    if (totalDy > 100) {
                      chromeVisible.value = false;
                      Navigator.pop(context);
                      dismissOffset = 0;
                    } else if (totalDy < -100) {
                      chromeVisible.value = true;
                      _showContextMenu();
                      dismissOffset = 0;
                    } else {
                      dismissOffset = 0;
                      setState(() {});
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, dismissOffset),
                    child: Transform.scale(
                      scale: 1 - (dismissOffset.abs() / 1000).clamp(0, 0.5),
                      child: _itemBuilder(context, index),
                    ),
                  ),
                ),

                //  GestureDetector(
                //   behavior: HitTestBehavior.opaque,
                //   onTap: () {
                //     chromeVisible.value = _allowPaging
                //         ? !chromeVisible.value
                //         : false;
                //   },
                //   onVerticalDragEnd: _allowPaging && _allowContextMenu
                //       ? (details) {
                //           if (details.primaryVelocity != null &&
                //               details.primaryVelocity! > 10) {
                //             Navigator.of(context).pop();
                //           }
                //           if (details.primaryVelocity != null &&
                //               details.primaryVelocity! < -10) {
                //             chromeVisible.value = true;
                //             sheetController.animateTo(
                //               0.7,
                //               duration: const Duration(milliseconds: 260),
                //               curve: Curves.easeOut,
                //             );
                //             SystemChrome.setEnabledSystemUIMode(
                //               SystemUiMode.edgeToEdge,
                //             );
                //           }
                //         }
                //       : null,
                //   child: _itemBuilder(context, index),
                // ),
              ),
              DraggableScrollableSheet(
                controller: sheetController,
                initialChildSize: 0,
                minChildSize: 0,
                maxChildSize: 0.7,
                snap: true,
                snapSizes: const [0.125, 0.7],
                snapAnimationDuration: const Duration(milliseconds: 100),
                builder: (context, scrollController) {
                  return Container(
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
                    child: ListView(
                      padding: EdgeInsets.zero,
                      controller: scrollController,
                      children: [
                        _grabHandle(),
                        widget.buildContextMenu != null
                            ? widget.buildContextMenu!(
                                widget.files[_currentIndex].file,
                              )
                            : const SizedBox.shrink(),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class MediaPreview extends StatefulWidget {
  final MediaProvider mediaProvider;
  final double? width;
  final double? height;
  final void Function(MediaProvider, String)? onContextMenuSelected;

  const MediaPreview({
    super.key,
    required this.mediaProvider,
    this.width,
    this.height,
    this.onContextMenuSelected,
  });

  @override
  MediaPreviewState createState() => MediaPreviewState();
}

class MediaPreviewState extends State<MediaPreview> {
  late MediaProvider _provider;
  bool _isLoading = true;
  double _progress = 0.0;

  // Future<void> _loadMedia() async {
  //   if (_provider is MemoryMediaProvider) {
  //     setState(() {
  //       _isLoading = false;
  //     });
  //     return;
  //   }
  //   if (_provider is MyUrlMediaProvider) {
  //     _provider = await ((_provider as MyUrlMediaProvider)).toMemoryProvider(
  //       onProgress: (int received, int total) {
  //         _progress = total != 0 ? received / total : 0.0;
  //       },
  //     );
  //   } else {
  //     _provider = await _provider.toMemoryProvider();
  //   }
  //   setState(() {
  //     _isLoading = false;
  //   });
  // }

  Widget fallback(_, media, progress) => Icon(
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
  );

  @override
  void initState() {
    super.initState();
    _provider = widget.mediaProvider;
    // _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    return _provider.isImage
        ? (_provider is UrlMediaProvider)
              ? Image(
                  image: CachedNetworkImageProvider(
                    (_provider as UrlMediaProvider).url,
                  ),
                  fit: BoxFit.cover,
                )
              : Image(
                  image: FileImage((_provider as FileMediaProvider).file),
                  fit: BoxFit.cover,
                )
        : _provider.mediaType == 'application/pdf'
        ? fallback(context, _provider, _progress)
        : _provider.isAudio
        ? fallback(context, _provider, _progress)
        : _provider.isVideo
        ? fallback(context, _provider, _progress)
        : fallback(context, _provider, _progress);
  }
}

Future<void> downloadMediaFile({
  required String url,
  required String savePath,
  required Function(int, int) onProgress,
}) async {
  final dio = Dio();

  try {
    await dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          onProgress(received, total);
        }
      },

      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status! < 500,
      ),
    );
  } catch (e) {
    rethrow;
  }
}

MediaProvider getMediaProvider({
  required String name,
  required String mediaType,
  required String url,
  required String path,
  int? size,
  String? description,
}) {
  if (File(path).existsSync()) {
    return FileMediaProvider(
      name,
      mediaType,
      File(path),
      description: description,
    );
  }
  return MyUrlMediaProvider(
    name,
    mediaType,
    url,
    path,
    size: size,
    description: description,
  );
}

class MyUrlMediaProvider extends UrlMediaProvider {
  final String path;

  const MyUrlMediaProvider(
    super.name,
    super.mediaType,
    super.url,
    this.path, {
    super.size,
    super.description,
  });

  @override
  Future<MemoryMediaProvider> toMemoryProvider({
    void Function(int, int)? onProgress,
  }) async {
    downloadMediaFile(
      url: url,
      savePath: path,
      onProgress: onProgress ?? (int received, int total) {},
    );
    final result = File(path).existsSync()
        ? File(path).readAsBytesSync()
        : null;
    if (result != null) {
      return MemoryMediaProvider(
        name,
        mediaType,
        result,
        description: description,
      );
    }
    throw StateError('Unable to download $url');
  }
}

class FileMediaProvider extends MediaProvider {
  final File file;

  FileMediaProvider(
    String name,
    String mediaType,
    this.file, {
    String? description,
  }) : super(name, mediaType, file.lengthSync(), description: description);

  @override
  Future<TextMediaProvider> toTextProvider() {
    return toMemoryProvider().then((p) => p.toTextProvider());
  }

  @override
  Future<MemoryMediaProvider> toMemoryProvider({
    void Function(int, int)? onProgress,
  }) async {
    final data = file.readAsBytesSync();
    return MemoryMediaProvider(name, mediaType, data, description: description);
  }

  @override
  int get hashCode => file.path.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileMediaProvider &&
          runtimeType == other.runtimeType &&
          file.path == other.file.path;
}
