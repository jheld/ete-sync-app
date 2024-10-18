import 'dart:convert';
import 'dart:typed_data';

class EtebaseNoteModel {
  final bool itemIsDeleted;

  final String itemUid;
  final Uint8List itemContent;
  final String? itemType;
  final String? itemName;
  final DateTime? mtime;
  final Uint8List byteBuffer;

  EtebaseNoteModel({
    required this.itemIsDeleted,
    required this.itemUid,
    required this.itemContent,
    required this.itemType,
    required this.itemName,
    required this.mtime,
    required this.byteBuffer,
  });

  static EtebaseNoteModel fromMap(Map<String, dynamic> theMap) {
    return EtebaseNoteModel(
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
    };
    return theMap;
  }
}
