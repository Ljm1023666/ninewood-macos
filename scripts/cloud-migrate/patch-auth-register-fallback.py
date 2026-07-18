#!/usr/bin/env python3
"""Patch production auth/captcha so registration works without SMS/hCaptcha keys."""
from pathlib import Path

captcha = Path("/opt/ninewood/server/src/routes/captcha.ts")
text = captcha.read_text()

old = """/** 仅当显式开启 CAPTCHA_DEV_BYPASS=1 且非生产时允许绕过（防 NODE_ENV 误配） */
const allowDevBypass =
  process.env.NODE_ENV !== 'production' && process.env.CAPTCHA_DEV_BYPASS === '1'
const DEV_TOKEN_PREFIX = 'dev-bypass-'

const verified = new Map<string, { expires: number }>();
"""

new = """/** 开发显式绕过：CAPTCHA_DEV_BYPASS=1 且非生产 */
const allowDevBypass =
  process.env.NODE_ENV !== 'production' && process.env.CAPTCHA_DEV_BYPASS === '1'
const DEV_TOKEN_PREFIX = 'dev-bypass-'
/** hCaptcha 未配置时，桌面端可用固定 token 完成发码前置校验 */
export const UNCONFIGURED_CAPTCHA_TOKEN = 'unconfigured-bypass'

const verified = new Map<string, { expires: number }>();

function captchaConfigured(): boolean {
  return Boolean(config.hcaptcha.siteKey && config.hcaptcha.secretKey)
}
"""

if old not in text:
    raise SystemExit("captcha preamble not found")
text = text.replace(old, new, 1)

old_verify = """export function verifyCaptcha(token: string): boolean {
  if (allowDevBypass && token.startsWith(DEV_TOKEN_PREFIX)) return true
  const entry = verified.get(token);
  if (!entry || entry.expires < Date.now()) return false;
  return true;
}
"""

new_verify = """export function verifyCaptcha(token: string): boolean {
  if (!token) return false
  if (!captchaConfigured()) {
    return token === UNCONFIGURED_CAPTCHA_TOKEN || token.startsWith(DEV_TOKEN_PREFIX)
  }
  if (allowDevBypass && token.startsWith(DEV_TOKEN_PREFIX)) return true
  const entry = verified.get(token);
  if (!entry || entry.expires < Date.now()) return false;
  return true;
}
"""

if old_verify not in text:
    raise SystemExit("verifyCaptcha not found")
text = text.replace(old_verify, new_verify, 1)

old_get = """captchaRouter.get('/', (_req: Request, res: Response) => {
  res.json({ siteKey: config.hcaptcha.siteKey });
});
"""

new_get = """captchaRouter.get('/', (_req: Request, res: Response) => {
  res.json({
    siteKey: config.hcaptcha.siteKey,
    mode: captchaConfigured() ? 'hcaptcha' : 'bypass',
  });
});
"""

if old_get not in text:
    raise SystemExit("GET captcha not found")
text = text.replace(old_get, new_get, 1)
captcha.write_text(text)
print("captcha.ts patched")

auth = Path("/opt/ninewood/server/src/services/auth.service.ts")
atext = auth.read_text()

old_send = """  async sendCode(phone: string) {
    const [legacyExists, modernExists] = await Promise.all([
      findLegacyUserByPhone(phone),
      findModernUserByPhone(phone),
    ]);
    if (legacyExists || modernExists) {
      throw { status: 400, message: '该手机号已注册，请直接输入密码登录' };
    }

    const code = generateCode();
    smsStore.set(phone, { code, expires: Date.now() + 5 * 60 * 1000 });

    let smsOk = false;
    try {
      await sendTencentSms(phone, code);
      console.log(`[SMS] Sent to ${phone}`);
      smsOk = true;
    } catch (err: any) {
      console.error(`[SMS] Send failed for ${phone}:`, err.message);
      if (process.env.NODE_ENV === 'production') {
        throw { status: 503, message: '短信发送失败，请稍后重试' };
      }
      console.warn(`[SMS] Dev fallback: code logged server-side only for ${phone}`);
    }

    if (!smsOk && process.env.NODE_ENV === 'production') {
      throw { status: 503, message: '短信发送失败，请稍后重试' };
    }

    return { phone };
  },
"""

new_send = """  async sendCode(phone: string) {
    const [legacyExists, modernExists] = await Promise.all([
      findLegacyUserByPhone(phone),
      findModernUserByPhone(phone),
    ]);
    if (legacyExists || modernExists) {
      throw { status: 400, message: '该手机号已注册，请直接输入密码登录' };
    }

    const code = generateCode();
    smsStore.set(phone, { code, expires: Date.now() + 5 * 60 * 1000 });

    const smsConfigured = Boolean(
      config.sms.secretId && config.sms.secretKey && config.sms.sdkAppId,
    );

    // 未配置腾讯云短信：仍写入验证码，并把 code 回传（临时；配好短信后自动关闭）
    if (!smsConfigured) {
      console.warn(`[SMS] Provider not configured; returning code in API for ${phone}`);
      return { phone, code, delivery: 'fallback' as const };
    }

    try {
      await sendTencentSms(phone, code);
      console.log(`[SMS] Sent to ${phone}`);
      return { phone, delivery: 'sms' as const };
    } catch (err: any) {
      console.error(`[SMS] Send failed for ${phone}:`, err.message);
      if (process.env.NODE_ENV === 'production') {
        throw { status: 503, message: '短信发送失败，请稍后重试' };
      }
      console.warn(`[SMS] Dev fallback: returning code in API for ${phone}`);
      return { phone, code, delivery: 'fallback' as const };
    }
  },
"""

if old_send not in atext:
    raise SystemExit("sendCode block not found")
atext = atext.replace(old_send, new_send, 1)
auth.write_text(atext)
print("auth.service.ts patched")
print("OK")
