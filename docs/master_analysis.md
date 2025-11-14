# Análisis de la rama `master`

Este documento resume hallazgos de seguridad, rendimiento y mantenibilidad detectados al revisar el código actual de CAPFISCAL, así como recomendaciones para endurecer los flujos con Stripe/Firebase y la estrategia de pruebas.

## 1. Seguridad

| Riesgo | Evidencia | Impacto | Mitigación propuesta |
| --- | --- | --- | --- |
| **Clientes pueden auto-activarse** modificando el documento `users/{uid}` porque las reglas permiten `write` completo y los formularios crean/cambian `subscription.*` desde el cliente. | `firestore.rules` permite escribir cualquier campo si `request.auth.uid == uid`. `lib/screens/login_screen.dart` y `lib/screens/user_profile_screen.dart` actualizan `subscription` directo desde el cliente. | Usuarios maliciosos pueden otorgarse acceso ilimitado o reescribir campos sensibles. | Limitar reglas para que el cliente sólo pueda actualizar campos de perfil no sensibles y mover toda la lógica de suscripción (start/end/paymentMethod/status) a Cloud Functions (ver nuevas `activateSubscriptionAccess` y `scheduleSubscriptionCancellation`). |
| **Endpoint de PaymentSheet sin control de origen ni App Check**. | `functions/index.js` expone `stripePaymentIntentRequest` con CORS `*` y sin verificación de identidad. El cliente (`lib/screens/subscription_required_screen.dart`) le envía `amount`, `email` y `uid` arbitrarios. | Cualquiera puede generar PaymentIntents/EphemeralKeys y abusar de la cuota de Stripe. | Requerir App Check y autenticar al usuario antes de crear intents; mover esta lógica a callable functions protegidas o validar tokens `Authorization`. |
| **Datos manuales permiten activar suscripción con cualquier texto**. | En el registro `_activateNow` sólo requiere un texto en `Método de pago (opcional)` para marcar `manual_active`. | Usuarios pueden saltarse Stripe y activar acceso con cualquier cadena. | Desactivar activaciones manuales en producción o moverlas a un flujo administrativo autenticado en backend. |
| **Sin validación de inputs en formularios**. | Campos como teléfono, ciudad o método de pago aceptan cualquier string; no hay límites ni sanitización. | Puede causar datos inconsistentes y vectores de XSS cuando se rendericen en web. | Normalizar inputs (regex para teléfono, longitud máxima, `TextInputFormatter`s) y validar en backend antes de escribir. |
| **Actualización de métodos de pago inexistente en backend**. | Actualmente sólo se guarda una cadena `paymentMethod`. | No se puede asociar múltiples fuentes ni rastrear `stripeSubscriptionId` para cancelar correctamente. | Persistir `paymentMethods` como lista con metadatos mínimos y guardar `stripeSubscriptionId`/`customerId` en el backend al crear la suscripción. |

### Claves/API
- `lib/config/subscription_config.dart` obtiene la publishable key vía `--dart-define` (correcto), pero el enlace Checkout por defecto `https://buy.stripe.com/...` está en texto claro; moverlo a Remote Config o `.env`.
- `functions/index.js` usa `defineSecret('STRIPE_SECRET_KEY')`, lo cual evita exponer la secret; mantenerlo así.

### Comunicación con Firebase
- `main.dart` inicializa App Check, pero las Cloud Functions HTTP no la validan. Utiliza `enforceAppCheck` en los nuevos callables y migra `_fnInitPaymentUrl` a una callable autenticada.
- Se recomienda habilitar `Firebase App Check` también en Storage/Firestore reglas para bloquear clientes no verificados.

## 2. Rendimiento y Mantenibilidad

1. **Carga de cursos** (`lib/screens/home_screen.dart`): cada render reconstruye `Image.network` sin `CachedNetworkImage`; usar cache o precarga con `precacheImage` para reducir requests.
2. **Chat** (`lib/screens/chat.dart`): carece de separación entre lógica FAQ y UI, dificultando agregar nuevos flujos. Se implementó `FaqEntry` y `ChatAssistant` para desacoplar.
3. **Servicios Stripe**: `SubscriptionPaymentService` no reutilizaba la respuesta del backend (e.g. `subscriptionId`). Ahora se propagó y se añadió cancelación/resume.
4. **Funciones Cloud**: faltaba `activateSubscriptionAccess`; se agregó callable con App Check + Firestore atomics para mantener consistencia.

## 3. Recomendaciones Stripe/Firebase

1. **Flujo de cobro** (archivo `lib/screens/subscription_required_screen.dart`): actualmente crea PaymentIntent vía `_fnInitPaymentUrl` y luego el cliente actualiza Firestore. Migrar a un flujo donde el backend:
   - cree el `PaymentIntent` / `Subscription` validando el `uid` autenticado;
   - actualice `users/{uid}/subscription` tras recibir `payment_intent.succeeded` webhook;
   - exponga únicamente IDs efímeras al cliente.
2. **Actualizaciones de base de datos**: usar las nuevas callables `activateSubscriptionAccess` (para pruebas/manual) y `scheduleSubscriptionCancellation`/`resumeSubscriptionCancellation`. Así, los clientes ya no escriben fechas/estados sensibles.
3. **Stripe → Firestore**: guardar `subscriptionId`, `customerId`, `paymentMethods` y `cancelAtPeriodEnd` en Firestore, siempre escritos por backend/webhook.
4. **Transición a producción**:
   - Habilitar claves `pk_live`/`sk_live` sólo mediante variables seguras.
   - Configurar webhooks (`invoice.payment_succeeded`, `customer.subscription.updated`, etc.) que actualicen Firestore usando Admin SDK.
   - Desactivar `_activateNow` y requerir método de pago válido antes de activar acceso.

## 4. Plan de pruebas

### Unidad
- `test/services/subscription_status_test.dart` cubre la lógica crítica que determina acceso, periodos de gracia, cancelaciones programadas y métodos de pago.
- Se recomienda añadir suites para `SubscriptionService` (mock Firestore) y para helpers de `PaymentService` usando `firebase_functions_mocks`.

### Estructura sugerida
```
test/
  services/
    subscription_status_test.dart
    subscription_service_test.dart
  widgets/
    chat/
      assistant_logic_test.dart
```
- `services/` contiene lógica de negocio pura (sin UI).
- `widgets/` agrupa pruebas de interfaz con `WidgetTester`.
- Añadir `integration_test/` para flujos end-to-end (login + compra + cancelación) usando `flutter_test` + `integration_test` plugin.

## 5. Migración a producción
- Documentar cada variable requerida (`STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `SUBSCRIPTION_MERCHANT_NAME`, etc.) y gestionarlas con un secret manager.
- Automatizar despliegues de funciones con `firebase deploy --only functions:stripePaymentIntentRequest,functions:activateSubscriptionAccess,...` y pruebas previas.
- Añadir monitoreo (Crashlytics + Stripe logs) para detectar errores en tiempo real.

---
Este documento debe actualizarse tras cada cambio relevante en los flujos de suscripción o en las reglas de seguridad.
