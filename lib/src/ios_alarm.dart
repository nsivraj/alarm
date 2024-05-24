import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/model/alarm_event.dart';
import 'package:alarm/model/alarm_settings.dart';
import 'package:alarm/service/alarm_storage.dart';
import 'package:alarm/utils/alarm_exception.dart';
import 'package:flutter/services.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';

/// Uses method channel to interact with the native platform.
class IOSAlarm {
  /// Method channel for the alarm.
  static const methodChannel = MethodChannel('com.gdelataillade/alarm');

  /// Send ring stream events back to the mobile app
  static late final StreamController<AlarmEvent> ringStream;

  /// Map of alarm timers.
  static Map<int, Timer?> timers = {};

  /// Map of foreground/background subscriptions.
  static Map<int, StreamSubscription<FGBGType>?> fgbgSubscriptions = {};

  /// Call this init method first before setting alarms
  static void init(StreamController<AlarmEvent> ringStreamParam) {
    ringStream = ringStreamParam;
    methodChannel.setMethodCallHandler(_callingThisMethodFromSwift);
  }

  static T? cast<T>(x) => x is T ? x : null;

  static Future<dynamic> _callingThisMethodFromSwift(MethodCall call) async {
    switch (call.method) {
      case 'alarmStopped':
        // Do something
        // final int id = call.arguments['Nepal'];
        // final String arg2 = arguments['UK'];
        // print('The arguments are: ${call.arguments}');
        // print(arg2);

        // final alarms = AlarmStorage.getSavedAlarms();
        final id = cast<int>(call.arguments['id']);
        if (id != null) {
          final alarm = Alarm.getAlarm(id);

          // for (final alarm in alarms) {
          //   if (alarm.id == call.arguments['id']) {
          if (alarm != null) {
            // print(
            // 'Letting the ring stream know about the event of stopping the alarm: $id');
            ringStream.add(
              AlarmEvent(
                eventType: AlarmEventType.RingingStopped,
                eventSource: 'iosAlarmStoppedCallback',
                alarm: alarm,
              ),
            );
          }
        }
        //   }
        //   // await stop(alarm);
        // }

        // print('\nOur Native iOS code is calling Flutter method/!!');
        return 'success';
      // break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Calls the native function `setAlarm` and listens to alarm ring state.
  ///
  /// Also set periodic timer and listens for app state changes to trigger
  /// the alarm ring callback at the right time.
  static Future<bool> setAlarm(
    AlarmSettings settings,
    void Function()? onRing,
  ) async {
    final id = settings.id;
    try {
      final delay = settings.dateTime
          .difference(DateTime.now())
          .inSeconds
          .abs()
          .toDouble();

      final res = await methodChannel.invokeMethod<bool?>(
            'setAlarm',
            {
              'id': id,
              'alarmName': settings.alarmName,
              'assetAudio': settings.assetAudioPath,
              'delayInSeconds': delay,
              'loopAudio': settings.loopAudio,
              'repeatSoundLoops': settings.repeatSoundLoops,
              'fadeDuration': settings.fadeDuration,
              'vibrate': settings.vibrate,
              'volume': settings.volume,
              'notifOnKillEnabled': settings.enableNotificationOnKill,
              'notificationTitle': settings.notificationTitle,
              'notificationBody': settings.notificationBody,
              'notifTitleOnAppKill':
                  AlarmStorage.getNotificationOnAppKillTitle(),
              'notifDescriptionOnAppKill':
                  AlarmStorage.getNotificationOnAppKillBody(),
              'snoozeDuration': settings.snoozeDuration,
              'autoRepeatDuration': settings.autoRepeatDuration,
            },
          ) ??
          false;

      alarmPrint(
        '''Alarm with id $id scheduled ${res ? 'successfully' : 'failed'} at ${settings.dateTime}''',
      );

      if (!res) return false;
    } catch (e) {
      await Alarm.stop(settings);
      throw AlarmException(e.toString());
    }

    if (timers[id] != null && timers[id]!.isActive) timers[id]!.cancel();
    timers[id] = periodicTimer(onRing, settings.dateTime, id);

    listenAppStateChange(
      id: id,
      onBackground: () => disposeTimer(id),
      onForeground: () async {
        if (fgbgSubscriptions[id] == null) return;

        final isRinging = await checkIfRinging(id);

        if (isRinging) {
          disposeAlarm(id);
          onRing?.call();
        } else {
          if (timers[id] != null && timers[id]!.isActive) timers[id]!.cancel();
          timers[id] = periodicTimer(onRing, settings.dateTime, id);
        }
      },
    );

    return true;
  }

  /// Disposes timer and FGBG subscription
  /// and calls the native `stopAlarm` function.
  static Future<bool> stopAlarm(int id) async {
    disposeAlarm(id);

    final res = await methodChannel.invokeMethod<bool?>(
          'stopAlarm',
          {'id': id},
        ) ??
        false;

    if (res) alarmPrint('Alarm with id $id stopped');

    return res;
  }

  /// Checks whether alarm is ringing by getting the native audio player's
  /// current time at two different moments. If the two values are different,
  /// it means the alarm is ringing and then returns `true`.
  static Future<bool> checkIfRinging(int id) async {
    final pos1 = await methodChannel
            .invokeMethod<double?>('audioCurrentTime', {'id': id}) ??
        0.0;
    await Future.delayed(const Duration(milliseconds: 100), () {});
    final pos2 = await methodChannel
            .invokeMethod<double?>('audioCurrentTime', {'id': id}) ??
        0.0;

    return pos2 > pos1;
  }

  /// Listens when app goes foreground so we can check if alarm is ringing.
  /// When app goes background, periodical timer will be disposed.
  static void listenAppStateChange({
    required int id,
    required void Function() onForeground,
    required void Function() onBackground,
  }) {
    fgbgSubscriptions[id] = FGBGEvents.stream.listen((event) {
      if (event == FGBGType.foreground) onForeground();
      if (event == FGBGType.background) onBackground();
    });
  }

  /// Checks periodically if alarm is ringing, as long as app is in foreground.
  static Timer periodicTimer(void Function()? onRing, DateTime dt, int id) {
    return Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (DateTime.now().isBefore(dt)) return;
      disposeAlarm(id);
      onRing?.call();
    });
  }

  /// Disposes alarm timer.
  static void disposeTimer(int id) {
    timers[id]?.cancel();
    timers.removeWhere((key, value) => key == id);
  }

  /// Disposes alarm timer and FGBG subscription.
  static void disposeAlarm(int id) {
    disposeTimer(id);
    fgbgSubscriptions[id]?.cancel();
    fgbgSubscriptions.removeWhere((key, value) => key == id);
  }
}
