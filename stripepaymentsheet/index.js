const admin = require("firebase-admin");
const Stripe = require("stripe");
const {onRequest} = require("firebase-functions/v2/https");

admin.initializeApp();

exports.createPaymentIntent = onRequest(
    {
      region: "us-central1",
      cors: true,
      secrets: ["STRIPE_SECRET_KEY"],
      invoker: "public",
    },
    async (req, res) => {
      try {
        if (req.method !== "POST") {
          return res.status(405).json({success: false, error: "Method not allowed"});
        }

        const stripeSecret = process.env.STRIPE_SECRET_KEY;
        if (!stripeSecret) {
          return res.status(500).json({success: false, error: "Missing STRIPE_SECRET_KEY"});
        }

        const stripe = new Stripe(stripeSecret, {apiVersion: "2023-10-16"});

        // ✅ Validar Firebase ID token (evita abuso)
        const authHeader = req.headers.authorization || "";
        const token = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : null;
        if (!token) {
          return res.status(401).json({success: false, error: "Missing auth token"});
        }

        const decoded = await admin.auth().verifyIdToken(token);
        const uid = decoded.uid;

        // 🔒 Monto fijo en servidor
        const amount = 1000; // $10 MXN
        const currency = "mxn";

        // Customer por usuario (guardado en Firestore)
        const userRef = admin.firestore().collection("users").doc(uid);
        const snap = await userRef.get();
        let customerId = snap.exists ? snap.get("stripeCustomerId") : null;

        if (!customerId) {
          const customer = await stripe.customers.create({metadata: {uid}});
          customerId = customer.id;
          await userRef.set({stripeCustomerId: customerId}, {merge: true});
        }

        const ephemeralKey = await stripe.ephemeralKeys.create(
            {customer: customerId},
            {apiVersion: "2023-10-16"},
        );

        const paymentIntent = await stripe.paymentIntents.create({
          amount,
          currency,
          customer: customerId,
          description: "Verificación de método de pago CAPFISCAL",
          automatic_payment_methods: {enabled: true},
          metadata: {uid, type: "payment_method_verification"},
        });

        return res.json({
          success: true,
          paymentIntent: paymentIntent.client_secret,
          customer: customerId,
          ephemeralKey: ephemeralKey.secret,
        });
      } catch (err) {
        console.error(err);
        return res.status(500).json({success: false, error: String(err)});
      }
    },
);
