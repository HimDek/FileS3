import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
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
  late UiConfig _uiConfig = widget.uiConfig ?? UiConfig();

  @override
  void didUpdateWidget(covariant InfoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteKey != widget.remoteKey) {
      // _file =
      //     (await Main.remoteFileByKey(widget.remoteKey)) ??
      //     RemoteFile(key: widget.remoteKey, etag: '');
    }
    if (oldWidget.uiConfig != widget.uiConfig) {
      _uiConfig = widget.uiConfig ?? UiConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Main.remoteFileByKey(widget.remoteKey),
      builder: (context, file) =>
          file.connectionState == ConnectionState.active ||
              !file.hasData ||
              file.data == null
          ? Row(children: [])
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
                  FutureBuilder<DateTime?>(
                    future: file.data!.getLastModified(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          file.data!.lastModified.isAfter(
                            DateTime.fromMillisecondsSinceEpoch(0),
                          )) {
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
                if (_uiConfig.showSize == DirOrFile.both ||
                    (_uiConfig.showSize == DirOrFile.file &&
                        !p.isDir(widget.remoteKey)))
                  FutureBuilder<int>(
                    future: file.data!.getSize(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          file.data!.size == 0) {
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
                if (_uiConfig.showDownloadStatus == DirOrFile.both ||
                    (_uiConfig.showDownloadStatus == DirOrFile.file &&
                        !p.isDir(widget.remoteKey)))
                  DownloadStatusIcon(
                    remoteKey: widget.remoteKey,
                    size: widget.iconSize,
                  ),
                if (p.isDir(widget.remoteKey)) ...[
                  if (_uiConfig.showContent)
                    FutureBuilder<(int, int)>(
                      future: file.data!.getCount(recursive: true),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            file.data!.count == (0, 0)) {
                          return Text('', style: widget.textStyle);
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return Text('', style: widget.textStyle);
                        }
                        final count = snapshot.data!;
                        if (count.$1 == 0) {
                          return Text(
                            '${count.$2} files',
                            style: widget.textStyle,
                          );
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
                ] else if (_uiConfig.showType)
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
  final String remoteKey;
  final double size;
  final Color? activeColor;

  const DownloadStatusIcon({
    super.key,
    required this.remoteKey,
    this.size = 16,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    RemoteFile? file;
    return FutureBuilder<void>(
      future: () async {
        file = await Main.remoteFileByKey(remoteKey);
        return file!.getDownloaded();
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            file?.downloaded == null) {
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
