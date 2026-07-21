// ============================================================
//  ZOOMFLY — BOOKING UI  (booking-ui.js)
//
//  Responsibility: ONLY modal rendering (success / error).
//  No DB calls, no WhatsApp, no form logic.
//
//  Imported by: booking.js (orchestrator)
// ============================================================

const WA = '918076136300';

// ─── HELPERS ─────────────────────────────────────────────────
function _fmt(n) {
  return parseFloat(n || 0).toLocaleString('en-IN', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

function _fmtDate(d) {
  if (!d) return '—';
  try {
    return new Date(d).toLocaleDateString('en-IN', {
      day: 'numeric', month: 'short', year: 'numeric',
    });
  } catch { return d; }
}

// booking.service_name and error messages can originate from
// customer-typed form fields (e.g. hotel name, pickup location) —
// escape before interpolating into innerHTML.
function _esc(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

// ─── MODAL BASE ───────────────────────────────────────────────
function _modal(id, content) {
  document.getElementById(id)?.remove();
  const el = document.createElement('div');
  el.id = id;
  el.innerHTML = `
    <div style="position:fixed;inset:0;background:rgba(0,0,0,.6);
                display:flex;align-items:center;justify-content:center;
                z-index:9999;padding:20px;backdrop-filter:blur(4px);
                animation:zfFadeIn .3s ease">
      <div style="background:#fff;border-radius:20px;padding:40px 36px;
                  max-width:460px;width:100%;text-align:center;
                  box-shadow:0 24px 80px rgba(0,0,0,.25);
                  animation:zfSlideUp .4s ease">
        ${content}
      </div>
    </div>
    <style>
      @keyframes zfFadeIn  { from{opacity:0}    to{opacity:1} }
      @keyframes zfSlideUp { from{opacity:0;transform:translateY(24px)} to{opacity:1;transform:translateY(0)} }
    </style>`;
  document.body.appendChild(el);
  // Close on backdrop click
  el.firstElementChild.addEventListener('click', e => {
    if (e.target === el.firstElementChild) el.remove();
  });
  return el;
}

// ─── SUCCESS MODAL ────────────────────────────────────────────
export function showBookingSuccess(booking) {
  _modal('zf-booking-modal', `
    <div style="width:72px;height:72px;background:linear-gradient(135deg,#22c55e,#16a34a);
                border-radius:50%;display:flex;align-items:center;justify-content:center;
                margin:0 auto 20px;font-size:32px;box-shadow:0 8px 24px rgba(34,197,94,.35)"></div>

    <h2 style="font-family:'Playfair Display',serif;font-size:1.5rem;color:#0f1923;margin-bottom:8px">
      Booking Request Sent!
    </h2>
    <p style="color:#64748b;font-size:.9rem;margin-bottom:24px;line-height:1.6">
      Your booking has been recorded and our team has been notified on WhatsApp.
      We'll confirm within <strong>30 minutes</strong>.
    </p>

    <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;
                padding:16px 20px;margin-bottom:24px">
      <div style="font-size:.72rem;font-weight:600;text-transform:uppercase;
                  letter-spacing:1px;color:#94a3b8;margin-bottom:4px">Booking Reference</div>
      <div style="font-size:1.2rem;font-weight:700;color:#1a73e8;letter-spacing:1px">
        ${booking.booking_ref}
      </div>
      <div style="font-size:.78rem;color:#94a3b8;margin-top:4px">Save this for tracking</div>
    </div>

    <div style="text-align:left;margin-bottom:24px">
      <div style="display:flex;justify-content:space-between;padding:8px 0;
                  border-bottom:1px solid #f1f5f9;font-size:.85rem">
        <span style="color:#64748b">Service</span>
        <span style="font-weight:600;color:#2d3748">${_esc(booking.service_name)}</span>
      </div>
      <div style="display:flex;justify-content:space-between;padding:8px 0;
                  border-bottom:1px solid #f1f5f9;font-size:.85rem">
        <span style="color:#64748b">Amount</span>
        <span style="font-weight:700;color:#ff6b35">₹${_fmt(booking.total_amount)}</span>
      </div>
      <div style="display:flex;justify-content:space-between;padding:8px 0;font-size:.85rem">
        <span style="color:#64748b">Date</span>
        <span style="color:#2d3748">${_fmtDate(booking.created_at)}</span>
      </div>
    </div>

    <a href="https://wa.me/${WA}" target="_blank" rel="noopener"
       style="display:block;background:linear-gradient(135deg,#25d366,#128c7e);
              color:#fff;padding:13px 24px;border-radius:10px;text-decoration:none;
              font-weight:700;font-size:.92rem;margin-bottom:12px;
              box-shadow:0 4px 16px rgba(37,211,102,.35)">
       Chat with Us on WhatsApp
    </a>
    <button onclick="document.getElementById('zf-booking-modal').remove()"
            style="background:none;border:1.5px solid #e2e8f0;color:#64748b;
                   padding:11px 24px;border-radius:10px;cursor:pointer;
                   font-size:.88rem;width:100%">
      Close
    </button>`);
}

// ─── ERROR MODAL ─────────────────────────────────────────────
export function showBookingError(message) {
  _modal('zf-booking-modal', `
    <div style="width:72px;height:72px;background:linear-gradient(135deg,#ef4444,#dc2626);
                border-radius:50%;display:flex;align-items:center;justify-content:center;
                margin:0 auto 20px;font-size:32px"></div>

    <h2 style="font-family:'Playfair Display',serif;font-size:1.4rem;color:#0f1923;margin-bottom:8px">
      Booking Failed
    </h2>
    <p style="color:#64748b;font-size:.88rem;margin-bottom:20px;line-height:1.6">
      ${_esc(message) || 'Something went wrong. Please try again or contact us on WhatsApp.'}
    </p>

    <a href="https://wa.me/${WA}" target="_blank" rel="noopener"
       style="display:block;background:linear-gradient(135deg,#25d366,#128c7e);
              color:#fff;padding:13px 24px;border-radius:10px;text-decoration:none;
              font-weight:700;font-size:.9rem;margin-bottom:12px">
       Contact Us on WhatsApp
    </a>
    <button onclick="document.getElementById('zf-booking-modal').remove()"
            style="background:none;border:1.5px solid #e2e8f0;color:#64748b;
                   padding:11px 24px;border-radius:10px;cursor:pointer;
                   font-size:.88rem;width:100%">
      Try Again
    </button>`);
}

// ─── LOADING STATE HELPER (used by form buttons) ─────────────
export function setLoading(btn, isLoading, loadingText = 'Processing...') {
  if (!btn) return;
  if (isLoading) {
    btn.dataset.originalText = btn.textContent;
    btn.textContent = loadingText;
    btn.disabled    = true;
    btn.style.opacity = '0.75';
  } else {
    btn.textContent   = btn.dataset.originalText || 'Submit';
    btn.disabled      = false;
    btn.style.opacity = '1';
  }
}
