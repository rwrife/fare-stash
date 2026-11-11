import 'dart:math';

import 'package:fare_stash/data/pass_store.dart';
import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      return CupertinoApp(
        title: 'Fare Stash',
        home: CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Fare Stash'),
          ),
          child: SafeArea(child: home),
        ),
      );
    }
    return MaterialApp(
      title: 'Fare Stash',
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Fare Stash')),
        body: SafeArea(child: home),
      ),
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
  List<PassLedger> _passes = [];
  static final _random = Random.secure();

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
  bool get _ios => widget.platform == TargetPlatform.iOS;

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
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Widget _button(String label, VoidCallback onPressed) => _ios
      ? CupertinoButton(onPressed: onPressed, child: Text(label))
      : TextButton(onPressed: onPressed, child: Text(label));

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: _ios
        ? CupertinoTextField(
            controller: controller,
            placeholder: label,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            prefix: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('$label: '),
            ),
          )
        : TextField(
            controller: controller,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
  );

  Future<void> _dialog(String title, Widget body, VoidCallback save) async {
    if (_ios) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: body,
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(onPressed: save, child: const Text('Save')),
          ],
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(child: body),
          ),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Text('Loading passes'));
    if (_store == null) {
      return Center(child: Text(_error ?? 'Storage unavailable'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Manual estimates only — not proof of a valid ticket.'),
        _button('Add pass', () => _passEditor()),
        if (_error != null) Text(_error!, key: const Key('store-error')),
        if (_passes.isEmpty) const Text('No passes yet'),
        for (final ledger in _passes) ...[
          const Divider(),
          Text(ledger.pass.title, style: const TextStyle(fontSize: 20)),
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
            children: [
              _button(
                'Edit ${ledger.pass.title}',
                () => _passEditor(ledger.pass),
              ),
              _button(
                'Log ride on ${ledger.pass.title}',
                () => _rideEditor(ledger),
              ),
            ],
          ),
          for (final event in ledger.events.reversed)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${event.kind.name} · ${event.occurredAt.toLocal()} · ${event.units ?? 'reverses ${event.reversesId}'}',
                  ),
                ),
                if (event.kind != PassEventKind.reversal &&
                    !ledger.events.any((e) => e.reversesId == event.id))
                  _button('Reverse ${event.id}', () => _correct(ledger, event)),
              ],
            ),
        ],
      ],
    );
  }
}
