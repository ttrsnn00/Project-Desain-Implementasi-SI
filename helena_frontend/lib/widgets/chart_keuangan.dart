import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ChartKeuangan extends StatelessWidget {
  final int pemasukanTotal;
  final int pengeluaranTotal;
  final String pemasukanRupiah;
  final String pengeluaranRupiah;

  const ChartKeuangan({
    super.key,
    required this.pemasukanTotal,
    required this.pengeluaranTotal,
    required this.pemasukanRupiah,
    required this.pengeluaranRupiah,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Analisis Keuangan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey[200]!)),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 40,
                      sections: [
                        if (pemasukanTotal > 0)
                          PieChartSectionData(
                            color: Colors.green,
                            value: pemasukanTotal.toDouble(),
                            title: '${((pemasukanTotal / (pemasukanTotal + pengeluaranTotal)) * 100).toStringAsFixed(1)}%',
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        if (pengeluaranTotal > 0)
                          PieChartSectionData(
                            color: Colors.red,
                            value: pengeluaranTotal.toDouble(),
                            title: '${((pengeluaranTotal / (pemasukanTotal + pengeluaranTotal)) * 100).toStringAsFixed(1)}%',
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLegend(Colors.green, "Pemasukan", pemasukanRupiah),
                    _buildLegend(Colors.red, "Pengeluaran", pengeluaranRupiah),
                  ],
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Fungsi helper internal untuk komponen ini
  Widget _buildLegend(Color color, String text, String nominal) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        Text(nominal, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
      ],
    );
  }
}