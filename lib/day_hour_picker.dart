import 'package:flutter/material.dart';

Future<Duration?> showDayHourPicker({
  required BuildContext context,
  Duration initialDuration = Duration.zero,
  Duration minDuration = Duration.zero,
  Duration? maxDuration,
}) {
  return showDialog(
    context: context,
    builder: (_) => _DayHourPickerDialog(
      initialDuration: initialDuration,
      minDuration: minDuration,
      maxDuration: Duration(days: 6, hours: 12),
    ),
  );
}

class _DayHourPickerDialog extends StatefulWidget {
  final Duration initialDuration;
  final Duration minDuration;
  final Duration? maxDuration;

  const _DayHourPickerDialog({
    required this.initialDuration,
    this.minDuration = Duration.zero,
    this.maxDuration,
  });

  @override
  State<_DayHourPickerDialog> createState() => _DayHourPickerDialogState();
}

class _DayHourPickerDialogState extends State<_DayHourPickerDialog> {
  late int day = widget.initialDuration.inDays;
  late int hour = widget.initialDuration.inHours % 24;
  late final daysController = FixedExtentScrollController(initialItem: day);
  late final hoursController = FixedExtentScrollController(initialItem: hour);

  @override
  void dispose() {
    daysController.dispose();
    hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      title: const Text("Select Duration"),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 32,
          children: [
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    child: ListWheelScrollView.useDelegate(
                      controller: daysController,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      diameterRatio: 2,
                      perspective: 0.01,
                      onSelectedItemChanged: (v) => setState(() {
                        day = v;
                        if (widget.maxDuration != null &&
                            Duration(days: day, hours: hour) >
                                widget.maxDuration!) {
                          hour = widget.maxDuration!.inHours % 24;
                          hoursController.animateToItem(
                            hour,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                        if (Duration(days: day, hours: hour) <
                            widget.minDuration) {
                          day = widget.minDuration.inDays;
                          hour = widget.minDuration.inHours % 24;
                          daysController.animateToItem(
                            day,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                          hoursController.animateToItem(
                            hour,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      }),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount:
                            (widget.maxDuration?.inDays.toInt() ?? 7) + 1,
                        builder: (_, index) => Center(
                          child: Text(
                            "$index",
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: index == day
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(":", style: Theme.of(context).textTheme.headlineLarge),
                  SizedBox(
                    width: 100,
                    child: ListWheelScrollView.useDelegate(
                      controller: hoursController,
                      itemExtent: 48,
                      physics: const FixedExtentScrollPhysics(),
                      diameterRatio: 2,
                      perspective: 0.01,
                      onSelectedItemChanged: (v) => setState(() {
                        hour = v;
                        if (widget.maxDuration != null &&
                            Duration(days: day, hours: hour) >
                                widget.maxDuration!) {
                          hour = widget.maxDuration!.inHours % 24;
                          hoursController.animateToItem(
                            hour,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                        if (Duration(days: day, hours: hour) <
                            widget.minDuration) {
                          day = widget.minDuration.inDays;
                          hour = widget.minDuration.inHours % 24;
                          daysController.animateToItem(
                            day,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                          hoursController.animateToItem(
                            hour,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      }),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 24,
                        builder: (_, index) => Center(
                          child: Text(
                            "$index",
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: index == hour
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: Center(
                    child: Text(
                      "Days",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Center(
                    child: Text(
                      "Hours",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context, Duration(days: day, hours: hour));
          },
          child: const Text("OK"),
        ),
      ],
    );
  }
}
