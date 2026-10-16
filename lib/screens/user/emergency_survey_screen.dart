import 'package:flutter/material.dart';
import 'package:areaguardian/services/firestore_service.dart';

enum _SurveyStep { wellbeing, falseAlarm, communityHelp, details, complete }

class EmergencySurveyScreen extends StatefulWidget {
  const EmergencySurveyScreen({super.key, required this.emergencyId});

  final String emergencyId;

  @override
  State<EmergencySurveyScreen> createState() => _EmergencySurveyScreenState();
}

class _EmergencySurveyScreenState extends State<EmergencySurveyScreen> {
  static const Color _background = Color(0xFF121420);
  static const Color _accent = Color(0xFF00E6A7);

  final TextEditingController _detailsController = TextEditingController();
  _SurveyStep _step = _SurveyStep.wellbeing;
  String? _completionMessage;
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _answerWellbeing(bool wasSafe) {
    setState(() {
      _step = wasSafe ? _SurveyStep.falseAlarm : _SurveyStep.communityHelp;
      _errorMessage = null;
    });
  }

  Future<void> _answerFalseAlarm(bool wasFalseAlarm) async {
    await _submit(
      wasSafe: true,
      falseAlarm: wasFalseAlarm,
      completionMessage: wasFalseAlarm
          ? 'Gracias, me alegra que haya sido una falsa alarma.'
          : 'Gracias por contarnos. Esperamos que la situación esté bajo control.',
    );
  }

  Future<void> _answerCommunityHelp(bool receivedHelp) async {
    if (!receivedHelp) {
      setState(() {
        _step = _SurveyStep.details;
        _errorMessage = null;
      });
      return;
    }

    await _submit(
      wasSafe: false,
      receivedHelp: true,
      completionMessage: 'Gracias, me alegra que la comunidad te haya ayudado.',
    );
  }

  Future<void> _submitDetails() async {
    final details = _detailsController.text.trim();
    if (details.isEmpty) {
      setState(() => _errorMessage = 'Escribe los detalles antes de enviar.');
      return;
    }

    await _submit(
      wasSafe: false,
      receivedHelp: false,
      details: details,
      completionMessage: 'Gracias por compartir los detalles. Estamos contigo.',
    );
  }

  Future<void> _submit({
    required bool wasSafe,
    required String completionMessage,
    bool? falseAlarm,
    bool? receivedHelp,
    String? details,
  }) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await FirestoreService().submitEmergencySurvey(
        emergencyId: widget.emergencyId,
        wasSafe: wasSafe,
        falseAlarm: falseAlarm,
        receivedHelp: receivedHelp,
        details: details,
      );
      if (!mounted) return;
      setState(() {
        _completionMessage = completionMessage;
        _step = _SurveyStep.complete;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'No se pudo guardar la respuesta. Reintenta.',
      );
      debugPrint('No se pudo guardar la encuesta de emergencia: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: const Text('Encuesta de emergencia'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _buildStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _SurveyStep.wellbeing:
        return _question(
          '¿Estás bien?',
          onYes: () => _answerWellbeing(true),
          onNo: () => _answerWellbeing(false),
        );
      case _SurveyStep.falseAlarm:
        return _question(
          '¿Fue una falsa alarma?',
          onYes: () => _answerFalseAlarm(true),
          onNo: () => _answerFalseAlarm(false),
        );
      case _SurveyStep.communityHelp:
        return _question(
          '¿Los vendedores ambulantes / policía te apoyaron?',
          onYes: () => _answerCommunityHelp(true),
          onNo: () => _answerCommunityHelp(false),
        );
      case _SurveyStep.details:
        return _buildDetailsForm();
      case _SurveyStep.complete:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: _accent, size: 56),
            const SizedBox(height: 20),
            Text(
              _completionMessage ?? 'Gracias por responder.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
    }
  }

  Widget _question(
    String prompt, {
    required VoidCallback onYes,
    required VoidCallback onNo,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 32),
        _answerButton('Sí', onYes),
        const SizedBox(height: 12),
        _answerButton('No', onNo, outlined: true),
        if (_isSubmitting) ...[
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: _accent),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '¿Quieres darnos detalles de cómo saliste de este problema?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _detailsController,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Escribe aquí',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isSubmitting ? null : _submitDetails,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }

  Widget _answerButton(
    String label,
    VoidCallback onPressed, {
    bool outlined = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: _isSubmitting ? null : onPressed,
              child: Text(label),
            )
          : FilledButton(
              onPressed: _isSubmitting ? null : onPressed,
              child: Text(label),
            ),
    );
  }
}
