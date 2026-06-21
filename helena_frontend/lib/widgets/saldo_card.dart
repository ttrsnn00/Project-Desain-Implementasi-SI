import 'package:flutter/material.dart';

class SaldoCard extends StatelessWidget {
  final String saldoRupiah;

  const SaldoCard({super.key, required this.saldoRupiah});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[800]!, Colors.blue[400]!], 
          begin: Alignment.topLeft, 
          end: Alignment.bottomRight
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Total Saldo Saat Ini", style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            saldoRupiah, 
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)
          ),
        ],
      ),
    );
  }
}