import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SessionRestoreErrorScreen extends StatefulWidget {
  const SessionRestoreErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onSignOut,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  State<SessionRestoreErrorScreen> createState() =>
      _SessionRestoreErrorScreenState();
}

class _SessionRestoreErrorScreenState
    extends State<SessionRestoreErrorScreen> {
  String? _actionError;

  String get _errorCode {
    final error = widget.error;
    if (error is FirebaseException) {
      return '${error.plugin}/${error.code}';
    }
    return error.runtimeType.toString();
  }

  bool get _isPermissionDenied {
    final error = widget.error;
    return error is FirebaseException && error.code == 'permission-denied';
  }

  Future<void> _signOut() async {
    setState(() => _actionError = null);
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = 'No se pudo cerrar sesión: $error');
      }
    }
  }

  Future<void> _reportProblem() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reportar problema'),
        content: SelectableText(
          'Código: $_errorCode\n\nCopia este código e inclúyelo en tu reporte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _errorCode));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Código copiado.')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar código'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121420),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.cloud_off,
                    color: Color(0xFFFFB74D),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudo restaurar tu perfil.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isPermissionDenied
                        ? 'El servicio rechazó el acceso a tu perfil.'
                        : 'Comprueba tu conexión e inténtalo de nuevo.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Código: $_errorCode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (_actionError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _actionError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.onRetry,
                    child: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _signOut,
                    child: const Text('Cerrar sesión'),
                  ),
                  TextButton(
                    onPressed: _reportProblem,
                    child: const Text('Reportar problema'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
