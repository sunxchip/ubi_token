import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:xml/xml.dart';

class ItsDatasource {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    responseType: ResponseType.plain, // XML 문자열로 받기
  ));

  static const double _boxDelta = 0.005; // 약 500m 반경 바운딩박스

  /// 현재 GPS 좌표 기준 도로 교통속도 조회
  /// 반환값: 해당 도로 속도(km/h), 조회 실패 시 null
  Future<int?> getRoadSpeed({
    required double latitude,
    required double longitude,
  }) async {
    final apiKey = dotenv.env['ITS_API_KEY'] ?? '';
    final apiUrl = dotenv.env['ITS_API_URL'] ?? '';

    if (apiKey.isEmpty || apiUrl.isEmpty) return null;

    final minX = (longitude - _boxDelta).toStringAsFixed(6);
    final maxX = (longitude + _boxDelta).toStringAsFixed(6);
    final minY = (latitude - _boxDelta).toStringAsFixed(6);
    final maxY = (latitude + _boxDelta).toStringAsFixed(6);

    // 전체 → 고속도로 → 국도 순으로 시도
    for (final getType in ['all', 'high', 'nation']) {
      for (final drctn in ['1', '2']) {
        try {
          final res = await _dio.get(apiUrl, queryParameters: {
            'apiKey': apiKey,
            'getType': getType,
            'drctnDivCd': drctn,
            'minX': minX,
            'maxX': maxX,
            'minY': minY,
            'maxY': maxY,
          });

          final speed = _parseSpeed(res.data.toString());
          if (speed != null) return speed;
        } on DioException {
          continue;
        }
      }
    }

    return null;
  }

  int? _parseSpeed(String xmlStr) {
    try {
      final doc = XmlDocument.parse(xmlStr);

      final resultCode = doc.findAllElements('resultCode').firstOrNull?.innerText;
      if (resultCode != '0') return null;

      final items = doc.findAllElements('item');
      if (items.isEmpty) return null;

      // 첫 번째 아이템의 speed 반환
      final speedStr = items.first.findElements('speed').firstOrNull?.innerText;
      if (speedStr == null || speedStr.isEmpty) return null;

      return int.tryParse(speedStr);
    } catch (_) {
      return null;
    }
  }
}
