import 'drive_event.dart';

class TripSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final double distanceKm;
  final List<DriveEvent> events;
  final int finalScore;

  const TripSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.distanceKm = 0.0,
    this.events = const [],
    this.finalScore = 100,
  });

  // 주행 시간 (분)
  int get durationMinutes {
    if (endTime == null) return 0;
    return endTime!.difference(startTime).inMinutes;
  }

  TripSession copyWith({
    DateTime? endTime,
    double? distanceKm,
    List<DriveEvent>? events,
    int? finalScore,
  }) => TripSession(
    id          : id,
    startTime   : startTime,
    endTime     : endTime ?? this.endTime,
    distanceKm  : distanceKm ?? this.distanceKm,
    events      : events ?? this.events,
    finalScore  : finalScore ?? this.finalScore,
  );

  Map<String, dynamic> toMap() => {
    'id'          : id,
    'startTime'   : startTime.millisecondsSinceEpoch,
    'endTime'     : endTime?.millisecondsSinceEpoch,
    'distanceKm'  : distanceKm,
    'finalScore'  : finalScore,
  };
}