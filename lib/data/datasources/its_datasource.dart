import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:xml/xml.dart';
import '../models/road_speed_limit.dart';
import '../../core/utils/geo_utils.dart';

/// ITS OpenAPI 연동 클래스
///
/// 동일한 ITS_API_KEY를 사용하는 두 가지 API를 제공한다.
///
/// 1. trafficInfo (교통소통정보) — .env: ITS_TRAFFIC_API_URL
///    - 현재 도로의 [통행속도]를 반환한다.
///    - 실제 차량들이 달리는 속도이며 [제한속도가 아니다].
///    - 과속 판단 기준값으로 절대 사용하지 말 것.
///    - linkId 확인, 도로 혼잡도 파악에 활용한다.
///
/// 2. VSL (가변형 속도제한표지정보) — .env: ITS_VSL_API_URL
///    - 현재 도로의 [제한속도]를 반환한다.
///    - OBD 차량 속도와 비교하여 과속 여부 판단에 사용한다.
///
/// 두 API 모두 동일한 ITS_API_KEY를 사용한다.
class ItsDatasource {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    responseType: ResponseType.plain,
  ));

  static const double _boxDelta    = 0.005;  // 약 500m 반경 바운딩박스
  static const double _vslMaxDistM = 500.0;  // VSL 좌표 매칭 최대 허용 거리 (m)

  // ── 1. trafficInfo: 현재 도로 통행속도 조회 ─────────────────────────────
  //
  // [중요] 반환값은 통행속도(실제 차량이 달리는 속도)이며 제한속도가 아니다.
  //        과속 판단 기준으로 사용하지 말 것.

  /// 현재 GPS 좌표 기준 도로 통행속도 조회 (km/h)
  /// 반환값: 통행속도, 조회 실패 시 null
  Future<int?> getRoadSpeed({
    required double latitude,
    required double longitude,
  }) async {
    final info = await getRoadTrafficInfo(latitude: latitude, longitude: longitude);
    return info?.speed;
  }

  /// 현재 GPS 좌표 기준 도로 통행정보 조회 (linkId 포함)
  Future<TrafficInfo?> getRoadTrafficInfo({
    required double latitude,
    required double longitude,
  }) async {
    final apiKey = dotenv.env['ITS_API_KEY'] ?? '';
    final apiUrl = dotenv.env['ITS_TRAFFIC_API_URL']
                ?? dotenv.env['ITS_API_URL'] // 기존 키 호환
                ?? '';

    if (apiKey.isEmpty) {
      dev.log('[ITS] ITS_API_KEY 설정 필요', name: 'ItsDatasource');
      return null;
    }
    if (apiUrl.isEmpty) {
      dev.log('[ITS] ITS_TRAFFIC_API_URL 설정 필요', name: 'ItsDatasource');
      return null;
    }

    final minX = (longitude - _boxDelta).toStringAsFixed(6);
    final maxX = (longitude + _boxDelta).toStringAsFixed(6);
    final minY = (latitude  - _boxDelta).toStringAsFixed(6);
    final maxY = (latitude  + _boxDelta).toStringAsFixed(6);

    for (final getType in ['all', 'high', 'nation']) {
      for (final drctn in ['1', '2']) {
        try {
          final res = await _dio.get(apiUrl, queryParameters: {
            'apiKey': apiKey, 'getType': getType, 'drctnDivCd': drctn,
            'minX': minX, 'maxX': maxX, 'minY': minY, 'maxY': maxY,
          });
          final info = _parseTrafficInfo(res.data.toString());
          if (info != null) return info;
        } on DioException {
          continue;
        }
      }
    }
    return null;
  }

  TrafficInfo? _parseTrafficInfo(String xmlStr) {
    try {
      final doc        = XmlDocument.parse(xmlStr);
      final resultCode = doc.findAllElements('resultCode').firstOrNull?.innerText;
      if (resultCode != '0') return null;

      final items = doc.findAllElements('item');
      if (items.isEmpty) return null;

      final item     = items.first;
      final speedStr = item.findElements('speed').firstOrNull?.innerText;
      final linkId   = item.findElements('linkId').firstOrNull?.innerText;
      final roadName = item.findElements('roadName').firstOrNull?.innerText
                    ?? item.findElements('roadNm').firstOrNull?.innerText;

      final speed = int.tryParse(speedStr ?? '');
      if (speed == null) return null;
      return TrafficInfo(speed: speed, linkId: linkId, roadName: roadName);
    } catch (_) {
      return null;
    }
  }

  // ── 2. VSL: 제한속도 조회 ───────────────────────────────────────────────
  //
  // VSL(가변형 속도제한표지) API로 제한속도를 조회한다.
  // OBD 차량 속도와 비교하여 과속 여부 판단에 사용한다.

  /// 현재 GPS 좌표 기준 VSL 제한속도 목록 조회
  ///
  /// [trafficLinkId] trafficInfo에서 얻은 linkId. linkId 1순위 매칭에 활용.
  /// 반환값: 주변 VSL 정보 목록 (빈 리스트 = 정보 없음)
  Future<List<RoadSpeedLimit>> fetchVslSpeedLimitsAround({
    required double latitude,
    required double longitude,
    String? trafficLinkId,
  }) async {
    final apiKey = dotenv.env['ITS_API_KEY'] ?? '';
    final vslUrl = dotenv.env['ITS_VSL_API_URL'] ?? '';

    if (apiKey.isEmpty) {
      dev.log('[VSL] ITS_API_KEY 설정 필요', name: 'ItsDatasource');
      return [];
    }
    if (vslUrl.isEmpty) {
      // TODO: ITS_VSL_API_URL 확정 후 .env에 추가
      dev.log('[VSL] ITS_VSL_API_URL 미설정 — .env에 VSL 엔드포인트 추가 필요', name: 'ItsDatasource');
      return [];
    }

    final minX = (longitude - _boxDelta).toStringAsFixed(6);
    final maxX = (longitude + _boxDelta).toStringAsFixed(6);
    final minY = (latitude  - _boxDelta).toStringAsFixed(6);
    final maxY = (latitude  + _boxDelta).toStringAsFixed(6);

    final params = <String, dynamic>{
      'apiKey': apiKey,
      'minX': minX, 'maxX': maxX,
      'minY': minY, 'maxY': maxY,
      // TODO: VSL API 필수 파라미터 확정 후 추가
      //       4002 오류 발생 시 필수 파라미터 누락 의미
    };

    dev.log('[VSL] 요청 URL: $vslUrl', name: 'ItsDatasource');
    dev.log('[VSL] 요청 파라미터: $params', name: 'ItsDatasource');

    try {
      final res  = await _dio.get(vslUrl, queryParameters: params);
      final body = res.data.toString();
      dev.log('[VSL] statusCode: ${res.statusCode}', name: 'ItsDatasource');
      dev.log('[VSL] 응답 앞 300자: ${body.substring(0, body.length.clamp(0, 300))}', name: 'ItsDatasource');
      return _parseVslResponse(body);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final body       = e.response?.data?.toString() ?? '';
      dev.log('[VSL] 요청 실패 — statusCode: $statusCode', name: 'ItsDatasource');
      dev.log('[VSL] 오류 body: ${body.substring(0, body.length.clamp(0, 300))}', name: 'ItsDatasource');
      return [];
    }
  }

  List<RoadSpeedLimit> _parseVslResponse(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _parseVslJson(body);
    }
    return _parseVslXmlFallback(body);
  }

  List<RoadSpeedLimit> _parseVslJson(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        final resultCode = decoded['resultCode']?.toString();
        final resultMsg  = decoded['resultMsg']?.toString();
        final totalCount = decoded['totalCount'];

        dev.log(
          '[VSL] resultCode: $resultCode, resultMsg: $resultMsg, totalCount: $totalCount',
          name: 'ItsDatasource',
        );

        if (resultCode == '4002') {
          dev.log('[VSL] 4002 오류 = 필수 파라미터 누락. 요청 파라미터 확인 필요', name: 'ItsDatasource');
          return [];
        }
        if (resultCode != null && resultCode != '0') {
          dev.log('[VSL] 비정상 resultCode: $resultCode / $resultMsg', name: 'ItsDatasource');
          return [];
        }

        final raw = decoded['data'] ?? decoded['items'] ?? decoded['item'] ?? [];
        if (raw is List) {
          return raw.whereType<Map<String, dynamic>>()
              .map(RoadSpeedLimit.fromJson)
              .toList();
        }
      }

      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>()
            .map(RoadSpeedLimit.fromJson)
            .toList();
      }

      return [];
    } catch (e) {
      dev.log('[VSL] JSON 파싱 실패: $e', name: 'ItsDatasource');
      return [];
    }
  }

  List<RoadSpeedLimit> _parseVslXmlFallback(String body) {
    try {
      final doc        = XmlDocument.parse(body);
      final resultCode = doc.findAllElements('resultCode').firstOrNull?.innerText;
      final resultMsg  = doc.findAllElements('resultMsg').firstOrNull?.innerText;
      final totalCount = doc.findAllElements('totalCount').firstOrNull?.innerText;

      dev.log(
        '[VSL] XML 응답 — resultCode: $resultCode, resultMsg: $resultMsg, totalCount: $totalCount',
        name: 'ItsDatasource',
      );

      if (resultCode == '4002') {
        dev.log('[VSL] 4002 오류 = 필수 파라미터 누락. 요청 파라미터 확인 필요', name: 'ItsDatasource');
        return [];
      }
      if (resultCode != '0') return [];

      return doc.findAllElements('item').map((item) {
        final json = <String, dynamic>{};
        for (final child in item.childElements) {
          json[child.name.local] = child.innerText;
        }
        return RoadSpeedLimit.fromJson(json);
      }).toList();
    } catch (e) {
      dev.log(
        '[VSL] XML 파싱 실패: $e / body: ${body.substring(0, body.length.clamp(0, 200))}',
        name: 'ItsDatasource',
      );
      return [];
    }
  }

  // ── 3. trafficInfo + VSL 매칭: 현재 위치 제한속도 결정 ─────────────────

  /// VSL 목록에서 현재 위치에 가장 적합한 제한속도 정보를 반환한다.
  ///
  /// 매칭 우선순위:
  ///   1순위: trafficInfo의 linkId == VSL의 linkId
  ///   2순위: GPS 기준 가장 가까운 VSL (_vslMaxDistM 이내)
  ///   없으면: null (제한속도 정보 없음)
  RoadSpeedLimit? findNearestVsl({
    required List<RoadSpeedLimit> vslList,
    required double latitude,
    required double longitude,
    String? trafficLinkId,
  }) {
    if (vslList.isEmpty) return null;

    // 1순위: linkId 매칭
    if (trafficLinkId != null && trafficLinkId.isNotEmpty) {
      final matched = vslList.where((v) => v.linkId == trafficLinkId);
      if (matched.isNotEmpty) return matched.first;
    }

    // 2순위: GPS 거리 기반 최근접
    RoadSpeedLimit? nearest;
    double minDist = double.infinity;
    for (final vsl in vslList) {
      if (vsl.latitude == null || vsl.longitude == null) continue;
      final dist = GeoUtils.distanceMeters(
        latitude, longitude, vsl.latitude!, vsl.longitude!,
      );
      if (dist < minDist) {
        minDist = dist;
        nearest = vsl;
      }
    }

    return (nearest != null && minDist <= _vslMaxDistM) ? nearest : null;
  }
}

// ── 교통정보 모델 ─────────────────────────────────────────────────────────────

/// trafficInfo API 응답 파싱 결과
///
/// [speed] 통행속도 (km/h) — 제한속도가 아님. 과속 판단에 사용 금지.
class TrafficInfo {
  /// 현재 차량들의 통행속도 (km/h). 제한속도가 아니므로 과속 기준으로 사용 금지.
  final int speed;
  final String? linkId;   // VSL API와 매칭할 때 사용
  final String? roadName;

  const TrafficInfo({required this.speed, this.linkId, this.roadName});
}
