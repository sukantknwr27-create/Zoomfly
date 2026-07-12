// Vercel Serverless Function: /api/config
// Exposes only the PUBLISHABLE Razorpay Key ID — never the secret.
// Set RAZORPAY_KEY_ID in Vercel Dashboard → Settings → Environment Variables.

export default function handler(req, res) {
  // Only allow GET
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Restrict to your domain in production
  const origin = req.headers.origin || '';
  const allowedOrigins = [
    'https://www.zoomfly.in',
    'https://zoomfly.in',
    'http://localhost:3000',
    'http://127.0.0.1:5500',
  ];
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }

  const razorpayKeyId = process.env.RAZORPAY_KEY_ID || '';

  if (!razorpayKeyId) {
    // Return empty — frontend will gracefully fall back to WhatsApp booking
    return res.status(200).json({ razorpay_key_id: '' });
  }

  res.setHeader('Cache-Control', 'public, max-age=3600'); // Cache 1hr — key rarely changes
  return res.status(200).json({ razorpay_key_id: razorpayKeyId });
}
