import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:files3/utils/path_utils.dart' as p;
import 'package:files3/utils/job.dart';
import 'package:files3/models.dart';

class ActiveJobs extends StatefulWidget {
  final List<Job> jobs;
  final Function() onUpdate;

  const ActiveJobs({super.key, required this.jobs, required this.onUpdate});

  @override
  ActiveJobsState createState() => ActiveJobsState();
}

class ActiveJobsState extends State<ActiveJobs> {
  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: widget.jobs.length,
      itemBuilder: (context, index) {
        final job = widget.jobs[index];
        return JobView(job: job, onUpdate: widget.onUpdate);
      },
    );
  }
}

class CompletedJobs extends StatefulWidget {
  final List<Job> completedJobs;
  final Function() onUpdate;

  const CompletedJobs({
    super.key,
    required this.completedJobs,
    required this.onUpdate,
  });

  @override
  CompletedJobsState createState() => CompletedJobsState();
}

class CompletedJobsState extends State<CompletedJobs> {
  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: widget.completedJobs.length,
      itemBuilder: (context, index) {
        final job = widget.completedJobs[index];
        return JobView(job: job, onUpdate: widget.onUpdate);
      },
    );
  }
}

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
          leading: widget.job.status == JobStatus.completed
              ? widget.job.runtimeType == UploadJob
                    ? Icon(Icons.done_all)
                    : Icon(Icons.download_done)
              : widget.job.startable()
              ? Icon(
                  widget.job.runtimeType == UploadJob
                      ? Icons.arrow_circle_up
                      : Icons.arrow_circle_down,
                )
              : widget.job.stoppable()
              ? Icon(Icons.pause_circle_filled)
              : Icon(Icons.info),
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
                  icon: Icon(Icons.clear),
                )
              : widget.job.removable()
              ? IconButton(
                  onPressed: () {
                    widget.job.remove();
                    if (widget.onUpdate != null) widget.onUpdate!();
                  },
                  icon: Icon(Icons.cancel),
                )
              : null,
        ),
        if (widget.job.status != JobStatus.completed)
          LinearPercentIndicator(
            percent: widget.job.bytesCompleted / widget.job.bytes,
            lineHeight: 2,
            backgroundColor: Theme.of(context).colorScheme.surface,
            progressColor: Theme.of(context).colorScheme.primary,
          )
        else
          SizedBox(height: 2),
      ],
    );
  }
}
