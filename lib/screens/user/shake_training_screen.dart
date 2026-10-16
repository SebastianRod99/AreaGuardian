import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../../services/protection_service.dart';
import '../../services/app_telemetry_service.dart';

class ShakeTrainingScreen extends StatefulWidget {
  const ShakeTrainingScreen({super.key, this.onDone});

  static const String completionCountKey = 'shake_training_completions';
  static const String invitationShownKey = 'shake_training_invitation_shown';

  final VoidCallback? onDone;

  @override
  State<ShakeTrainingScreen> createState() => _ShakeTrainingScreenState();
}

class _ShakeTrainingScreenState extends State<ShakeTrainingScreen> {
  final ProtectionService _practiceService = ProtectionService(
    practiceMode: true,
  );
  bool _realGuardIsActive = false;
  bool _completionWasSaved = false;
  int _lastObservedShakeEvent = 0;
  int _completionCount = 0;

  @override
  void initState() {
    super.initState();
    _realGuardIsActive = ProtectionService.shared.isProtected;
    _practiceService.addListener(_onPracticeChanged);
    if (!_realGuardIsActive) _practiceService.activate();
    _loadCompletionCount();
  }

  Future<void> _loadCompletionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _completionCount =
            prefs.getInt(ShakeTrainingScreen.completionCountKey) ?? 0;
      });
    } catch (error) {
      debugPrint('No se pudo leer el progreso de la práctica: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el progreso de la práctica.'),
          ),
        );
      }
    }
  }

  void _onPracticeChanged() {
    final detectedEvents = _practiceService.shakeEventCount;
    if (detectedEvents > _lastObservedShakeEvent) {
      _lastObservedShakeEvent = detectedEvents;
      unawaited(_vibrateForShake());
    }

    if (_practiceService.isPracticeComplete && !_completionWasSaved) {
      _completionWasSaved = true;
      unawaited(_saveCompletion());
    }

    if (mounted) setState(() {});
  }

  Future<void> _vibrateForShake() async {
    try {
      await Vibration.vibrate(duration: 60);
    } catch (error) {
      debugPrint('No se pudo vibrar durante la práctica: $error');
    }
  }

  Future<void> _saveCompletion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count =
          (prefs.getInt(ShakeTrainingScreen.completionCountKey) ?? 0) + 1;
      await prefs.setInt(ShakeTrainingScreen.completionCountKey, count);
      await AppTelemetryService.logPracticeCompleted();
      if (mounted) setState(() => _completionCount = count);
    } catch (error) {
      debugPrint('No se pudo guardar la práctica completada: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el progreso de la práctica.'),
          ),
        );
      }
    }
  }

  void _practiceAgain() {
    _completionWasSaved = false;
    _practiceService.resetPractice();
  }

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _practiceService.removeListener(_onPracticeChanged);
    _practiceService.deactivate();
    _practiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121420),
        title: const Text('Practica tu agitación'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFFFB300),
              child: const Text(
                'MODO PRÁCTICA — no se envía ninguna alerta',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF121420),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _realGuardIsActive
                    ? _buildGuardActiveNotice()
                    : _buildTrainingContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuardActiveNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB300)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.pause_circle_outline,
            size: 48,
            color: Color(0xFFFFB300),
          ),
          const SizedBox(height: 12),
          const Text(
            'Desactiva la guardia antes de practicar',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'La guardia real sigue activa y no se pausará automáticamente. '
            'Vuelve a Seguridad, desactívala y abre esta práctica de nuevo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Volver'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingContent() {
    final shakeCount = _practiceService.shakeCount;
    final isComplete = _practiceService.isPracticeComplete;

    if (isComplete) {
      return _buildSuccess(shakeCount);
    }

    final threshold = _practiceService.shakeThreshold;
    final acceleration = _practiceService.latestAcceleration;
    final showStrongerHint =
        acceleration >= threshold * 0.25 && acceleration < threshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Prueba el gesto con calma. Aquí no se contacta a nadie.',
          style: TextStyle(color: Colors.white70, fontSize: 15),
        ),
        const SizedBox(height: 20),
        _buildInstructions(),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            4,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: index < shakeCount ? 18 : 14,
              height: index < shakeCount ? 18 : 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < shakeCount
                    ? const Color(0xFF00E6A7)
                    : Colors.white24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Fuerza de la sacudida',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        _buildStrengthBar(acceleration, threshold),
        const SizedBox(height: 8),
        Text(
          'Actual: ${acceleration.toStringAsFixed(1)} m/s²   ·   '
          'Umbral: ${threshold.toStringAsFixed(1)} m/s²',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 18),
        if (_practiceService.shakeRejectionReason case final reason?)
          _buildFeedback(reason, isWarning: true)
        else if (showStrongerHint)
          _buildFeedback('Agita más fuerte para superar la línea.')
        else if (shakeCount > 0)
          _buildFeedback('Bien. Continúa hasta completar las 4 sacudidas.'),
        const SizedBox(height: 8),
        TextButton(onPressed: _finish, child: const Text('Salir de práctica')),
      ],
    );
  }

  Widget _buildInstructions() {
    const steps = [
      'Sujeta el celular con firmeza.',
      'Agítalo de forma brusca, no rítmica.',
      'Completa 4 sacudidas dentro de unos segundos.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFF00E6A7),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF121420),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[index],
                    style: const TextStyle(color: Colors.white70, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStrengthBar(double acceleration, double threshold) {
    const maxStrengthMultiplier = 1.5;
    final maxStrength = threshold * maxStrengthMultiplier;
    final value = (acceleration / maxStrength).clamp(0.0, 1.0);
    final thresholdPosition = 1 / maxStrengthMultiplier;

    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Container(color: Colors.white12),
              FractionallySizedBox(
                widthFactor: value,
                child: Container(color: const Color(0xFF00E6A7)),
              ),
              Positioned(
                left: constraints.maxWidth * thresholdPosition - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedback(String message, {bool isWarning = false}) {
    final color = isWarning ? const Color(0xFFFFB300) : Colors.white70;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSuccess(int shakeCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Icon(
          Icons.check_circle_outline,
          size: 72,
          color: Color(0xFF00E6A7),
        ),
        const SizedBox(height: 16),
        const Text(
          '¡Práctica completada!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Detectamos $shakeCount sacudidas bruscas. '
          'Prácticas completadas: $_completionCount.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _practiceAgain,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00E6A7),
            foregroundColor: Colors.black,
          ),
          child: const Text('Practicar otra vez'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _finish, child: const Text('Listo')),
      ],
    );
  }
}
