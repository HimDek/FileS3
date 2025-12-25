import 'package:flutter/material.dart';
import 'package:s3_drive/job_view.dart';
import 'services/job.dart';

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
    return Column(
      children: widget.completedJobs.map((job) {
        return JobView(job: job, onUpdate: widget.onUpdate);
      }).toList(),
    );
  }
}
