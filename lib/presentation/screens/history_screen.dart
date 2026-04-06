import 'package:flutter/material.dart';
import '../../data/database/app_database.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('주행 이력'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<TripSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return const Center(
              child: Text(
                '주행 기록이 없습니다',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final score = session.finalScore;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 50,
                      decoration: BoxDecoration(
                        color: score >= 90
                            ? Colors.green
                            : score >= 70
                            ? const Color(0xFFEF9F27)
                            : Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(session.startTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${session.distanceKm.toStringAsFixed(1)} km · ${_formatDuration(session.startTime, session.endTime)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B3A5C),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$score점',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: score >= 90
                            ? Colors.green
                            : score >= 70
                            ? const Color(0xFFEF9F27)
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
