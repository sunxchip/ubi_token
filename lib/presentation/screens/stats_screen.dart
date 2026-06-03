import 'package:flutter/material.dart';
import '../../data/database/app_database.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = AppDatabase.instance;
  late Future<_StatsData> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<_StatsData> _loadStats() async {
    final sessions = await _db.getRecentSessions(limit: 7);
    if (sessions.isEmpty) return _StatsData.empty();

    final scores = sessions.map((s) => s.finalScore.toDouble()).toList();
    final avgScore = (scores.reduce((a, b) => a + b) / scores.length).round();
    final totalKm = sessions.fold(0.0, (sum, s) => sum + s.distanceKm);

    // 요일 레이블 (최신순 → 역순으로 표시)
    final days = sessions.reversed.map((s) {
      final dt = DateTime.fromMillisecondsSinceEpoch(s.startTime);
      const labels = ['일', '월', '화', '수', '목', '금', '토'];
      return labels[dt.weekday % 7];
    }).toList();

    return _StatsData(
      scores: sessions.reversed.map((s) => s.finalScore.toDouble()).toList(),
      days: days,
      avgScore: avgScore,
      totalSessions: sessions.length,
      totalKm: totalKm,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('통계'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<_StatsData>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? _StatsData.empty();
          if (data.scores.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bar_chart_outlined,
                          size: 36, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(height: 16),
                    const Text('아직 데이터가 없습니다',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B))),
                    const SizedBox(height: 8),
                    const Text(
                      '주행을 시작하면 여기에\n통계가 표시됩니다',
                      style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          final maxScore = 100.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '최근 주행 점수',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B3A5C),
                  ),
                ),
                const SizedBox(height: 16),

                // 막대 그래프
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: data.scores.asMap().entries.map((e) {
                      final score = e.value;
                      final color = score >= 90
                          ? Colors.green
                          : score >= 70
                          ? const Color(0xFFEF9F27)
                          : Colors.red;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${score.toInt()}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FractionallySizedBox(
                                heightFactor: score / maxScore,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                e.key < data.days.length ? data.days[e.key] : '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  '최근 요약',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B3A5C),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatCard(
                      label: '평균 점수',
                      value: '${data.avgScore}',
                      unit: '점',
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: '총 주행',
                      value: '${data.totalSessions}',
                      unit: '회',
                      color: const Color(0xFF1D9E75),
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: '총 거리',
                      value: data.totalKm.toStringAsFixed(1),
                      unit: 'km',
                      color: const Color(0xFF7F77DD),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsData {
  final List<double> scores;
  final List<String> days;
  final int avgScore;
  final int totalSessions;
  final double totalKm;

  _StatsData({
    required this.scores,
    required this.days,
    required this.avgScore,
    required this.totalSessions,
    required this.totalKm,
  });

  factory _StatsData.empty() => _StatsData(
        scores: [],
        days: [],
        avgScore: 0,
        totalSessions: 0,
        totalKm: 0,
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    )),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
