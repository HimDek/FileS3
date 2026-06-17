import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

typedef _SimpleDecoderCallback = Future<Codec> Function(ImmutableBuffer buffer);

class HybridImageProvider extends ImageProvider<HybridImageProvider> {
  final String? url;
  final String? path;
  final String? cachePath;
  final String? thumbPath;
  final bool thumbnail;
  final int? maxWidth;
  final int? maxHeight;
  final String? cacheKey;
  final Function()? onCached;

  HybridImageProvider({
    this.url,
    this.path,
    this.cachePath,
    this.thumbPath,
    this.thumbnail = false,
    this.maxWidth,
    this.maxHeight,
    this.cacheKey,
    this.onCached,
  });

  static final Map<String, Future<Codec>> _inflight = {};
  bool pathExists = false;
  bool cacheExists = false;
  bool thumbExists = false;

  @override
  Future<HybridImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    HybridImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final String k = cacheKey ?? url ?? path ?? thumbPath ?? cachePath!;
    final chunkEvents = StreamController<ImageChunkEvent>();

    final future = _inflight[k] ??= _loadAsync(chunkEvents, decode: decode)
        .whenComplete(() {
          _inflight.remove(k);
        });

    return MultiFrameImageStreamCompleter(
      codec: future,
      chunkEvents: chunkEvents.stream,
      scale: 1,
      debugLabel: key.url,
    );
  }

  Future<Codec> _loadAsync(
    StreamController<ImageChunkEvent> chunkEvents, {
    required _SimpleDecoderCallback decode,
  }) async {
    Uint8List bytes;

    pathExists = path != null && File(path!).existsSync();
    cacheExists = cachePath != null && File(cachePath!).existsSync();
    thumbExists = thumbPath != null && File(thumbPath!).existsSync();

    if (thumbnail && thumbExists) {
      bytes = File(thumbPath!).readAsBytesSync();
    } else if (pathExists) {
      bytes = File(path!).readAsBytesSync();
    } else if (cacheExists) {
      bytes = File(cachePath!).readAsBytesSync();
    } else if (url != null) {
      bytes = await _download(
        onReceiveProgress: (received, total) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: received,
              expectedTotalBytes: total,
            ),
          );
        },
      );
    } else {
      throw StateError("No image source");
    }

    final ImmutableBuffer buffer = await ImmutableBuffer.fromUint8List(bytes);
    final ImageDescriptor descriptor = await ImageDescriptor.encoded(buffer);

    final bool needsResize =
        (maxWidth != null || maxHeight != null) &&
        (descriptor.width > (maxWidth ?? descriptor.width) ||
            descriptor.height > (maxHeight ?? descriptor.height));

    if (needsResize) {
      final Codec codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width < descriptor.height ? maxWidth : null,
        targetHeight: descriptor.height < descriptor.width ? maxHeight : null,
      );

      final FrameInfo frame = await codec.getNextFrame();
      final Image image = frame.image;

      final Uint8List? png = (await image.toByteData(
        format: ImageByteFormat.png,
      ))?.buffer.asUint8List();
      final ImmutableBuffer resultBuffer = await ImmutableBuffer.fromUint8List(
        png!,
      );

      if (thumbnail && thumbPath != null && !thumbExists) {
        _writeThumbnail(png);
      }

      return await decode(resultBuffer);
    } else if (cachePath != null && !thumbnail && !cacheExists && !pathExists) {
      _writeOriginal(bytes);
    }

    chunkEvents.close().catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'painting library',
          context: ErrorDescription(
            'while closing chunkEvents stream in NetworkImage.load',
          ),
        ),
      );
    });

    return await descriptor.instantiateCodec();
  }

  Future<Uint8List> _download({Function(int, int)? onReceiveProgress}) async {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url!,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
    );
    return Uint8List.fromList(response.data!);
  }

  Future<void> _writeThumbnail(Uint8List png) async {
    img.Image? ima = img.decodeImage(png);
    if (ima == null) return;

    final file = File(thumbPath!);
    await file.parent.create(recursive: true);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(img.encodeJpg(ima, quality: 40));
    await tmp.rename(file.path);
  }

  Future<void> _writeOriginal(Uint8List bytes) async {
    final file = File(cachePath!);
    await file.parent.create(recursive: true);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(file.path);
    onCached?.call();
  }

  @override
  bool operator ==(Object other) =>
      other is HybridImageProvider &&
      other.url == url &&
      other.path == path &&
      other.cachePath == cachePath &&
      other.thumbPath == thumbPath &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      other.cacheKey == cacheKey;

  @override
  int get hashCode => Object.hash(
    url,
    path,
    cachePath,
    thumbPath,
    maxWidth,
    maxHeight,
    cacheKey,
  );
}
