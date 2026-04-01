import 'package:dio/dio.dart';

class ApiDatasource {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  // 공공데이터포털 과속 카메라 API
  // 실제 API 키는 pubspec에 환경변수로 관리 권장
  static const String _baseUrl =
      'https://api.odcloud.kr/api';
  static const String _apiKey = 'YOUR_API_KEY'; // 발급 후 교체

  // 현재 위치 주변 과속 카메라 조회
  Future<List<Map<String, dynamic>>> getSpeedCameras({
    required double latitude,
    required double longitude,
    double radiusKm = 1.0,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/15070282/v1/uddi:speed-camera',
        queryParameters: {
          'serviceKey': _apiKey,
          'pageNo': 1,
          'numOfRows': 50,
          'type': 'json',
        },
      );
      if (response.statusCode == 200) {
        final items = response.data['response']['body']['items'] as List?;
        return items?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (_) {}
    return [];
  }

  // 도로 제한속도 조회
  Future<int> getSpeedLimit({
    required double latitude,
    required double longitude,
  }) async {
    // 공공데이터포털 도로 정보 API 연동
    // 임시로 일반도로 60km/h 반환
    // 실제 API 키 발급 후 구현
    return 60;
  }
}