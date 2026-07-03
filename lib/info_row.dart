import 'dart:async';
import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/models.dart';
import 'package:files3/helpers.dart';

class InfoRow extends StatefulWidget {
  final String remoteKey;
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
    required this.remoteKey,
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
  RemoteFile? _file;
  late UiConfig _uiConfig = widget.uiConfig ?? UiConfig();

  @override
  void didUpdateWidget(covariant InfoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteKey != widget.remoteKey) {
      _file = null;
    }
    if (oldWidget.uiConfig != widget.uiConfig) {
      _uiConfig = widget.uiConfig ?? UiConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: () async {
        _file = await RemoteFile.getByKey(widget.remoteKey);
      }(),
      builder: (context, _) => _file == null
          ? SizedBox.shrink()
          : Row(
              mainAxisAlignment: widget.mainAxisAlignment,
              mainAxisSize: widget.mainAxisSize,
              crossAxisAlignment: widget.crossAxisAlignment,
              textDirection: widget.textDirection,
              verticalDirection: widget.verticalDirection,
              spacing: widget.spacing,
              children: [
                if (_uiConfig.showTime == DirOrFile.both ||
                    (_uiConfig.showTime == DirOrFile.file &&
                        !p.isDir(widget.remoteKey)))
                  if (_file!.lastModified !=
                      DateTime.fromMillisecondsSinceEpoch(0))
                    Text(
                      timeToReadable(_file!.lastModified),
                      style: widget.textStyle,
                    ),
                if (_uiConfig.showSize == DirOrFile.both ||
                    (_uiConfig.showSize == DirOrFile.file &&
                        !p.isDir(widget.remoteKey)))
                  if (_file!.size != 0)
                    Text(bytesToReadable(_file!.size), style: widget.textStyle),
                if (_uiConfig.showDownloadStatus == DirOrFile.both ||
                    (_uiConfig.showDownloadStatus == DirOrFile.file &&
                        !p.isDir(widget.remoteKey)))
                  DownloadStatusIcon(fileFuture: _file, size: widget.iconSize),
                if (p.isDir(widget.remoteKey))
                  if (_uiConfig.showContent)
                    _file!.count == (0, 0)
                        ? SizedBox.shrink()
                        : _file!.count.$1 == 0
                        ? Text(
                            '${_file!.count.$2} files',
                            style: widget.textStyle,
                          )
                        : _file!.count.$2 == 0
                        ? Text(
                            '${_file!.count.$1} subfolders',
                            style: widget.textStyle,
                          )
                        : Text(
                            '${_file!.count.$2} files in ${_file!.count.$1} subfolders',
                            style: widget.textStyle,
                          )
                  else if (_uiConfig.showType)
                    Text(
                      p.s3.extension(widget.remoteKey),
                      style: widget.textStyle,
                    ),
              ],
            ),
    );
  }
}

class DownloadStatusIcon extends StatelessWidget {
  final FutureOr<RemoteFile?> fileFuture;
  final double size;
  final Color? activeColor;

  const DownloadStatusIcon({
    super.key,
    required this.fileFuture,
    this.size = 16,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    RemoteFile? file = fileFuture is RemoteFile
        ? fileFuture as RemoteFile
        : null;
    return FutureBuilder<void>(
      future: () async {
        file = await fileFuture;
        await file!.getDownloaded();
      }(),
      builder: (context, snapshot) {
        if (file?.downloaded == null) {
          return Icon(Icons.hourglass_empty, size: size);
        }
        if (file?.downloaded == true) {
          return Icon(Icons.download_done, size: size);
        } else {
          return Icon(
            Icons.cloud_download,
            color: activeColor ?? Theme.of(context).colorScheme.primary,
            size: size,
          );
        }
      },
    );
  }
}
