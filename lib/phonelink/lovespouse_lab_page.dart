// PhoneLink addition: LoveSpouse Test Lab.
//
// Lets the user broadcast any plain LoveSpouse command number and record what
// the toy does with it (responds or not, how fast compared with others, which
// motor, steady or a pattern). Results are kept on the phone and can be copied
// as text to share for analysis.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intiface_central/phonelink/broadcast_channel.dart';
import 'package:intiface_central/phonelink/lovespouse.dart';
import 'package:intiface_central/phonelink/lovespouse_encoder.dart';
import 'package:intiface_central/widget/detail_header_widget.dart';
import 'package:loggy/loggy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LabOutcome { works, noResponse }

class LabResult {
  LabOutcome? outcome;
  int? speed; // 1 (slowest) .. 10 (fastest), null = not rated
  bool vibration;
  bool stroke;
  bool pattern;
  String note;

  LabResult({
    this.outcome,
    this.speed,
    this.vibration = false,
    this.stroke = false,
    this.pattern = false,
    this.note = '',
  });

  bool get isEmpty =>
      outcome == null && speed == null && !vibration && !stroke && !pattern && note.isEmpty;

  Map<String, dynamic> toJson() => {
        'outcome': outcome?.name,
        'speed': speed,
        'vibration': vibration,
        'stroke': stroke,
        'pattern': pattern,
        'note': note,
      };

  factory LabResult.fromJson(Map<String, dynamic> json) => LabResult(
        outcome: LabOutcome.values.where((o) => o.name == json['outcome']).firstOrNull,
        speed: json['speed'] as int?,
        vibration: json['vibration'] as bool? ?? false,
        stroke: json['stroke'] as bool? ?? false,
        pattern: json['pattern'] as bool? ?? false,
        note: json['note'] as String? ?? '',
      );
}

class LoveSpouseLabPage extends StatefulWidget {
  final VoidCallback onBack;

  const LoveSpouseLabPage({super.key, required this.onBack});

  @override
  State<LoveSpouseLabPage> createState() => _LoveSpouseLabPageState();
}

class _LoveSpouseLabPageState extends State<LoveSpouseLabPage> {
  static const _prefsKey = 'phonelink.lovespouse_lab.v1';
  static const _stopHold = Duration(seconds: 2);

  /// Commands with a known meaning, shown as labels next to the number.
  static const Map<int, String> _known = {
    0x00: 'Stop',
    0x12: 'Level 1',
    0x13: 'Level 2',
    0x14: 'Level 3',
    0x15: 'Level 4',
    0x16: 'Level 5',
    0x17: 'Level 6',
    0x18: 'Level 7',
    0x19: 'Level 8',
    0x20: 'Max (captured)',
    0x30: 'Captured, unknown',
    0x31: 'Captured, unknown',
  };

  int _command = 0x11;
  int? _playing; // command currently on the air, null when quiet
  String? _error;
  Timer? _stopTimer;
  final Map<int, LabResult> _results = {};
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    Permission.bluetoothAdvertise.request().catchError((Object e) {
      logError('PhoneLink lab: could not request advertise permission: $e');
      return PermissionStatus.denied;
    });
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    // Never leave the toy running when the screen closes.
    if (_playing != null && _playing != LoveSpouse.plainStop) {
      PhoneLinkBroadcast.advertiseServiceUuids(
        LoveSpouse.serviceUuidsForPlain([LoveSpouse.plainStop]),
      );
      Timer(_stopHold, PhoneLinkBroadcast.stop);
    } else {
      PhoneLinkBroadcast.stop();
    }
    _noteController.dispose();
    super.dispose();
  }

  // ---------- persistence ----------

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _results.clear();
        map.forEach((k, v) {
          _results[int.parse(k)] = LabResult.fromJson(v as Map<String, dynamic>);
        });
        _noteController.text = _results[_command]?.note ?? '';
      });
    } catch (e) {
      logError('PhoneLink lab: could not load results: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _results.removeWhere((_, r) => r.isEmpty);
      await prefs.setString(
        _prefsKey,
        jsonEncode({for (final e in _results.entries) '${e.key}': e.value.toJson()}),
      );
    } catch (e) {
      logError('PhoneLink lab: could not save results: $e');
    }
  }

  LabResult get _current => _results.putIfAbsent(_command, LabResult.new);

  void _update(void Function(LabResult r) change) {
    setState(() => change(_current));
    _save();
  }

  // ---------- broadcasting ----------

  Future<void> _play(int plain) async {
    _stopTimer?.cancel();
    final error = await PhoneLinkBroadcast.advertiseServiceUuids(
      LoveSpouse.serviceUuidsForPlain([plain]),
    );
    if (!mounted) return;
    setState(() {
      _error = error;
      _playing = error == null ? plain : null;
    });
    if (error == null && plain == LoveSpouse.plainStop) {
      _stopTimer = Timer(_stopHold, () {
        PhoneLinkBroadcast.stop();
        if (mounted) setState(() => _playing = null);
      });
    }
  }

  void _stop() => _play(LoveSpouse.plainStop);

  void _selectCommand(int command) {
    final wasPlayingTest = _playing != null &&
        _playing != LoveSpouse.plainStop &&
        _playing == _command;
    setState(() {
      _command = command & 0xFF;
      _noteController.text = _results[_command]?.note ?? '';
    });
    // While testing, stepping to another number sends it right away.
    if (wasPlayingTest) _play(_command);
  }

  void _nextUntested() {
    for (var i = 1; i <= 256; i++) {
      final c = (_command + i) & 0xFF;
      if (_results[c]?.outcome == null) {
        _selectCommand(c);
        return;
      }
    }
  }

  // ---------- export ----------

  String _hex(int v) => '0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  String _exportText() {
    final buf = StringBuffer('LoveSpouse lab results (PhoneLink)\n');
    buf.writeln('cmd | known as | result | speed 1-10 | vibration | stroke | pattern | note');
    final keys = _results.keys.toList()..sort();
    for (final k in keys) {
      final r = _results[k]!;
      if (r.isEmpty) continue;
      buf.writeln([
        _hex(k),
        _known[k] ?? '',
        switch (r.outcome) {
          LabOutcome.works => 'works',
          LabOutcome.noResponse => 'no response',
          null => 'not marked',
        },
        r.speed?.toString() ?? '-',
        r.vibration ? 'yes' : '-',
        r.stroke ? 'yes' : '-',
        r.pattern ? 'yes' : '-',
        r.note.replaceAll('\n', ' '),
      ].join(' | '));
    }
    return buf.toString();
  }

  Future<void> _copyResults() async {
    await Clipboard.setData(ClipboardData(text: _exportText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Results copied. Paste them into the chat.')),
    );
  }

  Future<void> _clearResults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all results?'),
        content: const Text('This deletes every recorded result on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _results.clear();
      _noteController.clear();
    });
    _save();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encoded = LoveSpouseEncoder.encode([_command]).sublist(8);
    final playingThis = _playing == _command && _playing != LoveSpouse.plainStop;
    final r = _results[_command];

    return Expanded(
      child: Column(
        children: [
          DetailHeader(title: 'LoveSpouse Test Lab', onBack: widget.onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                Text(
                  'Turn off any LoveSpouse device in PhoneLink while testing, so only '
                  'this screen is broadcasting. Use Compare to play a known level, then '
                  'tap Send to go back to the test command.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),

                // Command picker
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton.filledTonal(
                              iconSize: 32,
                              icon: const Icon(Icons.remove),
                              onPressed: () => _selectCommand(_command - 1),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(_hex(_command), style: theme.textTheme.displaySmall),
                                  Text(
                                    _known[_command] ?? 'decimal $_command',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    'sends ${encoded.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              iconSize: 32,
                              icon: const Icon(Icons.add),
                              onPressed: () => _selectCommand(_command + 1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            ActionChip(label: const Text('Next untested'), onPressed: _nextUntested),
                            for (final c in [0x11, 0x20, 0x30, 0x40])
                              ActionChip(label: Text('Go to ${_hex(c)}'), onPressed: () => _selectCommand(c)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Send / stop
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                        icon: Icon(playingThis ? Icons.wifi_tethering : Icons.play_arrow),
                        label: Text(playingThis ? 'Sending ${_hex(_command)}' : 'Send ${_hex(_command)}'),
                        onPressed: () => _play(_command),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.stop),
                        label: const Text('STOP'),
                        onPressed: _stop,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Compare:', style: theme.textTheme.bodyMedium),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _play(LoveSpouse.plainLevel1),
                      child: const Text('Level 1'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _play(LoveSpouse.plainLevel8),
                      child: const Text('Level 8'),
                    ),
                  ],
                ),
                if (_playing != null && _playing != _command)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Now playing ${_known[_playing] ?? _hex(_playing!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Broadcast error: $_error',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),

                // Result for this command
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What did ${_hex(_command)} do?', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        SegmentedButton<LabOutcome>(
                          emptySelectionAllowed: true,
                          segments: const [
                            ButtonSegment(
                              value: LabOutcome.works,
                              icon: Icon(Icons.check_circle_outline),
                              label: Text('Works'),
                            ),
                            ButtonSegment(
                              value: LabOutcome.noResponse,
                              icon: Icon(Icons.block),
                              label: Text('No response'),
                            ),
                          ],
                          selected: {if (r?.outcome != null) r!.outcome!},
                          onSelectionChanged: (s) =>
                              _update((res) => res.outcome = s.isEmpty ? null : s.first),
                        ),
                        if (r?.outcome == LabOutcome.works) ...[
                          const SizedBox(height: 12),
                          Text(
                            r?.speed == null
                                ? 'Speed: not rated (1 = slowest, 10 = fastest)'
                                : 'Speed: ${r!.speed} of 10',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Slider(
                            min: 1,
                            max: 10,
                            divisions: 9,
                            value: (r?.speed ?? 5).toDouble(),
                            label: '${r?.speed ?? 5}',
                            onChanged: (v) => _update((res) => res.speed = v.round()),
                          ),
                          Text(
                            'Tip: Level 1 is about 1-2 and Level 8 about 8-9. Use Compare to check.',
                            style: theme.textTheme.bodySmall,
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Vibration motor runs'),
                            value: r?.vibration ?? false,
                            onChanged: (v) => _update((res) => res.vibration = v ?? false),
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Stroke motor runs'),
                            value: r?.stroke ?? false,
                            onChanged: (v) => _update((res) => res.stroke = v ?? false),
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Changes by itself (a pattern, not steady)'),
                            value: r?.pattern ?? false,
                            onChanged: (v) => _update((res) => res.pattern = v ?? false),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (t) => _update((res) => res.note = t),
                        ),
                      ],
                    ),
                  ),
                ),

                // All results
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Results (${_results.values.where((x) => !x.isEmpty).length})',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                      onPressed: _copyResults,
                    ),
                    TextButton(onPressed: _clearResults, child: const Text('Clear')),
                  ],
                ),
                for (final k in (_results.keys.toList()..sort()))
                  if (!_results[k]!.isEmpty)
                    ListTile(
                      dense: true,
                      selected: k == _command,
                      leading: Icon(switch (_results[k]!.outcome) {
                        LabOutcome.works => Icons.check_circle,
                        LabOutcome.noResponse => Icons.block,
                        null => Icons.help_outline,
                      }),
                      title: Text('${_hex(k)}  ${_known[k] ?? ''}'),
                      subtitle: Text(_summary(_results[k]!)),
                      onTap: () => _selectCommand(k),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _summary(LabResult r) {
    final parts = <String>[
      if (r.outcome == LabOutcome.noResponse) 'no response',
      if (r.speed != null) 'speed ${r.speed}',
      if (r.vibration) 'vibration',
      if (r.stroke) 'stroke',
      if (r.pattern) 'pattern',
      if (r.note.isNotEmpty) r.note,
    ];
    return parts.isEmpty ? 'works' : parts.join(', ');
  }
}
