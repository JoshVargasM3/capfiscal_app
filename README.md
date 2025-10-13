# 📚 CAPFISCAL - Biblioteca Legal Digital

CAPFISCAL es una aplicación móvil desarrollada en **Flutter** que brinda acceso organizado, accesible y actualizado a documentos legales en México. Pensada como una herramienta de consulta para profesionales, contadores, abogados y empresarios, ofrece una **experiencia de usuario moderna, rápida y práctica**, con planes de suscripción mensual.

---

## 🚀 Objetivo del Proyecto

Crear una plataforma **centralizada de conocimiento legal** que:

- Permita **descargar documentos oficiales y actualizados**
- Muestre **videos explicativos sobre temas fiscales y legales**
- Brinde acceso personalizado mediante **suscripción**
- Integre funcionalidades como **favoritos, notificaciones, chat y más**

---

## 🧠 Visión a Futuro

La app CAPFISCAL está pensada como **ecosistema digital para el cumplimiento fiscal y la consulta legal**. A mediano plazo incluirá:

- Módulo de **asistente virtual por IA** para responder dudas fiscales
- Canal de atención directa con **abogados o contadores certificados**
- **Alertas automáticas** sobre cambios fiscales y publicaciones oficiales
- Integración con **pasarelas de pago como Stripe**
- Soporte para **firma electrónica de documentos**

---

## 📱 Funcionalidades Actuales

| Módulo                | Descripción                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| 📁 Biblioteca Legal   | Consulta y descarga de documentos desde Firebase Storage                    |
| 🎥 Videos Explicativos| Visualización y reproducción de material audiovisual legal desde la app     |
| ❤️ Favoritos          | Guardado personalizado de documentos clave por usuario                     |
| 🔐 Autenticación      | Registro e inicio de sesión con Firebase Auth                               |
| 🧭 Navegación          | Interfaz optimizada con navegación por pestañas y rutas nombradas           |
| 🎨 UI & UX            | Diseño responsivo basado en Figma, adaptable a Android y iOS               |

---

## 💳 Suscripciones y medios de pago

- La app ahora integra **Stripe Payment Sheet** para cobrar la membresía mensual con
  distintos métodos de pago (tarjetas, wallets, pagos diferidos) mediante una
  experiencia nativa.
- El backend debe exponer las Cloud Functions:
  - `createStripeSubscriptionIntent` → crea el cliente/intent de pago y devuelve
    `paymentIntentClientSecret`, `customerId`, `customerEphemeralKeySecret` y
    `subscriptionId`.
  - `finalizeStripeSubscription` → confirma el cobro y actualiza el documento del
    usuario en Firestore con la vigencia de la suscripción.
- Para inicializar Stripe en Flutter define las llaves en tiempo de compilación:

  ```bash
  flutter run \
    --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_xxx \
    --dart-define=STRIPE_PRICE_ID=price_xxx \
    --dart-define=SUBSCRIPTION_MERCHANT_NAME="CAPFISCAL" \
    --dart-define=STRIPE_MERCHANT_ID=merchant.com.capfiscal
  ```

- Si las llaves no están configuradas, la pantalla de suscripción mostrará un
  recordatorio y se podrá seguir usando la activación manual.
- Cada vez que el estado de Stripe se actualiza, la app refresca los datos de
  la colección `users` y bloquea la descarga de archivos cuando la suscripción
  caduca.

---

## 🛠️ Stack Tecnológico

- **Flutter & Dart** - Desarrollo multiplataforma nativo
- **Firebase** (Auth, Storage) - Backend ágil, escalable y seguro
- **GitHub** - Control de versiones y colaboración
- **VSCode / Android Studio** - Entornos de desarrollo utilizados
- **Figma** - Diseño visual colaborativo de interfaces

---

## 📅 Cronograma por Fases

| Mes       | Fase                                     |
|-----------|------------------------------------------|
| **Mes 1** | Diseño e infraestructura base            |
| **Mes 2** | Módulo de suscripción + Biblioteca Legal |
| **Mes 3** | Reproductor de Videos educativos         |
| **Mes 4** | Chat en tiempo real + notificaciones     |
| **Mes 5-6** | Pruebas, pulido, despliegue y publicación |

---

## 🧑‍💻 Autor y Mantenimiento

Proyecto desarrollado y mantenido por  
**Josh Vargas**  
[GitHub](https://github.com/JoshVargasM3)

---

## 🏁 Estado del Proyecto

> 🚧 En desarrollo activo. Primer release estable estimado para Octubre 2025.

---

## 💬 Contribuciones

Por ahora el repositorio está siendo desarrollado de forma interna, pero se planea abrir a colaboración futura bajo lineamientos específicos.

---

## 📣 Contacto

Para colaboraciones, alianzas o licencias:  
📧 **capfiscal.app@gmail.com**  
📲 Instagram: [@capfiscal](https://www.instagram.com/capfiscal.mx?utm_source=ig_web_button_share_sheet&igsh=ZDNlZDc0MzIxNw==) *(provisional)*

---
