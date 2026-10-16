import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../map_dashboard_screen.dart';
import '../../services/directions_service.dart';

class IncomingEmergencyScreen extends StatefulWidget {
  const IncomingEmergencyScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<IncomingEmergencyScreen> createState() =>
      _IncomingEmergencyScreenState();
}

class _IncomingEmergencyScreenState extends State<IncomingEmergencyScreen> {
  static const Color _background = Color(0xFF11141D);
  static const Color _green = Color(0xFF00E6A7);
  static const Color _red = Color(0xFFFF4D5A);

  bool _accepted = false;
  final DirectionsService _directionsService = DirectionsService();

  String get _userName =>
      widget.data['userName']?.toString().trim().isNotEmpty == true
      ? widget.data['userName'].toString()
      : 'Un vecino';

  String get _roleLabel => widget.data['role']?.toString() == 'vendor'
      ? 'Puesto de apoyo'
      : 'Persona en emergencia';

  String get _shopName => widget.data['shopName']?.toString() ?? '';

  double? get _latitude => double.tryParse('${widget.data['latitude']}');

  double? get _longitude => double.tryParse('${widget.data['longitude']}');

  Future<void> _callNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la aplicación de llamadas.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la llamada: $error')),
      );
    }
  }

  Future<void> _openLocation() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapDashboardScreen(
          focusLatitude: latitude,
          focusLongitude: longitude,
          focusSourceLabel: _userName,
        ),
      ),
    );
  }

  Future<void> _openDirections() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return;

    final opened = await _directionsService.openWalkingDirections(
      destinationLatitude: latitude,
      destinationLongitude: longitude,
    );
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir una aplicación de rutas.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _latitude != null && _longitude != null;
    final source = _roleLabel == 'Puesto de apoyo' && _shopName.isNotEmpty
        ? _shopName
        : _roleLabel;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Cerrar alerta',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white60),
                ),
              ),
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _red.withValues(alpha: 0.12),
                  border: Border.all(color: _red, width: 2),
                ),
                child: const Icon(
                  Icons.call_received_rounded,
                  color: _red,
                  size: 48,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'ALERTA DE EMERGENCIA',
                style: TextStyle(
                  color: _red,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _userName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                source,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const Spacer(),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: _accepted
                    ? _buildVictimDetails(hasLocation)
                    : const SizedBox(width: double.infinity),
              ),
              if (!_accepted) ...[
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: () => setState(() => _accepted = true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.call),
                    label: const Text(
                      'Atender emergencia',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: () => _callNumber('123'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red, width: 1.5),
                  ),
                  icon: const Icon(Icons.local_police_outlined),
                  label: const Text(
                    'Llamar a policía · 123',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVictimDetails(bool hasLocation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'DATOS PARA COORDINAR APOYO',
            style: TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _detailRow(Icons.person_outline, 'Persona', _userName),
          if (hasLocation)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _openLocation,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Ver ubicación en el mapa'),
                  style: TextButton.styleFrom(foregroundColor: _green),
                ),
                TextButton.icon(
                  onPressed: _openDirections,
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Cómo llegar'),
                  style: TextButton.styleFrom(foregroundColor: _green),
                ),
              ],
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
