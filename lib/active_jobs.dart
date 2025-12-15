import 'package:flutter/material.dart';
import 'package:s3_drive/job_view.dart';
import 'services/job.dart';

class ActiveJobs extends StatefulWidget {
  final List<Job> jobs;
  final Processor processor;
  final Function onUpdate;
  final Function(Job, dynamic) onJobComplete;

  const ActiveJobs({
    super.key,
    required this.jobs,
    required this.processor,
    required this.onUpdate,
    required this.onJobComplete,
  });

  @override
  ActiveJobsState createState() => ActiveJobsState();
}

class ActiveJobsState extends State<ActiveJobs> {
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ListBody(
        children: widget.jobs.map((job) {
          return JobView(
            job: job,
            processor: widget.processor,
            onUpdate: () {
              setState(() {});
            },
            onJobComplete: widget.onJobComplete,
          );
        }).toList(),
      ),
    );
  }
}
