import 'package:alarm/model/alarm_settings.dart';

enum AlarmEventType { CreateAlarm, RingingStarted, Ringing, RingingStopped }

class AlarmEvent {
  const AlarmEvent({required this.eventType, required this.alarm});

  final AlarmEventType eventType;
  final AlarmSettings alarm;
}
