/* eslint-disable no-console, max-len */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Stripe = require('stripe');

admin.initializeApp();
const db = admin.firestore();

/* ===========================================================
   Stripe: inicialización perezosa (evita crash si falta config)
   =========================================================== */
let stripeInstance = null;
function getStripe() {
  const cfg = functions.config();
  const key = process.env.STRIPE_SECRET_KEY
    || (cfg && cfg.stripe && cfg.stripe.secret ? cfg.stripe.secret : null);
  if (!key) {
    throw new Error(
      'Missing Stripe secret. Configure it with either the STRIPE_SECRET_KEY ' +
      'env variable or firebase functions:config:set stripe.secret="sk_test_..."'
    );
  }
  if (!stripeInstance) {
    stripeInstance = new Stripe(key, { apiVersion: '2024-06-20' });
  }
  return stripeInstance;
}

function normalizeEmail(email) {
  if (!email || typeof email !== 'string') return null;
  const trimmed = email.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

function ensureCheckoutSuccessUrl(url) {
  if (!url) return url;
  if (url.includes('session_id={CHECKOUT_SESSION_ID}')) {
    return url;
  }
  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}session_id={CHECKOUT_SESSION_ID}`;
}

async function getOrCreateStripeCustomer(uid) {
  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  const current = snap.exists ? snap.data() : {};

  if (current && current.stripeCustomerId) {
    return { customerId: current.stripeCustomerId, existed: true };
  }

  const stripe = getStripe();
  let email;
  try {
    const authUser = await admin.auth().getUser(uid);
    email = authUser?.email;
  } catch (err) {
    console.error('No se pudo obtener el usuario de Firebase Auth:', err.message);
  }

  const normalizedEmail = normalizeEmail(email);

  const customer = await stripe.customers.create({
    email: normalizedEmail || undefined,
    metadata: { uid },
  });

  const updates = { stripeCustomerId: customer.id };
  if (normalizedEmail) {
    updates.email = normalizedEmail;
  }
  await userRef.set(updates, { merge: true });
  return { customerId: customer.id, existed: false };
}

/* ==============================
   Helpers de estado / presentación
   ============================== */
function normalizeStripeStatus(status) {
  switch (status) {
    case 'active':
    case 'trialing':
      return 'active';
    case 'past_due':
    case 'incomplete':
    case 'incomplete_expired':
    case 'paused':
      return 'pending';
    case 'canceled':
    case 'unpaid':
      return 'expired';
    default:
      return status || 'pending';
  }
}

function describePaymentMethod(paymentMethod) {
  if (!paymentMethod) return null;

  if (paymentMethod.card) {
    const brand = paymentMethod.card.brand || 'Tarjeta';
    const brandLabel = brand.charAt(0).toUpperCase() + brand.slice(1);
    return `${brandLabel} •••• ${paymentMethod.card.last4}`;
  }

  if (paymentMethod.type) {
    const typeLabel = paymentMethod.type.charAt(0).toUpperCase() + paymentMethod.type.slice(1);
    return `Stripe ${typeLabel}`;
  }

  return null;
}

async function resolvePaymentMethodLabel(subscription) {
  if (!subscription) return null;
  const stripe = getStripe();
  const visitedIds = new Set();
  const candidates = [];

  // default_payment_method directo en la suscripción
  if (subscription.default_payment_method) {
    candidates.push(subscription.default_payment_method);
  }

  // latest_invoice -> payment_intent.payment_method
  let latestInvoice = subscription.latest_invoice;
  if (typeof latestInvoice === 'string') {
    try {
      latestInvoice = await stripe.invoices.retrieve(latestInvoice, {
        expand: ['payment_intent.payment_method'],
      });
    } catch (err) {
      console.error('No se pudo obtener la factura más reciente de Stripe:', err.message);
      latestInvoice = null;
    }
  } else if (latestInvoice && typeof latestInvoice === 'object') {
    let paymentIntent = latestInvoice.payment_intent;
    if (typeof paymentIntent === 'string') {
      try {
        paymentIntent = await stripe.paymentIntents.retrieve(paymentIntent, {
          expand: ['payment_method'],
        });
        latestInvoice = { ...latestInvoice, payment_intent: paymentIntent };
      } catch (err) {
        console.error('No se pudo obtener el PaymentIntent asociado:', err.message);
      }
    }
  }

  if (latestInvoice?.payment_intent?.payment_method) {
    candidates.push(latestInvoice.payment_intent.payment_method);
  }
  if (latestInvoice?.payment_method) {
    candidates.push(latestInvoice.payment_method);
  }

  // pending_setup_intent -> payment_method
  let pendingSetupIntent = subscription.pending_setup_intent;
  if (typeof pendingSetupIntent === 'string') {
    try {
      pendingSetupIntent = await stripe.setupIntents.retrieve(pendingSetupIntent, {
        expand: ['payment_method'],
      });
    } catch (err) {
      console.error('No se pudo obtener el SetupIntent pendiente:', err.message);
      pendingSetupIntent = null;
    }
  }
  if (pendingSetupIntent?.payment_method) {
    candidates.push(pendingSetupIntent.payment_method);
  }

  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      let pm = candidate;
      if (typeof candidate === 'string') {
        if (visitedIds.has(candidate)) continue;
        visitedIds.add(candidate);
        pm = await stripe.paymentMethods.retrieve(candidate);
      }
      const label = describePaymentMethod(pm);
      if (label) return label;
    } catch (err) {
      console.error('No se pudo obtener el método de pago de Stripe:', err.message);
    }
  }

  return null;
}

async function findUserRefByEmail(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;

  try {
    const userRecord = await admin.auth().getUserByEmail(normalized);
    if (userRecord?.uid) {
      return { uid: userRecord.uid, ref: db.collection('users').doc(userRecord.uid) };
    }
  } catch (err) {
    if (err.code !== 'auth/user-not-found') {
      console.error('Error buscando usuario por email en Auth:', err.message);
    }
  }

  try {
    const snapshot = await db.collection('users')
      .where('email', '==', normalized)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      const doc = snapshot.docs[0];
      return { uid: doc.id, ref: db.collection('users').doc(doc.id) };
    }
  } catch (err) {
    console.error('Error consultando Firestore por email:', err.message);
  }

  return null;
}

async function resolveUserRefFromStripeContext({ customerId, email }) {
  let lookupEmail = normalizeEmail(email);

  if (customerId) {
    try {
      const q = await db.collection('users')
        .where('stripeCustomerId', '==', customerId)
        .limit(1)
        .get();
      if (!q.empty) {
        const doc = q.docs[0];
        const ref = db.collection('users').doc(doc.id);
        const data = doc.data() || {};
        if (!lookupEmail && data.email) {
          lookupEmail = normalizeEmail(data.email);
        }
        return { uid: doc.id, ref, email: lookupEmail || data.email || null };
      }
    } catch (err) {
      console.error('Error buscando usuario por customerId:', err.message);
    }
  }

  if (!lookupEmail && customerId) {
    try {
      const stripe = getStripe();
      const customer = await stripe.customers.retrieve(customerId);
      if (customer && !customer.deleted) {
        lookupEmail = normalizeEmail(customer.email);
      }
    } catch (err) {
      console.error('No se pudo obtener el cliente de Stripe:', err.message);
    }
  }

  if (!lookupEmail) {
    return null;
  }

  const result = await findUserRefByEmail(lookupEmail);
  if (result) {
    return { ...result, email: lookupEmail, customerId };
  }

  return null;
}

function toTimestamp(seconds) {
  if (!seconds) return null;
  try {
    return new admin.firestore.Timestamp(seconds, 0);
  } catch (err) {
    return null;
  }
}

function shouldGrantAccess(status) {
  if (!status) return false;
  const normalized = status.trim().toLowerCase();
  return normalized === 'active'
    || normalized === 'trialing'
    || normalized === 'manual_active'
    || normalized === 'grace';
}

async function applyStripeSubscriptionToUser({
  userRef,
  uid,
  subscription,
  customerId,
  overrideStatus,
  ensureEmail,
}) {
  if (!subscription) {
    throw new Error('subscription requerido para sincronizar.');
  }

  const periodStart = toTimestamp(subscription.current_period_start);
  const periodEnd = toTimestamp(subscription.current_period_end);
  const cancelAt = toTimestamp(
    subscription.cancel_at
    || (subscription.cancel_at_period_end ? subscription.current_period_end : null),
  );

  const normalizedStatus = normalizeStripeStatus(subscription.status);
  const effectiveStatus = overrideStatus || normalizedStatus;
  const accessGranted = shouldGrantAccess(effectiveStatus);
  const paymentMethodLabel = await resolvePaymentMethodLabel(subscription);

  const updatePayload = {
    stripeSubscriptionId: subscription.id,
    subscriptionStatus: subscription.status ?? normalizedStatus,
    'subscription.status': effectiveStatus,
    'subscription.paymentMethod': paymentMethodLabel || null,
    'subscription.startDate': periodStart,
    'subscription.endDate': periodEnd,
    'subscription.graceEndsAt': cancelAt,
    'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    entitlements: { library: accessGranted },
  };

  if (customerId) {
    updatePayload.stripeCustomerId = customerId;
  }

  if (ensureEmail) {
    updatePayload.email = ensureEmail;
  }

  await userRef.set(updatePayload, { merge: true });

  return {
    status: effectiveStatus,
    endDate: periodEnd ? periodEnd.toDate().toISOString() : null,
    accessGranted,
  };
}

async function applyManualSubscription({
  userRef,
  customerId,
  paymentMethod,
  durationDays,
  status,
  ensureEmail,
}) {
  const now = admin.firestore.Timestamp.now();
  const safeDuration = Math.max(1, Math.min(365, Math.round(durationDays || 30)));
  const endDate = admin.firestore.Timestamp.fromDate(new Date(
    now.toDate().getTime() + safeDuration * 24 * 60 * 60 * 1000,
  ));

  const finalStatus = status || 'manual_active';
  const accessGranted = shouldGrantAccess(finalStatus);

  const updatePayload = {
    subscriptionStatus: finalStatus,
    'subscription.status': finalStatus,
    'subscription.paymentMethod': paymentMethod || 'Stripe Checkout',
    'subscription.startDate': now,
    'subscription.endDate': endDate,
    'subscription.graceEndsAt': admin.firestore.FieldValue.delete(),
    'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    entitlements: { library: accessGranted },
  };

  if (customerId) {
    updatePayload.stripeCustomerId = customerId;
  }

  if (ensureEmail) {
    updatePayload.email = ensureEmail;
  }

  await userRef.set(updatePayload, { merge: true });

  return {
    status: finalStatus,
    endDate: endDate.toDate().toISOString(),
    accessGranted,
  };
}

async function findActiveSubscriptionForEmail(email, priceId) {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) return null;

  const stripe = getStripe();
  try {
    const customers = await stripe.customers.list({ email: normalizedEmail, limit: 10 });
    let bestMatch = null;

    for (const customer of customers.data) {
      if (!customer || customer.deleted) continue;

      try {
        const subs = await stripe.subscriptions.list({
          customer: customer.id,
          status: 'all',
          limit: 10,
          expand: ['data.default_payment_method', 'data.latest_invoice.payment_intent'],
        });

        for (const sub of subs.data) {
          if (!sub) continue;
          const matchesPrice = !priceId
            || sub.items?.data?.some((item) => item?.price?.id === priceId);
          if (!matchesPrice) continue;

          const normalizedStatus = normalizeStripeStatus(sub.status);
          const accessReady = shouldGrantAccess(normalizedStatus);
          const score = (sub.current_period_end || 0) + (accessReady ? 10_000_000_000 : 0);

          if (!bestMatch || score > bestMatch.score) {
            bestMatch = {
              customer,
              subscription: sub,
              normalizedStatus,
              score,
            };
          }
        }
      } catch (err) {
        console.error('No se pudieron listar suscripciones para el cliente:', err.message);
      }
    }

    if (!bestMatch) return null;
    return {
      customer: bestMatch.customer,
      subscription: bestMatch.subscription,
      normalizedStatus: bestMatch.normalizedStatus,
    };
  } catch (err) {
    console.error('Error buscando clientes de Stripe por email:', err.message);
    return null;
  }
}

/* ==============================================
   WEBHOOK: sincroniza estados en Firestore (users)
   ============================================== */
exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  let event = req.body;
  const sig = req.headers['stripe-signature'];

  try {
    const cfg = functions.config();
    const wh = process.env.STRIPE_WEBHOOK_SECRET
      || (cfg && cfg.stripe && cfg.stripe.webhook_secret ? cfg.stripe.webhook_secret : null);
    if (!wh) {
      throw new Error(
        'Missing Stripe webhook secret. Configure STRIPE_WEBHOOK_SECRET env ' +
        'or firebase functions:config:set stripe.webhook_secret="whsec_..."'
      );
    }

    const stripe = getStripe();
    event = stripe.webhooks.constructEvent(req.rawBody, sig, wh);
  } catch (err) {
    console.error('Webhook signature verification failed / init error:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  try {
    switch (event.type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        const customerId = sub.customer;

        const userContext = await resolveUserRefFromStripeContext({
          customerId,
          email: sub.customer_email,
        });

        if (userContext?.ref) {
          await applyStripeSubscriptionToUser({
            userRef: userContext.ref,
            uid: userContext.uid,
            subscription: sub,
            customerId,
            overrideStatus: event.type === 'customer.subscription.deleted' ? 'expired' : null,
            ensureEmail: userContext.email || normalizeEmail(sub.customer_email),
          });
        } else {
          console.warn(
            'No encontramos usuario para sincronizar la suscripción por webhook.',
            customerId,
            sub.customer_email,
          );
        }
        break;
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object;
        const customerId = invoice.customer;
        const customerEmail = invoice.customer_email
          || invoice.customer_email_address
          || invoice.customer_email_address_legacy;

        const userContext = await resolveUserRefFromStripeContext({
          customerId,
          email: customerEmail,
        });

        if (userContext?.ref) {
          await userContext.ref.set({
            subscriptionStatus: 'past_due',
            'subscription.status': 'pending',
            'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            entitlements: { library: false },
            ...(userContext.email ? { email: userContext.email } : {}),
          }, { merge: true });
        } else {
          console.warn('No se pudo ubicar usuario para invoice fallido', customerId);
        }
        break;
      }

      case 'checkout.session.completed': {
        const session = event.data.object;
        if (session.mode !== 'subscription' || !session.subscription) {
          break;
        }

        const customerId = session.customer || session.customer_details?.customer;
        const email = session.customer_details?.email || session.customer_email;

        const userContext = await resolveUserRefFromStripeContext({
          customerId,
          email,
        });

        if (!userContext?.ref) {
          console.warn('No se pudo ubicar usuario para checkout.session.completed');
          break;
        }

        const stripe = getStripe();
        let subscription;
        try {
          subscription = await stripe.subscriptions.retrieve(session.subscription, {
            expand: ['default_payment_method', 'latest_invoice.payment_intent'],
          });
        } catch (err) {
          console.error('No se pudo obtener la suscripción del checkout completado:', err.message);
        }

        if (subscription) {
          await applyStripeSubscriptionToUser({
            userRef: userContext.ref,
            uid: userContext.uid,
            subscription,
            customerId,
            overrideStatus: null,
            ensureEmail: userContext.email || normalizeEmail(email),
          });
        }
        break;
      }

      default:
        // otros eventos no los procesamos
        break;
    }

    return res.json({ received: true });
  } catch (e) {
    console.error('Error procesando webhook', e);
    return res.status(500).send('Webhook handler failed');
  }
});

/* =========================================
   CALLABLES usados por la app (PaymentSheet)
   ========================================= */

// helper: exige auth
async function assertAuth(context, data) {
  let fallbackToken = null;

  if (data && Object.prototype.hasOwnProperty.call(data, '__authToken')) {
    fallbackToken = data.__authToken;
    delete data.__authToken;
  }

  if (context.auth && context.auth.uid) {
    return context.auth.uid;
  }

  if (fallbackToken) {
    try {
      const decoded = await admin.auth().verifyIdToken(fallbackToken);
      return decoded.uid;
    } catch (err) {
      console.error('ID token inválido recibido en callable:', err.message);
      throw new functions.https.HttpsError('unauthenticated', 'Auth inválida');
    }
  }

  throw new functions.https.HttpsError('unauthenticated', 'Auth requerida');
}

// 1) Crear/recuperar Customer y guardarlo en users/{uid}.stripeCustomerId
exports.createStripeCustomer = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);
  const { customerId, existed } = await getOrCreateStripeCustomer(uid);
  return { customerId, existed };
});

// 2) Crear Ephemeral Key (requerido por Payment Sheet)
exports.createEphemeralKey = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);
  const apiVersion = data?.api_version;
  if (!apiVersion) {
    throw new functions.https.HttpsError('invalid-argument', 'api_version requerido');
  }

  const userRef = db.collection('users').doc(uid);
  const doc = await userRef.get();
  const { stripeCustomerId } = doc.data() || {};
  if (!stripeCustomerId) {
    throw new functions.https.HttpsError('failed-precondition', 'Customer inexistente');
  }

  const stripe = getStripe();
  const ekey = await stripe.ephemeralKeys.create(
    { customer: stripeCustomerId },
    { apiVersion }
  );
  return ekey; // incluye "secret"
});

// 3) Crear suscripción (default_incomplete) y devolver client_secret del PaymentIntent
exports.createSubscription = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);

  const cfg = functions.config();
  const priceId = process.env.STRIPE_PRICE_ID || cfg?.stripe?.price_id;
  if (!priceId) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Falta STRIPE_PRICE_ID (env) o stripe.price_id en functions:config'
    );
  }

  const userRef = db.collection('users').doc(uid);
  const doc = await userRef.get();
  const { stripeCustomerId } = doc.data() || {};
  if (!stripeCustomerId) {
    throw new functions.https.HttpsError('failed-precondition', 'Customer inexistente');
  }

  const stripe = getStripe();
  const sub = await stripe.subscriptions.create({
    customer: stripeCustomerId,
    items: [{ price: priceId }],
    payment_behavior: 'default_incomplete',
    payment_settings: { save_default_payment_method: 'on_subscription' },
    expand: ['latest_invoice.payment_intent'],
  });

  const pi = sub?.latest_invoice?.payment_intent;
  if (!pi?.client_secret) {
    throw new functions.https.HttpsError('internal', 'No se generó PaymentIntent');
  }

  const normalizedStatus = normalizeStripeStatus(sub.status);

  // Estado inicial en Firestore
  await userRef.set({
    stripeSubscriptionId: sub.id,
    subscriptionStatus: sub.status ?? 'incomplete',
    'subscription.status': normalizedStatus,
    'subscription.paymentMethod': null,
    'subscription.startDate': null,
    'subscription.endDate': null,
    'subscription.graceEndsAt': null,
    'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    entitlements: { library: false },
  }, { merge: true });

  return {
    subscriptionId: sub.id,
    clientSecret: pi.client_secret,
    status: sub.status,
  };
});

// 3b) Crear Checkout Session (flujo con enlace externo)
exports.createCheckoutSession = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);

  const cfg = functions.config();
  const priceId = (data && data.priceId) || process.env.STRIPE_PRICE_ID || cfg?.stripe?.price_id;
  if (!priceId) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Falta STRIPE_PRICE_ID (env) o stripe.price_id en functions:config',
    );
  }

  const successUrl = ensureCheckoutSuccessUrl(
    (data && data.successUrl)
      || process.env.STRIPE_CHECKOUT_SUCCESS_URL
      || cfg?.stripe?.checkout_success_url,
  );
  const cancelUrl = (data && data.cancelUrl)
    || process.env.STRIPE_CHECKOUT_CANCEL_URL
    || cfg?.stripe?.checkout_cancel_url;

  if (!successUrl || !cancelUrl) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Debes configurar las URLs de retorno de Stripe Checkout.',
    );
  }

  const metadataRaw = data && data.metadata && typeof data.metadata === 'object'
    ? data.metadata
    : {};
  let metadata = {};
  try {
    metadata = JSON.parse(JSON.stringify(metadataRaw || {}));
  } catch (err) {
    console.error('Metadata inválida recibida para Checkout:', err.message);
  }

  const { customerId } = await getOrCreateStripeCustomer(uid);
  const userRef = db.collection('users').doc(uid);

  const stripe = getStripe();
  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    customer: customerId,
    line_items: [
      {
        price: priceId,
        quantity: 1,
      },
    ],
    allow_promotion_codes: true,
    success_url: successUrl,
    cancel_url: cancelUrl,
    metadata: { uid, ...metadata },
    subscription_data: {
      metadata: { uid, ...metadata },
    },
    client_reference_id: uid,
  });

  await userRef.set({
    stripeCustomerId: customerId,
    subscriptionStatus: 'pending',
    'subscription.status': 'pending',
    'subscription.paymentMethod': null,
    'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    entitlements: { library: false },
  }, { merge: true });

  return {
    sessionId: session.id,
    url: session.url,
    status: session.status,
  };
});

// 3c) Confirmar Checkout Session y sincronizar Firestore
exports.confirmCheckoutSession = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);
  const sessionId = data?.sessionId;

  if (!sessionId || typeof sessionId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'sessionId requerido');
  }

  const stripe = getStripe();
  let session;
  try {
    session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ['subscription'],
    });
  } catch (err) {
    console.error('Error al consultar Checkout Session:', err.message);
    throw new functions.https.HttpsError('not-found', 'No se encontró la sesión de pago');
  }

  if (!session) {
    throw new functions.https.HttpsError('not-found', 'No se encontró la sesión de pago');
  }

  if (session.status === 'expired') {
    return { status: 'canceled', message: 'El enlace de pago expiró en Stripe.' };
  }

  if (session.payment_status === 'unpaid') {
    return { status: 'canceled', message: 'Stripe rechazó el pago.' };
  }

  if (session.status !== 'complete' || session.payment_status !== 'paid') {
    return { status: 'pending', message: 'Stripe sigue procesando el pago.' };
  }

  let subscription = session.subscription;
  if (!subscription) {
    return { status: 'pending', message: 'La suscripción aún no está disponible.' };
  }

  const subscriptionId = typeof subscription === 'string' ? subscription : subscription.id;
  if (typeof subscription === 'string' || !subscription.latest_invoice) {
    subscription = await stripe.subscriptions.retrieve(subscriptionId, {
      expand: [
        'default_payment_method',
        'latest_invoice.payment_intent.payment_method',
        'pending_setup_intent.payment_method',
      ],
    });
  }

  const emailFromSession = normalizeEmail(
    session.customer_details?.email
      || session.customer_email
      || subscription.customer_email
      || subscription.customer_details?.email,
  );

  const userRef = db.collection('users').doc(uid);
  if (emailFromSession) {
    await userRef.set({ email: emailFromSession }, { merge: true });
  }

  const syncResult = await applyStripeSubscriptionToUser({
    userRef,
    uid,
    subscription,
    customerId: session.customer || subscription.customer,
    overrideStatus: null,
    ensureEmail: emailFromSession,
  });

  const resultStatus = syncResult.status || normalizeStripeStatus(subscription.status);
  let resultMessage = 'Pago confirmado y acceso actualizado.';
  if (resultStatus !== 'active') {
    resultMessage = `Stripe registró la suscripción en estado "${resultStatus}". Se actualizará en cuanto quede activa.`;
  }

  return {
    status: resultStatus,
    subscriptionId: subscription.id,
    message: resultMessage,
  };
});

// 3d) Activar acceso manualmente tras volver del Checkout hospedado
exports.activateSubscriptionAccess = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);

  const rawDuration = data?.durationDays;
  let durationDays = 30;
  if (typeof rawDuration === 'number' && Number.isFinite(rawDuration)) {
    durationDays = rawDuration;
  } else if (typeof rawDuration === 'string') {
    const parsed = parseInt(rawDuration, 10);
    if (!Number.isNaN(parsed)) {
      durationDays = parsed;
    }
  }

  durationDays = Math.max(1, Math.min(365, Math.round(durationDays)));

  const paymentMethodRaw = typeof data?.paymentMethod === 'string'
    ? data.paymentMethod.trim()
    : '';
  const paymentMethod = paymentMethodRaw || 'Stripe Checkout';

  const statusRaw = typeof data?.status === 'string' ? data.status.trim().toLowerCase() : '';
  const allowedOverrides = new Set(['active', 'manual_active', 'pending', 'grace']);
  const requestedStatus = allowedOverrides.has(statusRaw) ? statusRaw : null;
  const userRef = db.collection('users').doc(uid);
  let email = null;
  try {
    const authUser = await admin.auth().getUser(uid);
    email = normalizeEmail(authUser?.email);
  } catch (err) {
    console.error('No se pudo obtener el usuario de Auth en activateSubscriptionAccess:', err.message);
  }

  if (!email) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Tu cuenta no tiene un correo electrónico verificado. Actualiza tu perfil y vuelve a intentarlo.',
    );
  }

  await userRef.set({ email }, { merge: true });

  const cfg = functions.config();
  const priceId = data?.priceId || process.env.STRIPE_PRICE_ID || cfg?.stripe?.price_id || null;

  const match = await findActiveSubscriptionForEmail(email, priceId);

  if (match?.subscription) {
    const sync = await applyStripeSubscriptionToUser({
      userRef,
      uid,
      subscription: match.subscription,
      customerId: match.customer?.id,
      overrideStatus: requestedStatus || null,
      ensureEmail: email,
    });

    const finalStatus = sync.status;
    let message = 'Confirmamos tu pago con Stripe y actualizamos tu acceso.';
    if (!shouldGrantAccess(finalStatus)) {
      message = `Stripe registró la suscripción en estado "${finalStatus}". Te notificaremos cuando quede activa.`;
    }

    return {
      status: finalStatus,
      message,
      subscriptionId: match.subscription.id,
      expiresAt: sync.endDate,
    };
  }

  const manual = await applyManualSubscription({
    userRef,
    customerId: null,
    paymentMethod,
    durationDays,
    status: requestedStatus || 'manual_active',
    ensureEmail: email,
  });

  return {
    status: manual.status,
    message: `Activamos tu suscripción por ${durationDays} días mientras confirmamos tu pago con Stripe.`,
    expiresAt: manual.endDate,
  };
});

// 4) Portal del cliente (opcional)
exports.createPortalSession = functions.https.onCall(async (data, context) => {
  const uid = await assertAuth(context, data);
  const userRef = db.collection('users').doc(uid);
  const doc = await userRef.get();
  const { stripeCustomerId } = doc.data() || {};
  if (!stripeCustomerId) {
    throw new functions.https.HttpsError('failed-precondition', 'Customer inexistente');
  }

  const cfg = functions.config();
  const returnUrl = cfg?.app?.portal_return || 'https://example.com';
  const stripe = getStripe();
  const session = await stripe.billingPortal.sessions.create({
    customer: stripeCustomerId,
    return_url: returnUrl,
  });
  return { url: session.url };
});

exports.ping = functions.https.onCall(async (data, context) => {
  let uid = context.auth?.uid ?? null;
  if (!uid) {
    try {
      uid = await assertAuth(context, data);
    } catch (err) {
      uid = null;
    }
  }
  console.log('PING auth?', !!context.auth, 'uid', uid, 'app?', !!context.app);
  return { uid, appCheck: !!context.app };
});

