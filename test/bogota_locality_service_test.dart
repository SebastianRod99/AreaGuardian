import 'package:flutter_test/flutter_test.dart';
import 'package:areaguardian/services/bogota_locality_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BogotaLocalityService localityService;

  setUpAll(() async {
    localityService = await BogotaLocalityService.load();
  });

  test('identifica Fontibón y las localidades vecinas Kennedy y Engativá', () {
    expect(localityService.localityAt(const LatLng(4.678, -74.14)), 'Fontibón');
    expect(localityService.localityAt(const LatLng(4.625, -74.15)), 'Kennedy');
    expect(localityService.localityAt(const LatLng(4.7, -74.11)), 'Engativá');
  });

  test('retorna null fuera de las localidades de Bogotá', () {
    expect(localityService.localityAt(const LatLng(4.7, -74.3)), isNull);
  });

  test('respeta el hueco de La Candelaria en el polígono de Santa Fe', () {
    expect(
      localityService.localityAt(const LatLng(4.596, -74.073)),
      'La Candelaria',
    );
  });
}
