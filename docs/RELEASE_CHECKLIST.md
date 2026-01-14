# Release checklist (Android/iOS)

## 1) Variables y secretos por ambiente

**Stripe** (obligatorias para producción):
- `STRIPE_PUBLISHABLE_KEY`
- `STRIPE_PAYMENT_INTENT_URL` (Cloud Function HTTP para PaymentIntent)
- `STRIPE_CHECKOUT_URL` (solo si usas Checkout en Web)
- `STRIPE_PRICE_ID` (si tu backend lo requiere)
- `SUBSCRIPTION_MERCHANT_NAME` (opcional, default `CAPFISCAL`)

**Firebase/Functions**
- `FUNCTIONS_REGION` (default `us-central1`)

**Store links**
- `ANDROID_PACKAGE_NAME` (para abrir Play Store manage subscriptions)
- `IOS_BUNDLE_ID` (si necesitas usarlo en enlaces internos)

**In-App Purchases (móvil)**
- `ANDROID_SUBSCRIPTION_ID` (Product ID de Google Play)
- `IOS_SUBSCRIPTION_ID` (Product ID de App Store)

### Cómo configurar (dev/prod)
**Recomendado (CI/CD):**
- Usa `--dart-define-from-file` con un archivo NO versionado.
- Ejemplo:
  ```bash
  flutter run --dart-define-from-file=config/stripe.dev.json
  flutter build appbundle --dart-define-from-file=config/stripe.prod.json
  ```

**Ejemplo de `config/stripe.prod.json` (no subir al repo):**
```json
{
  "STRIPE_PUBLISHABLE_KEY": "pk_live_...",
  "STRIPE_PAYMENT_INTENT_URL": "https://REGION-PROJECT.cloudfunctions.net/stripePaymentIntentRequest",
  "STRIPE_CHECKOUT_URL": "https://buy.stripe.com/...",
  "STRIPE_PRICE_ID": "price_...",
  "SUBSCRIPTION_MERCHANT_NAME": "CAPFISCAL",
  "ANDROID_PACKAGE_NAME": "com.capfiscal.biblioteca",
  "IOS_BUNDLE_ID": "com.capfiscal.biblioteca",
  "ANDROID_SUBSCRIPTION_ID": "capfiscal_monthly",
  "IOS_SUBSCRIPTION_ID": "capfiscal_monthly"
}
```

> Nota: **Nunca** subas llaves/URLs sensibles al repo. Usa archivos locales o secretos de CI.

---

## 2) Build Android (firmado)

1. Crea `android/keystore.properties` (NO versionar):
   ```properties
   storeFile=/absolute/path/to/release.jks
   storePassword=***
   keyAlias=***
   keyPassword=***
   ```
2. Verifica `versionCode` y `versionName` en `android/local.properties` o `pubspec.yaml`.
3. Comandos:
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   dart format --set-exit-if-changed .
   flutter build apk --release --dart-define-from-file=config/stripe.prod.json
   flutter build appbundle --release --dart-define-from-file=config/stripe.prod.json
   ```
4. Sube el `.aab` a Play Console.

---

## 3) Build iOS (firmado)

1. Actualiza `Runner` Bundle ID en Xcode y/o `IOS_BUNDLE_ID` en el archivo de defines.
2. Verifica `Info.plist` (permisos, URL schemes) y `Podfile` (deployment target).
3. Comandos (macOS):
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   dart format --set-exit-if-changed .
   flutter build ios --release --dart-define-from-file=config/stripe.prod.json
   ```
4. Subir build con Xcode/Transporter a App Store Connect.

---

## 4) Checklist final de publicación

- [ ] `STRIPE_PUBLISHABLE_KEY` y `STRIPE_PAYMENT_INTENT_URL` configurados.
- [ ] Checkout Web configurado (si aplica).
- [ ] Product IDs de IAP configurados (Android/iOS).
- [ ] Links de **Manage Subscription** funcionando (iOS/Play Store).
- [ ] Permisos iOS mínimos: Fotos (si actualizas foto de perfil).
- [ ] `usesCleartextTraffic` deshabilitado (Android).
- [ ] App Check activo en producción (Play Integrity / DeviceCheck).
- [ ] Reglas Firestore/Storage revisadas (mínimo privilegio).
- [ ] Política de privacidad y términos listos.
- [ ] Pantallas de pago sin inputs manuales de tarjeta (solo PaymentSheet/Checkout).

---

## 5) Troubleshooting

**Gradle/Android**
- Error `Keystore was tampered with`: revisa `keystore.properties`.
- `minSdk` incompatible: valida que `flutter.minSdkVersion` sea >= 21.

**iOS**
- `pod install` falla: borra `Pods/` y `Podfile.lock`, ejecuta `pod repo update`.
- Permisos faltantes: revisa `Info.plist` (`NSPhotoLibraryUsageDescription`).

**Stripe**
- PaymentSheet no abre: revisa `STRIPE_PUBLISHABLE_KEY` y `STRIPE_PAYMENT_INTENT_URL`.
- Checkout Web no abre: revisa `STRIPE_CHECKOUT_URL`.

**Firebase**
- `permission-denied`: valida reglas de Firestore/Storage.
- Cloud Functions 401: confirma que App Check esté correctamente configurado.
