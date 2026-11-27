import 'dart:convert';
import 'dart:math';

import 'package:fare_stash/adaptive.dart';
import 'package:fare_stash/data/pass_backup.dart';
import 'package:fare_stash/data/pass_store.dart';
import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const FareStashApp());

class FareStashApp extends StatelessWidget {
  final TargetPlatform? platformOverride;
  final PassStore? store;

  const FareStashApp({super.key, this.platformOverride, this.store});

  @override
  Widget build(BuildContext context) {
    final platform = platformOverride ?? defaultTargetPlatform;
    final home = PassHome(store: store, platform: platform);
    if (platform == TargetPlatform.iOS) {
      return CupertinoApp(title: 'Fare Stash', home: home);
    }
    if (platform == TargetPlatform.windows) {
      return fluent.FluentApp(
        title: 'Fare Stash',
        themeMode: fluent.ThemeMode.system,
        theme: fluent.FluentThemeData(brightness: Brightness.light),
        darkTheme: fluent.FluentThemeData(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery.highContrastOf(context)
            ? fluent.FluentTheme(
                data: fluent.FluentThemeData(
                  brightness: Brightness.dark,
                  scaffoldBackgroundColor: Colors.black,
                  cardColor: Colors.black,
                  acrylicBackgroundColor: Colors.black,
                  accentColor: fluent.Colors.yellow,
                ),
                child: child!,
              )
            : child!,
        home: home,
      );
    }
    return MaterialApp(
      title: 'Fare Stash',
      theme: ThemeData(useMaterial3: true, platform: platform),
      darkTheme: ThemeData(
        useMaterial3: true,
        platform: platform,
        brightness: Brightness.dark,
      ),
      highContrastTheme: ThemeData(
        useMaterial3: true,
        platform: platform,
        colorScheme: const ColorScheme.highContrastLight(),
      ),
      highContrastDarkTheme: ThemeData(
        useMaterial3: true,
        platform: platform,
        colorScheme: const ColorScheme.highContrastDark(),
      ),
      home: home,
    );
  }
}

class PassHome extends StatefulWidget {
  final PassStore? store;
  final TargetPlatform platform;

  const PassHome({super.key, this.store, required this.platform});

  @override
  State<PassHome> createState() => _PassHomeState();
}

class _PassHomeState extends State<PassHome> {
  PassStore? _store;
  bool _loading = true;
  String? _error;
  String? _notice;
  List<PassLedger> _passes = [];
  int _selected = 0;
  static final _random = Random.secure();

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
  AdaptiveControls get _controls => AdaptiveControls(widget.platform);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final store = widget.store ?? await PassStore.openDefault();
      if (!mounted) {
        if (widget.store == null) store.close();
        return;
      }
      setState(() {
        _store = store;
        _passes = store.all();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (widget.store == null) _store?.close();
    super.dispose();
  }

  void _change(VoidCallback action) {
    try {
      action();
      setState(() {
        _passes = _store!.all();
        _error = null;
        _notice = null;
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Widget _button(String label, VoidCallback onPressed) =>
      _controls.button(label, onPressed);

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: _controls.field(label, controller, numeric: numeric),
  );

  Future<void> _dialog(String title, Widget body, VoidCallback save) =>
      _controls.dialog(context, title, body, save);

  void _passEditor([TransitPass? original]) {
    final title = TextEditingController(text: original?.title);
    final balance = TextEditingController(
      text: original?.startingBalance?.toString(),
    );
    final currency = TextEditingController(text: original?.currency ?? 'USD');
    final from = TextEditingController(
      text: original?.validFrom?.toLocal().toIso8601String() ?? '',
    );
    final until = TextEditingController(
      text: original?.validUntil?.toLocal().toIso8601String() ?? '',
    );
    var kind = original?.kind ?? PassKind.ridePack;
    String? message;
    StateSetter? refresh;
    _dialog(
      original == null ? 'Add pass' : 'Edit pass',
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Pass name', title),
              // Explicit kind controls prevent implicit balance/currency assumptions.
              for (final option in PassKind.values)
                _button(
                  '${kind == option ? '●' : '○'} ${option.name}',
                  () => setState(() => kind = option),
                ),
              if (kind != PassKind.timeLimited)
                _field(
                  kind == PassKind.ridePack
                      ? 'Starting rides'
                      : 'Starting minor units',
                  balance,
                  numeric: true,
                ),
              if (kind == PassKind.storedValue)
                _field('ISO currency', currency),
              if (kind == PassKind.timeLimited)
                _field('Valid from (ISO date/time)', from),
              if (kind == PassKind.timeLimited)
                _field('Valid until (ISO date/time)', until),
              if (message != null) Text(message!, key: const Key('form-error')),
            ],
          );
        },
      ),
      () {
        try {
          final pass = TransitPass(
            id: original?.id ?? _id(),
            title: title.text.trim(),
            kind: kind,
            startingBalance: kind == PassKind.timeLimited
                ? null
                : int.parse(balance.text.trim()),
            currency: kind == PassKind.storedValue
                ? currency.text.trim().toUpperCase()
                : null,
            validFrom: from.text.trim().isEmpty
                ? null
                : DateTime.parse(from.text.trim()),
            validUntil: until.text.trim().isEmpty
                ? null
                : DateTime.parse(until.text.trim()),
          );
          if (original == null) {
            _store!.save(pass, []);
          } else {
            _store!.update(pass);
          }
          Navigator.pop(context);
          setState(() {
            _passes = _store!.all();
            _error = null;
          });
        } catch (error) {
          message = '$error';
          refresh?.call(() {});
        }
      },
    );
  }

  void _rideEditor(PassLedger ledger) {
    final units = TextEditingController(
      text: ledger.pass.kind == PassKind.ridePack
          ? '1'
          : ledger.pass.kind == PassKind.timeLimited
          ? '0'
          : '',
    );
    final when = TextEditingController(
      text: DateTime.now().toLocal().toIso8601String(),
    );
    String? message;
    StateSetter? refresh;
    _dialog(
      'Log ride: ${ledger.pass.title}',
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Local date/time (ISO)', when),
              if (ledger.pass.kind == PassKind.storedValue)
                _field('Fare in minor units', units, numeric: true),
              if (message != null) Text(message!, key: const Key('form-error')),
            ],
          );
        },
      ),
      () {
        try {
          _store!.record(
            PassEvent(
              id: _id(),
              passId: ledger.pass.id,
              occurredAt: DateTime.parse(when.text.trim()),
              kind: PassEventKind.ride,
              units: int.parse(units.text.trim()),
              currency: ledger.pass.currency,
            ),
          );
          Navigator.pop(context);
          setState(() {
            _passes = _store!.all();
            _error = null;
          });
        } catch (error) {
          message = '$error';
          refresh?.call(() {});
        }
      },
    );
  }

  void _correct(PassLedger ledger, PassEvent event) {
    _change(
      () => _store!.record(
        PassEvent(
          id: _id(),
          passId: ledger.pass.id,
          occurredAt: DateTime.now(),
          kind: PassEventKind.reversal,
          reversesId: event.id,
        ),
      ),
    );
  }

  Future<void> _saveTextFile({
    required String title,
    required String fileName,
    required String extension,
    required String Function() contents,
  }) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: title,
        fileName: fileName,
        mimeType: extension == 'json' ? 'application/json' : 'text/csv',
        bytes: Uint8List.fromList(utf8.encode(contents())),
      );
      if (uri == null) return;
      if (!mounted) return;
      setState(() {
        _error = null;
        _notice = 'Saved $fileName';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _notice = null;
      });
    }
  }

  Future<void> _exportBackup() => _saveTextFile(
    title: 'Export Fare Stash backup',
    fileName: 'fare-stash-backup.json',
    extension: 'json',
    contents: () => PassBackup.encode(_store!.all()),
  );

  Future<void> _exportCsv() => _saveTextFile(
    title: 'Export Fare Stash ride history',
    fileName: 'fare-stash-rides.csv',
    extension: 'csv',
    contents: () => PassBackup.toCsv(_store!.all()),
  );

  Future<bool?> _confirmRestore() {
    const warning =
        'This replaces all passes and ride history currently stored on this device.';
    if (_controls.ios) {
      return showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Restore backup?'),
          content: const Text(warning),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace data'),
            ),
          ],
        ),
      );
    }
    if (_controls.windows) {
      return fluent.showDialog<bool>(
        context: context,
        builder: (context) => fluent.ContentDialog(
          title: const Text('Restore backup?'),
          content: const Text(warning),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            fluent.FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace data'),
            ),
          ],
        ),
      );
    }
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(warning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace data'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup() async {
    try {
      final selection = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (selection == null) return;
      final ledgers = PassBackup.decode(
        utf8.decode(await selection.readAsBytes()),
      );
      if (!mounted || await _confirmRestore() != true) return;
      _store!.restoreAll(ledgers);
      setState(() {
        _passes = _store!.all();
        _error = null;
        _notice = 'Backup restored';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _notice = null;
      });
    }
  }

  Widget _heading(String text) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget _passList() => ListView(
    key: const PageStorageKey('passes'),
    padding: const EdgeInsets.all(16),
    children: [
      _heading('Your passes'),
      const Text('Manual estimates only — not proof of a valid ticket.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _button('Add pass', () => _passEditor()),
          _button('Export JSON backup', _exportBackup),
          _button('Restore JSON backup', _restoreBackup),
          _button('Export ride history CSV', _exportCsv),
        ],
      ),
      if (_notice != null)
        Semantics(
          liveRegion: true,
          child: Text(_notice!, key: const Key('store-notice')),
        ),
      if (_error != null)
        Semantics(
          liveRegion: true,
          child: Text(_error!, key: const Key('store-error')),
        ),
      if (_passes.isEmpty) const Text('No passes yet'),
      for (final ledger in _passes)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _controls.card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(ledger.pass.title),
                Text(
                  '${ledger.pass.kind.name} · ${ledger.balance == null ? 'time pass' : '${ledger.balance} ${ledger.pass.currency ?? 'rides'} left'} · ${ledger.rideCount} rides logged',
                ),
                Text(
                  ledger.pass.validAt(DateTime.now()) &&
                          (ledger.balance == null || ledger.balance! > 0)
                      ? 'Estimated active'
                      : 'Expired or depleted (estimate)',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _button(
                      'Edit ${ledger.pass.title}',
                      () => _passEditor(ledger.pass),
                    ),
                    _button(
                      'Log ride on ${ledger.pass.title}',
                      () => _rideEditor(ledger),
                    ),
                    _button(
                      'History for ${ledger.pass.title}',
                      () => _showHistory(ledger.pass),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _history({String? passId, VoidCallback? onChanged}) {
    final passes = _passes.where(
      (ledger) => passId == null || ledger.pass.id == passId,
    );
    return ListView(
      key: PageStorageKey('history-${passId ?? 'all'}'),
      padding: const EdgeInsets.all(16),
      children: [
        _heading('Ride history'),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (passes.every((ledger) => ledger.events.isEmpty))
          const Text('No rides recorded yet'),
        for (final ledger in passes)
          if (ledger.events.isNotEmpty) ...[
            _heading(ledger.pass.title),
            for (final event in ledger.events.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _controls.card(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event.kind.name} · ${event.occurredAt.toLocal()} · ${event.units ?? 'reverses ${event.reversesId}'}',
                      ),
                      if (event.kind != PassEventKind.reversal &&
                          !ledger.events.any((e) => e.reversesId == event.id))
                        _button('Reverse ${event.id}', () {
                          _correct(ledger, event);
                          onChanged?.call();
                        }),
                    ],
                  ),
                ),
              ),
          ],
      ],
    );
  }

  void _showHistory(TransitPass pass) {
    Widget page(BuildContext context) => StatefulBuilder(
      builder: (context, refresh) {
        final body = _history(passId: pass.id, onChanged: () => refresh(() {}));
        if (_controls.ios) {
          return CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text(pass.title)),
            child: SafeArea(child: body),
          );
        }
        if (_controls.windows) {
          return fluent.NavigationView(
            content: fluent.ScaffoldPage(
              header: fluent.PageHeader(
                title: Text(pass.title),
                leading: fluent.IconButton(
                  icon: const Icon(fluent.FluentIcons.back),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              content: body,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(pass.title)),
          body: SafeArea(child: body),
        );
      },
    );

    Navigator.of(context).push<void>(
      _controls.ios
          ? CupertinoPageRoute<void>(builder: page)
          : _controls.windows
          ? fluent.FluentPageRoute<void>(builder: page)
          : MaterialPageRoute<void>(builder: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = !_loading && _store != null;
    final placeholder = Center(
      child: Semantics(
        liveRegion: true,
        child: Text(
          _loading ? 'Loading passes' : _error ?? 'Storage unavailable',
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        if (available) ...{
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              _passEditor(),
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              _passEditor(),
        },
      },
      child: FocusTraversalGroup(
        child: Focus(
          autofocus: true,
          child: AdaptiveWorkspace(
            platform: widget.platform,
            selected: _selected,
            onSelected: (value) => setState(() => _selected = value),
            passes: available ? _passList() : placeholder,
            history: available ? _history() : placeholder,
          ),
        ),
      ),
    );
  }
}
