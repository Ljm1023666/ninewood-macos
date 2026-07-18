  async sendCode(phone: string) {
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

    // 未配置腾讯云短信：仅当 AUTH_SMS_FALLBACK=1 时回传 code（显式开发/过渡开关）
    if (!smsConfigured) {
      if (process.env.AUTH_SMS_FALLBACK !== '1') {
        throw { status: 503, message: '短信服务未配置，请联系管理员或稍后重试' };
      }
      console.warn(`[SMS] Provider not configured; AUTH_SMS_FALLBACK=1 returning code for ${phone}`);
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
