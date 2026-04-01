import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../core/constants/obd_constants.dart';

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: false,
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

  Timer.periodic(const Duration(milliseconds: 500), (timer) async {
    final rpm = lastRpm;

    if (rpm > 0 && !isDriving) {
      isDriving = true;
      engineOffTimer?.cancel();
      service.invoke('session_start', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    if (rpm == 0 && isDriving) {
      engineOffTimer ??= Timer(
        Duration(milliseconds: ObdConstants.engineOffDelayMs),
            () {
          isDriving = false;
          service.invoke('session_end', {
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        },
      );
    } else {
      engineOffTimer?.cancel();
      engineOffTimer = null;
    }
  });

  service.on('stop').listen((event) {
    service.stopSelf();
  });
}