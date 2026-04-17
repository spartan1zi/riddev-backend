/**
 * Blocks sharing of phone numbers, emails, WhatsApp / Telegram links, and common contact workarounds.
 * Used for job posts, quotes, chats, disputes, and reviews — server-side only (never trust the client).
 */

export const CONTACT_INFO_BLOCKED_MESSAGE =
  "Sharing contact details (phone numbers, email addresses, WhatsApp links, or similar) is not allowed. All communication must stay on the platform.";

/** Standard email */
const EMAIL_RE = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/;

/** Obfuscated: "name at gmail dot com" */
const EMAIL_OBFUSCATED_RE =
  /\b[a-z0-9._%+-]+\s+at\s+[a-z0-9._-]+\s+dot\s+[a-z]{2,}\b/i;

/** mailto / tel / sms / whatsapp scheme */
const DANGEROUS_SCHEME_RE = /\b(?:mailto:|tel:|sms:|whatsapp:)/i;

/** WhatsApp / Telegram link hosts (path may vary) */
const MESSAGING_HOST_RE =
  /(?:https?:\/\/|www\.)[^\s]*(?:wa\.me|whatsapp\.com|api\.whatsapp|web\.whatsapp|t\.me|telegram\.me|telegram\.org)/i;

/** Standalone wa.me without scheme */
const WA_ME_STANDALONE = /\bwa\.me\b/i;

function containsGhanaPhoneDigitWindow(text: string): boolean {
  const digits = text.replace(/\D/g, "");
  for (let i = 0; i <= digits.length - 10; i++) {
    const slice = digits.slice(i, i + 10);
    if (/^0[2345][0-9]{8}$/.test(slice)) return true;
  }
  for (let i = 0; i <= digits.length - 12; i++) {
    const slice = digits.slice(i, i + 12);
    if (/^233[0-9]{9}$/.test(slice)) return true;
  }
  return false;
}

/** +233 / 00 233 / spaced Ghana local */
const GH_INTL_FORMATTED_RE =
  /(?:\+|00)233[\s\-/.]*[0-9]{2}[\s\-/.]*[0-9]{3}[\s\-/.]*[0-9]{3,4}/;
const GH_LOCAL_FORMATTED_RE =
  /(?:^|[^\d])0[2345][\s\-/.]*[0-9]{2}[\s\-/.]*[0-9]{3}[\s\-/.]*[0-9]{3,4}(?:[^\d]|$)/;

/** Kept narrow to avoid blocking legitimate job wording (e.g. “my phone screen”). */
const CONTACT_KEYWORDS_RE =
  /\b(?:whatsapp|telegram|signal|viber)\b|\b(?:dm|pm)\s+me\b|\b(?:call|text|ring|sms|ping)\s+me\b/i;

/**
 * Returns whether the text appears to leak off-platform contact information.
 */
export function validateNoContactInfo(
  text: string
): { ok: true } | { ok: false; message: string } {
  const t = text.trim();
  if (!t) return { ok: true };

  if (DANGEROUS_SCHEME_RE.test(t)) {
    return { ok: false, message: CONTACT_INFO_BLOCKED_MESSAGE };
  }

  if (MESSAGING_HOST_RE.test(t) || WA_ME_STANDALONE.test(t)) {
    return { ok: false, message: CONTACT_INFO_BLOCKED_MESSAGE };
  }

  if (EMAIL_RE.test(t) || EMAIL_OBFUSCATED_RE.test(t)) {
    return { ok: false, message: CONTACT_INFO_BLOCKED_MESSAGE };
  }

  if (
    GH_INTL_FORMATTED_RE.test(t) ||
    GH_LOCAL_FORMATTED_RE.test(t) ||
    containsGhanaPhoneDigitWindow(t)
  ) {
    return { ok: false, message: CONTACT_INFO_BLOCKED_MESSAGE };
  }

  if (CONTACT_KEYWORDS_RE.test(t)) {
    return { ok: false, message: CONTACT_INFO_BLOCKED_MESSAGE };
  }

  return { ok: true };
}

/** @deprecated Use validateNoContactInfo — kept for existing imports */
export function validateChatContent(
  content: string
): { ok: true } | { ok: false; message: string } {
  return validateNoContactInfo(content);
}
