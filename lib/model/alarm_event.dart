import 'package:alarm/model/alarm_settings.dart';

enum AlarmEventType { CreateAlarm, RingingStarted, Ringing, RingingStopped }

class AlarmEvent {
  const AlarmEvent(
      {required this.eventType,
      required this.eventSource,
      required this.alarm});

  final AlarmEventType eventType;
  final String eventSource;
  final AlarmSettings alarm;
}
