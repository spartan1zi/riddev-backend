import { describe, it, expect } from "vitest";
import { validateNoContactInfo, CONTACT_INFO_BLOCKED_MESSAGE } from "./contactInfoGuard";

describe("validateNoContactInfo", () => {
  it("allows normal job text", () => {
    expect(validateNoContactInfo("Kitchen sink leaking under the cabinet in Osu")).toEqual({ ok: true });
    expect(validateNoContactInfo("Need plumber tomorrow morning")).toEqual({ ok: true });
  });

  it("blocks Ghana phone digits", () => {
    const r = validateNoContactInfo("Reach me 0244123456 thanks");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.message).toBe(CONTACT_INFO_BLOCKED_MESSAGE);
  });

  it("blocks +233 format", () => {
    expect(validateNoContactInfo("Call +233 24 123 4567").ok).toBe(false);
  });

  it("blocks email", () => {
    expect(validateNoContactInfo("email me user@gmail.com").ok).toBe(false);
  });

  it("blocks obfuscated email", () => {
    expect(validateNoContactInfo("write to john dot doe at gmail dot com").ok).toBe(false);
  });

  it("blocks WhatsApp links", () => {
    expect(validateNoContactInfo("https://wa.me/233241234567").ok).toBe(false);
    expect(validateNoContactInfo("chat on whatsapp.com/send").ok).toBe(false);
  });

  it("blocks mailto and tel", () => {
    expect(validateNoContactInfo("mailto:a@b.com").ok).toBe(false);
    expect(validateNoContactInfo("tel:+233241234567").ok).toBe(false);
  });

  it("blocks contact keywords", () => {
    expect(validateNoContactInfo("message me on whatsapp").ok).toBe(false);
    expect(validateNoContactInfo("call me when you arrive").ok).toBe(false);
  });

  it("does not block unrelated wording", () => {
    expect(validateNoContactInfo("My phone screen is cracked — need replacement").ok).toBe(true);
    expect(validateNoContactInfo("Reach me at the main gate on Liberation Road").ok).toBe(true);
  });
});
