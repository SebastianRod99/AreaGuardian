import '../models/vendor_model.dart';

class VendorService {
  // Simula la obtención de puestos de vendedores cercanos
  Future<List<VendorModel>> getNearbyVendors(double lat, double lng) async {
    // Simulamos un pequeño retraso de red (800 milisegundos)
    await Future.delayed(const Duration(milliseconds: 800));

    // Lista de puestos de prueba en la red de AreaGuardian
    return [
      VendorModel(
        id: 'v1',
        userId: 'user_01',
        shopName: 'Tienda Don Pedro',
        category: 'Víveres y Seguridad',
        latitude: lat + 0.0010,
        longitude: lng + 0.0010,
        nequiNumber: '3101234567',
        daviplataNumber: '3101234567',
        isActive: true,
      ),
      VendorModel(
        id: 'v2',
        userId: 'user_02',
        shopName: 'Papelería El Punto',
        category: 'Comercio Local',
        latitude: lat - 0.0015,
        longitude: lng + 0.0020,
        nequiNumber: '3209876543',
        daviplataNumber: '3209876543',
        isActive: true,
      ),
      VendorModel(
        id: 'v3',
        userId: 'user_03',
        shopName: 'Ferretería La Alerta',
        category: 'Herramientas y Auxilio',
        latitude: lat + 0.0020,
        longitude: lng - 0.0015,
        nequiNumber: '3005554433',
        daviplataNumber: '3005554433',
        isActive: true,
      ),
    ];
  }
}