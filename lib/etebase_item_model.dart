import 'dart:convert';

import 'package:etebase_flutter/etebase_flutter.dart';
import 'dart:typed_data';

class EtebaseItemModel {
  final bool itemIsDeleted;

  final String itemUid;
  final Uint8List itemContent;
  final String? itemType;
  final String? itemName;
  final DateTime? mtime;
  final Uint8List byteBuffer;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? snoozeTime;
  final String? relatedTo;
  final String? summary;
  final String? uid;
  final String? status;

  EtebaseItemModel(
      {required this.itemIsDeleted,
      required this.itemUid,
      required this.itemContent,
      required this.itemType,
      required this.itemName,
      required this.mtime,
      required this.byteBuffer,
      required this.startTime,
      required this.endTime,
      required this.snoozeTime,
      required this.relatedTo,
      required this.summary,
      required this.uid,
      required this.status});

  static EtebaseItemModel fromMap(Map<String, dynamic> theMap) {
    return EtebaseItemModel(
      itemIsDeleted: theMap["itemIsDeleted"] is int
          ? ((theMap["itemIsDeleted"] == 1) ? true : false)
          : theMap["itemIsDeleted"],
      itemUid: theMap["itemUid"],
      itemContent: theMap["itemContent"],
      itemType: theMap["itemType"],
      itemName: theMap["itemName"],
      mtime: theMap["mtime"] is String
          ? DateTime.parse(theMap["mtime"])
          : theMap["mtime"],
      byteBuffer: theMap["byteBuffer"] is String
          ? base64Decode(theMap["byteBuffer"])
          : theMap["byteBuffer"],
      startTime: theMap["startTime"] is String
          ? DateTime.parse(theMap["startTime"])
          : theMap["startTime"],
      endTime: theMap["endTime"] is String
          ? DateTime.parse(theMap["endTime"])
          : theMap["endTime"],
      snoozeTime: theMap["snoozeTime"] is String
          ? DateTime.parse(theMap["snoozeTime"])
          : theMap["snoozeTime"],
      relatedTo: theMap["relatedTo"],
      summary: theMap["summary"],
      uid: theMap["uid"],
      status: theMap["status"],
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> theMap = {
      "itemIsDeleted": itemIsDeleted,
      "itemContent": itemContent,
      "itemUid": itemUid,
      "itemType": itemType,
      "itemName": itemName,
      "mtime": mtime?.toIso8601String(),
      "byteBuffer": byteBuffer,
      "startTime": startTime?.toIso8601String(),
      "endTime": endTime?.toIso8601String(),
      "snoozeTime": snoozeTime?.toIso8601String(),
      "relatedTo": relatedTo,
      "summary": summary,
      "uid": uid,
      "status": status,
    };
    return theMap;
  }

  Map<String, dynamic> toDbMap() {
    final Map<String, dynamic> theMap = {
      "itemIsDeleted": itemIsDeleted == true ? 1 : 0,
      "itemContent": itemContent,
      "itemUid": itemUid,
      "itemType": itemType,
      "itemName": itemName,
      "mtime": mtime?.toIso8601String(),
      "byteBuffer": base64Encode(byteBuffer),
      "startTime": startTime?.toIso8601String(),
      "endTime": endTime?.toIso8601String(),
      "snoozeTime": snoozeTime?.toIso8601String(),
      "relatedTo": relatedTo,
      "summary": summary,
      "uid": uid,
      "status": status,
    };
    return theMap;
  }
}
