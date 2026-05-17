import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/score_result.dart';
import '../../data/models/drive_event.dart';

class DrivingScoreResultScreen extends StatefulWidget {
  final ScoreResult result;
  final DateTime?   startTime;
  final DateTime?   endTime;

  const DrivingScoreResultScreen({
    super.key,
    required this.result,
    this.startTime,
    this.endTime,
  });

  @override
  State<DrivingScoreResultScreen> createState() => _DrivingScoreResultScreenState();
}

class _DrivingScoreResultScreenState extends State<DrivingScoreResultScreen> {
  @override
  void initState() {
    super.initState();
    _saveLastScore();
  }

  Future<void> _saveLastScore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_score', widget.result.score);
  }

  String get _durationLabel {
    final start = widget.startTime;
    final end   = widget.endTime;
    if (start == null || end == null) return '-';
    final diff = end.difference(start);
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 ${diff.inSeconds % 60}초';
    return '${diff.inSeconds}초';
  }

  Color get _scoreColor {
    final s = widget.result.score;
    if (s >= 90) return const Color(0xFF1D9E75);
    if (s >= 70) return const Color(0xFFEF9F27);
    return const Color(0xFFE53E3E);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('주행 결과', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B3A5C),
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기', style: TextStyle(color: Color(0xFF1B3A5C))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 최종 점수 헤더 ──────────────────────────────
            _ScoreHeader(score: r.score, color: _scoreColor, result: r),
            const SizedBox(height: 12),

            // ── 주행 시간 표시 ──────────────────────────────
            if (widget.startTime != null)
              Center(
                child: Text(
                  '주행 시간: $_durationLabel',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
            const SizedBox(height: 8),

            // ── 감점 요약 ───────────────────────────────────
            const _SectionTitle('감점 요약'),
            const SizedBox(height: 10),
            _PenaltySummaryGrid(result: r),
            const SizedBox(height: 20),

            // ── 이벤트 타임라인 ─────────────────────────────
            if (r.events.isNotEmpty) ...[
              const _SectionTitle('이벤트 타임라인'),
              const SizedBox(height: 10),
              ...r.events.map((e) => _TimelineItem(event: e)),
            ] else ...[
              const _PerfectDriveCard(),
            ],

            const SizedBox(height: 24),

            // ── 홈으로 버튼 ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B3A5C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '주행 화면으로 돌아가기',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 최종 점수 헤더 ─────────────────────────────────────────────────────────────
class _ScoreHeader extends StatelessWidget {
  final int score;
  final Color color;
  final ScoreResult result;

  const _ScoreHeader({
    required this.score,
    required this.color,
    required this.result,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // 등급 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${result.grade}등급 · ${result.gradeLabel}',
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 점수
            Text(
              '$score',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '/ 100점',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // 감점 총계
            if (result.totalPenalty > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.remove_circle_outline, size: 14, color: Colors.red[300]),
                    const SizedBox(width: 6),
                    Text(
                      '총 ${result.totalPenalty}점 감점  ·  이벤트 ${result.events.length}건',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: Color(0xFF1D9E75)),
                    SizedBox(width: 6),
                    Text(
                      '감점 없음!  완벽한 주행',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1D9E75)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

// ── 감점 요약 그리드 ───────────────────────────────────────────────────────────
class _PenaltySummaryGrid extends StatelessWidget {
  final ScoreResult result;
  const _PenaltySummaryGrid({required this.result});

  @override
  Widget build(BuildContext context) {
    final items = [
      _PenaltyItem('급가속',     result.harshAccelCount,    3, Icons.arrow_upward_rounded,        const Color(0xFFE67E22)),
      _PenaltyItem('급감속',     result.harshBrakeCount,    4, Icons.arrow_downward_rounded,       const Color(0xFFE53E3E)),
      _PenaltyItem('급출발',     result.hardStartCount,     4, Icons.directions_car_rounded,       const Color(0xFFE53E3E)),
      _PenaltyItem('고RPM',     result.highRpmCount,       2, Icons.speed_rounded,                const Color(0xFF7F77DD)),
      _PenaltyItem('스로틀급변', result.throttleSpikeCount, 2, Icons.tune_rounded,                 const Color(0xFFEF9F27)),
      _PenaltyItem('공회전',    result.idlingCount,         2, Icons.timer_rounded,                const Color(0xFF2563EB)),
      _PenaltyItem('엔진과부하', result.engineOverloadCount, 2, Icons.local_fire_department_rounded, const Color(0xFFD85A30)),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: items.map((item) => _PenaltyCard(item: item)).toList(),
    );
  }
}

class _PenaltyItem {
  final String label;
  final int count;
  final int unitPenalty;
  final IconData icon;
  final Color color;
  const _PenaltyItem(this.label, this.count, this.unitPenalty, this.icon, this.color);
  int get totalPenalty => count * unitPenalty;
}

class _PenaltyCard extends StatelessWidget {
  final _PenaltyItem item;
  const _PenaltyCard({required this.item});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.count > 0
                ? item.color.withValues(alpha: 0.3)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 16,
              color: item.count > 0 ? item.color : Colors.grey[300],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                  Text(
                    item.count > 0 ? '${item.count}회 · -${item.totalPenalty}점' : '0회',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: item.count > 0 ? item.color : Colors.grey[300],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── 이벤트 타임라인 아이템 ─────────────────────────────────────────────────────
class _TimelineItem extends StatelessWidget {
  final DriveEvent event;
  const _TimelineItem({required this.event});

  Color get _color {
    switch (event.penalty) {
      case 2: return const Color(0xFFEF9F27);
      case 3: return const Color(0xFFE67E22);
      case 4: return const Color(0xFFE53E3E);
      default: return Colors.grey;
    }
  }

  IconData get _icon {
    switch (event.type) {
      case EventType.harshAccel:    return Icons.arrow_upward_rounded;
      case EventType.harshBrake:    return Icons.arrow_downward_rounded;
      case EventType.hardStart:     return Icons.directions_car_rounded;
      case EventType.highRpm:       return Icons.speed_rounded;
      case EventType.throttleSpike: return Icons.tune_rounded;
      case EventType.idling:        return Icons.timer_rounded;
      case EventType.engineOverload: return Icons.local_fire_department_rounded;
      default:                      return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts   = event.timestamp;
    final time = '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타임라인 선 + 아이콘
          Column(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_icon, size: 16, color: _color),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title.isNotEmpty ? event.title : event.type.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF1B3A5C),
                          ),
                        ),
                        if (event.description.isNotEmpty)
                          Text(
                            event.description,
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        Text(
                          time,
                          style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '-${event.penalty}점',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 감점 없음 카드 ─────────────────────────────────────────────────────────────
class _PerfectDriveCard extends StatelessWidget {
  const _PerfectDriveCard();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFFE1F5EE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1D9E75).withValues(alpha: 0.3)),
        ),
        child: const Column(
          children: [
            Icon(Icons.emoji_events_rounded, size: 48, color: Color(0xFF1D9E75)),
            SizedBox(height: 12),
            Text(
              '완벽한 주행!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D9E75),
              ),
            ),
            SizedBox(height: 4),
            Text(
              '감점 이벤트가 발생하지 않았습니다.\n안전 운전 습관을 유지하세요!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF2D9B70)),
            ),
          ],
        ),
      );
}

// ── 섹션 타이틀 ───────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1B3A5C),
        ),
      );
}
