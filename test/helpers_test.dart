import 'package:areaguardian/utils/helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeColombianMobileNumber', () {
    test('normaliza un celular colombiano local', () {
      expect(normalizeColombianMobileNumber('300 123 4567'), '+573001234567');
    });

    test(
      'extrae el teléfono del contacto guardado en formato nombre — número',
      () {
        expect(
          normalizeColombianMobileNumber(
            'Contacto de confianza — +57 310 555 0198',
          ),
          '+573105550198',
        );
      },
    );

    test('rechaza teléfonos fijos, longitudes inválidas y otros países', () {
      expect(normalizeColombianMobileNumber('601 555 1234'), isNull);
      expect(normalizeColombianMobileNumber('+1 415 555 2671'), isNull);
      expect(normalizeColombianMobileNumber('300 123 456'), isNull);
    });
  });
}
