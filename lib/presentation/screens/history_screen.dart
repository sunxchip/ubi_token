import 'package:flutter/material.dart';
import '../../data/database/app_database.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = AppDatabase.instance;
  late Future<List<TripSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _db.getAllSessions();
  }

  String _formatDate(int milliseconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    final diff = now.difference(dt);
    final timeStr =
        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

    if (diff.inDays == 0) return '오늘 $timeStr';
    if (diff.inDays == 1) return '어제 $timeStr';
    return '${diff.inDays}일 전 $timeStr';
  }

  String _formatDuration(int startMs, int? endMs) {
    if (endMs == null) return '주행 중';
    final minutes = ((endMs - startMs) / 60000).round();
    return '$minutes분';
  }

  Color _scoreColor(int score) {
    if (score >= 90) return AppColors.success;
    if (score >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  Color _scoreBg(int score) {
    if (score >= 90) return AppColors.successLight;
    if (score >= 70) return AppColors.warningLight;
    return AppColors.dangerLight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('주행 이력', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: FutureBuilder<List<TripSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.history_outlined,
                          size: 36, color: AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text('아직 주행 기록이 없습니다',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    const Text(
                      '스캐너를 연결하고 주행을 시작하면\n기록이 이곳에 표시됩니다',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final score = session.finalScore;
              final isActive = session.endTime == null;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // 점수 뱃지
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: _scoreBg(score),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$score',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _scoreColor(score),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _formatDate(session.startTime),
                                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.successLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('주행 중', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${session.distanceKm.toStringAsFixed(1)} km · ${_formatDuration(session.startTime, session.endTime)}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
