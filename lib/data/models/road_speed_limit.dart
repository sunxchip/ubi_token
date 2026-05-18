/// VSL(가변형 속도제한표지) API 응답 모델
///
/// 필드 명칭은 ITS VSL API 응답 필드명을 그대로 따른다.
/// - coordX → longitude (경도)
/// - coordY → latitude  (위도)
/// - registedDate: API 오타지만 실제 필드명이므로 그대로 사용
class RoadSpeedLimit {
  final String? vslId;
  final String? sectionCode;   // 1: 고속도로, 2: 국도
  final DateTime? createdDate;
  final double? limitSpeed;        // 현재 적용 제한속도 (km/h)
  final double? defaultLimitSpeed; // 기본 제한속도 (km/h), API 필드명 defLmtSpeed
  final String? roadNo;
  final String? linkId;
  final double? longitude;   // coordX
  final double? latitude;    // coordY
  final DateTime? registeredDate; // API 필드명 registedDate (오타 유지)

  const RoadSpeedLimit({
    this.vslId,
    this.sectionCode,
    this.createdDate,
    this.limitSpeed,
    this.defaultLimitSpeed,
    this.roadNo,
    this.linkId,
    this.longitude,
    this.latitude,
    this.registeredDate,
  });

  /// 실제 적용할 제한속도
  /// limitSpeed 우선 → defaultLimitSpeed → null
  double? get effectiveLimitSpeed {
    if (limitSpeed != null && limitSpeed! > 0) return limitSpeed;
    if (defaultLimitSpeed != null && defaultLimitSpeed! > 0) return defaultLimitSpeed;
    return null;
  }

  String get sectionLabel {
    if (sectionCode == '1') return '고속도로';
    if (sectionCode == '2') return '국도';
    return '알 수 없음';
  }

  factory RoadSpeedLimit.fromJson(Map<String, dynamic> json) {
    return RoadSpeedLimit(
      vslId:             _str(json['vslId']),
      sectionCode:       _str(json['sectionCode']),
      createdDate:       _parseDate(_str(json['createdDate'])),
      limitSpeed:        _dbl(json['limitSpeed']),
      defaultLimitSpeed: _dbl(json['defLmtSpeed']),
      roadNo:            _str(json['roadNo']),
      linkId:            _str(json['linkId']),
      longitude:         _dbl(json['coordX']),
      latitude:          _dbl(json['coordY']),
      registeredDate:    _parseDate(_str(json['registedDate'])),
    );
  }

  // ── 내부 파싱 헬퍼 ────────────────────────────────────────────────────────

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _dbl(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  /// YYYYMMDDHH24MISS → DateTime 파싱 (실패 시 null)
  static DateTime? _parseDate(String? s) {
    if (s == null || s.length < 14) return null;
    try {
      final y  = int.parse(s.substring(0, 4));
      final mo = int.parse(s.substring(4, 6));
      final d  = int.parse(s.substring(6, 8));
      final h  = int.parse(s.substring(8, 10));
      final mi = int.parse(s.substring(10, 12));
      final sec = int.parse(s.substring(12, 14));
      return DateTime(y, mo, d, h, mi, sec);
    } catch (_) {
      return null;
    }
  }
}
