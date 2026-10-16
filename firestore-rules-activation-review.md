# Revisión de activación de reglas

## Accesos vigentes

- `users/{uid}`: cada usuario lee y modifica únicamente su perfil; los campos admitidos se validan y el cliente no puede borrar el documento.
- `vendors/{uid}`: solo el propietario autenticado puede leer o modificar su puesto. La proyección `public_vendors/{uid}` es de solo lectura para usuarios autenticados y la mantiene Cloud Functions.
- `emergencies/{id}`: el propietario puede leer sus alertas. Otros usuarios autenticados solo pueden leer emergencias activas, no simulacros, de los últimos 21 minutos y dentro del rectángulo aproximado de su última ubicación conocida (que debe tener menos de 24 horas).
- La app además consulta una ventana de 20 minutos y un rectángulo de 300 m, y filtra la distancia exacta con Haversine antes de mostrar o sonar una alerta.
- El cliente solo puede crear una alerta propia, activa y con `isTest` explícito, junto con el puntero `activeEmergencyId` del perfil en la misma operación. Solo puede resolver/cancelar su alerta y enviar una respuesta de encuesta válida.
- Los campos de SMS, destinatarios/notificaciones y estado de entrega no se admiten en las escrituras del cliente; los administra Cloud Functions con Admin SDK.
- `storage.rules` limita la escritura de fotos de perfil a su propietario y restringe tamaño y tipo de contenido.

## Comprobaciones realizadas

- Las reglas se cargaron en el emulador local sin errores de sintaxis.
- Las pruebas dirigidas de Flutter pasaron (25 pruebas) y el APK Android debug compiló.
- No se ejecutó una matriz de autorización con clientes autenticados contra el emulador; antes de producción hay que probar lecturas fuera de zona, escrituras cruzadas, transiciones de estado, simulacros y campos de servidor.
- No se desplegaron reglas, índices ni funciones.

## Riesgos y activación

- Las coordenadas de `lastKnownLatitude`/`lastKnownLongitude` las escribe el cliente. Las reglas limitan las consultas accidentales, pero no prueban que el GPS sea auténtico: una app modificada puede falsificar su propia ubicación y consultar otra zona.
- El rectángulo de autorización es deliberadamente aproximado; la app reduce la exposición adicionalmente a 300 m y aplica Haversine, pero las reglas no garantizan ese círculo exacto.
- Los usuarios autenticados pueden leer los documentos de `public_vendors` y las emergencias activas recientes permitidas por su zona. Verificar que ese nivel de divulgación de ubicación corresponde a la política de privacidad publicada.
- Para activar el cambio, revisar y desplegar explícitamente `firestore.rules`, `storage.rules`, `firestore.indexes.json` y las funciones requeridas. La consulta geográfica necesita los índices definidos en `firestore.indexes.json`.
- Eliminar cuenta depende de desplegar `deleteAccountAndData`; el botón no puede completar el borrado si la función no está disponible. No se probó el borrado contra datos reales.
