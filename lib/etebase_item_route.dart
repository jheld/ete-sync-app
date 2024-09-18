import 'dart:convert';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:datetime_picker_formfield_new/datetime_picker_formfield.dart';
import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:ete_sync_app/i_calendar_custom_parser.dart';
import 'package:ete_sync_app/util.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_input_chips/flutter_input_chips.dart';

import 'package:intl/intl.dart' hide TextDirection;

import 'package:pretty_diff_text/pretty_diff_text.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum StartDateTimeOptions {
  /* hide until array index -> significance  */
  hideUntilNone,
  hideUntilDue,
  hideUntilDayBefore,
  hideUntilWeekBefore,
  hideUntilSpecificDay,
  hideUntilSpecificDayTime,
  hideUntilDueTime,
}

extension ExtensionTodoStatus on StartDateTimeOptions {
  String get name {
    switch (this) {
      case StartDateTimeOptions.hideUntilNone:
        return 'No Start Date';
      case StartDateTimeOptions.hideUntilDue:
        return 'Due date';
      case StartDateTimeOptions.hideUntilDueTime:
        return 'Due time';
      case StartDateTimeOptions.hideUntilDayBefore:
        return 'Day Before Due';
      case StartDateTimeOptions.hideUntilWeekBefore:
        return 'Week Before Due';
      case StartDateTimeOptions.hideUntilSpecificDay:
        return 'Specific Day';
      case StartDateTimeOptions.hideUntilSpecificDayTime:
        return 'Specific Day and Time';
    }
  }
}

MaterialColor priorityColor(Priority priority) {
  return switch (priority) {
    Priority.undefined => Colors.grey,
    Priority.low => Colors.blue,
    Priority.medium => Colors.orange,
    Priority.high => Colors.red,
  };
}

class EtebaseItemCreateRoute extends StatefulWidget {
  const EtebaseItemCreateRoute({
    super.key,
    required this.itemManager,
    required this.client,
  });

  final EtebaseItemManager itemManager;
  final EtebaseClient client;

  @override
  State<StatefulWidget> createState() => _EtebaseItemCreateRouteState();
}

class _EtebaseItemCreateRouteState extends State<EtebaseItemCreateRoute> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController summaryController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController startController = TextEditingController();
  final TextEditingController dueController = TextEditingController();
  bool wasEdited = false;
  TodoStatus _status = TodoStatus.unknown;
  Priority? _priority = Priority.undefined;
  List<VAlarm> alarms = [];
  List<String> categories = [];
  final _startTimeFieldKey = GlobalKey();

  final recurrenceRuleController = TextEditingController();
  final alarmController = TextEditingController();

  @override
  void initState() {
    super.initState();

    summaryController.text = "";
    descriptionController.text = "";
    startController.text = "";
    dueController.text = "";
    recurrenceRuleController.text = "";
    const beginVAlarm = """BEGIN:VALARM
TRIGGER;RELATED=END:PT0S
ACTION:DISPLAY
DESCRIPTION:Default Tasks.org description
END:VALARM""";
    final beginVAlarmComp = VComponent.parse(beginVAlarm) as VAlarm;
    alarmController.text = beginVAlarmComp.toString();

    _status = TodoStatus.unknown;
    _priority = Priority.undefined;
    alarms = <VAlarm>[];
    categories = <String>[];
  }

  @override
  void dispose() {
    summaryController.dispose();
    startController.dispose();
    dueController.dispose();
    recurrenceRuleController.dispose();
    descriptionController.dispose();
    alarmController.dispose();
    super.dispose();
  }

  String localizedStartDateTimeOption(
      StartDateTimeOptions option, BuildContext context) {
    switch (option) {
      case StartDateTimeOptions.hideUntilNone:
        return AppLocalizations.of(context)!.hideUntilNone;
      case StartDateTimeOptions.hideUntilDue:
        return AppLocalizations.of(context)!.hideUntilDue;
      case StartDateTimeOptions.hideUntilDueTime:
        return AppLocalizations.of(context)!.hideUntilDueTime;
      case StartDateTimeOptions.hideUntilDayBefore:
        return AppLocalizations.of(context)!.hideUntilDayBefore;
      case StartDateTimeOptions.hideUntilWeekBefore:
        return AppLocalizations.of(context)!.hideUntilWeekBefore;
      case StartDateTimeOptions.hideUntilSpecificDay:
        return AppLocalizations.of(context)!.hideUntilSpecificDay;
      case StartDateTimeOptions.hideUntilSpecificDayTime:
        return AppLocalizations.of(context)!.hideUntilSpecificDayTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () {
            Navigator.maybePop(context, null);
          }),
          actions: [
            buildIconSaveButton(context),
            const Divider(height: 50),
            buildIconDiscardButton(context),
          ],
          // TRY THIS: Try changing the color here to a specific color (to
          // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
          // change color while the other colors stay the same.
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: const Text("Item view"),
        ),
        body: Center(
          child: Column(
            children: [
              Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                      controller: summaryController,
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.summary),
                      onChanged: (val) {},
                    ),
                    DropdownButtonFormField(
                      items: Priority.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Row(
                                  children: [
                                    Icon(Icons.circle,
                                        size: 16, color: priorityColor(e)),
                                    Text(e.name),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _priority = value;
                          });
                        }
                      },
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.priority),
                      value: _priority,
                    ),
                    DropdownButtonFormField(
                      items: TodoStatus.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _status = value;
                          });
                        }
                      },
                      validator: (TodoStatus? value) {
                        if (value == null) {
                          return "can't empty";
                        } else {
                          return null;
                        }
                      },
                      decoration: const InputDecoration(labelText: "Status"),
                      value: _status,
                    ),
                    DateTimeField(
                      key: _startTimeFieldKey,
                      format: DateFormat("yyyy-MM-dd HH:mm"),
                      decoration:
                          const InputDecoration(labelText: "Start date"),
                      controller: startController,
                      onShowPicker: (context, currentValue) async {
                        final dueDT = DateTime.tryParse(dueController.text);
                        final offset = _startTimeFieldKey.currentContext!
                            .findRenderObject() as RenderBox;
                        Offset position = offset.localToGlobal(
                            Offset.zero); //this is global position
                        final startDateTimeOption =
                            await showMenu<StartDateTimeOptions>(
                                context: context,
                                position: RelativeRect.fromLTRB(position.dx,
                                    position.dy, position.dx, position.dy),
                                items: StartDateTimeOptions.values
                                    .map((e) => PopupMenuItem(
                                        value: e,
                                        child: Text(
                                            localizedStartDateTimeOption(
                                                e, context))))
                                    .toList());
                        if (startDateTimeOption != null &&
                            startDateTimeOption !=
                                StartDateTimeOptions.hideUntilNone) {
                          {
                            if (startDateTimeOption ==
                                StartDateTimeOptions.hideUntilDue) {
                              currentValue = DateTimeField.combine(
                                  dueDT ?? DateTime.now(),
                                  const TimeOfDay(hour: 0, minute: 0));
                            } else if (startDateTimeOption ==
                                StartDateTimeOptions.hideUntilDueTime) {
                              currentValue = dueDT;
                            } else if (startDateTimeOption ==
                                StartDateTimeOptions.hideUntilDayBefore) {
                              currentValue =
                                  dueDT!.subtract(const Duration(days: 1));
                            } else if (startDateTimeOption ==
                                StartDateTimeOptions.hideUntilWeekBefore) {
                              currentValue =
                                  dueDT!.subtract(const Duration(days: 7));
                            } else {
                              if (context.mounted) {
                                return await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2000),
                                  initialDate: currentValue ?? DateTime.now(),
                                  lastDate: DateTime(2100),
                                ).then((DateTime? date) async {
                                  if (date != null) {
                                    if (startDateTimeOption ==
                                        StartDateTimeOptions
                                            .hideUntilSpecificDayTime) {
                                      final time = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                            currentValue ?? DateTime.now()),
                                      );
                                      return DateTimeField.combine(date, time);
                                    } else {
                                      return DateTimeField.combine(date,
                                          const TimeOfDay(hour: 0, minute: 0));
                                    }
                                  } else {
                                    return currentValue;
                                  }
                                });
                              } else {
                                return null;
                              }
                            }
                            return currentValue;
                          }
                        } else {
                          return null;
                        }
                      },
                    ),
                    DateTimeField(
                      format: DateFormat("yyyy-MM-dd HH:mm"),
                      decoration: const InputDecoration(labelText: "Due date"),
                      controller: dueController,
                      onShowPicker: (context, currentValue) async {
                        return await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          initialDate: currentValue ?? DateTime.now(),
                          currentDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        ).then((DateTime? date) async {
                          if (date != null) {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(
                                  currentValue ?? DateTime.now()),
                            );
                            return DateTimeField.combine(date, time);
                          } else {
                            return currentValue;
                          }
                        });
                      },
                    ),
                    TextFormField(
                      controller: descriptionController,
                      initialValue: null,
                      validator: (String? value) {
                        // if (value == null || value.isEmpty) {
                        //   return 'Please enter some text';
                        // }
                        return null;
                      },
                      decoration:
                          const InputDecoration(labelText: "Description"),
                      onChanged: (val) {},
                    ),
                    FlutterInputChips(
                      initialValue: categories,
                      onChanged: (v) => setState(() {
                        categories = v;
                      }),
                    ),
                    TextFormField(
                      controller: recurrenceRuleController,
                      decoration: InputDecoration(
                        labelText: "RRULE",
                        suffixIcon: IconButton(
                          onPressed: recurrenceRuleController.clear,
                          icon: const Icon(Icons.clear),
                          tooltip: AppLocalizations.of(context)!.clear,
                        ),
                      ),
                      onTap: () {
                        final valueToUseIfCancel =
                            recurrenceRuleController.text;
                        showDialog(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: const Text("Recurrence"),
                            icon: const Icon(Icons.repeat),
                            actions: [
                              TextButton(
                                  onPressed: () {
                                    setState(() {
                                      recurrenceRuleController.text =
                                          valueToUseIfCancel;
                                    });
                                    Navigator.pop(context);
                                  },
                                  child: const Text("Cancel")),
                              TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: const Text("OK")),
                            ],
                            content: SingleChildScrollView(
                              child: RRuleGenerator(
                                config: RRuleGeneratorConfig(),
                                initialRRule: recurrenceRuleController.text,
                                textDelegate: const EnglishRRuleTextDelegate(),
                                onChange: (value) {
                                  recurrenceRuleController.text =
                                      value.startsWith("RRULE:")
                                          ? value.replaceFirst("RRULE:", "")
                                          : value;
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    TextFormField(
                      controller: alarmController,
                      decoration: InputDecoration(
                        labelText: "ALARM",
                        suffixIcon: IconButton(
                          onPressed: alarmController.clear,
                          icon: const Icon(Icons.clear),
                          tooltip: AppLocalizations.of(context)!.clear,
                        ),
                      ),
                      validator: (String? value) {
                        // if (value == null || value.isEmpty) {
                        //   return 'Please enter some text';
                        // }
                        return null;
                      },
                    ),
                    Column(children: [
                      ListView.builder(
                          shrinkWrap: true,
                          itemCount: alarms.length,
                          itemBuilder: (BuildContext context, int index) {
                            return ListTile(
                              title: TextFormField(
                                initialValue: alarms[index]
                                        .triggerRelativeDuration
                                        ?.toString() ??
                                    alarms[index]
                                        .triggerDate
                                        ?.toIso8601String() ??
                                    "",
                                validator: (value) {
                                  try {
                                    if (value == null || value == "") {
                                      return 'Cannot be blank';
                                    }
                                    IsoDuration.parse(value);
                                  } on FormatException {
                                    return 'Not a valid ISO duration';
                                  }
                                  return null;
                                },
                              ),
                            );
                          }),
                    ]),
                  ])),
            ],
          ),
        ));
  }

  IconButton buildIconDiscardButton(BuildContext context) {
    return IconButton(
        onPressed: () async {
          final action = await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Discard creating todo'),
                  content: const Text(
                      'Would you like to discard creating this todo?'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Continue'),
                      child: const Text('Continue'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'OK'),
                      child: const Text('OK'),
                    ),
                  ],
                );
              });
          if (action == "OK") {
            if (context.mounted) Navigator.of(context).pop();
          }
        },
        tooltip: AppLocalizations.of(context)!.cancel,
        icon: const Icon(Icons.cancel));
  }

  IconButton buildIconSaveButton(BuildContext context) {
    return IconButton(
        onPressed: () async {
          if (_formKey.currentState!.validate()) {
            final icalendar = VCalendar();
            final todoComp = VTodo(parent: icalendar);
            icalendar.children.add(todoComp);

            bool sequenceChange = false;
            /*
                          
                          sequence must change if:
                          o  "DTSTART"
                          
                          o  "DTEND"
                          
                          o  "DURATION"
                          
                          o  "DUE"
                          
                          o  "RRULE"
                          
                          o  "RDATE"
                          
                          o  "EXDATE"
                          
                          o  "STATUS"
                          */
            bool statusChanged = false;
            if (_status != todoComp.status) {
              todoComp.status = _status;
              sequenceChange = true;
              statusChanged = true;
            }
            if (_priority != todoComp.priority) {
              todoComp.priority = _priority;
            }
            if (todoComp.summary != summaryController.text) {
              todoComp.summary = summaryController.text;
            }
            if (todoComp.description != descriptionController.text) {
              todoComp.description = descriptionController.text;
            }

            todoComp.lastModified = DateTime.now();
            final updatedRecurrenceRule =
                recurrenceRuleController.text.isNotEmpty
                    ? Recurrence.parse(recurrenceRuleController.text)
                    : null;
            if (todoComp.recurrenceRule != updatedRecurrenceRule) {
              todoComp.recurrenceRule = updatedRecurrenceRule;
              sequenceChange = true;
              //if (statusChanged) {
              //  todoComp.recurrenceId = todoComp.start;
              //}
            }
            //if (todoComp.recurrenceRule != null && statusChanged) {
            //todoComp.recurrenceId = todoComp.start;
            // }
            final updatedStart = DateTime.tryParse(startController.text);
            final updatedDue = DateTime.tryParse(dueController.text);

            if ((updatedDue != null && todoComp.due == null) ||
                (updatedDue == null && todoComp.due != null)) {
              todoComp.due = updatedDue;
              sequenceChange = true;
            } else if (todoComp.due != null &&
                updatedDue != null &&
                todoComp.due!.compareTo(updatedDue) != 0) {
              todoComp.due = updatedDue;
              sequenceChange = true;
            }
            if ((updatedStart != null && todoComp.start == null) ||
                (updatedStart == null && todoComp.start != null)) {
              todoComp.start = updatedStart;
              sequenceChange = true;
            } else if (todoComp.start != null &&
                updatedStart != null &&
                todoComp.start!.compareTo(updatedStart) != 0) {
              todoComp.start = updatedStart;
              sequenceChange = true;
            }

            if (updatedStart != null &&
                todoComp.start != null &&
                todoComp.due != null &&
                todoComp.start!.isAtSameMomentAs(
                    todoComp.due!.subtract(const Duration(seconds: 1)))) {
              todoComp.due = todoComp.due!.add(const Duration(seconds: 1));
            }

            if (categories.length != (todoComp.categories ?? []).length) {
              todoComp.categories = categories.isNotEmpty ? categories : null;
            } else if (categories
                .toSet()
                .difference((todoComp.categories ?? []).toSet())
                .isNotEmpty) {
              todoComp.categories = categories.isNotEmpty ? categories : null;
            }

            if (sequenceChange) {
              todoComp.sequence = (todoComp.sequence ?? 0) + 1;
            }
            todoComp.uid = VCalendar.createUid();
            todoComp.timeStamp = DateTime.now();
            if (alarmController.text.isNotEmpty) {
              final todoAlarmComp = VAlarm(parent: todoComp);
              todoAlarmComp.trigger = TriggerProperty.createWithDuration(
                  IsoDuration.parse(alarmController.text),
                  relation: AlarmTriggerRelationship.end);
              todoAlarmComp.action = AlarmAction.display;
              todoAlarmComp.description = "Default Tasks.org description";
              todoComp.children.add(todoAlarmComp);
            }
            final nextTodo = (statusChanged &&
                    (todoComp.status == TodoStatus.completed ||
                        todoComp.status == TodoStatus.cancelled))
                ? getNextOccurrence(todoComp, todoComp.recurrenceRule)
                : todoComp;

            final actualNextTodo = nextTodo ?? todoComp;

            actualNextTodo.checkValidity();
            final item = await widget.itemManager.create(
                EtebaseItemMetadata(mtime: DateTime.now()),
                utf8.encode(todoComp.parent!.toString()));

            await widget.itemManager.transaction([item]);

            final itemUpdatedFromServer =
                await widget.itemManager.fetch((await item.getUid()));

            final username = await getUsernameInCacheDir();

            final cacheClient = await EtebaseFileSystemCache.create(
                widget.client, await getCacheDir(), username);
            final colUid = await getCollectionUIDInCacheDir();
            await cacheClient.itemSet(
                widget.itemManager, colUid, itemUpdatedFromServer);
            await cacheClient.dispose();

            final updatedItemContent = await itemUpdatedFromServer.getContent();
            final updateVCalendar =
                VComponent.parse(utf8.decode(updatedItemContent)) as VCalendar;
            final sendingToNavigator = {
              "item": itemUpdatedFromServer,
              "icalendar": itemUpdatedFromServer,
              "itemContent": updatedItemContent,
              "itemIsDeleted": await itemUpdatedFromServer.isDeleted(),
              "itemUid": await itemUpdatedFromServer.getUid(),
              "todo": updateVCalendar.todo!,
            };
            if (context.mounted) {
              Navigator.maybePop(context, sendingToNavigator);
            }
          }
        },
        icon: const Icon(Icons.save),
        tooltip: AppLocalizations.of(context)!.save);
  }
}

class EtebaseItemRoute extends StatefulWidget {
  const EtebaseItemRoute({
    super.key,
    required this.item,
    required this.icalendar,
    required this.itemManager,
    required this.itemMap,
    required this.client,
  });

  final EtebaseItem item;
  final EtebaseItemManager itemManager;
  final VCalendar icalendar;
  final Map<String, dynamic> itemMap;
  final EtebaseClient client;

  @override
  State<StatefulWidget> createState() => _EtebaseItemRouteState();
}

class _EtebaseItemRouteState extends State<EtebaseItemRoute> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController summaryController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController startController = TextEditingController();
  final TextEditingController dueController = TextEditingController();
  bool wasEdited = false;
  TodoStatus _status = TodoStatus.unknown;
  Priority? _priority = Priority.undefined;
  List<VAlarm> alarms = [];
  final rawContentFormKey = GlobalKey<FormState>();
  final recurrenceRuleController = TextEditingController();
  List<String> categories = [];

  final _startTimeFieldKey = GlobalKey();

  final alarmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final todoComp = widget.icalendar.todo!;
    summaryController.text = todoComp.summary ?? "";
    descriptionController.text = todoComp.description ?? "";
    startController.text = todoComp.start != null
        ? DateFormat("yyyy-MM-dd HH:mm").format(todoComp.start!.toLocal())
        : "";
    dueController.text = todoComp.due != null
        ? DateFormat("yyyy-MM-dd HH:mm").format(todoComp.due!.toLocal())
        : "";
    recurrenceRuleController.text = todoComp.recurrenceRule?.toString() ?? "";
    final beginVAlarm = todoComp.children
            .where((element) => element.componentType == VComponentType.alarm)
            .map((element) => element as VAlarm)
            .toList()
            .firstOrNull
            ?.toString() /* ??
        """BEGIN:VALARM
TRIGGER;RELATED=END:PT0S
ACTION:DISPLAY
DESCRIPTION:Default Tasks.org description
END:VALARM"""*/
        ;
    if (beginVAlarm != null) {
      final beginVAlarmComp = VComponent.parse(beginVAlarm) as VAlarm;
      alarmController.text = beginVAlarmComp.toString();
    } else {
      alarmController.text = "";
    }

    _status = todoComp.status;
    _priority = todoComp.priority;
    alarms = todoComp.children
        .where((element) => element.componentType == VComponentType.alarm)
        .map((element) => element as VAlarm)
        .toList();
    categories = todoComp.categories ?? [];
    // if (todoComp.start == null) {
    //   _startDateTimeOption = StartDateTimeOptions.hideUntilNone;
    // } else if (todoComp.due != null &&
    //     todoComp.start!.isAtSameMomentAs(todoComp.due!)) {
    //   _startDateTimeOption = StartDateTimeOptions.hideUntilDueTime;
    // } else {
    //   _startDateTimeOption = null;
    // }
  }

  @override
  void dispose() {
    super.dispose();
    summaryController.dispose();
    startController.dispose();
    dueController.dispose();
    recurrenceRuleController.dispose();
    descriptionController.dispose();
  }

  String localizedStartDateTimeOption(
      StartDateTimeOptions option, BuildContext context) {
    switch (option) {
      case StartDateTimeOptions.hideUntilNone:
        return AppLocalizations.of(context)!.hideUntilNone;
      case StartDateTimeOptions.hideUntilDue:
        return AppLocalizations.of(context)!.hideUntilDue;
      case StartDateTimeOptions.hideUntilDueTime:
        return AppLocalizations.of(context)!.hideUntilDueTime;
      case StartDateTimeOptions.hideUntilDayBefore:
        return AppLocalizations.of(context)!.hideUntilDayBefore;
      case StartDateTimeOptions.hideUntilWeekBefore:
        return AppLocalizations.of(context)!.hideUntilWeekBefore;
      case StartDateTimeOptions.hideUntilSpecificDay:
        return AppLocalizations.of(context)!.hideUntilSpecificDay;
      case StartDateTimeOptions.hideUntilSpecificDayTime:
        return AppLocalizations.of(context)!.hideUntilSpecificDayTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoComp = widget.icalendar.todo!;

    /*
  const Recurrence(
    this.frequency, {
    this.until,
    this.count,
    int? interval,
    this.bySecond,
    this.byMinute,
    this.byHour,
    this.byWeekDay,
    this.byYearDay,
    this.byWeek,
    this.byMonth,
    this.byMonthDay,
    int? startOfWorkWeek,
    this.bySetPos,
  })
    */
    return Scaffold(
        appBar: AppBar(
          actions: [
            buildIconButtonDelete(context),
            const VerticalDivider(width: 100),
            buildIconButtonSave(todoComp, context),
          ],
          leading: BackButton(onPressed: () {
            Navigator.maybePop(context, null);
          }),
          // TRY THIS: Try changing the color here to a specific color (to
          // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
          // change color while the other colors stay the same.
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: const Text("Item view"),
        ),
        bottomNavigationBar: BottomAppBar(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
              TextButton.icon(
                  label: const Text("RAW Content"),
                  onPressed: () async {
                    final editedContent = await showDialog<String?>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                              title: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Item UID: "),
                                    SelectableText(
                                      widget.itemMap["itemUid"],
                                    ),
                                  ]),
                              content: SingleChildScrollView(
                                  child: Shortcuts(
                                shortcuts: const <ShortcutActivator, Intent>{
                                  SingleActivator(LogicalKeyboardKey.tab):
                                      NextFocusIntent(),
                                },
                                child: FocusTraversalGroup(
                                  child: Form(
                                      key: rawContentFormKey,
                                      autovalidateMode: AutovalidateMode.always,
                                      child: Wrap(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: TextFormField(
                                              initialValue:
                                                  todoComp.parent!.toString(),
                                              maxLines: null,
                                              validator: (String? value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return "Cannot be empty";
                                                }
                                                try {
                                                  (VComponent.parse(value)
                                                          as VCalendar)
                                                      .checkValidity();
                                                } on FormatException catch (e) {
                                                  // TODO
                                                  /*rawContentFormKey
                                                      .currentState!
                                                      .reset();*/
                                                  return "Error: ${e.message}";
                                                }
                                                return null;
                                              },
                                              onSaved: (String? value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  value = todoComp.parent!
                                                      .toString();
                                                }

                                                try {
                                                  (VComponent.parse(value)
                                                          as VCalendar)
                                                      .checkValidity();
                                                } on FormatException catch (e) {
                                                  if (kDebugMode) {
                                                    print(e.message);
                                                  }
                                                  value = todoComp.parent!
                                                      .toString();
                                                }

                                                Navigator.maybePop(
                                                    context, value);
                                              },
                                            ),
                                          ),
                                          TextButton(
                                              onPressed: () {
                                                if (rawContentFormKey
                                                    .currentState!
                                                    .validate()) {
                                                  rawContentFormKey
                                                      .currentState!
                                                      .save();
                                                }
                                              },
                                              child: const Text("Done"))
                                        ],
                                      )),
                                ),
                              )),
                            ));
                    if (editedContent != null &&
                        editedContent != todoComp.parent!.toString() &&
                        context.mounted) {
                      VCalendar icalendar =
                          VComponent.parse(editedContent) as VCalendar;
                      await Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (BuildContext context) =>
                                  EtebaseItemRoute(
                                      item: widget.item,
                                      icalendar: icalendar,
                                      itemManager: widget.itemManager,
                                      itemMap: widget.itemMap,
                                      client: widget.client)));
                    }
                  },
                  icon: const Icon(Icons.data_exploration)),
              TextButton.icon(
                  label: const Text("Revisions"),
                  onPressed: () async {
                    bool done = false;
                    final eteItemRevisionList = <RevisionItemWrapper>[];
                    String? revisionIteratorValue;

                    while (!done) {
                      final itemRevisionListResponse =
                          await widget.itemManager.itemRevisions(
                              widget.item,
                              EtebaseFetchOptions(
                                iterator: revisionIteratorValue,
                              ));
                      for (var element
                          in await itemRevisionListResponse.getData()) {
                        eteItemRevisionList.add(RevisionItemWrapper(
                            revision: element,
                            mtime: (await element.getMeta()).mtime));
                      }

                      revisionIteratorValue =
                          await itemRevisionListResponse.getIterator();
                      done = await itemRevisionListResponse.isDone();
                    }

                    if (context.mounted) {
                      final action = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (BuildContext context) =>
                                  RevisionStatefulWidget(
                                      revisions: eteItemRevisionList)));
                      if (action != null && action is RevisionItemWrapper) {
                        final revisionCalendar = VComponent.parse(
                                utf8.decode(await action.revision.getContent()))
                            as VCalendar;
                        revisionCalendar.todo!.sequence =
                            (revisionCalendar.todo!.sequence ?? 0) + 1;
                        final revisionClone = await action.revision.clone();
                        await revisionClone.setContent(
                            utf8.encode(revisionCalendar.toString()));
                        final revisionMetaClone =
                            (await revisionClone.getMeta())
                                .copyWith(mtime: DateTime.now());
                        await revisionClone.setMeta(revisionMetaClone);
                        await widget.itemManager.batch([revisionClone]);
                        final itemUpdatedFromServer = await widget.itemManager
                            .fetch(widget.itemMap["itemUid"]);

                        final updatedItemContent =
                            await itemUpdatedFromServer.getContent();
                        final updateVCalendar =
                            VComponent.parse(utf8.decode(updatedItemContent))
                                as VCalendar;
                        final sendingToNavigator = {
                          "item": itemUpdatedFromServer,
                          "icalendar": itemUpdatedFromServer,
                          "itemContent": updatedItemContent,
                          "itemIsDeleted":
                              await itemUpdatedFromServer.isDeleted(),
                          "itemUid": await itemUpdatedFromServer.getUid(),
                          "todo": updateVCalendar.todo!,
                        };
                        if (context.mounted) {
                          Navigator.maybePop(context, sendingToNavigator);
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.history)),
            ])),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Form(
                    key: _formKey,
                    child: Column(children: [
                      Directionality(
                          textDirection: Bidi.detectRtlDirectionality(
                                  summaryController.text)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: TextFormField(
                            controller: summaryController,
                            validator: (String? value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter some text';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(context)!.summary),
                            onChanged: (val) {},
                          )),
                      DropdownButtonFormField(
                        items: Priority.values
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.circle,
                                          size: 16, color: priorityColor(e)),
                                      Text(e.name),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _priority = value;
                            });
                          }
                        },
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.priority),
                        value: _priority,
                      ),
                      DropdownButtonFormField(
                        items: TodoStatus.values
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e.name),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _status = value;
                            });
                          }
                        },
                        validator: (TodoStatus? value) {
                          if (value == null) {
                            return "can't empty";
                          } else {
                            return null;
                          }
                        },
                        decoration: const InputDecoration(labelText: "Status"),
                        value: _status,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          SizedBox(
                            width: 225,
                            child: DateTimeField(
                              key: _startTimeFieldKey,
                              format: DateFormat("yyyy-MM-dd HH:mm"),
                              decoration: const InputDecoration(
                                  labelText: "Start date",
                                  icon: Icon(Icons.content_paste_go)),
                              initialValue: todoComp.start,
                              controller: startController,
                              onShowPicker: (context, currentValue) async {
                                final offset = _startTimeFieldKey
                                    .currentContext!
                                    .findRenderObject() as RenderBox;
                                Offset position = offset.localToGlobal(
                                    Offset.zero); //this is global position
                                final startDateTimeOption = await showMenu<
                                        StartDateTimeOptions>(
                                    context: context,
                                    position: RelativeRect.fromLTRB(position.dx,
                                        position.dy, position.dx, position.dy),
                                    items: StartDateTimeOptions.values
                                        .map((e) => PopupMenuItem(
                                            value: e,
                                            child: Text(
                                                localizedStartDateTimeOption(
                                                    e, context))))
                                        .toList());
                                if (startDateTimeOption != null &&
                                    startDateTimeOption !=
                                        StartDateTimeOptions.hideUntilNone) {
                                  {
                                    if (startDateTimeOption ==
                                        StartDateTimeOptions.hideUntilDue) {
                                      currentValue = DateTimeField.combine(
                                          (DateTime.tryParse(
                                                      dueController.text) ??
                                                  todoComp.due) ??
                                              DateTime.now(),
                                          const TimeOfDay(hour: 0, minute: 0));
                                    } else if (startDateTimeOption ==
                                        StartDateTimeOptions.hideUntilDueTime) {
                                      currentValue = (DateTime.tryParse(
                                              dueController.text) ??
                                          todoComp.due);
                                    } else if (startDateTimeOption ==
                                        StartDateTimeOptions
                                            .hideUntilDayBefore) {
                                      currentValue = (DateTime.tryParse(
                                                  dueController.text) ??
                                              todoComp.due!)
                                          .subtract(const Duration(days: 1));
                                    } else if (startDateTimeOption ==
                                        StartDateTimeOptions
                                            .hideUntilWeekBefore) {
                                      currentValue = (DateTime.tryParse(
                                                  dueController.text) ??
                                              todoComp.due!)
                                          .subtract(const Duration(days: 7));
                                    } else {
                                      if (context.mounted) {
                                        return await showDatePicker(
                                          context: context,
                                          firstDate: DateTime(2000),
                                          initialDate:
                                              currentValue ?? DateTime.now(),
                                          lastDate: DateTime(2100),
                                        ).then((DateTime? date) async {
                                          if (date != null) {
                                            if (startDateTimeOption ==
                                                StartDateTimeOptions
                                                    .hideUntilSpecificDayTime) {
                                              final time = await showTimePicker(
                                                context: context,
                                                initialTime:
                                                    TimeOfDay.fromDateTime(
                                                        currentValue ??
                                                            DateTime.now()),
                                              );
                                              return DateTimeField.combine(
                                                  date, time);
                                            } else {
                                              return DateTimeField.combine(
                                                  date,
                                                  const TimeOfDay(
                                                      hour: 0, minute: 0));
                                            }
                                          } else {
                                            return currentValue;
                                          }
                                        });
                                      } else {
                                        return null;
                                      }
                                    }
                                    return currentValue;
                                  }
                                } else {
                                  return null;
                                }
                              },
                            ),
                          ),
                          SizedBox(
                            width: 225,
                            child: DateTimeField(
                              format: DateFormat("yyyy-MM-dd HH:mm"),
                              decoration: const InputDecoration(
                                  labelText: "Due date",
                                  icon: Icon(Icons.punch_clock)),
                              initialValue: todoComp.due,
                              controller: dueController,
                              onShowPicker: (context, currentValue) async {
                                return await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2000),
                                  initialDate: currentValue ?? DateTime.now(),
                                  lastDate: DateTime(2100),
                                ).then((DateTime? date) async {
                                  if (date != null) {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                          currentValue ?? DateTime.now()),
                                    );
                                    return DateTimeField.combine(date, time);
                                  } else {
                                    return currentValue;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      Directionality(
                          textDirection: Bidi.detectRtlDirectionality(
                                  descriptionController.text)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: TextFormField(
                            controller: descriptionController,
                            validator: (String? value) {
                              // if (value == null || value.isEmpty) {
                              //   return 'Please enter some text';
                              // }
                              return null;
                            },
                            decoration:
                                const InputDecoration(labelText: "Description"),
                            onChanged: (val) {},
                          )),
                      FlutterInputChips(
                        initialValue: categories,
                        onChanged: (v) => setState(() {
                          categories = v;
                        }),
                        inputDecoration:
                            const InputDecoration(labelText: "Tags"),
                      ),
                      TextFormField(
                        controller: recurrenceRuleController,
                        decoration: InputDecoration(
                          labelText: "RRULE",
                          suffixIcon: IconButton(
                            onPressed: recurrenceRuleController.clear,
                            icon: const Icon(Icons.clear),
                            tooltip: AppLocalizations.of(context)!.clear,
                          ),
                        ),
                        onTap: () {
                          final valueToUseIfCancel =
                              recurrenceRuleController.text;
                          showDialog(
                            context: context,
                            builder: (BuildContext context) => AlertDialog(
                              title: const Text("Recurrence"),
                              icon: const Icon(Icons.repeat),
                              actions: [
                                TextButton(
                                    onPressed: () {
                                      setState(() {
                                        recurrenceRuleController.text =
                                            valueToUseIfCancel;
                                      });
                                      Navigator.pop(context);
                                    },
                                    child: const Text("Cancel")),
                                TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: const Text("OK")),
                              ],
                              content: SingleChildScrollView(
                                child: RRuleGenerator(
                                  config: RRuleGeneratorConfig(),
                                  initialRRule: recurrenceRuleController.text,
                                  textDelegate:
                                      const EnglishRRuleTextDelegate(),
                                  onChange: (value) {
                                    recurrenceRuleController.text =
                                        value.startsWith("RRULE:")
                                            ? value.replaceFirst("RRULE:", "")
                                            : value;
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      TextFormField(
                        controller: alarmController,
                        decoration: InputDecoration(
                          labelText: "ALARM",
                          suffixIcon: IconButton(
                            onPressed: alarmController.clear,
                            icon: const Icon(Icons.clear),
                            tooltip: AppLocalizations.of(context)!.clear,
                          ),
                        ),
                        validator: (String? value) {
                          // if (value == null || value.isEmpty) {
                          //   return 'Please enter some text';
                          // }
                          return null;
                        },
                      ),
                      Column(children: [
                        ListView.builder(
                            shrinkWrap: true,
                            itemCount: alarms.length,
                            itemBuilder: (BuildContext context, int index) {
                              return ListTile(
                                title: TextFormField(
                                  initialValue: alarms[index]
                                          .triggerRelativeDuration
                                          ?.toString() ??
                                      alarms[index]
                                          .triggerDate
                                          ?.toIso8601String() ??
                                      "",
                                  validator: (value) {
                                    try {
                                      if (value == null || value == "") {
                                        return 'Cannot be blank';
                                      }
                                      IsoDuration.parse(value);
                                    } on FormatException {
                                      return 'Not a valid ISO duration';
                                    }
                                    return null;
                                  },
                                ),
                                /*subtitle: TextFormField(initialValue: alarms[index].repeat.toString(),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value == "" || int.tryParse(value) == null || (int.tryParse(value)! < 0)) {
                              return 'Must be non-negative number';
                            } else {
                              return null;
                            }
                            
                      }, decoration: InputDecoration(labelText: "Alarm action repeat"), onChanged: (value) {
                        if (alarms[index] != null && int.tryParse(value) != null && int.tryParse(value)! >= 0) {
                          alarms[index].repeat = int.parse(value);
                          }
                    },),*/
                              );
                            }),
                      ]),
                    ])),
              ],
            ),
          ),
        ));
  }

  IconButton buildIconButtonSave(VTodo todoComp, BuildContext context) {
    return IconButton(
        tooltip: "Save",
        onPressed: () async {
          if (_formKey.currentState!.validate()) {
            //                                  final itemUid = await this.widget.item.getUid();
            final itemClone = await widget.item.clone();
            bool sequenceChange = false;
            /*
                            
                            sequence must change if:
                            o  "DTSTART"
                            
                            o  "DTEND"
                            
                            o  "DURATION"
                            
                            o  "DUE"
                            
                            o  "RRULE"
                            
                            o  "RDATE"
                            
                            o  "EXDATE"
                            
                            o  "STATUS"
                            */
            bool statusChanged = false;
            if (_status != todoComp.status) {
              todoComp.status = _status;
              sequenceChange = true;
              statusChanged = true;
            }
            if (_priority != todoComp.priority) {
              todoComp.priority = _priority;
            }
            if (todoComp.summary != summaryController.text) {
              todoComp.summary = summaryController.text;
            }
            if (todoComp.description != descriptionController.text) {
              todoComp.description = descriptionController.text;
            }

            todoComp.lastModified = DateTime.now();
            final updatedRecurrenceRule =
                recurrenceRuleController.text.isNotEmpty
                    ? Recurrence.parse(recurrenceRuleController.text)
                    : null;
            if (todoComp.recurrenceRule != updatedRecurrenceRule) {
              todoComp.recurrenceRule = updatedRecurrenceRule;
              sequenceChange = true;
              //if (statusChanged) {
              //  todoComp.recurrenceId = todoComp.start;
              //}
            }
            //if (todoComp.recurrenceRule != null && statusChanged) {
            //todoComp.recurrenceId = todoComp.start;
            // }
            final updatedStart = DateTime.tryParse(startController.text);
            final updatedDue = DateTime.tryParse(dueController.text);

            if ((updatedDue != null && todoComp.due == null) ||
                (updatedDue == null && todoComp.due != null)) {
              todoComp.due = updatedDue;
              sequenceChange = true;
            } else if (todoComp.due != null &&
                updatedDue != null &&
                todoComp.due!.compareTo(updatedDue) != 0) {
              todoComp.due = updatedDue.toUtc();
              sequenceChange = true;
            }
            if ((updatedStart != null && todoComp.start == null) ||
                (updatedStart == null && todoComp.start != null)) {
              todoComp.start = updatedStart?.toUtc();
              sequenceChange = true;
            } else if (todoComp.start != null &&
                updatedStart != null &&
                todoComp.start!.compareTo(updatedStart) != 0) {
              todoComp.start = updatedStart;
              sequenceChange = true;
            }

            if (updatedStart != null &&
                todoComp.start != null &&
                todoComp.due != null &&
                todoComp.start!.isAtSameMomentAs(
                    todoComp.due!.subtract(const Duration(seconds: 1)))) {
              todoComp.due = todoComp.due!.add(const Duration(seconds: 1));
            }

            if (categories.length != (todoComp.categories ?? []).length) {
              todoComp.categories = categories.isNotEmpty ? categories : null;
            } else if (categories
                .toSet()
                .difference((todoComp.categories ?? []).toSet())
                .isNotEmpty) {
              todoComp.categories = categories.isNotEmpty ? categories : null;
            }
            if (alarmController.text.isNotEmpty &&
                alarmController.text !=
                    todoComp.children
                        .where((element) =>
                            element.componentType == VComponentType.alarm)
                        .map((element) => element as VAlarm)
                        .toList()
                        .firstOrNull) {
              final todoAlarmComp = VAlarm(parent: todoComp);
              todoAlarmComp.trigger = TriggerProperty.createWithDuration(
                  IsoDuration.parse(alarmController.text),
                  relation: AlarmTriggerRelationship.end);
              todoAlarmComp.action = AlarmAction.display;
              todoAlarmComp.description = "Default Tasks.org description";
              todoComp.children.add(todoAlarmComp);
            }
            if (sequenceChange) {
              todoComp.sequence = (todoComp.sequence ?? 0) + 1;
            }
            final nextTodo = (statusChanged &&
                    (todoComp.status == TodoStatus.completed ||
                        todoComp.status == TodoStatus.cancelled))
                ? getNextOccurrence(todoComp, todoComp.recurrenceRule)
                : todoComp;

            final actualNextTodo = nextTodo ?? todoComp;

            if (actualNextTodo != todoComp) {
              if (actualNextTodo.getProperty("X-MOZ-SNOOZE-TIME") != null) {
                actualNextTodo.removeProperty("X-MOZ-SNOOZE-TIME");
              }
            }
            actualNextTodo.checkValidity();
            final itemMetaClone = (await itemClone.getMeta()).copyWith(
                mtime: nextTodo?.lastModified ?? todoComp.lastModified);
            await itemClone.setMeta(itemMetaClone);

            await itemClone
                .setContent(utf8.encode(actualNextTodo.parent!.toString()));
            try {
              await widget.itemManager.transaction([itemClone]);
            } on EtebaseException catch (error, stackTrace) {
              if (kDebugMode) {
                print(error);
                print(stackTrace);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(error.message),
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'OK',
                    onPressed: () async {
                      if (error.code == EtebaseErrorCode.conflict) {
                        final itemUpdatedFromServer = await widget.itemManager
                            .fetch(widget.itemMap["itemUid"]);
                        await widget.item.setContent(
                            await itemUpdatedFromServer.getContent());
                        final contentFromServer =
                            await widget.item.getContent();
                        final iCalendarFromServer =
                            VComponent.parse(utf8.decode(contentFromServer))
                                as VCalendar;

                        final todoFromServer = iCalendarFromServer.todo!;
                        await widget.item
                            .setMeta(await itemUpdatedFromServer.getMeta());
                        if (await itemUpdatedFromServer.isDeleted()) {
                          await widget.item.delete();
                        }

                        setState(() {
                          widget.itemMap["itemContent"] = contentFromServer;
                          descriptionController.text =
                              todoFromServer.description ?? "";
                          summaryController.text = todoFromServer.summary ?? "";
                        });
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      }
                    },
                  ),
                ));
              }
              return;
            }
            final itemUpdatedFromServer =
                await widget.itemManager.fetch(widget.itemMap["itemUid"]);

            final username = await getUsernameInCacheDir();

            final cacheClient = await EtebaseFileSystemCache.create(
                widget.client, await getCacheDir(), username);
            final colUid = await getCollectionUIDInCacheDir();
            await cacheClient.itemSet(
                widget.itemManager, colUid, itemUpdatedFromServer);
            await cacheClient.dispose();
            await widget.item
                .setContent(await itemUpdatedFromServer.getContent());
            await widget.item.setMeta(await itemUpdatedFromServer.getMeta());

            if (await itemUpdatedFromServer.isDeleted()) {
              await widget.item.delete();
            }

            final possiblyChangedItemMapData = {
              "itemContent": await widget.item.getContent(),
              "itemUid": await widget.item.getUid(),
              "itemIsDeleted": await widget.item.isDeleted()
            };
            widget.itemMap.addAll(possiblyChangedItemMapData);

            final updatedItemContent = await itemUpdatedFromServer.getContent();
            final updateVCalendar =
                VComponent.parse(utf8.decode(updatedItemContent)) as VCalendar;
            final sendingToNavigator = {
              "item": itemUpdatedFromServer,
              "icalendar": itemUpdatedFromServer,
              "itemContent": updatedItemContent,
              "itemIsDeleted": await itemUpdatedFromServer.isDeleted(),
              "itemUid": await itemUpdatedFromServer.getUid(),
              "todo": updateVCalendar.todo!,
            };
            if (context.mounted) {
              Navigator.maybePop(context, sendingToNavigator);
            }
          }
        },
        icon: const Icon(Icons.save));
  }

  IconButton buildIconButtonDelete(BuildContext context) {
    return IconButton(
        tooltip: "Delete",
        onPressed: () async {
          final action = await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Delete todo'),
                  content: const Text('Would you like to delete this todo?'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Cancel'),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'OK'),
                      child: const Text('OK'),
                    ),
                  ],
                );
              });
          if (action == "OK") {
            await widget.item.delete();
            await widget.itemManager.transaction([widget.item]);
            setState(() {
              wasEdited = true;
            });
            final itemUpdatedFromServer =
                await widget.itemManager.fetch((await widget.item.getUid()));

            final username = await getUsernameInCacheDir();

            final cacheClient = await EtebaseFileSystemCache.create(
                widget.client, await getCacheDir(), username);
            final colUid = await getCollectionUIDInCacheDir();
            await cacheClient.itemSet(
                widget.itemManager, colUid, itemUpdatedFromServer);
            await cacheClient.dispose();

            final updatedItemContent = await itemUpdatedFromServer.getContent();
            final updateVCalendar =
                VComponent.parse(utf8.decode(updatedItemContent)) as VCalendar;
            final sendingToNavigator = {
              "item": itemUpdatedFromServer,
              "icalendar": itemUpdatedFromServer,
              "itemContent": updatedItemContent,
              "itemIsDeleted": await itemUpdatedFromServer.isDeleted(),
              "itemUid": await itemUpdatedFromServer.getUid(),
              "todo": updateVCalendar.todo!,
            };
            if (context.mounted) {
              await Navigator.maybePop(context, sendingToNavigator);
            }
          }
        },
        icon: const Icon(Icons.delete));
  }
}

class RevisionItemWrapper {
  final EtebaseItem revision;
  final DateTime? mtime;

  RevisionItemWrapper({
    required this.revision,
    required this.mtime,
  });
}

class RevisionStatefulWidget extends StatefulWidget {
  final List<RevisionItemWrapper> revisions;

  const RevisionStatefulWidget({super.key, required this.revisions});
  @override
  State<StatefulWidget> createState() => _RevisionStatefulWidgetState();
}

class _RevisionStatefulWidgetState extends State<RevisionStatefulWidget> {
  final toDiff = <RevisionItemWrapper>[];

  @override
  Widget build(BuildContext context) {
    final revisionChildren = <Widget>[];
    for (final element in widget.revisions) {
      final elementWidget = ListTile(
          title: Text(element.mtime!.toString()),
          onLongPress: () {
            setState(() {
              if (toDiff.contains(element)) {
                toDiff.remove(element);
              } else {
                toDiff.add(element);
              }
            });
          },
          selected: toDiff.contains(element),
          leading: toDiff.contains(element) ? const Icon(Icons.check) : null,
          onTap: () async {
            final elementContent = await element.revision.getContent();
            RevisionItemWrapper? action;
            if (context.mounted) {
              action = await showDialog(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                        icon: const CloseButton(),
                        title: Text(element.mtime!.toIso8601String()),
                        content: SelectableText(
                            (VComponent.parse(utf8.decode(elementContent))
                                    as VCalendar)
                                .toString()),
                        actions: [
                          TextButton(
                            child: const Text('Close'),
                            onPressed: () => Navigator.pop(context),
                          ),
                          TextButton(
                              child: const Text("Restore State"),
                              onPressed: () {
                                if (mounted) {
                                  Navigator.pop(context, element);
                                }
                              })
                        ],
                      ));
            }
            if (action != null) {
              if (context.mounted) {
                Navigator.pop(context, action);
              }
            }
          });
      revisionChildren.add(elementWidget);
    }

    return Scaffold(
      appBar: AppBar(
          title: const Text("Revisions"),
          actions: toDiff.length == 2
              ? [
                  IconButton(
                      onPressed: () async {
                        final diffSorted = toDiff.sorted((a, b) {
                          final compared = a.mtime!.compareTo(b.mtime!);
                          return compared;
                        });

                        final diffing = SingleChildScrollView(
                          child: PrettyDiffText(
                            oldText: childrenSorted((VComponent.parse(
                                utf8.decode(
                                    await diffSorted[0].revision.getContent()),
                                customParser:
                                    iCalendarCustomParser) as VCalendar)),
                            newText: childrenSorted((VComponent.parse(
                                utf8.decode(
                                    await diffSorted[1].revision.getContent()),
                                customParser:
                                    iCalendarCustomParser) as VCalendar)),
                          ),
                        );
                        if (context.mounted) {
                          await showDialog(
                              context: context,
                              builder: (BuildContext context) =>
                                  AlertDialog(content: diffing));
                        }
                      },
                      icon: const Icon(Icons.difference))
                ]
              : null),
      body: SingleChildScrollView(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: revisionChildren)),
    );
  }
}

String childrenSorted(VComponent component) {
  final asSorted = <String>[];
  for (var element
      in component.properties.sorted((a, b) => a.name.compareTo(b.name))) {
    asSorted.add(element.toString());
  }
  for (var element
      in component.children.sorted((a, b) => a.name.compareTo(b.name))) {
    asSorted.add(childrenSorted(element));
  }
  return asSorted.join("\n");
}
