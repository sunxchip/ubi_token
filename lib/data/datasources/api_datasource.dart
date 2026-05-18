import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/road_speed_limit.dart';
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

  // ── 현재 도로 통행속도 조회 (trafficInfo) ──────────────────
  // [주의] 이 값은 통행속도이며 제한속도가 아니다. 과속 판단에 사용 금지.
  Future<int> getCurrentRoadSpeed({
    required double latitude,
    required double longitude,
  }) async {
    return await _its.getRoadSpeed(latitude: latitude, longitude: longitude) ?? 0;
  }

  // ── 현재 도로 통행정보 조회 (linkId 포함) ──────────────────
  Future<TrafficInfo?> getCurrentTrafficInfo({
    required double latitude,
    required double longitude,
  }) async {
    return _its.getRoadTrafficInfo(latitude: latitude, longitude: longitude);
  }

  // ── VSL 제한속도 조회 ──────────────────────────────────────
  // VSL(가변형 속도제한표지) API → 법정 제한속도 조회용
  // ITS_API_KEY를 trafficInfo와 동일하게 사용한다.
  Future<RoadSpeedLimit?> getSpeedLimit({
    required double latitude,
    required double longitude,
    String? trafficLinkId,
  }) async {
    final vslList = await _its.fetchVslSpeedLimitsAround(
      latitude: latitude,
      longitude: longitude,
      trafficLinkId: trafficLinkId,
    );
    return _its.findNearestVsl(
      vslList: vslList,
      latitude: latitude,
      longitude: longitude,
      trafficLinkId: trafficLinkId,
    );
  }
}
