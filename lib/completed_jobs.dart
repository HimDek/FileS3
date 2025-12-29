import 'package:flutter/material.dart';
import 'package:files3/job_view.dart';
import 'package:files3/services/job.dart';

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
