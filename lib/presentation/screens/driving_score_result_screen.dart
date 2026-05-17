import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/score_result.dart';
import '../../data/models/drive_event.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

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
    if (s >= 90) return AppColors.success;
    if (s >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('주행 리포트', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 최종 점수 헤더
            _ScoreHeader(score: r.score, color: _scoreColor, result: r),
            const SizedBox(height: 10),

            // 주행 시간 표시
            if (widget.startTime != null)
              Center(
                child: Text(
                  '주행 시간: $_durationLabel',
                  style: AppTextStyles.caption,
                ),
              ),
            const SizedBox(height: 14),

            // 감점 요약
            const Text('감점 요약', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            _PenaltySummaryGrid(result: r),
            const SizedBox(height: 18),

            // 이벤트 타임라인
            if (r.events.isNotEmpty) ...[
              const Text('이벤트 타임라인', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ...r.events.map((e) => _TimelineItem(event: e)),
            ] else ...[
              const _PerfectDriveCard(),
            ],

            const SizedBox(height: 20),

            // 돌아가기 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '주행 화면으로 돌아가기',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(
          children: [
            // 등급 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${result.grade}등급 · ${result.gradeLabel}',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 점수
            Text(
              '$score',
              style: TextStyle(
                fontSize: 68,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            const Text('/ 100점', style: AppTextStyles.captionHint),
            const SizedBox(height: 12),

            // 감점 총계
            if (result.totalPenalty > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_circle_outline, size: 13, color: AppColors.danger),
                    const SizedBox(width: 5),
                    Text(
                      '총 ${result.totalPenalty}점 감점  ·  이벤트 ${result.events.length}건',
                      style: const TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 13, color: AppColors.success),
                    SizedBox(width: 5),
                    Text(
                      '감점 없음!  완벽한 주행',
                      style: TextStyle(fontSize: 12, color: AppColors.success),
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
      _PenaltyItem('급가속',     result.harshAccelCount,    3, Icons.arrow_upward_rounded,        const Color(0xFFEA580C)),
      _PenaltyItem('급감속',     result.harshBrakeCount,    4, Icons.arrow_downward_rounded,       AppColors.danger),
      _PenaltyItem('급출발',     result.hardStartCount,     4, Icons.directions_car_rounded,       AppColors.danger),
      _PenaltyItem('고RPM',     result.highRpmCount,       2, Icons.speed_rounded,                const Color(0xFF7C3AED)),
      _PenaltyItem('스로틀급변', result.throttleSpikeCount, 2, Icons.tune_rounded,                 AppColors.warning),
      _PenaltyItem('공회전',    result.idlingCount,         2, Icons.timer_rounded,                AppColors.primary),
      _PenaltyItem('엔진과부하', result.engineOverloadCount, 2, Icons.local_fire_department_rounded, const Color(0xFFEA580C)),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: item.count > 0
                ? item.color.withValues(alpha: 0.25)
                : AppColors.border,
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 14,
              color: item.count > 0 ? item.color : AppColors.border,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.label, style: AppTextStyles.captionHint),
                  Text(
                    item.count > 0 ? '${item.count}회 · -${item.totalPenalty}점' : '0회',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: item.count > 0 ? item.color : AppColors.border,
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
      case 2: return AppColors.warning;
      case 3: return const Color(0xFFEA580C);
      case 4: return AppColors.danger;
      default: return AppColors.textSecondary;
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
          // 아이콘
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(_icon, size: 15, color: _color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title.isNotEmpty ? event.title : event.type.name,
                          style: AppTextStyles.label,
                        ),
                        if (event.description.isNotEmpty)
                          Text(event.description, style: AppTextStyles.captionHint),
                        Text(time, style: AppTextStyles.captionHint),
                      ],
                    ),
                  ),
                  Text(
                    '-${event.penalty}점',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: _color),
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
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: const Column(
          children: [
            Icon(Icons.emoji_events_rounded, size: 40, color: AppColors.success),
            SizedBox(height: 10),
            Text(
              '완벽한 주행!',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.success),
            ),
            SizedBox(height: 4),
            Text(
              '감점 이벤트가 발생하지 않았습니다.\n안전 운전 습관을 유지하세요!',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      );
}
