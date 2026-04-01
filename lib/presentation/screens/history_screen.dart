import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: drift DB에서 실제 세션 데이터 불러오기
    final dummySessions = [
      {'date': '오늘 09:32', 'score': 88, 'km': 12.3, 'min': 24},
      {'date': '어제 18:15', 'score': 74, 'km': 8.7,  'min': 18},
      {'date': '어제 08:50', 'score': 92, 'km': 15.1, 'min': 31},
      {'date': '2일 전 19:20', 'score': 65, 'km': 6.2, 'min': 14},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('주행 이력'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: dummySessions.length,
        itemBuilder: (context, index) {
          final session = dummySessions[index];
          final score   = session['score'] as int;
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
                        session['date'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session['km']} km · ${session['min']}분',
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
      ),
    );
  }
}