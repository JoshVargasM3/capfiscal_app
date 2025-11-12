/* eslint-disable valid-jsdoc, require-jsdoc, max-len */
/**
 * Stripe PaymentSheet endpoint (Functions v2).
 * Crea/recupera Customer, genera Ephemeral Key
 * y crea un PaymentIntent con Automatic Payment Methods.
 */

const admin = require("firebase-admin");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const Stripe = require("stripe");

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
      apiVersion: "2024-06-20",
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
        {apiVersion: "2024-06-20"},
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
