/* eslint-disable no-console, max-len */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Stripe = require('stripe');

admin.initializeApp();
const db = admin.firestore();

// ===== Stripe init perezosa (evita crash si falta config) =====
let stripeInstance = null;
function getStripe() {
  const cfg = functions.config();
  const key = cfg && cfg.stripe && cfg.stripe.secret ? cfg.stripe.secret : null;
  if (!key) {
    throw new Error('Missing Stripe secret (functions.config().stripe.secret). Set it with "firebase functions:config:set stripe.secret=sk_test_..."');
  }
  if (!stripeInstance) {
    stripeInstance = new Stripe(key, { apiVersion: '2024-06-20' });
  }
  return stripeInstance;
}

// ===== Webhook de Stripe (sincroniza estado en Firestore) =====
exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  let event = req.body;
  const sig = req.headers['stripe-signature'];

  try {
    const cfg = functions.config();
    const wh = cfg && cfg.stripe && cfg.stripe.webhook_secret ? cfg.stripe.webhook_secret : null;
    if (!wh) {
      throw new Error('Missing webhook secret (functions.config().stripe.webhook_secret).');
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
          const status = sub.status; // active | trialing | past_due | canceled | incomplete
          const periodEnd = sub.current_period_end
            ? new admin.firestore.Timestamp(sub.current_period_end, 0)
            : null;

          await ref.set({
            subscriptionStatus: status,
            currentPeriodEnd: periodEnd,
            entitlements: { library: status === 'active' || status === 'trialing' },
          }, { merge: true });
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
            entitlements: { library: false },
          }, { merge: true });
        }
        break;
      }

      default:
        break;
    }

    return res.json({ received: true });
  } catch (e) {
    console.error('Error procesando webhook', e);
    return res.status(500).send('Webhook handler failed');
  }
});

// =====================================================================
// ====================  CALLABLES PARA LA APP  ========================
// =====================================================================

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
  return ekey; // contiene "secret"
});

// 3) Crear suscripción (default_incomplete) y devolver client_secret del PaymentIntent
exports.createSubscription = functions.https.onCall(async (data, context) => {
  const uid = assertAuth(context);

  const cfg = functions.config();
  const priceId = cfg?.stripe?.price_id;
  if (!priceId) {
    throw new functions.https.HttpsError('failed-precondition', 'Falta stripe.price_id en functions:config');
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

  // estado inicial
  await userRef.set({ subscriptionStatus: sub.status ?? 'incomplete' }, { merge: true });

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
