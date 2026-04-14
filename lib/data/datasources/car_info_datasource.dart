import 'package:dio/dio.dart';

class CarInfo {
  final String vin;
  final String make;       // 제조사 (예: HYUNDAI)
  final String model;      // 모델명 (예: ELANTRA)
  final String modelYear;  // 연식 (예: 2019)
  final String fuelType;   // 연료 (예: Gasoline)
  final String bodyClass;  // 차종 (예: Sedan/Saloon)
  final String plantCountry; // 생산국

  const CarInfo({
    required this.vin,
    required this.make,
    required this.model,
    required this.modelYear,
    required this.fuelType,
    required this.bodyClass,
    required this.plantCountry,
  });

  bool get isValid => make.isNotEmpty && model.isNotEmpty;
}

class CarInfoDatasource {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// OBD/CAN에서 읽은 VIN으로 차량 정보 조회
  /// NHTSA (미국 도로교통안전청) VIN 디코더 API 사용 - 무료, API키 불필요
  /// 현대/기아 등 한국 수출 차량 지원
  Future<CarInfo> decodeVin(String vin) async {
    if (vin.length != 17) {
      throw Exception('VIN은 17자리여야 합니다. (현재: ${vin.length}자리)');
    }

    final res = await _dio.get(
      'https://vpic.nhtsa.dot.gov/api/vehicles/decodevinvalues/$vin',
      queryParameters: {'format': 'json'},
    );

    final results = res.data['Results'] as List?;
    if (results == null || results.isEmpty) {
      throw Exception('차량 정보를 가져올 수 없습니다.');
    }

    final data = results.first as Map<String, dynamic>;

    // API 에러 코드 확인
    final errorCode = data['ErrorCode']?.toString() ?? '';
    if (errorCode.startsWith('8') || errorCode.startsWith('9')) {
      // 6, 7은 부분 일치 경고이므로 허용
      throw Exception('유효하지 않은 VIN입니다. (코드: $errorCode)');
    }

    String get(String key) {
      final v = data[key]?.toString().trim() ?? '';
      return v == 'Not Applicable' || v == '0' ? '' : v;
    }

    return CarInfo(
      vin: vin,
      make: get('Make'),
      model: get('Model'),
      modelYear: _correctModelYear(get('ModelYear'), vin),
      fuelType: get('FuelTypePrimary'),
      bodyClass: get('BodyClass'),
      plantCountry: get('PlantCountry'),
    );
  }

  /// VIN 10번째 자리 연식 코드는 30년 주기 반복 (1986 = 2016 등)
  /// OBD-II는 1996년 이후 의무 → NHTSA가 1995년 이전으로 반환하면 +30년 보정
  String _correctModelYear(String year, String vin) {
    final y = int.tryParse(year);
    if (y == null || y >= 1996) return year;
    return (y + 30).toString();
  }
}
