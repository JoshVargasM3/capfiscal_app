# Configuración de cobros in-app (Apple App Store + Google Play)

## Estado actual en el código

La app **sí tiene flujo de compra in-app para documentos** usando `in_app_purchase`:

- Carga catálogo de productos y compra no consumibles (`DocIapService`).
- Escucha `purchaseStream`, completa transacciones y restaura compras.
- Persiste compras por usuario en `users/{uid}/doc_purchases/{productId}`.
- Ahora el guardado se hace por Cloud Function callable (`registerDocumentPurchase`) con `Auth + App Check`.

## Lo que debes tener listo en cuentas de desarrollador

> Sin esto, Apple/Google no aprobarán pruebas de compra real aunque el código compile.

### 1) Google Play Console (Android)

1. Crear la app en Play Console con el **mismo package name** (`applicationId`).
2. Subir al menos un `AAB` en pista interna/cerrada.
3. En **Monetize > Products > In-app products**:
   - Crear cada producto NO consumible con IDs exactos al patrón del código:
   - `capfiscal_doc_<nombre_normalizado>`
   - Ejemplo: `capfiscal_doc_contrato_arrendamiento_v1`.
4. Activar estado de productos en **Active**.
5. Configurar testers de licencia en:
   - **Settings > License testing**.
6. Enviar versión a **Internal testing** y esperar que quede disponible.

### 2) App Store Connect (iOS)

1. Crear App ID y app en App Store Connect con el mismo Bundle ID.
2. En **In-App Purchases**, crear cada producto **Non-Consumable** con el mismo ID que Android.
3. Completar metadata de cada IAP:
   - Reference Name
   - Product ID
   - Pricing
   - Localización (nombre/descripcion)
   - Screenshot de revisión (si aplica)
4. Firmar acuerdos y completar datos fiscales/bancarios en Apple Developer/App Store Connect.
5. Crear usuarios en **Users and Access > Sandbox Testers**.
6. Subir build a TestFlight y probar compras con cuenta sandbox.

### 3) Firebase/Backend (obligatorio para producción robusta)

1. Desplegar Cloud Function:
   - `registerDocumentPurchase`
2. Mantener **Firebase App Check** activo (ya requerido por la function).
3. Recomendado antes de producción:
   - Verificar recibos/tokens contra Apple/Google server-side.
   - No confiar solo en datos enviados por cliente.

## Checklist rápido antes de enviar a revisión

- [ ] IDs de productos idénticos entre código, Google Play y App Store Connect.
- [ ] Productos activos en ambas tiendas.
- [ ] Testers configurados (Play License testers + Apple Sandbox testers).
- [ ] Build instalada desde canal de prueba (Internal testing/TestFlight), no desde debug local.
- [ ] `registerDocumentPurchase` desplegada y funcionando.
- [ ] Flujo “comprar → restaurar → abrir documento” validado en Android e iOS.

