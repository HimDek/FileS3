import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:pool/pool.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:files3/models/models.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/helpers.dart';

typedef _SimpleDecoderCallback =
    Future<ui.Codec> Function(ui.ImmutableBuffer buffer);

class HybridImageProvider extends ImageProvider<HybridImageProvider> {
  final String? key;
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
    this.key,
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

  static final Map<String, Future<ui.Codec>> _inflight = {};
  static final Set<String> _thumbInflight = {};
  static final Pool _readPool = Pool(5);
  static final Pool _thumbQueue = Pool(1);

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

  Future<ui.Codec> _loadAsync(
    StreamController<ImageChunkEvent> chunkEvents, {
    required _SimpleDecoderCallback decode,
  }) async {
    Uint8List? bytes;

    final results = await _readPool.withResource(
      () => Future.wait([
        thumbPath != null ? File(thumbPath!).exists() : Future.value(false),
        path != null ? File(path!).exists() : Future.value(false),
        cachePath != null ? File(cachePath!).exists() : Future.value(false),
      ]),
    );

    thumbExists = results[0];
    pathExists = results[1];
    cacheExists = results[2];

    try {
      if (thumbnail && thumbExists) {
        bytes = await _readPool.withResource(
          () => File(thumbPath!).readAsBytes(),
        );
      } else if (pathExists) {
        bytes = await _readPool.withResource(() => File(path!).readAsBytes());
      } else if (cacheExists) {
        bytes = await _readPool.withResource(
          () => File(cachePath!).readAsBytes(),
        );
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
      }
      if (bytes == null) {
        throw StateError("No image source");
      }
    } catch (e, s) {
      Error.throwWithStackTrace(StateError('Failed to load image: $e'), s);
    } finally {
      unawaited(
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
        }),
      );
    }

    if (thumbnail && thumbPath != null && !thumbExists) {
      unawaited(
        _writeThumbnail(bytes, maxWidth ?? 200, maxHeight ?? 200, thumbPath!),
      );
    }
    if (cachePath != null && !thumbnail && !cacheExists && !pathExists) {
      unawaited(_writeOriginal(bytes));
    }

    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );

    // if (maxWidth == null && maxHeight == null) {
    //   return decode(buffer);
    // }

    final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
      buffer,
    );
    final bool needsResize =
        (maxWidth != null || maxHeight != null) &&
        (descriptor.width > (maxWidth ?? descriptor.width) ||
            descriptor.height > (maxHeight ?? descriptor.height));

    if (key != null) {
      ConfigManager.setString(
        '${key}_resolution',
        jsonEncode({'width': descriptor.width, 'height': descriptor.height}),
      );
    }

    if (needsResize) {
      return descriptor.instantiateCodec(
        targetWidth: descriptor.width >= descriptor.height ? maxWidth : null,
        targetHeight: descriptor.width <= descriptor.height ? maxHeight : null,
      );
    }

    return decode(buffer);
  }

  Future<Uint8List> _download({Function(int, int)? onReceiveProgress}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url!));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );

      if (key != null && response.headers['etag']?.isNotEmpty == true) {
        final file = RemoteFile.fromHttpHeaders(key!, response.headers);
        final profile = Main.profileFromKey(key!);
        profile?.metaDB.withNestedTransaction((txn, localTxn) async {
          RemoteFile? oldFile = (await RemoteFile.getByKey(key!, txn: txn));
          profile.metaDB.addOrUpdateFile(
            file,
            oldEtag: oldFile?.etag,
            txn: txn,
            localTxn: localTxn,
          );
        }, 'hybrid_image_provider');
      }

      final total = response.contentLength;
      var received = 0;

      final builder = BytesBuilder(copy: false);

      await for (final chunk in response) {
        builder.add(chunk);
        received += chunk.length;
        onReceiveProgress?.call(received, total);
      }

      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  static Future<void> _writeThumbnail(
    Uint8List png,
    int maxWidth,
    int maxHeight,
    String thumbPath,
  ) async {
    if (_thumbInflight.add(thumbPath)) {
      try {
        final thumb = await _thumbQueue.withResource<TransferableTypedData>(
          () =>
              compute<(TransferableTypedData, int, int), TransferableTypedData>(
                _genThumb,
                (TransferableTypedData.fromList([png]), maxWidth, maxHeight),
              ),
        );

        final file = File(thumbPath);
        await file.parent.create(recursive: true);

        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(thumb.materialize().asUint8List());
        await tmp.rename(file.path);
      } finally {
        _thumbInflight.remove(thumbPath);
      }
    }
  }

  static TransferableTypedData _genThumb(
    (TransferableTypedData, int, int) args,
  ) {
    final png = args.$1.materialize().asUint8List();
    final maxWidth = args.$2;
    final maxHeight = args.$3;

    img.Image? ima = img.decodeImage(png);
    if (ima == null) throw StateError('Failed to decode image');

    final thumb = img.copyResize(
      ima,
      width: ima.width >= ima.height ? maxWidth : null,
      height: ima.width <= ima.height ? maxHeight : null,
      maintainAspect: true,
    );

    return TransferableTypedData.fromList([img.encodeJpg(thumb, quality: 60)]);
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
