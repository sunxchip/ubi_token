import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'its_datasource.dart';

class ApiDatasource {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: dotenv.env['SERVER_BASE_URL'] ?? 'http://127.0.0.1:8000',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  // ── 회원가입 ─────────────────────────────────────────
  Future<Map<String, dynamic>?> signup({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
      });
      return res.data;
    } on DioException catch (e) {
      return {'error': e.response?.data['detail'] ?? '서버 오류'};
    }
  }

  // ── 로그인 ───────────────────────────────────────────
  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      return res.data;
    } on DioException catch (e) {
      return {'error': e.response?.data['detail'] ?? '서버 오류'};
    }
  }

  // ── VIN 인증 ─────────────────────────────────────────
  Future<Map<String, dynamic>?> vinVerify({
    required String userId,
    required String vin,
  }) async {
    try {
      final res = await _dio.post('/auth/vin-verify', data: {
        'user_id': userId,
        'vin': vin,
      });
      return res.data;
    } on DioException catch (e) {
      return {'error': e.response?.data['detail'] ?? '서버 오류'};
    }
  }

  // ── 토큰 검증 ────────────────────────────────────────
  Future<bool> verifyToken(String token) async {
    try {
      final res = await _dio.get('/auth/verify-token/$token');
      return res.data['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  final _its = ItsDatasource();

  // ── [비교값] 현재 도로 흐름 속도 (trafficInfo) ────────────
  // 교통소통정보 API → 지금 이 도로에서 차들이 실제로 얼마나 달리는지
  Future<int> getCurrentRoadSpeed({
    required double latitude,
    required double longitude,
  }) async {
    return await _its.getRoadSpeed(latitude: latitude, longitude: longitude) ?? 0;
  }

  // ── [기준값] 법정 제한속도 (detectorInfo) ─────────────────
  // 차량검지기 API → 미승인 상태, 추후 구현 예정
  Future<int?> getLegalSpeedLimit({
    required double latitude,
    required double longitude,
  }) async {
    // TODO: detectorInfo API 승인 후 구현
    return null;
  }
}
