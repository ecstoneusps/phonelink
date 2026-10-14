// PhoneLink addition: connects LoveSpouse toys to the Buttplug engine.
//
// How it works: the user adds a simulated vibrator in PhoneLink and gives it a
// display name containing "LoveSpouse". Games and the app's own controls then
// see a normal vibrator. The engine reports every command it sends to a device
// as an "output observation"; this bridge watches those for the LoveSpouse
// device and broadcasts the matching LoveSpouse advertisement.

import 'dart:async';

import 'package:buttplug/buttplug.dart';
import 'package:intiface_central/bloc/device/device_cubit.dart';
import 'package:intiface_central/bloc/device/device_manager_bloc.dart';
import 'package:intiface_central/bloc/engine/engine_control_bloc.dart';
import 'package:intiface_central/bloc/engine/engine_messages.dart';
import 'package:intiface_central/phonelink/broadcast_channel.dart';
import 'package:intiface_central/phonelink/lovespouse.dart';
import 'package:loggy/loggy.dart';
import 'package:permission_handler/permission_handler.dart';

class LoveSpouseBridge {
  /// Device cubit -> (device index, max output value) for LoveSpouse devices.
  final Map<DeviceCubit, ({int index, double maxValue})> _devices = {};
  final Stream<DeviceOutputObservation> Function() _observationStream;
  StreamSubscription<DeviceOutputObservation>? _observationSub;
  Timer? _stopTimer;
  int _currentLevel = -1;

  /// How long to keep broadcasting the stop command before going quiet.
  static const _stopHold = Duration(seconds: 2);

  LoveSpouseBridge({
    required Stream<DeviceManagerState> deviceStates,
    required Stream<EngineControlState> engineStates,
    required Stream<DeviceOutputObservation> Function() observationStream,
  }) : _observationStream = observationStream {
    if (!PhoneLinkBroadcast.supported) return;
    deviceStates.listen(_onDeviceState);
    engineStates.listen((state) {
      if (state is EngineStoppedState) _reset();
    });
  }

  static bool isLoveSpouse(ButtplugClientDevice device) {
    final names = '${device.displayName ?? ''} ${device.name}'.toLowerCase();
    return names.contains('lovespouse') || names.contains('love spouse');
  }

  static double _maxValue(ButtplugClientDevice device) {
    double max = 0;
    for (final feature in device.features.values) {
      final outputs = feature.feature.output;
      if (outputs == null) continue;
      for (final output in outputs.values) {
        final range = output.value;
        if (range != null && range.length > 1 && range[1] > max) {
          max = range[1].toDouble();
        }
      }
    }
    return max > 0 ? max : 100;
  }

  Future<void> _onDeviceState(DeviceManagerState state) async {
    if (state is DeviceManagerDeviceOnlineState) {
      final device = state.device.device;
      if (device == null) return;
      if (!isLoveSpouse(device)) {
        logInfo('PhoneLink: "${device.displayName ?? device.name}" is not a LoveSpouse device, ignoring');
        return;
      }
      logInfo('PhoneLink: LoveSpouse bridge attached to "${device.displayName ?? device.name}"');
      _devices[state.device] = (index: device.index, maxValue: _maxValue(device));
      final permission = await Permission.bluetoothAdvertise.request();
      logInfo('PhoneLink: Bluetooth advertise permission: $permission');
      // The observation stream is recreated on each engine start, so
      // resubscribe now that we know the engine is running.
      await _observationSub?.cancel();
      _observationSub = _observationStream().listen(_onObservation);
    } else if (state is DeviceManagerDeviceOfflineState) {
      if (_devices.remove(state.device) != null) {
        logInfo('PhoneLink: LoveSpouse device went offline, stopping toy');
        _setLevel(0);
      }
    }
  }

  void _onObservation(DeviceOutputObservation obs) {
    for (final entry in _devices.values) {
      if (entry.index == obs.deviceIndex) {
        _setLevel(LoveSpouse.levelForValue(obs.value.abs(), entry.maxValue));
        return;
      }
    }
  }

  Future<void> _setLevel(int level) async {
    if (level == _currentLevel) return;
    _currentLevel = level;
    _stopTimer?.cancel();
    final error = await PhoneLinkBroadcast.advertiseServiceUuids(
      LoveSpouse.serviceUuids(LoveSpouse.commandForLevel(level)),
    );
    if (error != null) {
      logError('PhoneLink: LoveSpouse broadcast error: $error');
      _currentLevel = -1;
      return;
    }
    logInfo('PhoneLink: LoveSpouse broadcasting level $level');
    if (level == 0) {
      // Keep sending "stop" briefly so the toy hears it, then go quiet.
      _stopTimer = Timer(_stopHold, () {
        if (_currentLevel == 0) PhoneLinkBroadcast.stop();
      });
    }
  }

  void _reset() {
    _devices.clear();
    _observationSub?.cancel();
    _observationSub = null;
    if (_currentLevel > 0) {
      _setLevel(0);
    } else {
      _stopTimer?.cancel();
      _currentLevel = -1;
      PhoneLinkBroadcast.stop();
    }
  }
}
