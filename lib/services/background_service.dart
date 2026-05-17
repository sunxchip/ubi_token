import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../core/constants/obd_constants.dart';

// TODO: Android Foreground Service로 확장 시 아래 항목 적용
//   1. AndroidConfiguration.isForegroundMode = true 로 변경
//   2. AndroidConfiguration.notificationChannelId, initialNotificationTitle,
//      initialNotificationContent 설정 추가
//   3. AndroidManifest.xml에 FOREGROUND_SERVICE 권한 및 서비스 선언 추가
//   4. 포그라운드 알림에 '주행 중 · 안전점수 xx점' 실시간 업데이트 구현

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: false, // TODO: 실제 배포 시 true로 변경 (Foreground Service)
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onServiceStart,
    ),
  );
}

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  double lastRpm = 0;
  bool isDriving = false;
  Timer? engineOffTimer;

  // ── 주행 데이터 수집 폴링 ───────────────────────────────
  // 현재는 RPM 값으로만 시동/종료를 판별한다.
  // TODO: 안전점수 화면(DrivingScoreScreen)과 연동하여
  //       DrivingDataSource 스트림을 백그라운드에서 구독하고
  //       'obd_sample' 이벤트로 UI에 전달하는 흐름으로 확장 가능
  //
  // 데이터 수집 시작 (주행 시작):
  //   service.invoke('driving_start', {'vin': vin, 'timestamp': ...})
  //   → DrivingDataSource.watchDrivingData(vin) 구독 시작
  //
  // 데이터 수집 종료 (주행 종료):
  //   service.invoke('driving_stop', {'timestamp': ...})
  //   → 구독 해제, ScoreResult 계산 후 DB 저장
  Timer.periodic(const Duration(milliseconds: 500), (timer) async {
    final rpm = lastRpm;

    if (rpm > 0 && !isDriving) {
      isDriving = true;
      engineOffTimer?.cancel();
      service.invoke('session_start', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      // TODO: 주행 시작 시 MockObdDataSource (또는 RealObdDataSource) 스트림 구독 시작
    }

    if (rpm == 0 && isDriving) {
      engineOffTimer ??= Timer(
        Duration(milliseconds: ObdConstants.engineOffDelayMs),
        () {
          isDriving = false;
          service.invoke('session_end', {
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          // TODO: 주행 종료 시 스트림 구독 해제 및 ScoreResult 저장
        },
      );
    } else {
      engineOffTimer?.cancel();
      engineOffTimer = null;
    }
  });

  // 외부에서 RPM 값을 전달받아 lastRpm 갱신
  // 사용 예: FlutterBackgroundService().invoke('update_rpm', {'rpm': 1200.0})
  service.on('update_rpm').listen((event) {
    lastRpm = (event?['rpm'] as num?)?.toDouble() ?? 0;
  });

  service.on('stop').listen((event) {
    engineOffTimer?.cancel();
    service.stopSelf();
  });
}