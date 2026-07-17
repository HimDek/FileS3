import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:ini/ini.dart';
import 'package:mime/mime.dart';
import 'package:exif/exif.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_magic_number/file_magic_number.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/globals.dart';
import 'package:files3/models/models.dart';
import 'package:files3/day_hour_picker.dart';

Future<File?> uriToFile(
  String uriString, {
  String? remoteKey,
  void Function(int, int)? onProgress,
  HttpClient? client,
}) async {
  File file;
  Uint8List? bytes;

  final HttpClient httpClient = client ?? HttpClient();

  final uri = Uri.parse(uriString);
  try {
    final request = await httpClient.getUrl(Uri.parse(uriString));
    final response = await request.close().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Request timed out');
      },
    );

    if (remoteKey != null && response.headers['etag']?.isNotEmpty == true) {
      final file = RemoteFile.fromHttpHeaders(remoteKey, response.headers);
      final profile = Main.profileFromKey(remoteKey);
      profile?.metaDB.withTransaction((txn) async {
        RemoteFile? oldFile = (await RemoteFile.getByKey(remoteKey, txn: txn));
        profile.metaDB.addOrUpdateFile(file, oldEtag: oldFile?.etag, txn: txn);
      }, debugLabel: 'uri_to_file');
    }

    final total = response.contentLength;
    var received = 0;

    final builder = BytesBuilder(copy: false);

    await for (final chunk in response) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }

    bytes = builder.takeBytes();
  } catch (e) {
    showSnackBar(SnackBar(content: Text(e.toString())));
    bytes = null;
    return null;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }

  FileMagicNumberType type = FileMagicNumber.detectFileTypeFromBytes(bytes);

  final b = p.posix.basename(uri.path);
  String destinationPath = p.context.join(Main.cacheDir, b);

  if (!destinationPath.endsWith('.${type.toString().split('.').last}') &&
      type != FileMagicNumberType.unknown &&
      type != FileMagicNumberType.emptyFile) {
    file = File('$destinationPath.${type.toString().split('.').last}');
  } else {
    file = File(destinationPath);
  }

  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);

  return file;
}

Future<int?> expiryDialog(BuildContext context) async {
  return (await showDayHourPicker(
        context: context,
        initialDuration: const Duration(hours: 1),
        minDuration: const Duration(hours: 1),
        maxDuration: const Duration(days: 7),
      ))?.inSeconds ??
      604800;
}

Future<String?> renameDialog(
  BuildContext context,
  String currentName, {
  String title = 'Rename File',
  Iterable<String> existingNames = const [],
}) => showDialog<String>(
  context: context,
  builder: (_) {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    TextEditingController controller = TextEditingController(text: currentName);
    return StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(title),
        ),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'New Name',
              errorText:
                  existingNames
                      .where((name) => name != currentName)
                      .contains(controller.text.trim())
                  ? 'Will overwrite existing'
                  : null,
            ),
            onChanged: (value) => set(() {}),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
            onFieldSubmitted: (value) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(c, controller.text.trim());
              }
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              bool valid = formKey.currentState?.validate() ?? false;
              if (valid) Navigator.pop(c, controller.text.trim());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  },
);

Future<FileSaveLocation?> saveAsDialog(
  BuildContext context, {
  String suggestedName = '',
}) async {
  final TextEditingController nameController = TextEditingController(
    text: suggestedName,
  );
  final String? fileName = await showDialog<String?>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save As...'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(labelText: 'File Name'),
        onSubmitted: (value) {
          Navigator.of(context).pop(value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(nameController.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (fileName == null || fileName.isEmpty) {
    return null;
  }
  final String? directory = await getDirectoryPath(canCreateDirectories: true);
  if (directory != null) {
    final String path = p.context.join(directory, fileName);
    if (await File(path).exists()) {
      final bool overwrite =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('File Already Exists'),
              content: Text(
                'A file named "$fileName" already exists. Overwrite?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Overwrite'),
                ),
              ],
            ),
          ) ??
          false;

      if (overwrite != true) {
        return null;
      }
    }
    return FileSaveLocation(path);
  }
  return null;
}

Future<bool> confirmDialog(
  BuildContext context, {
  String title = 'Confirm',
  Widget? content,
  String okText = 'Confirm',
  String cancelText = 'Cancel',
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(title),
      ),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<T> showProgressDialog<T>(
  BuildContext context, {
  String title = 'Processing...',
  required ValueNotifier<double> progress,
  required ValueNotifier<String> message,
  VoidCallback? onCancel,
  required Future<T> future,
}) async {
  showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: ListenableBuilder(
        listenable: Listenable.merge([progress, message]),
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress.value),
            SizedBox(height: 16),
            Text(message.value),
          ],
        ),
      ),
      actions: [
        if (onCancel != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancel'),
          ),
      ],
    ),
  ).then((value) {
    if (value == false) {
      onCancel?.call();
    }
  });
  final result = await future;
  Navigator.of(context).pop(true);
  return result;
}

String bytesToReadable(int bytes) {
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(2)} ${suffixes[i]}';
}

String monthToString(int month) {
  return [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];
}

String timeToReadable(DateTime time) {
  final localTime = time.toLocal();
  final now = DateTime.now().toLocal();
  final diff = now.difference(localTime);
  final dateString =
      '${localTime.day.toString().padLeft(2, '0')} ${monthToString(localTime.month)} ${localTime.year}';
  final timeString =
      '${(localTime.hour % 12).toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')} ${localTime.hour >= 12 ? 'PM' : 'AM'}';
  return diff.inSeconds < 60
      ? '${diff.inSeconds}s ago'
      : diff.inMinutes < 60
      ? '${diff.inMinutes}m ago'
      : localTime.year == now.year && localTime.month == now.month
      ? localTime.day == now.day
            ? 'Today $timeString'
            : localTime.day == now.day - 1
            ? 'Yesterday $timeString'
            : dateString + timeString
      : dateString + timeString;
}

Future<Map<String, String?>> getFileMetadata(String path) async {
  final file = File(path);
  final fileStat = await file.stat();
  final bytes = await file
      .openRead(0, 64)
      .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));

  final mime = lookupMimeType(path, headerBytes: bytes.takeBytes());

  final metadata = <String, String?>{};
  metadata['created'] = fileStat.changed.toUtc().toIso8601String();
  metadata['original'] = fileStat.changed.toUtc().toIso8601String();

  // Dispatch to format-specific parser...
  switch (mime?.split('/').first) {
    case 'image':
      metadata.addEntries((await _imageMetadata(file)).entries);
      metadata['original'] =
          metadata['DateTimeOriginal'] ??
          metadata['DateTimeDigitized'] ??
          metadata['DateTime'];
      final offsetTime =
          metadata['OffsetTimeOriginal'] ??
          metadata['OffsetTimeDigitized'] ??
          metadata['OffsetTime'];
      metadata['original'] = metadata['original'] != null && offsetTime != null
          ? '${metadata['original']}$offsetTime'
          : metadata['original'];
      metadata['original'] = metadata['original']?.replaceFirstMapped(
        RegExp(r'^(\d{4}):(\d{2}):(\d{2})'),
        (m) => '${m[1]}-${m[2]}-${m[3]}',
      );
      metadata['original'] = metadata['original'] != null
          ? DateTime.parse(metadata['original']!).toUtc().toIso8601String()
          : metadata['original'];
      break;

    // case 'video':
    //   metadata['format'] = await _videoMetadata(file);
    //   break;

    // case 'audio':
    //   metadata['format'] = await _audioMetadata(file);
    //   break;
  }

  return metadata;
}

Future<Map<String, String>> _imageMetadata(File file) async {
  final bytes = await file.readAsBytes();
  final exif = await readExifFromBytes(bytes);
  final data = {
    "ImageLength":
        exif["Image ImageLength"]?.printable ??
        exif["EXIF ExifImageLength"]?.printable ??
        "",
    "ImageWidth":
        exif["Image ImageWidth"]?.printable ??
        exif["EXIF ExifImageWidth"]?.printable ??
        "",
    "ExifImageLength": exif["EXIF ExifImageLength"]?.printable ?? "",
    "ExifImageWidth": exif["EXIF ExifImageWidth"]?.printable ?? "",
    "Make": exif["Image Make"]?.printable ?? "",
    "Model": exif["Image Model"]?.printable ?? "",
    "LensMake": exif["EXIF LensMake"]?.printable ?? "",
    "LensModel": exif["EXIF LensModel"]?.printable ?? "",
    "DateTime": exif["Image DateTime"]?.printable ?? "",
    "Orientation": exif["Image Orientation"]?.printable ?? "",
    "XResolution": exif["Image XResolution"]?.printable ?? "",
    "YResolution": exif["Image YResolution"]?.printable ?? "",
    "ResolutionUnit": exif["Image ResolutionUnit"]?.printable ?? "",
    "GPSInfo": exif["Image GPSInfo"]?.printable ?? "",
    "GPS-GPSVersionID": exif["GPS GPSVersionID"]?.printable ?? "",
    "GPS-GPSLatitudeRef": exif["GPS GPSLatitudeRef"]?.printable ?? "",
    "GPS-GPSLatitude": exif["GPS GPSLatitude"]?.printable ?? "",
    "GPS-GPSLongitudeRef": exif["GPS GPSLongitudeRef"]?.printable ?? "",
    "GPS-GPSLongitude": exif["GPS GPSLongitude"]?.printable ?? "",
    "GPS-GPSAltitudeRef": exif["GPS GPSAltitudeRef"]?.printable ?? "",
    "GPS-GPSAltitude": exif["GPS GPSAltitude"]?.printable ?? "",
    "GPS-GPSTimeStamp": exif["GPS GPSTimeStamp"]?.printable ?? "",
    "GPS-GPSImgDirectionRef": exif["GPS GPSImgDirectionRef"]?.printable ?? "",
    "GPS-GPSImgDirection": exif["GPS GPSImgDirection"]?.printable ?? "",
    "GPS-GPSDate": exif["GPS GPSDate"]?.printable ?? "",
    "DateTimeDigitized": exif["EXIF DateTimeDigitized"]?.printable ?? "",
    "DateTimeOriginal": exif["EXIF DateTimeOriginal"]?.printable ?? "",
    "OffsetTimeDigitized": exif["EXIF OffsetTimeDigitized"]?.printable ?? "",
    "OffsetTimeOriginal": exif["EXIF OffsetTimeOriginal"]?.printable ?? "",
    "OffsetTime": exif["EXIF OffsetTime"]?.printable ?? "",
    "ISOSpeed": exif["EXIF ISOSpeed"]?.printable ?? "",
    "ISOSpeedRatings": exif["EXIF ISOSpeedRatings"]?.printable ?? "",
    "SensitivityType": exif["EXIF SensitivityType"]?.printable ?? "",
    "ShutterSpeedValue": exif["EXIF ShutterSpeedValue"]?.printable ?? "",
    "FNumber": exif["EXIF FNumber"]?.printable ?? "",
    "ApertureValue": exif["EXIF ApertureValue"]?.printable ?? "",
    "MaxApertureValue": exif["EXIF MaxApertureValue"]?.printable ?? "",
    "ExposureTime": exif["EXIF ExposureTime"]?.printable ?? "",
    "FocalLength": exif["EXIF FocalLength"]?.printable ?? "",
    "FocalLengthIn35mmFilm":
        exif["EXIF FocalLengthIn35mmFilm"]?.printable ?? "",
    "ExposureBiasValue": exif["EXIF ExposureBiasValue"]?.printable ?? "",
    "WhiteBalance": exif["EXIF WhiteBalance"]?.printable ?? "",
    "ColorSpace": exif["EXIF ColorSpace"]?.printable ?? "",
  };
  return data;
}

String mimeTypeFromMagic(FileMagicNumberType type) {
  switch (type) {
    case FileMagicNumberType.png:
      return 'image/png';

    case FileMagicNumberType.jpg:
      return 'image/jpeg';

    case FileMagicNumberType.gif:
      return 'image/gif';

    case FileMagicNumberType.webp:
      return 'image/webp';

    case FileMagicNumberType.heic:
      return 'image/heic';

    case FileMagicNumberType.bmp:
      return 'image/bmp';

    case FileMagicNumberType.tiff:
      return 'image/tiff';

    case FileMagicNumberType.mp3:
      return 'audio/mpeg';

    case FileMagicNumberType.wav:
      return 'audio/wav';

    case FileMagicNumberType.mp4:
      return 'video/mp4';

    case FileMagicNumberType.avi:
      return 'video/x-msvideo';

    case FileMagicNumberType.pdf:
      return 'application/pdf';

    case FileMagicNumberType.zip:
      return 'application/zip';

    case FileMagicNumberType.rar:
      return 'application/vnd.rar';

    case FileMagicNumberType.sevenZ:
      return 'application/x-7z-compressed';

    case FileMagicNumberType.tar:
      return 'application/x-tar';

    case FileMagicNumberType.sqlite:
      return 'application/vnd.sqlite3';

    case FileMagicNumberType.exe:
      return 'application/vnd.microsoft.portable-executable';

    case FileMagicNumberType.elf:
      return 'application/x-executable';

    default:
      return 'application/octet-stream';
  }
}

IconData mediaTypeIcon(String? name) {
  return (name ?? '').startsWith('image/')
      ? Icons.image
      : (name ?? '').startsWith('video/')
      ? Icons.videocam
      : (name ?? '').startsWith('audio/')
      ? Icons.audiotrack
      : (name ?? '').startsWith('text/')
      ? Icons.description
      : (name ?? '').startsWith('font/')
      ? Icons.font_download
      : (name ?? '').startsWith('message/')
      ? Icons.message
      : (name ?? '').startsWith('model/')
      ? Icons.model_training
      : (name ?? '').startsWith('application/')
      ? (name ?? '').toLowerCase() == 'application/pdf'
            ? Icons.picture_as_pdf
            : Icons.apps
      : Icons.insert_drive_file;
}

List<FileProps> sort(
  Iterable<FileProps> items,
  SortMode sortMode,
  bool foldersFirst,
) {
  List<FileProps> sortedItems = List.from(items);
  sortedItems.sort((a, b) {
    final aIsDir = p.isDir(a.key);
    final bIsDir = p.isDir(b.key);

    if (foldersFirst) {
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
    }

    switch (sortMode) {
      case SortMode.nameAsc:
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      case SortMode.nameDesc:
        return b.key.toLowerCase().compareTo(a.key.toLowerCase());
      case SortMode.dateAsc:
        DateTime aDate =
            a.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate =
            b.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      case SortMode.dateDesc:
        DateTime aDate =
            a.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bDate =
            b.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      case SortMode.sizeAsc:
        return a.size.compareTo(b.size);
      case SortMode.sizeDesc:
        return b.size.compareTo(a.size);
      case SortMode.typeAsc:
        String aExt = a.key.contains('.')
            ? p.s3.extension(a.key).toLowerCase()
            : '';
        String bExt = b.key.contains('.')
            ? p.s3.extension(b.key).toLowerCase()
            : '';
        return aExt.compareTo(bExt);
      case SortMode.typeDesc:
        String aExt = a.key.contains('.')
            ? p.s3.extension(a.key).toLowerCase()
            : '';
        String bExt = b.key.contains('.')
            ? p.s3.extension(b.key).toLowerCase()
            : '';
        return bExt.compareTo(aExt);
    }
  });
  return sortedItems;
}

Future<List<String>> keysToPathWithProgressDialog(
  BuildContext context, {
  required Iterable<String> keys,
  String title = 'Preparing files...',
}) async {
  final progress = ValueNotifier<double>(0.0);
  final message = ValueNotifier<String>('');
  final cancelNotifier = ValueNotifier<bool>(false);
  final files = await showProgressDialog(
    context,
    title: title,
    progress: progress,
    message: message,
    onCancel: () => cancelNotifier.value = true,
    future: keysToPaths(
      keys,
      onMessage: (m) => message.value = m,
      onProgress: (p) => progress.value = p,
      cancelNotifier: cancelNotifier,
    ),
  );
  progress.dispose();
  message.dispose();
  cancelNotifier.dispose();
  if (!cancelNotifier.value) {
    return files;
  }
  return [];
}

Future<List<String>> keysToPaths(
  Iterable<String> keys, {
  Function(double progress)? onProgress,
  Function(String message)? onMessage,
  ValueNotifier<bool>? cancelNotifier,
}) async {
  final HttpClient httpClient = HttpClient();
  final List<String> paths = [];
  final ikeys = keys.iterator;
  int i = 0;
  try {
    while (ikeys.moveNext()) {
      final fileExists = await File(Main.pathFromKey(ikeys.current)).exists();
      final cachePath = Main.cachePathFromKey(ikeys.current);
      final cacheExists = await File(cachePath).exists();
      if (fileExists || cacheExists) {
        onMessage?.call('Adding ${i + 1}/${keys.length}...');
        if (fileExists) {
          paths.add(Main.pathFromKey(ikeys.current));
        } else {
          paths.add(Main.cachePathFromKey(ikeys.current));
        }
      } else {
        onMessage?.call('Downloading ${i + 1}/${keys.length}...');
        try {
          final file = await uriToFile(
            Main.profileFromKey(ikeys.current)!.getUrl(ikeys.current),
            remoteKey: ikeys.current,
            onProgress: (bytesRead, totalBytes) {
              double progress = totalBytes > 0 ? bytesRead / totalBytes : 0.0;
              onProgress?.call((i + progress) / keys.length);
              if (cancelNotifier?.value ?? false) {
                throw 'Download Cancelled';
              }
            },
            client: httpClient,
          );
          if (file != null) {
            if ((await Directory(p.context.dirname(cachePath)).exists()) ==
                false) {
              await Directory(
                p.context.dirname(cachePath),
              ).create(recursive: true);
            }
            await renameOrCopyAndDelete(file, cachePath);
            paths.add(cachePath);
          }
        } catch (e) {
          if (!(cancelNotifier?.value ?? false)) {
            showSnackBar(SnackBar(content: Text('Error downloading file: $e')));
          }
        }
      }
      if (cancelNotifier?.value ?? false) {
        break;
      }
      onProgress?.call((i + 1) / keys.length);
      i++;
    }
  } catch (e) {
    if (!(cancelNotifier?.value ?? false)) {
      showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    return [];
  } finally {
    httpClient.close();
  }
  return paths;
}

final md5RegEx = RegExp(r'^[a-fA-F0-9]{32}$');
Digest etagToDigest(String etag) {
  final hex = etag.replaceAll('"', '');

  if (!md5RegEx.hasMatch(hex)) {
    throw StateError('ETag is not a single-part MD5 digest');
  }

  final bytes = List<int>.generate(
    16,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  );

  return Digest(bytes);
}

Future<void> renameOrCopyAndDelete(File file, String newPath) async {
  try {
    await file.rename(newPath);
  } catch (e) {
    await file.copy(newPath);
    await file.delete();
  }
}

class ManualNotifier extends ChangeNotifier {
  @override
  void notifyListeners() {
    super.notifyListeners();
  }
}

class UiConfigNotifier extends ChangeNotifier {
  final ValueNotifier<ThemeMode> colorMode = ValueNotifier(ThemeMode.system);
  final ValueNotifier<Color?> accentColor = ValueNotifier(null);
  final ValueNotifier<bool> ultraDark = ValueNotifier(false);
  final ValueNotifier<bool> showDirectorySummary = ValueNotifier(true);
  final ValueNotifier<bool> showDirectoryBackupConfig = ValueNotifier(true);
  final ValueNotifier<DirOrFile> showTime = ValueNotifier(DirOrFile.both);
  final ValueNotifier<DirOrFile> showSize = ValueNotifier(DirOrFile.both);
  final ValueNotifier<DirOrFile> showDownloadStatus = ValueNotifier(
    DirOrFile.both,
  );
  final ValueNotifier<bool> showType = ValueNotifier(true);
  final ValueNotifier<bool> showContent = ValueNotifier(true);

  late final Listenable listenable = Listenable.merge([
    colorMode,
    accentColor,
    ultraDark,
    showDirectorySummary,
    showDirectoryBackupConfig,
    showTime,
    showSize,
    showDownloadStatus,
    showType,
    showContent,
  ]);

  UiConfigNotifier({UiConfig? config}) {
    setValues(config);
  }

  UiConfig get uiConfig => UiConfig(
    colorMode: colorMode.value,
    accentColor: accentColor.value,
    ultraDark: ultraDark.value,
    showDirectorySummary: showDirectorySummary.value,
    showDirectoryBackupConfig: showDirectoryBackupConfig.value,
    showTime: showTime.value,
    showSize: showSize.value,
    showDownloadStatus: showDownloadStatus.value,
    showType: showType.value,
    showContent: showContent.value,
  );

  bool get fileListInfo =>
      showTime.value == DirOrFile.both ||
      showTime.value == DirOrFile.file ||
      showSize.value == DirOrFile.both ||
      showSize.value == DirOrFile.file ||
      showDownloadStatus.value == DirOrFile.both ||
      showDownloadStatus.value == DirOrFile.file ||
      showType.value;
  bool get dirListInfo =>
      showTime.value == DirOrFile.both ||
      showTime.value == DirOrFile.dir ||
      showSize.value == DirOrFile.both ||
      showSize.value == DirOrFile.dir ||
      showDownloadStatus.value == DirOrFile.both ||
      showDownloadStatus.value == DirOrFile.dir ||
      showContent.value;

  void setValues(UiConfig? config) {
    listenable.removeListener(notifyListeners);
    colorMode.value = config?.colorMode ?? ThemeMode.system;
    accentColor.value = config?.accentColor;
    ultraDark.value = config?.ultraDark ?? false;
    showDirectorySummary.value = config?.showDirectorySummary ?? true;
    showDirectoryBackupConfig.value = config?.showDirectoryBackupConfig ?? true;
    showTime.value = config?.showTime ?? DirOrFile.both;
    showSize.value = config?.showSize ?? DirOrFile.both;
    showDownloadStatus.value = config?.showDownloadStatus ?? DirOrFile.both;
    showType.value = config?.showType ?? true;
    showContent.value = config?.showContent ?? true;
    listenable.addListener(notifyListeners);
    notifyListeners();
  }
}

abstract class IniManager {
  static late final File _file;
  static ValueNotifier<Config?> config = ValueNotifier<Config?>(null);

  static Future<void> init(String dir) async {
    _file = File(p.context.join(dir, 'config.ini'));

    if (!await _file.exists()) {
      await _file.create(recursive: true);
      await _file.writeAsString(
        '[profiles]\n[directories]\n[modes]\n[ui]\n[download]\n[list_options]',
      );
    }

    final lines = await _file.readAsLines();
    config.value = Config.fromStrings(lines);
    cleanDirectories();
  }

  static Future<void> save() async {
    await _file.writeAsString(config.value!.toString());
  }

  static void cleanDirectories({String? keepKey}) {
    for (String key in config.value!.options('directories') ?? []) {
      final dirPath = config.value!.get('directories', key).toString();
      for (String k in config.value!.options('directories') ?? []) {
        if (k != key &&
            p.context.equals(
              config.value!.get('directories', k).toString(),
              dirPath,
            )) {
          if (keepKey != k) {
            config.value!.removeOption('directories', k);
          }
          if (keepKey != key) {
            config.value!.removeOption('directories', key);
          }
        }
      }
    }
  }
}

abstract class ConfigManager {
  static final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  static const _storage = FlutterSecureStorage();
  static late final SharedPreferences _sharedPreferences;

  static Future<void> init(String dir) async {
    if (!initialized.value || IniManager.config.value == null) {
      if (IniManager.config.value == null) {
        await IniManager.init(dir);
      }
      await _migrateIfNeeded();
      _sharedPreferences = await SharedPreferences.getInstance();
      initialized.value = true;
    }
  }

  static bool _is_1_0() {
    return IniManager.config.value!.sections().contains('aws') &&
        IniManager.config.value!.sections().contains('s3');
  }

  static bool _is_1_1() {
    return IniManager.config.value!.sections().contains('profiles');
  }

  // ignore: non_constant_identifier_names
  static Future<void> _migrate_1_0_to_1_1() async {
    final legacyAccessKey = await _storage.read(key: 'aws_access_key') ?? '';
    final legacySecretKey = await _storage.read(key: 'aws_secret_key') ?? '';

    final legacyRegion = IniManager.config.value?.get('aws', 'region') ?? '';
    final legacyBucket = IniManager.config.value?.get('s3', 'bucket') ?? '';
    final legacyPrefix = IniManager.config.value?.get('s3', 'prefix') ?? '';
    final legacyHost = IniManager.config.value?.get('s3', 'host') ?? '';

    if (legacyAccessKey.isNotEmpty && legacySecretKey.isNotEmpty) {
      final defaultConfig = S3Config(
        accessKey: legacyAccessKey,
        secretKey: legacySecretKey,
        region: legacyRegion,
        bucket: legacyBucket,
        prefix: legacyPrefix,
        host: legacyHost,
      );
      await saveS3Config('default', defaultConfig);
      await _storage.delete(key: 'aws_access_key');
      await _storage.delete(key: 'aws_secret_key');
      IniManager.config.value!.removeSection('aws');
      IniManager.config.value!.removeSection('s3');
      IniManager.save();
    }
  }

  static Future<void> _migrateIfNeeded() async {
    if (!_is_1_1() && _is_1_0()) {
      await _migrate_1_0_to_1_1();
    }
  }

  static Future<Map<String, S3Config>> loadS3Config() async {
    Map<String, S3Config> configs = {};
    for (String profileName
        in IniManager.config.value?.options('profiles') ?? []) {
      final accessKey =
          await _storage.read(key: 'aws_access_key_$profileName') ?? '';
      final secretKey =
          await _storage.read(key: 'aws_secret_key_$profileName') ?? '';
      final config =
          IniManager.config.value?.get('profiles', profileName) ?? '';
      final parts = config.split('|');
      final region = parts.isNotEmpty ? parts[0] : '';
      final bucket = parts.length > 1 ? parts[1] : '';
      final prefix = parts.length > 2 ? parts[2] : '';
      final host = parts.length > 3 ? parts[3] : '';
      configs[profileName] = S3Config(
        accessKey: accessKey,
        secretKey: secretKey,
        region: region,
        bucket: bucket,
        prefix: prefix,
        host: host,
      );
    }
    return configs;
  }

  static Future<void> saveS3Config(String name, S3Config config) async {
    if (!IniManager.config.value!.sections().contains("profiles")) {
      IniManager.config.value!.addSection("profiles");
    }
    final profileStr =
        '${config.region}|${config.bucket}|${config.prefix}|${config.host}';
    IniManager.config.value!.set("profiles", name, profileStr);
    await _storage.write(key: 'aws_access_key_$name', value: config.accessKey);
    await _storage.write(key: 'aws_secret_key_$name', value: config.secretKey);
    IniManager.save();
  }

  static Future<void> deleteS3Config(String name) async {
    IniManager.config.value!.removeOption("profiles", name);
    await _storage.delete(key: 'aws_access_key_$name');
    await _storage.delete(key: 'aws_secret_key_$name');
    IniManager.save();
  }

  static void setBackupMode(String key, BackupMode? mode) {
    if (!(IniManager.config.value?.sections().contains('modes') ?? true)) {
      IniManager.config.value?.addSection('modes');
    }
    if (mode == null) {
      IniManager.config.value?.removeOption('modes', key);
    } else {
      IniManager.config.value?.set('modes', key, mode.value.toString());
      if (mode == BackupMode.sync && p.s3.split(key).length == 1) {
        final toremove = <String>[];
        for (var dir
            in IniManager.config.value?.options('modes') ?? <String>[]) {
          if (p.s3.isWithin(key, dir) && dir != key) {
            toremove.add(dir);
          }
        }
        for (var dir in toremove) {
          IniManager.config.value?.removeOption('modes', dir);
        }
      }
    }
    IniManager.save();
  }

  static void setLocalDir(String key, String? path) {
    if (!IniManager.config.value!.sections().contains('directories')) {
      IniManager.config.value!.addSection('directories');
    }
    if (path == null) {
      IniManager.config.value?.removeOption('directories', key);
    } else {
      IniManager.config.value?.set('directories', key, path);
    }
    IniManager.cleanDirectories(keepKey: key);
    IniManager.save();
  }

  static UiConfig loadUiConfig() {
    final accentColorStr =
        IniManager.config.value?.get("ui", "accent_color") ?? '';

    final colorMode =
        switch (IniManager.config.value?.get("ui", "color_mode") ?? 'system') {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
    final accentColor = accentColorStr.isNotEmpty
        ? Color.fromARGB(
            int.tryParse(accentColorStr.substring(0, 2), radix: 16) ?? 0,
            int.tryParse(accentColorStr.substring(2, 4), radix: 16) ?? 0,
            int.tryParse(accentColorStr.substring(4, 6), radix: 16) ?? 0,
            int.tryParse(accentColorStr.substring(6, 8), radix: 16) ?? 0,
          )
        : null;
    final ultraDark =
        IniManager.config.value?.get("ui", "ultra_dark")?.toLowerCase() ==
        'true';
    final showDirectorySummary =
        IniManager.config.value
            ?.get("ui", "show_directory_summary")
            ?.toLowerCase() !=
        'false';
    final showDirectoryBackupConfig =
        IniManager.config.value
            ?.get("ui", "show_directory_backup_config")
            ?.toLowerCase() !=
        'false';
    final showTimeStr = IniManager.config.value
        ?.get("ui", "show_time")
        ?.toLowerCase();
    final showSizeStr = IniManager.config.value
        ?.get("ui", "show_size")
        ?.toLowerCase();
    final showDownloadStatusStr = IniManager.config.value?.get(
      "ui",
      "show_download_status",
    );
    final showType =
        IniManager.config.value?.get("ui", "show_type")?.toLowerCase() !=
        'false';
    final showContent =
        IniManager.config.value?.get("ui", "show_content")?.toLowerCase() !=
        'false';

    final showTime = switch (showTimeStr) {
      'dir' => DirOrFile.dir,
      'file' => DirOrFile.file,
      _ => DirOrFile.both,
    };

    final showSize = switch (showSizeStr) {
      'dir' => DirOrFile.dir,
      'file' => DirOrFile.file,
      _ => DirOrFile.both,
    };

    final showDownloadStatus = switch (showDownloadStatusStr?.toLowerCase()) {
      'dir' => DirOrFile.dir,
      'file' => DirOrFile.file,
      _ => DirOrFile.both,
    };

    return UiConfig(
      colorMode: colorMode,
      accentColor: accentColor,
      ultraDark: ultraDark,
      showDirectorySummary: showDirectorySummary,
      showDirectoryBackupConfig: showDirectoryBackupConfig,
      showTime: showTime,
      showSize: showSize,
      showDownloadStatus: showDownloadStatus,
      showType: showType,
      showContent: showContent,
    );
  }

  static void saveUiConfig(UiConfig config) {
    if (!IniManager.config.value!.sections().contains("ui")) {
      IniManager.config.value!.addSection("ui");
    }
    IniManager.config.value!.set("ui", "color_mode", switch (config.colorMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    IniManager.config.value!.set(
      "ui",
      "accent_color",
      config.accentColor != null
          ? ColorTools.colorCode(config.accentColor!)
          : '',
    );
    IniManager.config.value!.set(
      "ui",
      "ultra_dark",
      config.ultraDark.toString(),
    );
    IniManager.config.value!.set(
      "ui",
      "show_directory_summary",
      config.showDirectorySummary.toString(),
    );
    IniManager.config.value!.set(
      "ui",
      "show_directory_backup_config",
      config.showDirectoryBackupConfig.toString(),
    );
    IniManager.config.value!.set("ui", "show_time", config.showTime.name);
    IniManager.config.value!.set("ui", "show_size", config.showSize.name);
    IniManager.config.value!.set(
      "ui",
      "show_download_status",
      config.showDownloadStatus.name,
    );
    IniManager.config.value!.set("ui", "show_type", config.showType.toString());
    IniManager.config.value!.set(
      "ui",
      "show_content",
      config.showContent.toString(),
    );
    IniManager.save();
  }

  static TransferConfig loadTransferConfig() {
    final maxConcurrentTransfersStr =
        IniManager.config.value?.get("transfer", "max_concurrent_transfers") ??
        '5';
    final hashIgnoreStr =
        IniManager.config.value?.get("transfer", "hash_ignore_mode") ??
        'sizeChanged';

    final maxConcurrentTransfers = int.tryParse(maxConcurrentTransfersStr) ?? 5;

    return TransferConfig(
      maxConcurrentTransfers: maxConcurrentTransfers,
      hashIgnoreMode: switch (hashIgnoreStr.toLowerCase()) {
        'always' => HashIgnoreMode.always,
        'optimistic' => HashIgnoreMode.optimistic,
        _ => HashIgnoreMode.sizeChanged,
      },
    );
  }

  static void saveTransferConfig(TransferConfig config) {
    if (!IniManager.config.value!.sections().contains("transfer")) {
      IniManager.config.value!.addSection("transfer");
    }
    IniManager.config.value!.set(
      "transfer",
      "max_concurrent_transfers",
      config.maxConcurrentTransfers.toString(),
    );
    IniManager.config.value!.set(
      "transfer",
      "hash_ignore_mode",
      config.hashIgnoreMode.name,
    );
    IniManager.save();
  }

  static Iterable<MapEntry<String, String>> loadPinnedFolders() {
    try {
      return IniManager.config.value?.options("pinned_folders")?.map((key) {
            final value = IniManager.config.value!.get("pinned_folders", key);
            if (value != null) {
              final jsonValue = jsonDecode(value);
              if (jsonValue is Map<String, dynamic> &&
                  jsonValue.containsKey('path') &&
                  jsonValue['path'] is String) {
                return MapEntry(key, jsonValue['path'] as String);
              }
            }
            return null;
          }).whereType<MapEntry<String, String>>() ??
          [];
    } catch (e) {
      return [];
    }
  }

  static void savePinnedFolders(Iterable<MapEntry<String, String>> folders) {
    if (IniManager.config.value!.sections().contains("pinned_folders")) {
      IniManager.config.value!.removeSection("pinned_folders");
    }
    IniManager.config.value!.addSection("pinned_folders");
    int i = 0;
    final iFolders = folders.iterator;
    while (iFolders.moveNext()) {
      final entry = iFolders.current;
      IniManager.config.value!.set(
        "pinned_folders",
        entry.key,
        jsonEncode({"path": entry.value, "index": i}),
      );
      i++;
    }
    IniManager.save();
  }

  static List<Color> loadRecentColors() {
    try {
      final recentColorsStr =
          _sharedPreferences.getString("ui_recent_colors") ?? '[]';
      final List<dynamic> recentColorsJson = jsonDecode(recentColorsStr);
      return recentColorsJson
          .map(
            (colorCode) => Color.fromARGB(
              int.tryParse(colorCode.substring(0, 2), radix: 16) ?? 0,
              int.tryParse(colorCode.substring(2, 4), radix: 16) ?? 0,
              int.tryParse(colorCode.substring(4, 6), radix: 16) ?? 0,
              int.tryParse(colorCode.substring(6, 8), radix: 16) ?? 0,
            ),
          )
          .whereType<Color>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveRecentColors(List<Color> colors) async {
    await _sharedPreferences.setString(
      "ui_recent_colors",
      jsonEncode(colors.map((color) => ColorTools.colorCode(color))),
    );
  }

  static Future<bool> setString(String key, String value) async {
    return await _sharedPreferences.setString(key, value);
  }

  static String? getString(String key) {
    return _sharedPreferences.getString(key);
  }
}

class MyPersistentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  MyPersistentHeaderDelegate({required this.child, this.height = 32});

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant MyPersistentHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

class MyPopupMenuButton<T> extends PopupMenuButton<T> {
  MyPopupMenuButton({
    super.key,
    required Iterable<MyPopupMenuItem<T>> Function(BuildContext) itemBuilder,
    super.initialValue,
    super.onOpened,
    super.onSelected,
    super.onCanceled,
    super.tooltip,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.padding = const EdgeInsets.all(8.0),
    double menuItemsSpacing = 8.0,
    super.menuPadding,
    super.child,
    super.borderRadius,
    super.splashRadius,
    super.icon,
    super.iconSize,
    super.offset = Offset.zero,
    super.enabled = true,
    super.shape,
    super.color,
    super.iconColor,
    super.enableFeedback,
    super.constraints,
    super.position,
    super.clipBehavior = Clip.none,
    super.useRootNavigator = false,
    super.popUpAnimationStyle,
    super.routeSettings,
    super.style,
    super.requestFocus,
  }) : super(
         itemBuilder: (context) => [
           PopupMenuItem(
             enabled: false,
             child: Column(
               spacing: menuItemsSpacing,
               children: [
                 for (final item in itemBuilder(context))
                   TextButton(
                     onPressed: () {
                       if (item.enabled) {
                         item.onTap?.call();
                         onSelected?.call(item.value as T);
                         Navigator.of(context).pop(item.value);
                       }
                     },
                     style: TextButton.styleFrom(
                       padding: item.padding,
                       minimumSize: Size(double.infinity, item.height),
                       alignment: Alignment.centerLeft,
                       backgroundColor: item.value == initialValue
                           ? item.selectedBackgroundColor
                           : item.backgroundColor,
                       foregroundColor: item.value == initialValue
                           ? item.selectedForegroundColor
                           : item.foregroundColor,
                       shape: item.shape,
                     ),
                     child:
                         item.child ??
                         Text(item.value.toString(), style: item.textStyle),
                   ),
               ],
             ),
           ),
         ],
       );
}

class MyPopupMenuItem<T> {
  final Key? key;
  final T? value;
  final void Function()? onTap;
  final bool enabled;
  final double height;
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final MouseCursor? mouseCursor;
  final Widget? child;
  final OutlinedBorder? shape;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledColor;
  final Color? selectedBackgroundColor;
  final Color? selectedForegroundColor;

  MyPopupMenuItem({
    this.key,
    this.value,
    this.onTap,
    this.enabled = true,
    this.height = kMinInteractiveDimension,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0),
    this.textStyle,
    this.labelTextStyle,
    this.mouseCursor,
    required this.child,
    this.shape,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledColor,
    this.selectedBackgroundColor,
    this.selectedForegroundColor,
  });
}

class PopupMenuListTile<T> extends StatefulWidget {
  final Iterable<MyPopupMenuItem<T>> Function(BuildContext) itemBuilder;
  final T? initialValue;
  final VoidCallback? onOpened;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final EdgeInsetsGeometry? menuPadding;
  final double? splashRadius;
  final BorderRadius? borderRadius;
  final Offset offset;
  final BoxConstraints? constraints;
  final PopupMenuPosition? position;
  final Clip clipBehavior;
  final bool useRootNavigator;
  final AnimationStyle? popUpAnimationStyle;
  final RouteSettings? routeSettings;
  final bool? requestFocus;
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool? isThreeLine;
  final bool? dense;
  final VisualDensity? visualDensity;
  final ShapeBorder? shape;
  final Color? selectedColor;
  final Color? iconColor;
  final Color? textColor;
  final TextStyle? titleTextStyle;
  final TextStyle? subtitleTextStyle;
  final TextStyle? leadingAndTrailingTextStyle;
  final ListTileStyle? style;
  final EdgeInsetsGeometry? contentPadding;
  final bool enabled;
  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final MouseCursor? mouseCursor;
  final bool selected;
  final Color? focusColor;
  final Color? hoverColor;
  final Color? splashColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final Color? tileColor;
  final Color? selectedTileColor;
  final double menuItemsSpacing;
  final bool? enableFeedback;
  final double? horizontalTitleGap;
  final double? minVerticalPadding;
  final double? minLeadingWidth;
  final double? minTileHeight;
  final ListTileTitleAlignment? titleAlignment;
  final bool internalAddSemanticForOnTap;

  const PopupMenuListTile({
    super.key,
    required this.itemBuilder,
    this.initialValue,
    this.onOpened,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.menuItemsSpacing = 8.0,
    this.menuPadding,
    this.borderRadius,
    this.splashRadius,
    this.offset = Offset.zero,
    this.constraints,
    this.position,
    this.clipBehavior = Clip.none,
    this.useRootNavigator = false,
    this.popUpAnimationStyle,
    this.routeSettings,
    this.requestFocus,

    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine,
    this.dense,
    this.visualDensity,
    this.shape,
    this.style,
    this.selectedColor,
    this.iconColor,
    this.textColor,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.leadingAndTrailingTextStyle,
    this.contentPadding,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.mouseCursor,
    this.selected = false,
    this.focusColor,
    this.hoverColor,
    this.splashColor,
    this.focusNode,
    this.autofocus = false,
    this.tileColor,
    this.selectedTileColor,
    this.enableFeedback,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
    this.minTileHeight,
    this.titleAlignment,
    this.internalAddSemanticForOnTap = true,
  }) : assert(
         isThreeLine != true || subtitle != null,
         'isThreeLine can only be true if [subtitle] is provided.',
       );

  @override
  State<PopupMenuListTile<T>> createState() => PopupMenuListTileState<T>();
}

class PopupMenuListTileState<T> extends State<PopupMenuListTile<T>> {
  bool _popupVisible = false;
  final GlobalKey<PopupMenuButtonState<T>> _popupMenuKey =
      GlobalKey<PopupMenuButtonState<T>>();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: MyPopupMenuButton<T>(
        key: _popupMenuKey,
        itemBuilder: widget.itemBuilder,
        initialValue: widget.initialValue,
        onOpened: () => setState(() {
          _popupVisible = true;
        }),
        onSelected: (T value) async {
          setState(() {
            _popupVisible = false;
            widget.onSelected?.call(value);
          });
        },
        onCanceled: () => setState(() {
          _popupVisible = false;
          widget.onCanceled?.call();
        }),
        tooltip: widget.tooltip,
        elevation: widget.elevation,
        shadowColor: widget.shadowColor,
        surfaceTintColor: widget.surfaceTintColor,
        padding: EdgeInsets.zero,
        menuItemsSpacing: widget.menuItemsSpacing,
        menuPadding: widget.menuPadding,
        borderRadius: widget.borderRadius,
        splashRadius: widget.splashRadius,
        icon:
            widget.trailing ??
            Icon(
              _popupVisible
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
            ),
        offset: widget.offset,
        enabled: widget.enabled,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        enableFeedback: widget.enableFeedback,
        constraints: widget.constraints,
        position: PopupMenuPosition.under,
        clipBehavior: widget.clipBehavior,
        useRootNavigator: widget.useRootNavigator,
        popUpAnimationStyle: widget.popUpAnimationStyle,
        routeSettings: widget.routeSettings,
        requestFocus: widget.requestFocus,
      ),
      isThreeLine: widget.isThreeLine,
      dense: widget.dense,
      visualDensity: widget.visualDensity,
      shape: widget.shape,
      style: widget.style,
      selectedColor: widget.selectedColor,
      iconColor: widget.iconColor,
      textColor: widget.textColor,
      titleTextStyle: widget.titleTextStyle,
      subtitleTextStyle: widget.subtitleTextStyle,
      leadingAndTrailingTextStyle: widget.leadingAndTrailingTextStyle,
      contentPadding: widget.contentPadding,
      enabled: widget.enabled,
      onTap: () {
        setState(() {
          _popupVisible = !_popupVisible;
        });
        if (_popupVisible) {
          _popupMenuKey.currentState?.showButtonMenu();
        }
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress,
      onFocusChange: widget.onFocusChange,
      mouseCursor: widget.mouseCursor,
      selected: widget.selected,
      focusColor: widget.focusColor,
      hoverColor: widget.hoverColor,
      splashColor: widget.splashColor,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      tileColor: widget.tileColor,
      selectedTileColor: widget.selectedTileColor,
      enableFeedback: widget.enableFeedback,
      horizontalTitleGap: widget.horizontalTitleGap,
      minVerticalPadding: widget.minVerticalPadding,
      minLeadingWidth: widget.minLeadingWidth,
      minTileHeight: widget.minTileHeight,
      titleAlignment: widget.titleAlignment,
      internalAddSemanticForOnTap: widget.internalAddSemanticForOnTap,
    );
  }
}

class MyGridTile extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final bool selected;
  final Widget? topLeftBadge;
  final Widget? topRightBadge;
  final Widget? bottomLeftBadge;
  final Widget? bottomRightBadge;
  final EdgeInsets footerPadding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  const MyGridTile({
    super.key,
    required this.child,
    this.footer,
    this.selected = false,
    this.topLeftBadge,
    this.topRightBadge,
    this.bottomLeftBadge,
    this.bottomRightBadge,
    this.footerPadding = const EdgeInsets.all(8.0),
    this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.surface,
        ),
        child: GridTile(
          header: topRightBadge != null || topLeftBadge != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    topLeftBadge ?? SizedBox.shrink(),
                    topRightBadge ?? SizedBox.shrink(),
                  ],
                )
              : null,
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bottomLeftBadge != null || bottomRightBadge != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    bottomLeftBadge ?? SizedBox.shrink(),
                    bottomRightBadge ?? SizedBox.shrink(),
                  ],
                ),
              Padding(padding: footerPadding, child: footer),
            ],
          ),
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            padding: EdgeInsets.only(
              left: selected ? 8 : 0,
              right: selected ? 8 : 0,
              top: selected ? 8 : 0,
              bottom: selected ? 40 : 32,
            ),
            child: Stack(
              children: [
                AnimatedPadding(
                  duration: Duration(milliseconds: 250),
                  padding: EdgeInsets.all(selected ? 2 : 0),
                  child: Center(child: child),
                ),
                AnimatedContainer(
                  duration: Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    border: selected
                        ? Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                            width: 2,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(selected ? 4 : 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
