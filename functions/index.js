/* eslint-disable valid-jsdoc, require-jsdoc, max-len */
/**
 * Stripe PaymentSheet endpoint (Functions v2).
 * Crea/recupera Customer, genera Ephemeral Key
 * y crea un PaymentIntent con Automatic Payment Methods.
 */

const admin = require("firebase-admin");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onRequest, onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const Stripe = require("stripe");

const STRIPE_API_VERSION = "2024-06-20";
const DAY_IN_MS = 24 * 60 * 60 * 1000;

// Secretos
const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");

// Firebase Admin
admin.initializeApp();

// Opciones globales
setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
  secrets: [STRIPE_SECRET_KEY],
});

/**
 * Agrega cabeceras CORS simples al response.
 * @param {object} res - Express Response
 * @returns {void}
 */
function cors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

/**
 * HTTP endpoint para inicializar PaymentSheet.
 * Body: { amount, currency?, email, uid?, description?, metadata? }
 * @returns {Promise<void>}
 */
exports.stripePaymentIntentRequest = onRequest(async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") {
    return res.status(204).send("");
  }
  if (req.method !== "POST") {
    return res.status(405).send({
      success: false,
      error: "Use POST",
    });
  }

  try {
    const {
      amount,
      currency = "mxn",
      email,
      uid,
      description,
      metadata = {},
    } = req.body || {};

    if (!amount || !email) {
      return res.status(400).send({
        success: false,
        error: "Faltan 'amount' y/o 'email'.",
      });
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: STRIPE_API_VERSION,
    });

    // 1) Customer por email
    let customerId;
    const existing = await stripe.customers.list({email, limit: 1});
    if (existing.data.length) {
      customerId = existing.data[0].id;
    } else {
      const customer = await stripe.customers.create({
        email,
        metadata: {uid: uid || "", ...metadata},
      });
      customerId = customer.id;
    }

    // 2) Ephemeral Key (PaymentSheet)
    const ephemeralKey = await stripe.ephemeralKeys.create(
        {customer: customerId},
        {apiVersion: STRIPE_API_VERSION},
    );

    // 3) PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Number(amount),
      currency,
      customer: customerId,
      description,
      automatic_payment_methods: {enabled: true},
      metadata: {uid: uid || "", ...metadata},
    });

    return res.status(200).send({
      success: true,
      customer: customerId,
      ephemeralKey: ephemeralKey.secret,
      paymentIntent: paymentIntent.client_secret,
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error("[stripePaymentIntentRequest]", error);
    return res.status(400).send({
      success: false,
      error: error.message,
    });
  }
});

/**
 * Callable que activa una suscripción en Firestore
 * sin exponer lógica sensible al cliente.
 */
exports.activateSubscriptionAccess = onCall({
  region: "us-central1",
  secrets: [STRIPE_SECRET_KEY],
  enforceAppCheck: true,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Inicia sesión para continuar.");
  }

  const durationDays = Number(request.data?.durationDays ?? 30);
  const paymentMethod = request.data?.paymentMethod || "manual";
  const status = request.data?.status || "pending";
  const subscriptionId = request.data?.subscriptionId || null;

  const now = admin.firestore.Timestamp.now();
  const endDate = admin.firestore.Timestamp.fromMillis(
      now.toDate().getTime() + durationDays * DAY_IN_MS,
  );

  await admin.firestore().collection("users").doc(uid).set({
    status,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    subscription: {
      startDate: now,
      endDate,
      paymentMethod,
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      cancelAtPeriodEnd: false,
      cancelsAt: null,
      stripeSubscriptionId: subscriptionId,
    },
  }, {merge: true});

  return {
    status,
    subscriptionId,
    cancelsAt: endDate.toDate().toISOString(),
    message: request.data?.message ||
        "Acceso activado por " + durationDays + " días.",
  };
});

/**
 * Programa la cancelación al final del periodo en Stripe/Firestore.
 */
exports.scheduleSubscriptionCancellation = onCall({
  region: "us-central1",
  secrets: [STRIPE_SECRET_KEY],
  enforceAppCheck: true,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Inicia sesión para continuar.");
  }

  const userRef = admin.firestore().collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Perfil no encontrado.");
  }

  const data = snap.data() || {};
  const sub = data.subscription || {};
  const storedEnd = sub.endDate;
  let endTimestamp;
  if (storedEnd && typeof storedEnd.toDate === "function") {
    endTimestamp = storedEnd;
  } else {
    endTimestamp = admin.firestore.Timestamp.fromMillis(
        Date.now() + 30 * DAY_IN_MS,
    );
  }

  const cancelsAt = endTimestamp.toDate();
  const subscriptionId = request.data?.subscriptionId ||
      sub.stripeSubscriptionId || null;

  if (subscriptionId) {
    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: STRIPE_API_VERSION,
    });
    await stripe.subscriptions.update(subscriptionId, {
      cancel_at_period_end: true,
    });
  }

  await userRef.set({
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    subscription: {
      cancelAtPeriodEnd: true,
      cancelsAt: endTimestamp,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      stripeSubscriptionId: subscriptionId,
    },
  }, {merge: true});

  return {
    status: "cancel_scheduled",
    subscriptionId,
    cancelsAt: cancelsAt.toISOString(),
    message: "La suscripción seguirá activa hasta " + cancelsAt.toISOString(),
  };
});

/**
 * Revierte la cancelación programada.
 */
exports.resumeSubscriptionCancellation = onCall({
  region: "us-central1",
  secrets: [STRIPE_SECRET_KEY],
  enforceAppCheck: true,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Inicia sesión para continuar.");
  }

  const userRef = admin.firestore().collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Perfil no encontrado.");
  }

  const data = snap.data() || {};
  const sub = data.subscription || {};
  const subscriptionId = sub.stripeSubscriptionId ||
      request.data?.subscriptionId || null;

  if (subscriptionId) {
    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: STRIPE_API_VERSION,
    });
    await stripe.subscriptions.update(subscriptionId, {
      cancel_at_period_end: false,
    });
  }

  await userRef.set({
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    subscription: {
      cancelAtPeriodEnd: false,
      cancelsAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  }, {merge: true});

  return {
    status: "active",
    subscriptionId,
    cancelsAt: null,
    message: "Restauramos la suscripción para próximos cobros.",
  };
});
