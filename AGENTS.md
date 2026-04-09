# CAPFISCAL – AGENTS.md

## Objetivo
Mantener y corregir la app Flutter CAPFISCAL sin perder funcionalidades existentes, priorizando aprobación en App Store y Google Play.

## Stack
- Flutter / Dart
- Firebase Auth / Firestore / Storage / App Check
- In-App Purchases para documentos digitales
- iOS + Android

## Reglas obligatorias
1. No eliminar funcionalidades existentes salvo que sea estrictamente necesario y se documente.
2. No introducir pagos externos para documentos digitales.
3. Mantener la compra de documentos digitales con IAP / Play Billing.
4. Conservar preview parcial de documentos no comprados, pero bloquear descarga/acceso completo hasta compra exitosa.
5. Restaurar compras debe seguir funcionando.
6. Mantener compatibilidad con Firebase actual.
7. No cambiar nombres de productos IAP ni IDs sin revisar impacto en tiendas.
8. Preferir cambios mínimos, seguros y reversibles.
9. Antes de editar, analizar arquitectura y listar riesgos.
10. Después de editar, entregar resumen de cambios, archivos modificados, riesgos y pasos de prueba.

## Tareas prioritarias
1. Auditar lógica de IAP y cumplimiento de tiendas.
2. Eliminar o neutralizar cualquier rastro de pago externo para contenido digital.
3. Verificar carga de productos, compra, restore y unlock de documentos.
4. Corregir iconos oficiales de redes en Home: Instagram, Spotify y TikTok.
5. Corregir barra inferior de navegación para que en iPhone quede pegada abajo y respete SafeArea.
6. No romper login, biblioteca, favoritos, videos ni documentos.
