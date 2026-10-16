# Localidades de Bogotá

`bogota_localities.geojson` es una versión simplificada del conjunto oficial
**Localidad. Bogotá D.C.**, publicado por la Secretaría Distrital de Planeación
en Datos Abiertos Bogotá:

- Fuente: <https://datosabiertos.bogota.gov.co/dataset/856cb657-8ca3-4ee8-857f-37211173b1f8>
- Archivo fuente GeoJSON: <https://datosabiertos.bogota.gov.co/dataset/856cb657-8ca3-4ee8-857f-37211173b1f8/resource/497b8756-0927-4aee-8da9-ca4e32ca3a8a/download/loca.json>
- Licencia: Creative Commons Attribution 4.0 International
  (<https://creativecommons.org/licenses/by/4.0/>).
- Sistema de coordenadas de origen: MAGNA-SIRGAS geográfico (EPSG:4686).

Se conservaron las 20 localidades y los anillos interiores, reduciendo los
vértices con una tolerancia aproximada de 2.8 m. La geometría resultante se
empaquetó como GeoJSON `MultiPolygon` para usarla sin conexión en la app.
