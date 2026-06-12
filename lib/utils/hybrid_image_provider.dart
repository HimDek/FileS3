import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class HybridImageProvider extends ImageProvider<HybridImageProvider> {
  final String? url;
  final String? path;
  final String? cachePath;
  final String? thumbPath;
  final bool thumbnail;
  final int? maxWidth;
  final int? maxHeight;
  final String? cacheKey;

  const HybridImageProvider({
    this.url,
    this.path,
    this.cachePath,
    this.thumbPath,
    this.thumbnail = false,
    this.maxWidth,
    this.maxHeight,
    this.cacheKey,
  });

  static final Map<String, Future<ui.Codec>> _inflight = {};

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

    final future = _inflight[k] ??= _loadAsync().whenComplete(() {
      _inflight.remove(k);
    });

    return MultiFrameImageStreamCompleter(
      codec: future,
      scale: 1,
      debugLabel: 'HybridImageProvider',
    );
  }

  Future<ui.Codec> _loadAsync() async {
    Uint8List bytes;
    if (thumbnail && thumbPath != null && await File(thumbPath!).exists()) {
      bytes = await File(thumbPath!).readAsBytes();
    } else if (path != null && await File(path!).exists()) {
      bytes = await File(path!).readAsBytes();
    } else if (cachePath != null && await File(cachePath!).exists()) {
      bytes = await File(cachePath!).readAsBytes();
    } else if (thumbPath != null && await File(thumbPath!).exists()) {
      bytes = await File(thumbPath!).readAsBytes();
    } else if (url != null) {
      bytes = await _download();
    } else {
      throw StateError("No image source");
    }

    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );

    final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
      buffer,
    );

    final bool needsResize =
        (maxWidth != null || maxHeight != null) &&
        (descriptor.width > (maxWidth ?? descriptor.width) ||
            descriptor.height > (maxHeight ?? descriptor.height));

    if (needsResize) {
      final ui.Codec codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width < descriptor.height ? maxWidth : null,
        targetHeight: descriptor.height < descriptor.width ? maxHeight : null,
      );

      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;

      if (thumbPath != null) {
        await _writeThumbnail(image);
      }

      final ui.ImmutableBuffer thumbBuffer = await _imageToPngBuffer(image);

      final ui.ImageDescriptor thumbDesc = await ui.ImageDescriptor.encoded(
        thumbBuffer,
      );

      return await thumbDesc.instantiateCodec();
    } else if (cachePath != null && !thumbnail && !File(path!).existsSync()) {
      await _writeOriginal(bytes);
    }

    return await descriptor.instantiateCodec();
  }

  Future<Uint8List> _download() async {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url!,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<void> _writeThumbnail(ui.Image image) async {
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (png == null) return;

    final file = File(thumbPath!);
    await file.parent.create(recursive: true);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(png.buffer.asUint8List());
    await tmp.rename(file.path);
  }

  Future<void> _writeOriginal(Uint8List bytes) async {
    final file = File(cachePath!);
    await file.parent.create(recursive: true);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(file.path);
  }

  Future<ui.ImmutableBuffer> _imageToPngBuffer(ui.Image image) async {
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return await ui.ImmutableBuffer.fromUint8List(png!.buffer.asUint8List());
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
