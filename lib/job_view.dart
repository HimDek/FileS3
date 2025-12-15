import 'package:percent_indicator/percent_indicator.dart';
import 'package:flutter/material.dart';
import 'services/job.dart';

class JobView extends StatefulWidget {
  final Job job;
  final Processor processor;
  final Function onUpdate;
  final Function(Job, dynamic)? onJobComplete;
  final Function()? remove;

  const JobView({
    super.key,
    required this.job,
    required this.processor,
    required this.onUpdate,
    this.onJobComplete,
    this.remove,
  });

  @override
  JobViewState createState() => JobViewState();
}

class JobViewState extends State<JobView> {
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.job.running
          ? CircularPercentIndicator(
              radius: 28.0,
              lineWidth: 4.0,
              percent: widget.job.bytesCompleted / widget.job.bytes,
              center: Text(
                '${((widget.job.bytesCompleted / widget.job.bytes) * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              progressColor: Theme.of(context).primaryColor,
            )
          : widget.job.completed
              ? Icon(Icons.done)
              : IconButton(
                  onPressed: () {
                    widget.processor
                        .processJob(widget.job, widget.onJobComplete!);
                  },
                  icon: Icon(Icons.start),
                ),
      title: Text(widget.job.remoteKey),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.job.localFile.path, maxLines: 1),
          Text(widget.job.statusMsg, maxLines: 1),
        ],
      ),
      trailing: widget.job.completed && widget.remove != null
          ? IconButton(
              onPressed: widget.remove,
              icon: Icon(Icons.close),
            )
          : null,
    );
  }
}
