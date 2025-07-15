import 'package:flutter/material.dart';
import 'services/job.dart';

class CompletedJobs extends StatefulWidget {
  final List<Job> completedJobs;
  final Processor processor;
  final Function onClose;
  final Function onUpdate;

  const CompletedJobs({
    super.key,
    required this.completedJobs,
    required this.processor,
    required this.onClose,
    required this.onUpdate,
  });

  @override
  CompletedJobsState createState() => CompletedJobsState();
}

class CompletedJobsState extends State<CompletedJobs> {
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
          Text('Completed Jobs'),
          if (widget.completedJobs.isNotEmpty)
            IconButton(
              onPressed: () {
                widget.completedJobs.clear();
                setState(() {});
              },
              icon: Icon(Icons.delete_sweep),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: widget.completedJobs.map((job) {
            return ListTile(
              leading: Icon(Icons.done),
              title: Text(job.remoteKey),
              subtitle: Column(
                children: [Text(job.localFile.path), Text(job.statusMsg)],
              ),
              trailing: IconButton(
                onPressed: () {
                  widget.completedJobs.remove(job);
                  setState(() {});
                },
                icon: Icon(Icons.close),
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
