import 'package:flutter/material.dart';
import 'package:s3_drive/job_view.dart';
import 'services/job.dart';

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
