import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FareStashApp());

class FareStashApp extends StatelessWidget {
  final TargetPlatform? platformOverride;

  const FareStashApp({super.key, this.platformOverride});

  @override
  Widget build(BuildContext context) {
    const welcome = Center(
      child: Text('Fare Stash — local transit pass journal'),
    );
    final targetPlatform = platformOverride ?? defaultTargetPlatform;
    if (targetPlatform == TargetPlatform.iOS) {
      return const CupertinoApp(
        title: 'Fare Stash',
        home: CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(middle: Text('Fare Stash')),
          child: SafeArea(child: welcome),
        ),
      );
    }
    return MaterialApp(
      title: 'Fare Stash',
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(body: SafeArea(child: welcome)),
    );
  }
}
