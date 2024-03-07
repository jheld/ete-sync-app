import 'dart:io';

import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:rrule/rrule.dart';

String cacheDir = "${Directory.current.path}/ete_sync_fs_cache";

String getUsernameInCacheDir() {
  final userNames = Directory(cacheDir).listSync().map((e) => e.path).toList();
  late final String username;
  if (userNames.length == 1) {
    username = userNames.first.split("/").last;
  } else {
    throw Exception("More than one username in the cache");
  }

  return username;
}

String getCollectionUIDInCacheDir() {
  final username = getUsernameInCacheDir();
  final collectionUIDNames = Directory("$cacheDir/$username/cols/").listSync();
  if (collectionUIDNames.isEmpty) {
    throw Exception("No collections in cache dir.");
  }
  if (collectionUIDNames.length == 1) {
    return collectionUIDNames.first.path.split("/").last;
  } else {
    throw Exception("Too many collections to naively pick.");
  }
}

Future<EtebaseClient> getEtebaseClient() async {
  final client = await EtebaseClient.create(
      'my-client',
      Uri(
          scheme: "https",
          host: dotenv.env["ete_base_url_host"],
          port: int.parse(dotenv.env["ete_base_url_port"]!)));
  return client;
}

Future<Map<String, dynamic>> getItemListResponse(
    EtebaseItemManager itemManager, EtebaseClient client, String colUid) async {
  bool done = false;
  String? stoken;

  Map<String, dynamic> theMap = {};

  final username = getUsernameInCacheDir();

  final cacheClient =
      await EtebaseFileSystemCache.create(client, cacheDir, username);
  final etebase = await cacheClient.loadAccount(client);
  final collUid = getCollectionUIDInCacheDir();
  final collectionManager = await etebase.getCollectionManager();

  final collection =
      await cacheClient.collectionGet(collectionManager, collUid);

  final collectionSToken = await collection.getStoken();
  if (collectionSToken != null) {
    await cacheClient.collectionSaveStoken(colUid, collectionSToken);
  }
  final cacheItemManager = await collectionManager.getItemManager(collection);
  theMap["itemManager"] = cacheItemManager;
  stoken = await cacheClient.loadStoken();
  final itemsAtCollPath = Directory(cacheDir +
          "/" +
          username +
          "/" +
          "cols" +
          "/" +
          collUid +
          "/" +
          "items")
      .listSync()
      .toList();

  theMap["items"] = <EtebaseItem, Map<String, dynamic>>{};
  for (var cachedItemUID in itemsAtCollPath.map((e) => e.path)) {
    final item = await cacheClient.itemGet(itemManager, collUid, cachedItemUID);
    theMap["items"][item] = {
      "itemIsDeleted": await item.isDeleted(),
      "itemUid": await item.getUid(),
      "itemContent": await item.getContent()
    };
  }
  while (!done) {
    EtebaseItemListResponse rawItemList =
        await itemManager.list(EtebaseFetchOptions(stoken: stoken, limit: 50));
    List<EtebaseItem> itemList = await (rawItemList).getData();
    stoken = await rawItemList.getStoken();
    done = await rawItemList.isDone();

    for (final item in itemList) {
      await cacheClient.itemSet(itemManager, colUid, item);
      final itemUid = await item.getUid();
      for (final elementKeyInMap
          in (theMap["items"] as Map<EtebaseItem, Map<String, dynamic>>).keys) {
        if ((await elementKeyInMap.getUid()) == itemUid) {
          (theMap["items"] as Map).remove(elementKeyInMap);
          break;
        }
      }
      theMap["items"][item] = {
        "itemIsDeleted": await item.isDeleted(),
        "itemUid": await item.getUid(),
        "itemContent": await item.getContent()
      };
    }
  }
  if (stoken != null) {
    await cacheClient.saveStoken(stoken);
  }

  return theMap;
}

VTodo? getNextOccurrence(VTodo todoComp, Recurrence? recurrenceRule) {
  if (recurrenceRule != null) {
    Frequency frequencyT = Frequency.secondly;
    switch (recurrenceRule.frequency) {
      case RecurrenceFrequency.secondly:
        frequencyT = Frequency.secondly;
        break;
      case RecurrenceFrequency.minutely:
        frequencyT = Frequency.minutely;
        break;
      case RecurrenceFrequency.hourly:
        frequencyT = Frequency.hourly;
        break;
      case RecurrenceFrequency.daily:
        frequencyT = Frequency.daily;
        break;
      case RecurrenceFrequency.weekly:
        frequencyT = Frequency.weekly;
        break;
      case RecurrenceFrequency.monthly:
        frequencyT = Frequency.monthly;
        break;
      case RecurrenceFrequency.yearly:
        frequencyT = Frequency.yearly;
        break;
      default:
    }
    if (recurrenceRule.count != null && recurrenceRule.count! <= 1) {
      return null; // end of reccurence
    } else {
      var rrule = RecurrenceRule(
          frequency: frequencyT,
          until: recurrenceRule.until?.toUtc(),
          count: null,
          interval: recurrenceRule.interval,
          bySeconds: recurrenceRule.bySecond ?? [],
          byMinutes: recurrenceRule.byMinute ?? [],
          byHours: recurrenceRule.byHour ?? [],
          byWeekDays: recurrenceRule.byWeekDay
                  ?.map((value) => ByWeekDayEntry(value.weekday, value.week))
                  .toList() ??
              [],
          byMonthDays: recurrenceRule.byMonthDay ?? [],
          byYearDays: recurrenceRule.byYearDay ?? [],
          byWeeks: recurrenceRule.byWeek ?? [],
          byMonths: recurrenceRule.byMonth ?? []);
      final instancesStart =
          (todoComp.start ?? todoComp.due!).copyWith(isUtc: true);
      final instances = rrule.getInstances(start: instancesStart).iterator;
      DateTime? nextInstance;
      while (instances.moveNext()) {
        final instance = instances.current;
        if (instance.compareTo(DateTime.now().toUtc()) == 1 &&
            instance.compareTo(instancesStart) == 1) {
          nextInstance = instance;
          break;
        }
      }
      if (nextInstance != null) {
        final nextStartDate = todoComp.start != null ? nextInstance : null;
        DateTime? nextDueDate = todoComp.due != null ? nextInstance : null;
        if (nextStartDate != null && nextDueDate != null) {
          final offset = todoComp.due!.difference(todoComp.start!);
          nextDueDate = nextDueDate.add(offset);
        }
        final nextTodo = todoComp as VTodo;

        //nextTodo.uid = (const Uuid()).v4();
        if (nextStartDate != null) {
          nextTodo.start =
              nextStartDate.copyWith(isUtc: todoComp.start?.isUtc ?? false);
        }
        if (nextDueDate != null) {
          nextTodo.due =
              nextDueDate.copyWith(isUtc: todoComp.due?.isUtc ?? false);
        }

        if (todoComp.recurrenceRule?.count != null &&
            todoComp.recurrenceRule!.count! > 0) {
          nextTodo.recurrenceRule =
              recurrenceRule.copyWith(count: recurrenceRule.count! - 1);
        }
        nextTodo.status = TodoStatus.needsAction;
        nextTodo.lastModified = DateTime.now();
        return nextTodo;
      }
    }

    return null;
  } else {
    return null;
  }
}

class ItemMapWrapper {
  final EtebaseItem item;
  final Map<String, dynamic> value;
  final VCalendar icalendar;

  ItemMapWrapper(
      {required this.item, required this.value, required this.icalendar});
}
/*
Recurrence initRRule(String recurrence) {
  final rrule = Recurrence.parse(recurrence);
              if (rrule.frequency != RecurrenceFrequency.weekly && rrule.frequency != RecurrenceFrequency.monthly) {
                rrule.byWeekDay?.clear();
                rrule.byMonthDay?.clear();
                
            }
            return rrule;
  }

  Future<void> handleRepeat(VTodo todo) async {
final recurrence = todo.recurrenceRule;
if (recurrence == null) {
  return;
  }
  final repeatAfterCompletion = true; // todo.repeatAfterCompletion();
  final rrule = initRRule(recurrence.toString());
              final count = rrule.count;
            if (count == 1) {
                //broadcastCompletion(task)
                return;
            }
                        final newDueDate = computeNextDueDate(todo, recurrence.toString(), repeatAfterCompletion)
            if (newDueDate == -1) {
                return;
            }
    }


            int computeNextDueDate(VTodo task, String recurrence, bool repeatAfterCompletion) {
            final rrule = initRRule(recurrence);

            // initialize startDateAsDV
            final original = setUpStartDate(task, repeatAfterCompletion, rrule.frequency);
            final startDateAsDV = setUpStartDateAsDV(task, original);
             
            if (rrule.frequency == RecurrenceFrequency.hourly || rrule.frequency == RecurrenceFrequency.minutely) {
                return handleSubdayRepeat(original, rrule);
            } else if (rrule.frequency == RecurrenceFrequency.weekly && (rrule.byWeekDay ?? rrule.byMonthDay ?? []).isNotEmpty  && repeatAfterCompletion) {
                return handleWeeklyRepeatAfterComplete(rrule, original, task.due != null);
            } else if (rrule.frequency == RecurrenceFrequency.monthly && (rrule.byWeekDay ?? rrule.byMonthDay ?? []).isNotEmpty) {
                return handleMonthlyRepeat(original, startDateAsDV, task.due != null, rrule);
            } else {
                return invokeRecurrence(rrule, original, startDateAsDV, task.recurrenceRule!);
            }
        }


        int invokeRecurrence(Recurrence recur, DateTime original, DateTime startDateAsDV) {
            final nextDateMaybe = recur.getNextDate(startDateAsDV, startDateAsDV, recur);

                return buildNewDueDate(original, nextDateMaybe!);

        }

        DateTime getNextDate(DateTime seed, DateTime startDateAsDV, Recurrence recur) {

          RecurrenceRule(Frequency((recur.frequency.index - 6).abs(), recur.frequency.name), until: recur.until, count: recur.count, interval: recur.interval, bySeconds: recur.bySecond, byMinutes: recur.byMinute, byHours: recur.byHour ?? [], byWeekDays: recur.byWeekDay ?? [], byMonthDays: recur.byMonthDay ?? [], byYearDays: recur.byYearDay ?? [], byWeeks: recur.byWeek ?? [], byMonth: recur.byMonth ?? [])
          }


        DateTime setUpStartDate(
                VTodo task, bool repeatAfterCompletion, RecurrenceFrequency frequency) {
            if (repeatAfterCompletion) {
                var startDate = task.completed != null ? task.completed!.copyWith() : DateTime.now();
                if (task.due != null && frequency != RecurrenceFrequency.hourly && frequency != RecurrenceFrequency.minutely) {
                    final dueDate = task.due!.copyWith();
                    startDate = startDate
                            .copyWith(hour: dueDate.hour, minute: dueDate.minute, second: dueDate.second);
                }
                return startDate;
            } else {
                if (task.due != null) {return task.due!.copyWith();} else {return DateTime.now();}
            }
        }


        DateTime setUpStartDateAsDV(VTodo task, DateTime startDate) {
            if (task.due != null) {
                return startDate.copyWith();
            } else {
                return startDate.copyWith(hour: 0, minute: 0, second: 0);
            }
        }


        int handleWeeklyRepeatAfterComplete(
                Recurrence recur, DateTime original, bool hasDueTime) {
            final byDay = recur.byWeekDay;
            var newDate = original.millisecond;
            
            newDate += 3600000 * 24 * 7 * ((recur.interval < 1 ? 1 : recur.interval) - 1);
            var date = DateTime.fromMillisecondsSinceEpoch(newDate);
            
            byDay?.sort((a, b) => convertToSundayFirst(a.toString()) - convertToSundayFirst(b.toString()));
            final next = findNextWeekday(byDay!.map((value) => value.weekday).toList(), date);
            date = date.add(Duration(days: 1));            
            while (date.weekday != next) {
              date = date.add(Duration(days: 1));            
              }
            final timeT = date.millisecondsSinceEpoch;
            if (hasDueTime) {
                return createDueDate(8, timeT);
            } else {
                return createDueDate(7, timeT);
            }
        }

        int createDueDate(int setting, int customDate) {
          int date = 0;
            switch (setting) {
                case 0: date = 0 ;break;
                case 1: date = DateTime.now().millisecondsSinceEpoch ;break;
                case 2: date = DateTime.now().add(Duration(days: 1)).millisecondsSinceEpoch 
;break;                case 3: date = DateTime.now().add(Duration(days: 2)).millisecondsSinceEpoch ;break;
                case 4: date = DateTime.now().add(Duration(days: 7)).millisecondsSinceEpoch ;break;
                case 5: DateTime.now().add(Duration(days: 14)).millisecondsSinceEpoch ; break;
                case 6:
                case 7: date = customDate; break;
            }
            if (date <= (0 )) {
                return date;
            }
            var dueDate = DateTime.fromMillisecondsSinceEpoch(date).copyWith(millisecond: 0);
            if (setting != 8) {
                dueDate = dueDate
                        .copyWith(hour: 12, minute:0, second: 0) // Seconds == 0 means no due time
            } else {
                dueDate = dueDate.copyWith(second: 1) // Seconds > 0 means due time exists
            }
            return dueDate.millisecondsSinceEpoch;
        }

        int sundayAsFirst(int day) {
          int adjustedDay = day + 1;
          return adjustedDay % DateTime.daysPerWeek;
          }

        int findNextWeekday(List<int> byDay, DateTime date) {
            final next = byDay[0];
            for (final weekday in byDay) {
              if (sundayAsFirst(weekday) > sundayAsFirst(date.weekday)) {
                return weekday;
                }
            }
            return next;
        }

        int convertToSundayFirst(String item) {
          int converted = -1;
          switch (item) {
            case "SU":
            converted = 1;
            break;
            case "MO":
            converted = 2;
            break;
            case "TU":
            converted = 3;
            break;
            case "WE":
            converted = 4;
            break;
            case "TH":
            converted = 5;
            break;
            case "FR":
            converted = 6;
            break;
            default:
            converted = 7;
            break;
            }
            return converted;
          }*/

