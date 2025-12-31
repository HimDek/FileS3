import 'package:flutter/material.dart';
import 'package:files3/services/models/remote_file.dart';
import 'package:files3/services/job.dart';
import 'package:path/path.dart' as p;
import 'package:percent_indicator/percent_indicator.dart';

class JobView extends StatefulWidget {
  final Job job;
  final RemoteFile? relativeTo;
  final Function()? onUpdate;

  const JobView({super.key, required this.job, this.relativeTo, this.onUpdate});

  @override
  JobViewState createState() => JobViewState();
}

class JobViewState extends State<JobView> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: MediaQuery.of(context).size.width < 600 ? true : false,
          visualDensity: MediaQuery.of(context).size.width < 600
              ? VisualDensity.compact
              : VisualDensity.standard,
          leading: widget.job.completed
              ? widget.job.runtimeType == UploadJob
                    ? Icon(Icons.done_all)
                    : Icon(Icons.download_done)
              : widget.job.running
              ? Icon(Icons.pause_circle_filled)
              : Icon(
                  widget.job.runtimeType == UploadJob
                      ? Icons.upload
                      : Icons.download,
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
              p.isWithin(widget.relativeTo?.key ?? '', widget.job.remoteKey)
                  ? p.relative(
                      widget.job.remoteKey,
                      from: widget.relativeTo?.key ?? '',
                    )
                  : widget.job.remoteKey,
            ),
          ),
          subtitle: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (widget.job.statusMsg.isNotEmpty) ...[
                  Text(widget.job.statusMsg, maxLines: 1),
                  SizedBox(width: 16),
                ],
                Text(widget.job.localFile.path, maxLines: 1),
              ],
            ),
          ),
          trailing: widget.job.dismissible()
              ? IconButton(
                  onPressed: () {
                    widget.job.dismiss();
                    if (widget.onUpdate != null) widget.onUpdate!();
                  },
                  icon: Icon(Icons.close),
                )
              : null,
        ),
        if (!widget.job.completed)
          LinearPercentIndicator(
            percent: widget.job.bytesCompleted / widget.job.bytes,
            lineHeight: 4,
            backgroundColor: Theme.of(context).colorScheme.surface,
            progressColor: Theme.of(context).colorScheme.primary,
          )
        else
          SizedBox(height: 4),
      ],
    );
  }
}
