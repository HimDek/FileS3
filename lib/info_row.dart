import 'dart:io';
import 'package:flutter/material.dart';
import 'package:files3/models.dart';
import 'package:files3/globals.dart';
import 'package:files3/helpers.dart';
import 'package:files3/utils/job.dart';
import 'package:files3/utils/path_utils.dart' as p;

class InfoRow extends StatefulWidget {
  final RemoteFile file;
  final UiConfig? uiConfig;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection? textDirection;
  final VerticalDirection verticalDirection;
  final TextBaseline? textBaseline;
  final double spacing;
  final double iconSize;
  final TextStyle? textStyle;

  const InfoRow({
    super.key,
    required this.file,
    this.uiConfig,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.min,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
    this.verticalDirection = VerticalDirection.down,
    this.textBaseline,
    this.spacing = 8.0,
    this.iconSize = 16.0,
    this.textStyle,
  });

  @override
  State<InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<InfoRow> {
  late UiConfig uiConfig;

  @override
  void initState() {
    uiConfig = widget.uiConfig ?? UiConfig();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: widget.mainAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      spacing: widget.spacing,
      children: [
        if (uiConfig.showTime)
          FutureBuilder<DateTime?>(
            future: () async {
              if (widget.file.lastModified != null) {
                return widget.file.lastModified;
              }
              final lastModified = await widget.file.getLastModified();
              return lastModified;
            }(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  widget.file.lastModified == null) {
                return Text('', style: widget.textStyle);
              }
              if (snapshot.hasError || snapshot.data == null) {
                return Text('', style: widget.textStyle);
              }
              return Text(
                timeToReadable(snapshot.data!),
                style: widget.textStyle,
              );
            },
          ),
        if (uiConfig.showSize)
          FutureBuilder<int>(
            future: () async {
              if (widget.file.size != 0) {
                return widget.file.size;
              }
              final size = await widget.file.getSize();
              return size;
            }(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  widget.file.size == 0) {
                return Text('', style: widget.textStyle);
              }
              if (snapshot.hasError || snapshot.data == null) {
                return Text('', style: widget.textStyle);
              }
              return Text(
                bytesToReadable(snapshot.data!),
                style: widget.textStyle,
              );
            },
          ),
        if (uiConfig.showDownloadStatus)
          DownloadStatusIcon(file: widget.file, size: widget.iconSize),
        if (p.isDir(widget.file.key)) ...[
          if (uiConfig.showContent)
            FutureBuilder<(int, int)>(
              future: widget.file.getCount(recursive: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    widget.file.count == (0, 0)) {
                  return Text('', style: widget.textStyle);
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return Text('', style: widget.textStyle);
                }
                final count = snapshot.data!;
                if (count.$1 == 0) {
                  return Text('${count.$2} files', style: widget.textStyle);
                }
                if (count.$2 == 0) {
                  return Text(
                    '${count.$1} subfolders',
                    style: widget.textStyle,
                  );
                }
                return Text(
                  '${count.$2} files in ${count.$1} subfolders',
                  style: widget.textStyle,
                );
              },
            ),
        ] else if (uiConfig.showType)
          Text(p.extension(widget.file.key), style: widget.textStyle),
      ],
    );
  }
}

class DownloadStatusIcon extends StatelessWidget {
  final RemoteFile file;
  final double size;
  final Color? activeColor;

  const DownloadStatusIcon({
    super.key,
    required this.file,
    this.size = 16,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: () async {
        if (p.isDir(file.key)) {
          for (var file in Main.remoteFiles.where(
            (f) => p.isWithin(file.key, f.key) && !p.isDir(f.key),
          )) {
            fileDownloadedCache[file.key] = await File(
              Main.pathFromKey(file.key) ?? file.key,
            ).exists();
          }
        } else {
          fileDownloadedCache[file.key] = await File(
            Main.pathFromKey(file.key) ?? file.key,
          ).exists();
        }
      }(),
      builder: (context, snapshot) {
        if (p.isDir(file.key)) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              fileDownloadedCache.keys.any(
                (key) =>
                    p.isWithin(file.key, key) &&
                    !p.isDir(key) &&
                    fileDownloadedCache[key] == null,
              )) {
            return Icon(Icons.hourglass_empty, size: size);
          }
          if (fileDownloadedCache.keys
              .where((key) => p.isWithin(file.key, key) && !p.isDir(key))
              .every((key) => fileDownloadedCache[key] == true)) {
            return Icon(Icons.download_done, size: size);
          } else {
            return Icon(
              Icons.cloud_download,
              color: activeColor ?? Theme.of(context).colorScheme.primary,
              size: size,
            );
          }
        } else {
          if (snapshot.connectionState == ConnectionState.waiting &&
              fileDownloadedCache[file.key] == null) {
            return Icon(Icons.hourglass_empty, size: size);
          }
          if (fileDownloadedCache[file.key] == true) {
            return Icon(Icons.download_done, size: size);
          } else {
            return Icon(
              Icons.cloud_download,
              color: activeColor ?? Theme.of(context).colorScheme.primary,
              size: size,
            );
          }
        }
      },
    );
  }
}
