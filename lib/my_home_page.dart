import 'dart:convert';
import 'package:datetime_picker_formfield_new/datetime_picker_formfield.dart';
import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:ete_sync_app/etebase_item_route.dart';
import 'package:ete_sync_app/i_calendar_custom_parser.dart';
import 'package:ete_sync_app/util.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rrule/rrule.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage(
      {super.key,
      required this.title,
      required this.itemManager,
      required this.client,
      required this.colUid});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;
  final EtebaseItemManager itemManager;
  final EtebaseClient client;
  final String colUid;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Future<Map<String, dynamic>>? _itemListResponse;
  String? _searchText;
  DateTime? dateSearchStart;
  DateTime? dateSearchEnd;
  bool todaySearch = true;
  bool showCompleted = false;

  final _searchTextController = TextEditingController();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void dispose() {
    this.widget.client.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _itemListResponse = getItemListResponse(
          this.widget.itemManager, this.widget.client, this.widget.colUid);
      dateSearchEnd = (dateSearchEnd ?? DateTime.now())
          .copyWith(hour: 23, minute: 59, second: 59);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateSelectionWidgets = <Widget>[
      Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text("Today"),
            Switch(
                value: todaySearch,
                activeColor:
                    _searchTextController.text.isNotEmpty ? Colors.grey : null,
                onChanged: (bool newValue) {
                  setState(() {
                    todaySearch = newValue;
                    if (newValue) {
                      dateSearchEnd = DateTime.now()
                          .copyWith(hour: 23, minute: 59, second: 59);
                      dateSearchStart = DateTime.now()
                          .copyWith(hour: 0, minute: 0, second: 0);
                    }
                  });
                }),
            const VerticalDivider()
          ]),
      Expanded(
        //width: max(MediaQuery.sizeOf(context).width / 6, 200),
        child: DateTimeField(
          format: DateFormat("yyyy-MM-dd"),
          enabled: !todaySearch,
          decoration: const InputDecoration(
            icon: Icon(Icons.calendar_month),
            labelText: "Start date range",
          ),
          initialValue: (dateSearchStart ?? DateTime.now())
              .copyWith(hour: 0, minute: 0, second: 0),
          controller: null,
          onShowPicker: (context, currentValue) async {
            return await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              initialDate: (currentValue ?? DateTime.now())
                  .copyWith(hour: 0, minute: 0, second: 0),
              lastDate: DateTime(2100),
            ).then((value) async => (value ?? DateTime.now())
                .copyWith(hour: 0, minute: 0, second: 0));
          },
          onChanged: (value) {
            setState(() {
              dateSearchStart = value?.copyWith(hour: 0, minute: 0, second: 0);
            });
          },
        ),
      ),
      Expanded(
        //width: max(MediaQuery.sizeOf(context).width / 6, 200),
        child: DateTimeField(
          format: DateFormat("yyyy-MM-dd"),
          enabled: !todaySearch,
          decoration: const InputDecoration(
              icon: Icon(Icons.calendar_month), labelText: "End date range"),
          initialValue: (dateSearchEnd ?? DateTime.now())
              .copyWith(hour: 23, minute: 59, second: 59),
          controller: null,
          onShowPicker: (context, currentValue) async {
            return await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              initialDate: (currentValue ?? DateTime.now())
                  .copyWith(hour: 23, minute: 59, second: 59),
              lastDate: DateTime(2100),
            ).then((value) async => (value ?? DateTime.now())
                .copyWith(hour: 23, minute: 59, second: 59));
          },
          onChanged: (value) {
            setState(() {
              dateSearchEnd = value?.copyWith(hour: 23, minute: 59, second: 59);
            });
          },
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (BuildContext context) => EtebaseItemCreateRoute(
                          itemManager: this.widget.itemManager,
                          client: this.widget.client)))
              .then((value) => _refreshIndicatorKey.currentState!.show());
        },
        tooltip: "Create task",
        child: const Icon(Icons.add),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SearchBar(
            controller: _searchTextController,
            hintText: "Search",
            leading: _searchTextController.text.isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: "Clear",
                    onPressed: () {
                      setState(() {
                        _searchText = null;
                        _searchTextController.text = "";
                      });
                    },
                  ),
            onSubmitted: (value) {
              setState(() {
                _searchText = value;
                _searchTextController.text = value;
              });
            },
            onChanged: (value) => setState(() {
              _searchText = value;
              _searchTextController.text = value;
            }),
          ),
          SizedBox(
              width: MediaQuery.sizeOf(context).width > 800
                  ? MediaQuery.sizeOf(context).width / 2
                  : null,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: dateSelectionWidgets)),
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.check),
                Switch(
                  value: showCompleted,
                  onChanged: (value) => setState(() {
                    showCompleted = value;
                  }),
                )
              ]),
          RefreshIndicator(
            key: _refreshIndicatorKey,
            onRefresh: () async {
              setState(() {
                _itemListResponse = getItemListResponse(this.widget.itemManager,
                    this.widget.client, this.widget.colUid);
              });
              return _itemListResponse!.then((value) => null);
            },
            child: Column(
              children: [
                FutureBuilder<Map<String, dynamic>?>(
                    future: _itemListResponse,
                    builder: (BuildContext context,
                        AsyncSnapshot<Map<String, dynamic>?> snapshot) {
                      List<Widget> children = [];
                      if (snapshot.hasData && snapshot.data != null) {
                        final itemManager = snapshot.data!["itemManager"];
                        final itemMap = (snapshot.data!)["items"]
                            as Map<EtebaseItem, Map<String, dynamic>>;
                        children.addAll(
                            todoItemList(itemManager, itemMap, snapshot.data!));
                      } else {
                        children.add(const CircularProgressIndicator());
                      }
                      return Padding(
                          padding: const EdgeInsets.all(8),
                          child: SizedBox(
                              //width: 600,
                              height: MediaQuery.sizeOf(context).height / 2,
                              child: ListView.builder(
                                  itemCount: children.length,
                                  itemBuilder: (context, index) =>
                                      children[index])));
                    }),
              ],
            ),
          ),
        ],
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  Future<Map<String, dynamic>?> onPressedItemWidget(
      BuildContext context,
      EtebaseItem item,
      VCalendar icalendar,
      EtebaseItemManager itemManager,
      Map<String, dynamic> itemMap,
      EtebaseClient client) async {
    return await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
            builder: (context) => EtebaseItemRoute(
                item: item,
                icalendar: icalendar,
                itemManager: itemManager,
                itemMap: itemMap,
                client: client)));
  }

  List<Widget> todoItemList(
      EtebaseItemManager itemManager,
      Map<EtebaseItem, Map<String, dynamic>> itemMap,
      Map<String, dynamic> fullSnapshot) {
    List<Widget> children = [];
    final itemsSorted = <ItemMapWrapper>[];
    final itemsByUID = <String, ItemMapWrapper>{};
    for (final entry in itemMap.entries) {
      final key = entry.key;
      final value = entry.value;
      late final VCalendar icalendar;
      try {
        icalendar = VComponent.parse(
            utf8.decode(value["itemContent"] as Uint8List),
            customParser: iCalendarCustomParser) as VCalendar;
      } catch (e) {
        continue;
      }

      if (value["itemIsDeleted"]) {
        continue;
      }

      if (icalendar.todo == null) {
        continue;
      }
      final compTodo = icalendar.todo!;

      final statusTodo = compTodo.status;

      if (statusTodo == TodoStatus.cancelled) {
        continue;
      }

      if (statusTodo == TodoStatus.completed && !showCompleted) {
        continue;
      }

      itemsSorted
          .add(ItemMapWrapper(item: key, value: value, icalendar: icalendar));
      itemsByUID[icalendar.todo!.uid] = itemsSorted.last;
    }
    itemsSorted.sort((a, b) {
      final priorityIntCompare =
          (a.icalendar.todo!.priorityInt ?? Priority.low.numericValue)
              .compareTo(
                  (b.icalendar.todo!.priorityInt ?? Priority.low.numericValue));

      DateTime? aDue = /*a.icalendar.todo!.start ??*/ a.icalendar.todo!.due;
      if (aDue == null && (a.icalendar.todo!.relatedTo?.isNotEmpty ?? false)) {
        aDue = /*itemsByUID[a.icalendar.todo!.relatedTo]?.icalendar.todo!.start ??*/
            itemsByUID[a.icalendar.todo!.relatedTo]?.icalendar.todo!.due;
      }
      DateTime? bDue = /*a.icalendar.todo!.start ??*/ b.icalendar.todo!.due;
      if (bDue == null && (b.icalendar.todo!.relatedTo?.isNotEmpty ?? false)) {
        bDue = /*itemsByUID[b.icalendar.todo!.relatedTo]?.icalendar.todo!.start ??*/
            itemsByUID[b.icalendar.todo!.relatedTo]?.icalendar.todo!.due;
      }
      final timeCompare = (aDue ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(bDue ?? DateTime.fromMillisecondsSinceEpoch(0));

      if ((aDue ?? DateTime.fromMillisecondsSinceEpoch(0)).day ==
          (bDue ?? DateTime.fromMillisecondsSinceEpoch(0)).day) {
        if (priorityIntCompare != 0) {
          return priorityIntCompare;
        }
      }

      if (timeCompare == 0) {
        if (a.icalendar.todo!.relatedTo?.isNotEmpty ?? false) {
          if (b.icalendar.todo!.relatedTo?.isEmpty ??
              b.icalendar.todo!.relatedTo == null) {
            return 1;
          } else {
            return timeCompare;
          }
        } else {
          if (b.icalendar.todo!.relatedTo == null ||
              b.icalendar.todo!.relatedTo!.isEmpty) {
            return timeCompare;
          } else {
            return -1;
          }
        }
      } else {
        return timeCompare;
      }
    });
    for (final item in itemsSorted) {
      final eteItem = item.item;

      VCalendar? icalendar;
      icalendar = item.icalendar;

      final compTodo = icalendar.todo!;

      final statusTodo = compTodo.status;

      if (_searchText != null &&
          !(compTodo.summary?.toLowerCase() ?? "")
              .contains(_searchText!.toLowerCase())) {
        continue;
      }
      DateTime? dateForLogicStart = compTodo.start;
      DateTime? dateForLogicDue = compTodo.due;
      compTodo.due;
      if (compTodo.relatedTo != null &&
          compTodo.relatedTo!.isNotEmpty &&
          compTodo.start == null &&
          compTodo.due == null) {
        dateForLogicStart =
            itemsByUID[compTodo.relatedTo!]!.icalendar.todo!.start;
        dateForLogicDue = itemsByUID[compTodo.relatedTo!]!.icalendar.todo!.due;
        // final theIterFromMap = itemsSorted
        //     .where(
        //         (element) => element.icalendar.todo!.uid == compTodo.relatedTo)
        //     .toList();
        // if (theIterFromMap.isNotEmpty) {
        //   final icalendarRelated = theIterFromMap[0].icalendar;
        //   dateForLogicStart = icalendarRelated.todo!.start;

        //   dateForLogicDue = icalendarRelated.todo!.due;
        // }
      }

      if (dateSearchEnd != null &&
          (dateForLogicStart != null || dateForLogicDue != null) &&
          (dateForLogicStart ?? dateForLogicDue!).compareTo(dateSearchEnd!) ==
              1 &&
          _searchTextController.text.isEmpty) {
        continue;
      }
      final actionColor = switch (compTodo.priority) {
        Priority.low => Colors.blue,
        Priority.undefined || null => Colors.grey,
        Priority.medium => Colors.orange,
        Priority.high => Colors.red,
      };
      final child = ListTile(
        title: Text(compTodo.summary ?? ""),
        subtitle: Text(
            'start: ${icalendar.todo!.start ?? (compTodo.relatedTo != null ? dateForLogicStart : null)}, due: ${icalendar.todo!.due ?? (compTodo.relatedTo != null ? dateForLogicDue : null)}'),
        trailing: IconButton(
          icon: Icon(icalendar.todo!.recurrenceRule != null
              ? Icons.repeat
              : (statusTodo == TodoStatus.completed
                  ? Icons.check
                  : Icons.check_box_outline_blank)),
          color: actionColor,
          onPressed: statusTodo == TodoStatus.completed
              ? null
              : () async {
                  await onPressedToggleCompletion(
                          eteItem, icalendar!, itemManager, compTodo)
                      .then((value) async {
                    setState(() {
                      (fullSnapshot["items"]! as Map).remove(eteItem);
                      (fullSnapshot["items"]! as Map)[value["item"]] = {
                        "itemContent": value["itemContent"],
                        "itemUid": value["itemUid"],
                        "itemIsDeleted": value["itemIsDeleted"]
                      };
                      _itemListResponse =
                          Future<Map<String, dynamic>>.value(fullSnapshot);
                    });

                    final username = getUsernameInCacheDir();
                    final cacheClient = await EtebaseFileSystemCache.create(
                        this.widget.client, cacheDir, username);
                    final colUid = getCollectionUIDInCacheDir();
                    await cacheClient.itemSet(
                        this.widget.itemManager, colUid, value["item"]);
                    await cacheClient.dispose();
                  }).onError((error, stackTrace) {
                    if (kDebugMode) {
                      print(error);
                    }
                    if (error is EtebaseException) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(error.message),
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: 'OK',
                          onPressed: () async {
                            if (error.code == EtebaseErrorCode.conflict) {
                              final itemUpdatedFromServer = await this
                                  .widget
                                  .itemManager
                                  .fetch(await eteItem.getUid());
                              final contentFromServer =
                                  await itemUpdatedFromServer.getContent();

                              (fullSnapshot["items"]! as Map).remove(eteItem);

                              (fullSnapshot["items"]!
                                  as Map)[itemUpdatedFromServer] = {
                                "itemContent": contentFromServer,
                                "itemUid": await itemUpdatedFromServer.getUid(),
                                "itemIsDeleted":
                                    await itemUpdatedFromServer.isDeleted(),
                              };
                              setState(() {
                                _itemListResponse =
                                    Future<Map<String, dynamic>>.value(
                                        fullSnapshot);
                              });
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                            }
                          },
                        ),
                      ));
                    }
                  });
                },
        ),
        onTap: () => onPressedItemWidget(context, eteItem, icalendar!,
                itemManager, item.value, this.widget.client)
            .then((value) {
          if (value != null) {
            (fullSnapshot["items"]! as Map).remove(eteItem);

            (fullSnapshot["items"]! as Map)[value["item"]] = {
              "itemContent": value["itemContent"],
              "itemUid": value["itemUid"],
              "itemIsDeleted": value["itemIsDeleted"]
            };
            setState(() {
              _itemListResponse =
                  Future<Map<String, dynamic>>.value(fullSnapshot);
            });
            //_refreshIndicatorKey.currentState?.show();
          } else {
            /*setState(() {
              _itemListResponse = getItemListResponse(itemManager);
            });*/
          }
        }),
      );
      children.add(child);
    }
    return children;
  }

  Future<Map<String, dynamic>> onPressedToggleCompletion(
      EtebaseItem eteItem,
      VCalendar icalendar,
      EtebaseItemManager itemManager,
      VTodo compTodo) async {
    final itemClone = await eteItem.clone();
    final todoComp = compTodo;
    bool sequenceChange = false;
    const changedStatus = TodoStatus.completed;
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
    if (changedStatus != todoComp.status) {
      todoComp.status = changedStatus;
      sequenceChange = true;
      statusChanged = true;
    }

    todoComp.lastModified = DateTime.now();

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
    final itemMetaClone = (await itemClone.getMeta())
        .copyWith(mtime: nextTodo?.lastModified ?? todoComp.lastModified);
    await itemClone.setMeta(itemMetaClone);
    if (kDebugMode) {
      print("--------BEGIN Intended changes---------");
      print(actualNextTodo.toString());
      print("--------END Intended changes-----------");
    }

    await itemClone.setContent(utf8.encode(actualNextTodo.parent!.toString()));
    await itemManager.transaction([itemClone]);
    await eteItem.setContent(await itemClone.getContent());
    final eteItemFromServer = await itemManager.fetch(await eteItem.getUid());
    final icalendarUpdated =
        VComponent.parse(utf8.decode(await eteItemFromServer.getContent()))
            as VCalendar;
    return {
      "item": eteItemFromServer,
      "icalendar": icalendarUpdated,
      "itemContent": (await eteItemFromServer.getContent()),
      "todo": icalendarUpdated.todo!,
      "itemIsDeleted": (await eteItemFromServer.isDeleted()),
      "itemUid": (await eteItemFromServer.getUid()),
    };
  }
}
