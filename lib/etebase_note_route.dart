import 'dart:convert';

import 'package:ete_sync_app/util.dart';
import 'package:etebase_flutter/etebase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart' as intl;

class EtebaseItemNoteCreateRoute extends StatefulWidget {
  const EtebaseItemNoteCreateRoute(
      {super.key, required this.itemManager, required this.client});

  final EtebaseItemManager itemManager;
  final EtebaseClient client;

  @override
  State<StatefulWidget> createState() => _EtebaseItemNoteCreateRouteState();
}

class _EtebaseItemNoteCreateRouteState
    extends State<EtebaseItemNoteCreateRoute> {
  final nameController = TextEditingController();
  final contentController = TextEditingController();
  bool showMarkdown = false;
  final _formKey = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    nameController.text = "";
    contentController.text = "";
  }

  @override
  void dispose() {
    nameController.dispose();
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(),
        body: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                      controller: nameController,
                      textDirection:
                          intl.Bidi.detectRtlDirectionality(nameController.text)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.title),
                      onChanged: (value) => ()),
                  Switch(
                      value: showMarkdown,
                      onChanged: (value) => setState(() {
                            showMarkdown = value;
                          })),
                  const Divider(),
                  !showMarkdown
                      ? TextFormField(
                          controller: contentController,
                          textDirection: intl.Bidi.detectRtlDirectionality(
                                  contentController.text)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)!.content),
                          maxLines: null,
                          onChanged: (value) => (),
                        )
                      : SizedBox(
                          height: 600,
                          child: Directionality(
                              textDirection: intl.Bidi.detectRtlDirectionality(
                                      contentController.text)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                              child: Markdown(data: contentController.text))),
                  TextButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          final item = await widget.itemManager.create(
                              EtebaseItemMetadata(
                                  mtime: DateTime.now(),
                                  name: nameController.text.isNotEmpty
                                      ? nameController.text
                                      : null),
                              utf8.encode(contentController.text));

                          await widget.itemManager.transaction([item]);

                          final itemUpdatedFromServer = await widget.itemManager
                              .fetch((await item.getUid()));

                          final username = await getUsernameInCacheDir();

                          final cacheClient =
                              await EtebaseFileSystemCache.create(
                                  widget.client, await getCacheDir(), username);
                          final colUid = await getCollectionUIDInCacheDir();
                          await cacheClient.itemSet(widget.itemManager, colUid,
                              itemUpdatedFromServer);
                          await cacheClient.dispose();

                          final updatedItemContent =
                              await itemUpdatedFromServer.getContent();

                          final sendingToNavigator = {
                            "item": itemUpdatedFromServer,
                            "itemContent": updatedItemContent,
                            "itemIsDeleted":
                                await itemUpdatedFromServer.isDeleted(),
                            "itemUid": await itemUpdatedFromServer.getUid(),
                            "itemName":
                                (await itemUpdatedFromServer.getMeta()).name,
                          };
                          if (context.mounted) {
                            Navigator.maybePop(context, sendingToNavigator);
                          }
                        }
                      },
                      child: Text(AppLocalizations.of(context)!.save))
                ],
              ),
            ),
          ],
        ));
  }
}

class EtebaseItemNoteRoute extends StatefulWidget {
  const EtebaseItemNoteRoute(
      {super.key,
      required this.itemManager,
      required this.client,
      required this.item,
      required this.itemMap});

  final EtebaseItemManager itemManager;
  final EtebaseClient client;
  final EtebaseItem item;
  final Map<String, dynamic> itemMap;

  @override
  State<StatefulWidget> createState() => _EtebaseItemNoteRouteState();
}

class _EtebaseItemNoteRouteState extends State<EtebaseItemNoteRoute> {
  final nameController = TextEditingController();
  final contentController = TextEditingController();
  bool showMarkdown = false;
  final _formKey = GlobalKey<FormState>();

  bool wasEdited = false;
  @override
  void initState() {
    super.initState();
    nameController.text = widget.itemMap["itemName"] ?? "";
    contentController.text = utf8.decode(widget.itemMap["itemContent"]);
  }

  @override
  void dispose() {
    nameController.dispose();
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          actions: [
            buildIconButtonDelete(context),
            const VerticalDivider(width: 100),
            buildIconButtonSave(context),
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
          title: const Text("Note view"),
        ),
        body: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(children: [
                Directionality(
                    textDirection:
                        intl.Bidi.detectRtlDirectionality(nameController.text)
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                    child: TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "Title"),
                        onChanged: (value) => ())),
                Switch(
                    value: showMarkdown,
                    onChanged: (value) => setState(() {
                          showMarkdown = value;
                        })),
                const Divider(),
                !showMarkdown
                    ? Directionality(
                        textDirection: intl.Bidi.detectRtlDirectionality(
                                contentController.text)
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: TextFormField(
                          controller: contentController,
                          decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)!.content),
                          maxLines: null,
                          onChanged: (value) => (),
                        ))
                    : SizedBox(
                        height: 600,
                        child: Directionality(
                            textDirection: intl.Bidi.detectRtlDirectionality(
                                    contentController.text)
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Markdown(data: contentController.text))),
              ]),
            ),
          ],
        ));
  }

  IconButton buildIconButtonSave(BuildContext context) {
    return IconButton(
        onPressed: () async {
          if (_formKey.currentState!.validate()) {
            final currentName = (await widget.item.getMeta()).name;
            String? updatedName = currentName;
            if (((currentName == null || currentName.isEmpty) &&
                    nameController.text.isNotEmpty) ||
                (currentName != null && currentName != nameController.text)) {
              updatedName = nameController.text;
            }
            bool anyChange = false;
            final itemClone = await widget.item.clone();

            if (utf8.decode(await widget.item.getContent()) !=
                contentController.text) {
              await itemClone.setContent(utf8.encode(contentController.text));
              anyChange = true;
            }
            if (updatedName != currentName || anyChange) {
              final itemMetaClone = (await itemClone.getMeta())
                  .copyWith(mtime: DateTime.now(), name: updatedName);
              await itemClone.setMeta(itemMetaClone);
              anyChange = true;
            }

            await widget.itemManager.transaction([itemClone]);

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

            final sendingToNavigator = {
              "item": await widget.itemManager
                  .cacheSaveWithContent(itemUpdatedFromServer),
              "itemContent": updatedItemContent,
              "itemIsDeleted": await itemUpdatedFromServer.isDeleted(),
              "itemUid": await itemUpdatedFromServer.getUid(),
              "itemName": (await itemUpdatedFromServer.getMeta()).name,
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
            final sendingToNavigator = {
              "item": await widget.itemManager
                  .cacheSaveWithContent(itemUpdatedFromServer),
              "itemContent": updatedItemContent,
              "itemIsDeleted": await itemUpdatedFromServer.isDeleted(),
              "itemUid": await itemUpdatedFromServer.getUid(),
              "itemName": (await itemUpdatedFromServer.getMeta()).name,
            };
            if (context.mounted) {
              await Navigator.maybePop(context, sendingToNavigator);
            }
          }
        },
        icon: const Icon(Icons.delete));
  }
}
