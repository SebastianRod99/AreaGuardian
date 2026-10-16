import 'package:flutter/material.dart';

export '../../services/emergency_alert_service.dart';

class ShakeVibrationScreen extends StatefulWidget {
  const ShakeVibrationScreen({super.key});

  @override
  State<ShakeVibrationScreen> createState() => _ShakeVibrationScreenState();
}

class _ShakeVibrationScreenState extends State<ShakeVibrationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detector de Sacudidas')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Agita tu celular 4 veces rápidamente para activar la vibración de emergencia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
