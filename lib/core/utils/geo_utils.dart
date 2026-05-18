import 'dart:math';

/// 지리 계산 유틸
class GeoUtils {
  GeoUtils._();

  /// Haversine 공식 기반 두 좌표 간 거리 계산 (미터)
  static double distanceMeters(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const r = 6371000.0; // 지구 반지름 (m)
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
