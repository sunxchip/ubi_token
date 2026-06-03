import 'package:flutter_test/flutter_test.dart';
import 'package:ubi_token/core/utils/safe_obd_command_validator.dart';

void main() {
  group('SafeObdCommandValidator', () {
    // ── 허용 명령 ─────────────────────────────────────────
    group('허용 명령', () {
      test('ATZ 허용', () => expect(SafeObdCommandValidator.isAllowed('ATZ'), isTrue));
      test('ATE0 허용', () => expect(SafeObdCommandValidator.isAllowed('ATE0'), isTrue));
      test('ATL0 허용', () => expect(SafeObdCommandValidator.isAllowed('ATL0'), isTrue));
      test('ATS0 허용', () => expect(SafeObdCommandValidator.isAllowed('ATS0'), isTrue));
      test('ATH0 허용', () => expect(SafeObdCommandValidator.isAllowed('ATH0'), isTrue));
      test('ATSP0 허용', () => expect(SafeObdCommandValidator.isAllowed('ATSP0'), isTrue));
      test('0100 허용', () => expect(SafeObdCommandValidator.isAllowed('0100'), isTrue));
      test('010C 허용 (RPM)', () => expect(SafeObdCommandValidator.isAllowed('010C'), isTrue));
      test('010D 허용 (속도)', () => expect(SafeObdCommandValidator.isAllowed('010D'), isTrue));
      test('0111 허용 (스로틀)', () => expect(SafeObdCommandValidator.isAllowed('0111'), isTrue));
      test('0104 허용 (엔진부하)', () => expect(SafeObdCommandValidator.isAllowed('0104'), isTrue));
      test('0105 허용 (냉각수)', () => expect(SafeObdCommandValidator.isAllowed('0105'), isTrue));
      test('012F 허용 (연료)', () => expect(SafeObdCommandValidator.isAllowed('012F'), isTrue));
      test('0902 허용 (VIN)', () => expect(SafeObdCommandValidator.isAllowed('0902'), isTrue));
      test('03 허용 (DTC 읽기)', () => expect(SafeObdCommandValidator.isAllowed('03'), isTrue));
    });

    // ── 정규화 처리 ─────────────────────────────────────────
    group('정규화 (공백·소문자·캐리지리턴)', () {
      test('소문자 010c → 허용', () => expect(SafeObdCommandValidator.isAllowed('010c'), isTrue));
      test('공백 포함 01 0D → 허용', () => expect(SafeObdCommandValidator.isAllowed('01 0D'), isTrue));
      test('캐리지리턴 010C\\r → 허용', () => expect(SafeObdCommandValidator.isAllowed('010C\r'), isTrue));
      test('소문자 atsp0 → 허용', () => expect(SafeObdCommandValidator.isAllowed('atsp0'), isTrue));
    });

    // ── 금지 명령 ─────────────────────────────────────────
    group('금지 명령 (차단)', () {
      test('04 DTC 삭제 차단', () => expect(SafeObdCommandValidator.isAllowed('04'), isFalse));
      test('08 온보드 제어 차단', () => expect(SafeObdCommandValidator.isAllowed('08'), isFalse));
      test('1003 Diagnostic Session 차단', () => expect(SafeObdCommandValidator.isAllowed('1003'), isFalse));
      test('1101 ECU Reset 차단', () => expect(SafeObdCommandValidator.isAllowed('1101'), isFalse));
      test('14FFFFFF UDS Clear DTC 차단', () => expect(SafeObdCommandValidator.isAllowed('14FFFFFF'), isFalse));
      test('22F190 제조사 PID 차단', () => expect(SafeObdCommandValidator.isAllowed('22F190'), isFalse));
      test('2E1234 Write Data 차단', () => expect(SafeObdCommandValidator.isAllowed('2E1234'), isFalse));
      test('2F 제어 차단', () => expect(SafeObdCommandValidator.isAllowed('2F'), isFalse));
      test('31 Routine Control 차단', () => expect(SafeObdCommandValidator.isAllowed('31'), isFalse));
      test('3E Tester Present 차단', () => expect(SafeObdCommandValidator.isAllowed('3E'), isFalse));
      test('27 Security Access 차단', () => expect(SafeObdCommandValidator.isAllowed('27'), isFalse));
    });

    // ── CAN/헤더 명령 차단 ────────────────────────────────
    group('CAN/헤더 명령 차단', () {
      test('ATSH7E0 CAN Header 차단', () => expect(SafeObdCommandValidator.isAllowed('ATSH7E0'), isFalse));
      test('ATH1 헤더 ON 차단 (ATH0만 허용)', () => expect(SafeObdCommandValidator.isAllowed('ATH1'), isFalse));
      test('ATSP6 특정 프로토콜 차단', () => expect(SafeObdCommandValidator.isAllowed('ATSP6'), isFalse));
      test('ATCRA 차단', () => expect(SafeObdCommandValidator.isAllowed('ATCRA'), isFalse));
      test('ATCAF0 차단', () => expect(SafeObdCommandValidator.isAllowed('ATCAF0'), isFalse));
      test('ATCF 차단', () => expect(SafeObdCommandValidator.isAllowed('ATCF'), isFalse));
      test('ATCM 차단', () => expect(SafeObdCommandValidator.isAllowed('ATCM'), isFalse));
      test('ATMA 차단 (모니터 모드)', () => expect(SafeObdCommandValidator.isAllowed('ATMA'), isFalse));
      test('ATAT1 차단', () => expect(SafeObdCommandValidator.isAllowed('ATAT1'), isFalse));
    });

    // ── assertSafe 예외 확인 ──────────────────────────────
    group('assertSafe 예외', () {
      test('금지 명령 → UnsafeObdCommandException 발생', () {
        expect(
          () => SafeObdCommandValidator.assertSafe('04'),
          throwsA(isA<UnsafeObdCommandException>()),
        );
      });

      test('허용 명령 → 예외 없음', () {
        expect(
          () => SafeObdCommandValidator.assertSafe('010C'),
          returnsNormally,
        );
      });

      test('예외 메시지에 "BLOCKED" 포함', () {
        try {
          SafeObdCommandValidator.assertSafe('22F190');
        } on UnsafeObdCommandException catch (e) {
          expect(e.toString(), contains('BLOCKED'));
          expect(e.toString(), contains('22F190'));
        }
      });
    });
  });
}
