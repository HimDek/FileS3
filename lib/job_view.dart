import 'package:mime/mime.dart';
import 'package:files3/helpers.dart';
import 'package:files3/media_view.dart';
import 'package:flutter/material.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models/models.dart';

class JobView extends StatefulWidget {
  final Job job;
  final String? relativeTo;
  final bool grid;

  const JobView({
    super.key,
    required this.job,
    this.relativeTo,
    this.grid = false,
  });

  @override
  JobViewState createState() => JobViewState();
}

class JobViewState extends State<JobView> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.job.status,
        widget.job.bytesCompleted,
        widget.job.statusMsg,
      ]),
      builder: (context, child) => widget.grid
          ? GestureDetector(
              onTap: widget.job.startable()
                  ? () {
                      widget.job.start();
                    }
                  : widget.job.stoppable()
                  ? () {
                      widget.job.stop();
                    }
                  : null,
              child: MyGridTile(
                footer: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.job.status.value != JobStatus.completed)
                      LinearProgressIndicator(
                        value:
                            widget.job.bytesCompleted.value / widget.job.bytes,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    else
                      SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          p.s3.isWithin(
                                widget.relativeTo ?? '',
                                widget.job.remoteKey,
                              )
                              ? p.s3.relative(
                                  widget.job.remoteKey,
                                  from: widget.relativeTo ?? '',
                                )
                              : widget.job.remoteKey,
                        ),
                      ),
                    ),
                  ],
                ),
                footerPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(height: 360, width: 360, child: child!),
                    widget.job.status.value == JobStatus.completed
                        ? SizedBox.shrink()
                        : widget.job.startable()
                        ? Icon(
                            widget.job.runtimeType == UploadJob
                                ? Icons.arrow_circle_up
                                : Icons.arrow_circle_down,
                          )
                        : widget.job.stoppable()
                        ? Icon(Icons.pause_circle_filled)
                        : Icon(Icons.info),
                  ],
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: MediaQuery.of(context).size.width < 600 ? true : false,
                  visualDensity: MediaQuery.of(context).size.width < 600
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  leading: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(height: 32, width: 32, child: child!),
                      widget.job.status.value == JobStatus.completed
                          ? SizedBox.shrink()
                          : widget.job.startable()
                          ? Icon(
                              widget.job.runtimeType == UploadJob
                                  ? Icons.arrow_circle_up
                                  : Icons.arrow_circle_down,
                            )
                          : widget.job.stoppable()
                          ? Icon(Icons.pause_circle_filled)
                          : Icon(Icons.info),
                    ],
                  ),
                  onTap: widget.job.startable()
                      ? () {
                          widget.job.start();
                        }
                      : widget.job.stoppable()
                      ? () {
                          widget.job.stop();
                        }
                      : null,
                  title: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      p.s3.isWithin(
                            widget.relativeTo ?? '',
                            widget.job.remoteKey,
                          )
                          ? p.s3.relative(
                              widget.job.remoteKey,
                              from: widget.relativeTo ?? '',
                            )
                          : widget.job.remoteKey,
                    ),
                  ),
                  subtitle: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (widget.job.statusMsg.value.isNotEmpty) ...[
                          Text(widget.job.statusMsg.value, maxLines: 1),
                          SizedBox(width: 8),
                        ],
                        Text(widget.job.localFile.path, maxLines: 1),
                      ],
                    ),
                  ),
                  trailing: widget.job.dismissible()
                      ? IconButton(
                          onPressed: () {
                            widget.job.dismiss();
                          },
                          icon: Icon(Icons.clear),
                        )
                      : widget.job.removable()
                      ? IconButton(
                          onPressed: () {
                            widget.job.remove();
                          },
                          icon: Icon(Icons.cancel),
                        )
                      : null,
                ),
                if (widget.job.status.value != JobStatus.completed)
                  LinearProgressIndicator(
                    value: widget.job.bytesCompleted.value / widget.job.bytes,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  SizedBox(height: 2),
              ],
            ),
      child: FutureBuilder(
        future: () async {
          final url = Main.profileFromKey(
            widget.job.remoteKey,
          )?.getUrl(widget.job.remoteKey);
          final file = await RemoteFile.getByKey(widget.job.remoteKey);
          return (file: file, url: url);
        }(),
        builder: (context, snapshot) {
          final file = snapshot.data?.file;
          final url = snapshot.data?.url;
          if (file == null ||
              url == null ||
              lookupMimeType(file.key)?.startsWith('image/') == false) {
            return SizedBox.shrink();
          }
          return MediaPreview(
            item: FileProps(key: file.key, size: file.size, url: url),
            height: 360,
            width: 360,
          );
        },
      ),
    );
  }
}
