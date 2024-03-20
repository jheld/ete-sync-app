import 'dart:convert';
import 'package:auto_direction/auto_direction.dart';
import 'package:collection/collection.dart';
import 'package:datetime_picker_formfield_new/datetime_picker_formfield.dart';
import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:ete_sync_app/util.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:flutter_input_chips/flutter_input_chips.dart';
import 'package:intl/intl.dart';
import 'package:pretty_diff_text/pretty_diff_text.dart';
import 'package:rrule_generator/rrule_generator.dart';

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

  final recurrenceRuleController = TextEditingController();

  @override
  void initState() {
    super.initState();

    summaryController.text = "";
    descriptionController.text = "";
    startController.text = "";
    dueController.text = "";
    recurrenceRuleController.text = "";
    _status = TodoStatus.unknown;
    _priority = Priority.undefined;
    alarms = <VAlarm>[];
    categories = <String>[];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
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
                      decoration: const InputDecoration(labelText: "Summary"),
                      onChanged: (val) {},
                    ),
                    DropdownButtonFormField(
                      items: Priority.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _priority = value;
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: "Priority"),
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
                      format: DateFormat("yyyy-MM-dd HH:mm"),
                      decoration:
                          const InputDecoration(labelText: "Start date"),
                      controller: startController,
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
                      decoration: const InputDecoration(labelText: "RRULE"),
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
                    TextButton(
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
                            if (todoComp.description !=
                                descriptionController.text) {
                              todoComp.description = descriptionController.text;
                            }

                            todoComp.lastModified = DateTime.now();
                            final updatedRecurrenceRule =
                                recurrenceRuleController.text.isNotEmpty
                                    ? Recurrence.parse(
                                        recurrenceRuleController.text)
                                    : null;
                            if (todoComp.recurrenceRule !=
                                updatedRecurrenceRule) {
                              todoComp.recurrenceRule = updatedRecurrenceRule;
                              sequenceChange = true;
                              //if (statusChanged) {
                              //  todoComp.recurrenceId = todoComp.start;
                              //}
                            }
                            //if (todoComp.recurrenceRule != null && statusChanged) {
                            //todoComp.recurrenceId = todoComp.start;
                            // }
                            final updatedStart =
                                DateTime.tryParse(startController.text);
                            final updatedDue =
                                DateTime.tryParse(dueController.text);

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
                            if ((updatedStart != null &&
                                    todoComp.start == null) ||
                                (updatedStart == null &&
                                    todoComp.start != null)) {
                              todoComp.start = updatedStart;
                              sequenceChange = true;
                            } else if (todoComp.start != null &&
                                updatedStart != null &&
                                todoComp.start!.compareTo(updatedStart) != 0) {
                              todoComp.start = updatedStart;
                              sequenceChange = true;
                            }

                            if (categories.length !=
                                (todoComp.categories ?? []).length) {
                              todoComp.categories =
                                  categories.isNotEmpty ? categories : null;
                            } else if (categories
                                .toSet()
                                .difference((todoComp.categories ?? []).toSet())
                                .isNotEmpty) {
                              todoComp.categories =
                                  categories.isNotEmpty ? categories : null;
                            }

                            if (sequenceChange) {
                              todoComp.sequence = (todoComp.sequence ?? 0) + 1;
                            }
                            todoComp.uid = VCalendar.createUid();
                            todoComp.timeStamp = DateTime.now();
                            final nextTodo = (statusChanged &&
                                    (todoComp.status == TodoStatus.completed ||
                                        todoComp.status ==
                                            TodoStatus.cancelled))
                                ? getNextOccurrence(
                                    todoComp, todoComp.recurrenceRule)
                                : todoComp;

                            final actualNextTodo = nextTodo ?? todoComp;

                            actualNextTodo.checkValidity();
                            final item = await widget.itemManager.create(
                                EtebaseItemMetadata(mtime: DateTime.now()),
                                utf8.encode(todoComp.parent!.toString()));

                            if (kDebugMode) {
                              print("--------BEGIN Intended changes---------");
                              print(actualNextTodo.parent!.toString());
                              print("--------END Intended changes-----------");
                            }

                            await widget.itemManager.transaction([item]);

                            final itemUpdatedFromServer = await widget
                                .itemManager
                                .fetch((await item.getUid()));

                            final username = await getUsernameInCacheDir();

                            final cacheClient =
                                await EtebaseFileSystemCache.create(
                                    widget.client,
                                    await getCacheDir(),
                                    username);
                            final colUid = await getCollectionUIDInCacheDir();
                            await cacheClient.itemSet(widget.itemManager,
                                colUid, itemUpdatedFromServer);
                            await cacheClient.dispose();

                            final updatedItemContent =
                                await itemUpdatedFromServer.getContent();
                            final updateVCalendar = VComponent.parse(
                                utf8.decode(updatedItemContent)) as VCalendar;
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
                        },
                        child: const Text("save")),
                    const Divider(height: 50),
                    IconButton(
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
                                      onPressed: () =>
                                          Navigator.pop(context, 'Continue'),
                                      child: const Text('Continue'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, 'OK'),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                );
                              });
                          if (action == "OK") {
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.cancel)),
                  ])),
            ],
          ),
        ));
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

  final recurrenceRuleController = TextEditingController();
  List<String> categories = [];

  @override
  void initState() {
    super.initState();
    final todoComp = widget.icalendar.todo!;
    summaryController.text = todoComp.summary ?? "";
    descriptionController.text = todoComp.description ?? "";
    startController.text = todoComp.start != null
        ? DateFormat("yyyy-MM-dd HH:mm").format(todoComp.start!)
        : "";
    dueController.text = todoComp.due != null
        ? DateFormat("yyyy-MM-dd HH:mm").format(todoComp.due!)
        : "";
    recurrenceRuleController.text = todoComp.recurrenceRule?.toString() ?? "";
    _status = todoComp.status;
    _priority = todoComp.priority;
    alarms = todoComp.children
        .where((element) => element.componentType == VComponentType.alarm)
        .map((element) => element as VAlarm)
        .toList();
    categories = todoComp.categories ?? [];
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
                    await showDialog(
                      context: context,
                      builder: (BuildContext context) => AlertDialog(
                          title: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Item UID: "),
                                SelectableText(
                                  widget.itemMap["itemUid"],
                                ),
                              ]),
                          content: SingleChildScrollView(
                              child: Text(todoComp.parent!.toString()))),
                    );
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
                      AutoDirection(
                          text: summaryController.text,
                          child: TextFormField(
                            controller: summaryController,
                            validator: (String? value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter some text';
                              }
                              return null;
                            },
                            decoration:
                                const InputDecoration(labelText: "Summary"),
                            onChanged: (val) {},
                          )),
                      DropdownButtonFormField(
                        items: Priority.values
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e.name),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _priority = value;
                            });
                          }
                        },
                        decoration:
                            const InputDecoration(labelText: "Priority"),
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
                              format: DateFormat("yyyy-MM-dd HH:mm"),
                              decoration: const InputDecoration(
                                  labelText: "Start date",
                                  icon: Icon(Icons.start)),
                              initialValue: todoComp.start,
                              controller: startController,
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
                          SizedBox(
                            width: 225,
                            child: DateTimeField(
                              format: DateFormat("yyyy-MM-dd HH:mm"),
                              decoration: const InputDecoration(
                                  labelText: "Due date",
                                  icon: Icon(Icons.stop_circle)),
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
                      AutoDirection(
                          text: descriptionController.text,
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
                        decoration: const InputDecoration(labelText: "RRULE"),
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
            debugPrint("etag: ${await widget.item.getEtag()}");
            final itemClone = await widget.item.clone();
            debugPrint("etag itemClone: ${await itemClone.getEtag()}");
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
            final nextTodo = (statusChanged &&
                    (todoComp.status == TodoStatus.completed ||
                        todoComp.status == TodoStatus.cancelled))
                ? getNextOccurrence(todoComp, todoComp.recurrenceRule)
                : todoComp;

            final actualNextTodo = nextTodo ?? todoComp;
            actualNextTodo.checkValidity();
            final itemMetaClone = (await itemClone.getMeta()).copyWith(
                mtime: nextTodo?.lastModified ?? todoComp.lastModified);
            await itemClone.setMeta(itemMetaClone);
            if (kDebugMode) {
              print("--------BEGIN Intended changes---------");
              print(actualNextTodo.parent!.toString());
              print("--------END Intended changes-----------");
            }
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
                        debugPrint("------ BEGIN server data ---------");
                        debugPrint(iCalendarFromServer.toString());
                        debugPrint("----- END server data -----------");
                        if (kDebugMode) {
                          print(actualNextTodo.parent!
                              .toString()
                              .compareTo(iCalendarFromServer.toString()));
                        }
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

                toDiff.sort((a, b) {
                  final compared = a.mtime!.compareTo(b.mtime!);
                  if (compared < 0) {
                    return -1 * compared;
                  } else if (compared == 0) {
                    return compared;
                  } else {
                    return -1 * compared;
                  }
                });
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
                        final diffing = SingleChildScrollView(
                          child: PrettyDiffText(
                            oldText: childrenSorted((VComponent.parse(
                                    utf8.decode(
                                        await toDiff[0].revision.getContent()))
                                as VCalendar)),
                            newText: childrenSorted((VComponent.parse(
                                    utf8.decode(
                                        await toDiff[1].revision.getContent()))
                                as VCalendar)),
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
