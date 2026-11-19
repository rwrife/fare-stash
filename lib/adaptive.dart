import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Keeps platform controls out of the pass and history presentation.
class AdaptiveControls {
  final TargetPlatform platform;

  const AdaptiveControls(this.platform);

  bool get ios => platform == TargetPlatform.iOS;
  bool get windows => platform == TargetPlatform.windows;

  Widget button(String label, VoidCallback onPressed) {
    if (ios) {
      return CupertinoButton(onPressed: onPressed, child: Text(label));
    }
    if (windows) {
      return fluent.Button(onPressed: onPressed, child: Text(label));
    }
    return TextButton(onPressed: onPressed, child: Text(label));
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) {
    final keyboard = numeric ? TextInputType.number : TextInputType.text;
    if (ios) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          CupertinoTextField(
            controller: controller,
            placeholder: label,
            keyboardType: keyboard,
          ),
        ],
      );
    }
    if (windows) {
      return fluent.InfoLabel(
        label: label,
        child: fluent.TextBox(controller: controller, keyboardType: keyboard),
      );
    }
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget card(BuildContext context, Widget child) {
    final content = Padding(padding: const EdgeInsets.all(16), child: child);
    if (ios) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      );
    }
    if (windows) return fluent.Card(child: child);
    return Card(child: content);
  }

  Future<void> dialog(
    BuildContext context,
    String title,
    Widget body,
    VoidCallback save,
  ) {
    final content = SingleChildScrollView(child: body);
    if (ios) {
      return showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: content,
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(onPressed: save, child: const Text('Save')),
          ],
        ),
      );
    }
    if (windows) {
      return fluent.showDialog<void>(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: Text(title),
          content: content,
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            fluent.FilledButton(onPressed: save, child: const Text('Save')),
          ],
        ),
      );
    }
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 420, child: content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: save, child: const Text('Save')),
        ],
      ),
    );
  }
}

class AdaptiveWorkspace extends StatelessWidget {
  final TargetPlatform platform;
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget passes;
  final Widget history;

  const AdaptiveWorkspace({
    super.key,
    required this.platform,
    required this.selected,
    required this.onSelected,
    required this.passes,
    required this.history,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final content = wide
          ? Row(
              key: const Key('split-workspace'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: passes),
                Expanded(child: history),
              ],
            )
          : selected == 0
          ? passes
          : history;
      if (platform == TargetPlatform.windows) {
        return fluent.NavigationView(
          key: const Key('windows-workspace'),
          pane: fluent.NavigationPane(
            header: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Fare Stash'),
            ),
            displayMode: constraints.maxWidth >= 1100
                ? fluent.PaneDisplayMode.expanded
                : fluent.PaneDisplayMode.compact,
            selected: selected,
            onChanged: onSelected,
            items: [
              fluent.PaneItem(
                icon: const Icon(fluent.FluentIcons.ticket),
                title: const Text('Passes'),
                body: content,
              ),
              fluent.PaneItem(
                icon: const Icon(fluent.FluentIcons.history),
                title: const Text('History'),
                body: content,
              ),
            ],
          ),
        );
      }
      if (platform == TargetPlatform.iOS) {
        return CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Fare Stash'),
          ),
          child: SafeArea(
            child: Column(
              children: [
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: CupertinoSlidingSegmentedControl<int>(
                      groupValue: selected,
                      children: const {0: Text('Passes'), 1: Text('History')},
                      onValueChanged: (value) {
                        if (value != null) onSelected(value);
                      },
                    ),
                  ),
                Expanded(child: content),
              ],
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Fare Stash')),
        body: SafeArea(
          child: constraints.maxWidth >= 600 && !wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selected,
                      onDestinationSelected: onSelected,
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.confirmation_number_outlined),
                          label: Text('Passes'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.history),
                          label: Text('History'),
                        ),
                      ],
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
        ),
        bottomNavigationBar: constraints.maxWidth < 600
            ? NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: onSelected,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.confirmation_number_outlined),
                    label: 'Passes',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history),
                    label: 'History',
                  ),
                ],
              )
            : null,
      );
    },
  );
}
