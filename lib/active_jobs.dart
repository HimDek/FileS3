import 'package:percent_indicator/percent_indicator.dart';
import 'package:flutter/material.dart';
import 'services/job.dart';

class ActiveJobs extends StatefulWidget {
  final List<Job> jobs;
  final Processor processor;
  final Function onClose;
  final Function onUpdate;
  final Function(Job, dynamic) onJobComplete;

  const ActiveJobs({
    super.key,
    required this.jobs,
    required this.processor,
    required this.onClose,
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
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Active Jobs'),
          SizedBox(width: 200),
          if (widget.jobs.isNotEmpty)
            widget.jobs.any((job) => job.running)
                ? IconButton(
                    onPressed: () {
                      widget.processor.stopall();
                      setState(() {});
                    },
                    icon: Icon(Icons.stop),
                  )
                : IconButton(
                    onPressed: () {
                      widget.processor.start();
                      setState(() {});
                    },
                    icon: Icon(Icons.start),
                  ),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: widget.jobs.map((job) {
            return ListTile(
              leading: job.running
                  ? CircularPercentIndicator(
                      radius: 28.0,
                      lineWidth: 4.0,
                      percent: job.bytesCompleted / job.bytes,
                      center: Text(
                        '${((job.bytesCompleted / job.bytes) * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      progressColor: Theme.of(context).primaryColor,
                    )
                  : job.completed
                  ? Icon(Icons.done)
                  : IconButton(
                      onPressed: () {
                        widget.processor.processJob(job, widget.onJobComplete);
                      },
                      icon: Icon(Icons.start),
                    ),
              title: Text(job.remoteKey),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.localFile.path, maxLines: 1),
                  Text(job.statusMsg, maxLines: 1),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => widget.onClose(), child: Text('Close')),
      ],
    );
  }
}
