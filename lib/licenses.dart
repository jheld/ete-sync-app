import 'package:flutter/material.dart';

class LicensesWidget extends StatelessWidget {
  const LicensesWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Licenses')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  "\"'There is a Phabricator task for that!' Sticker version 2A\" by takidelfin is marked with CC0 1.0. To view the terms, visit https://creativecommons.org/publicdomain/zero/1.0/deed.en/?ref=openverse.")
            ],
          ),
        ));
  }
}
