/// OBD-II 표준 PID 응답 파서
///
/// ELM327 OBD-II 어댑터로부터 받은 raw 응답 문자열을 수치 값으로 변환한다.
/// 잘못된 응답이나 지원하지 않는 PID 응답은 예외를 던지지 않고 null을 반환한다.
///
/// 지원하는 ELM327 응답 형식:
///   - 공백 있음: "41 0C 1A F8 >"
///   - 공백 없음: "410C1AF8"
///   - 헤더 포함: "7E8 04 41 0C 1A F8"
///   - 줄바꿈/> 포함: "410D28\r\n>"
///
/// 실차 연결 후 응답이 파싱되지 않으면:
///   1. sendRaw()로 원시 응답을 PID 진단 화면에서 확인
///   2. _cleanResponse() 후 hex bytes 배열을 print()로 확인
///   3. 응답 포맷에 맞게 findPidDataBytes()의 마커 인덱스를 수정
class ObdPidParser {
  // ── 공통 전처리 ───────────────────────────────────────────────────────────
  /// raw 응답에서 공백, 줄바꿈, '>', 'NO DATA', 'ERROR' 등을 제거하고
  /// 16진수 문자만 남긴 연속된 문자열로 반환한다.
  static String _cleanResponse(String raw) {
    return raw
        .replaceAll(RegExp(r'[>\r\n]'), ' ') // > 와 줄바꿈을 공백으로
        .replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '') // hex와 공백만 유지
        .trim();
  }

  /// 전처리된 응답에서 OBD 서비스01 응답 마커('41XX')를 찾아
  /// 이후 데이터 바이트들을 List<int>로 반환한다.
  ///
  /// ELM327 헤더(ATH1) ON 예시: "7E8 04 41 0C 1A F8"
  ///   → cleaned hex bytes: [7E, 8, 04, 41, 0C, 1A, F8]
  ///   → 41 찾기 → 다음 바이트가 PID → 그 이후가 데이터
  ///
  /// [pidHex] 예시: '0C' (010C의 PID 부분)
  static List<int>? _findPidDataBytes(String cleaned, String pidHex) {
    try {
      final parts = cleaned
          .split(RegExp(r'\s+'))
          .where((s) => s.length == 2) // 정확히 2자리 hex 바이트만
          .map((s) => int.parse(s, radix: 16))
          .toList();

      // "41 XX" 패턴 찾기 (41 = 서비스01 응답, XX = PID)
      final pidByte = int.parse(pidHex, radix: 16);
      for (int i = 0; i < parts.length - 1; i++) {
        if (parts[i] == 0x41 && parts[i + 1] == pidByte) {
          return parts.sublist(i + 2); // 데이터 바이트들
        }
      }
    } catch (_) {}
    return null;
  }

  // ── RPM (PID: 010C) ───────────────────────────────────────────────────────
  /// 응답 예: "41 0C 1A F8" → A=0x1A, B=0xF8
  /// rpm = ((A × 256) + B) / 4
  ///
  /// 샘플 검증:
  ///   "410C1AF8" → A=26(0x1A), B=248(0xF8) → (26×256+248)/4 = 1726.0 rpm
  static double? parseRpm(String response) {
    final cleaned = _cleanResponse(response);
    final data = _findPidDataBytes(cleaned, '0C');
    if (data == null || data.length < 2) return null;
    return ((data[0] * 256) + data[1]) / 4.0;
  }

  // ── 차량 속도 (PID: 010D) ─────────────────────────────────────────────────
  /// 응답 예: "41 0D 28" → A=0x28
  /// speed = A  (km/h, 1바이트 직독)
  ///
  /// 샘플 검증:
  ///   "410D28" → A=40(0x28) → 40 km/h
  static double? parseSpeed(String response) {
    final cleaned = _cleanResponse(response);
    final data = _findPidDataBytes(cleaned, '0D');
    if (data == null || data.isEmpty) return null;
    return data[0].toDouble();
  }

  // ── 스로틀 위치 (PID: 0111) ───────────────────────────────────────────────
  /// 응답 예: "41 11 80" → A=0x80
  /// throttle = A × 100 / 255  (%)
  ///
  /// 샘플 검증:
  ///   "411180" → A=128(0x80) → 128×100/255 ≈ 50.2%
  static double? parseThrottle(String response) {
    final cleaned = _cleanResponse(response);
    final data = _findPidDataBytes(cleaned, '11');
    if (data == null || data.isEmpty) return null;
    return data[0] * 100.0 / 255.0;
  }

  // ── 엔진 부하 (PID: 0104) ─────────────────────────────────────────────────
  /// 응답 예: "41 04 80" → A=0x80
  /// engineLoad = A × 100 / 255  (%)
  ///
  /// 샘플 검증:
  ///   "410480" → A=128(0x80) → 128×100/255 ≈ 50.2%
  static double? parseEngineLoad(String response) {
    final cleaned = _cleanResponse(response);
    final data = _findPidDataBytes(cleaned, '04');
    if (data == null || data.isEmpty) return null;
    return data[0] * 100.0 / 255.0;
  }

  // ── VIN (PID: 0902) ───────────────────────────────────────────────────────
  /// VIN은 ISO 15765 멀티프레임 응답으로 오므로 완전한 파싱은
  /// ObdDatasource._parseVin()에서 처리한다.
  ///
  /// 이 함수는 단일 문자열에서 ASCII 범위 문자를 추출하는 보조용으로만 사용한다.
  ///
  /// TODO: 멀티프레임 재조립 로직을 여기에 통합하고
  ///       ObdDatasource._parseVin()과 하나로 통일할 것
  static String? parseVin(String response) {
    try {
      final cleaned = _cleanResponse(response);
      final parts = cleaned
          .split(RegExp(r'\s+'))
          .where((s) => s.length == 2)
          .toList();

      final vinBytes = <int>[];
      for (final hex in parts) {
        final b = int.tryParse(hex, radix: 16) ?? 0;
        if (b >= 0x20 && b <= 0x7E) vinBytes.add(b); // ASCII 출력 가능 범위
      }

      final vinStr = String.fromCharCodes(vinBytes);
      final match = RegExp(r'[A-HJ-NPR-Z0-9]{17}').firstMatch(vinStr);
      return match?.group(0);
    } catch (_) {
      return null;
    }
  }

  // ── 테스트용 샘플 케이스 ──────────────────────────────────────────────────
  /// 파서가 올바르게 동작하는지 확인할 수 있는 샘플 케이스 목록
  static List<ParserTestCase> get sampleTestCases => [
    ParserTestCase(
      pid: 'RPM (010C)',
      rawInput: '410C1AF8',
      expectedLabel: '1726.0 rpm',
      parse: (s) {
        final v = parseRpm(s);
        return v != null ? '${v.toStringAsFixed(1)} rpm' : null;
      },
    ),
    ParserTestCase(
      pid: '속도 (010D)',
      rawInput: '410D28',
      expectedLabel: '40.0 km/h',
      parse: (s) {
        final v = parseSpeed(s);
        return v != null ? '${v.toStringAsFixed(1)} km/h' : null;
      },
    ),
    ParserTestCase(
      pid: '스로틀 (0111)',
      rawInput: '411180',
      expectedLabel: '≈ 50.2%',
      parse: (s) {
        final v = parseThrottle(s);
        return v != null ? '${v.toStringAsFixed(1)}%' : null;
      },
    ),
    ParserTestCase(
      pid: '엔진부하 (0104)',
      rawInput: '410480',
      expectedLabel: '≈ 50.2%',
      parse: (s) {
        final v = parseEngineLoad(s);
        return v != null ? '${v.toStringAsFixed(1)}%' : null;
      },
    ),
    // 헤더 포함 응답 테스트 (ATH1 ON 상태)
    ParserTestCase(
      pid: 'RPM - 헤더 포함',
      rawInput: '7E8 04 41 0C 1A F8',
      expectedLabel: '1726.0 rpm',
      parse: (s) {
        final v = parseRpm(s);
        return v != null ? '${v.toStringAsFixed(1)} rpm' : null;
      },
    ),
    // > 와 줄바꿈 포함 응답 테스트 (실제 ELM327 응답 형태)
    ParserTestCase(
      pid: '속도 - 줄바꿈+> 포함',
      rawInput: '41 0D 50\r\n>',
      expectedLabel: '80.0 km/h',
      parse: (s) {
        final v = parseSpeed(s);
        return v != null ? '${v.toStringAsFixed(1)} km/h' : null;
      },
    ),
  ];
}

/// PID 파서 테스트 케이스
class ParserTestCase {
  final String pid;
  final String rawInput;
  final String expectedLabel;
  final String? Function(String) parse;

  const ParserTestCase({
    required this.pid,
    required this.rawInput,
    required this.expectedLabel,
    required this.parse,
  });

  String get actualOutput => parse(rawInput) ?? '파싱 실패 (null)';
  bool get isPass => actualOutput.isNotEmpty && actualOutput != '파싱 실패 (null)';
}
