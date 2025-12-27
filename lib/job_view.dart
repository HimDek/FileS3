import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:s3_drive/services/models/remote_file.dart';
import 'package:path/path.dart' as p;
import 'services/job.dart';

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
    return ListTile(
      dense: MediaQuery.of(context).size.width < 600 ? true : false,
      visualDensity: MediaQuery.of(context).size.width < 600
          ? VisualDensity.compact
          : VisualDensity.standard,
      leading: widget.job.running
          ? CircularPercentIndicator(
              radius: 20.0,
              lineWidth: 4.0,
              percent: widget.job.bytesCompleted / widget.job.bytes,
              center: Text(
                '${((widget.job.bytesCompleted / widget.job.bytes) * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              progressColor: Theme.of(context).primaryColor,
            )
          : widget.job.completed
          ? widget.job.runtimeType == UploadJob
                ? Icon(Icons.done_all)
                : Icon(Icons.download_done)
          : IconButton(
              onPressed: () {
                widget.job.start();
              },
              icon: Icon(Icons.start),
            ),
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: p.isWithin(widget.job.remoteKey, widget.relativeTo?.key ?? '')
            ? Text(
                p.relative(
                  widget.job.remoteKey,
                  from: widget.relativeTo?.key ?? '',
                ),
              )
            : Text(widget.job.remoteKey),
      ),
      subtitle: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(widget.job.statusMsg, maxLines: 1),
            SizedBox(width: 16),
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
    );
  }
}
