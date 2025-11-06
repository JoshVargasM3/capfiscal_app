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

        const q = await db.collection('users')
          .where('stripeCustomerId', '==', customerId)
          .limit(1).get();

        if (!q.empty) {
          const ref = db.collection('users').doc(q.docs[0].id);

          const periodStart = sub.current_period_start
            ? new admin.firestore.Timestamp(sub.current_period_start, 0)
            : null;

          const periodEnd = sub.current_period_end
            ? new admin.firestore.Timestamp(sub.current_period_end, 0)
            : null;

          const cancelAtSeconds = sub.cancel_at || (sub.cancel_at_period_end ? sub.current_period_end : null);
          const cancelAt = cancelAtSeconds
            ? new admin.firestore.Timestamp(cancelAtSeconds, 0)
            : null;

          const normalizedStatus = normalizeStripeStatus(sub.status);
          const isDeletion = event.type === 'customer.subscription.deleted';

          const paymentMethodLabel = await resolvePaymentMethodLabel(sub);

          const updatePayload = {
            stripeSubscriptionId: sub.id,
            subscriptionStatus: sub.status ?? 'incomplete',
            'subscription.status': normalizedStatus,
            'subscription.paymentMethod': paymentMethodLabel || (isDeletion ? null : admin.firestore.FieldValue.delete()),
            'subscription.startDate': periodStart,
            'subscription.endDate': periodEnd,
            'subscription.graceEndsAt': cancelAt,
            'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            entitlements: { library: normalizedStatus === 'active' },
          };

          await ref.set(updatePayload, { merge: true });
        }
        break;
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object;
        const customerId = invoice.customer;

        const q = await db.collection('users')
          .where('stripeCustomerId', '==', customerId)
          .limit(1).get();

        if (!q.empty) {
          const ref = db.collection('users').doc(q.docs[0].id);
          await ref.set({
            subscriptionStatus: 'past_due',
            'subscription.status': 'pending',
            'subscription.updatedAt': admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            entitlements: { library: false },
          }, { merge: true });
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
function assertAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Auth requerida');
  }
  return context.auth.uid;
}

// 1) Crear/recuperar Customer y guardarlo en users/{uid}.stripeCustomerId
exports.createStripeCustomer = functions.https.onCall(async (data, context) => {
  const uid = assertAuth(context);
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
  } catch (_) { /* ignore */ }

  const customer = await stripe.customers.create({
    email,
    metadata: { uid },
  });

  await userRef.set({ stripeCustomerId: customer.id }, { merge: true });
  return { customerId: customer.id, existed: false };
});

// 2) Crear Ephemeral Key (requerido por Payment Sheet)
exports.createEphemeralKey = functions.https.onCall(async (data, context) => {
  const uid = assertAuth(context);
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
  const uid = assertAuth(context);

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

// 4) Portal del cliente (opcional)
exports.createPortalSession = functions.https.onCall(async (data, context) => {
  const uid = assertAuth(context);
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
