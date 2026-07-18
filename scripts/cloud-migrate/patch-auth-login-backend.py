#!/usr/bin/env python3
"""Align auth login/register/me user payload with macOS AuthPayloadDTO contract."""
from pathlib import Path

AUTH = Path("/opt/ninewood/server/src/services/auth.service.ts")
text = AUTH.read_text()

old_type = """  snatchCredits: number | null;
  creditScore: number | null;
  passwordHash?: string | null;
  createdAt?: Date;
};"""

new_type = """  snatchCredits: number | null;
  creditScore: number | null;
  completedOrders?: number | null;
  passwordHash?: string | null;
  createdAt?: Date;
};"""

if old_type not in text:
    raise SystemExit("LegacyUser type block not found")
text = text.replace(old_type, new_type, 1)

old_response = """    snatchCredits: user.snatchCredits || 0,
    creditScore: user.creditScore || 60,
    createdAt: user.createdAt?.toISOString(),
  };
}"""

new_response = """    snatchCredits: user.snatchCredits || 0,
    creditScore: user.creditScore || 60,
    completedOrders: user.completedOrders ?? 0,
    createdAt: user.createdAt?.toISOString(),
  };
}"""

if old_response not in text:
    raise SystemExit("legacyUserResponse block not found")
text = text.replace(old_response, new_response, 1)

LEGACY_COLS = (
    '"id","accountNo","phone","email","nickname","avatarUrl","coverUrl",'
    '"demandCardCoverUrl","cityCode","ipRegion","bio","birthday",'
    '"certificationLevel","snatchCredits","creditScore","completedOrders",'
    '"passwordHash","createdAt"'
)

RETURNING_COLS = LEGACY_COLS.replace('"passwordHash",', "")

replacements = [
    (
        'SELECT "id","phone","nickname","avatarUrl","coverUrl","demandCardCoverUrl","cityCode","ipRegion","bio","birthday","certificationLevel","snatchCredits","creditScore","passwordHash","createdAt"\n      FROM "User" WHERE "phone" =',
        f"SELECT {LEGACY_COLS}\n      FROM \"User\" WHERE \"phone\" =",
    ),
    (
        'SELECT "id","accountNo","phone","nickname","avatarUrl","coverUrl","demandCardCoverUrl","cityCode","ipRegion","bio","birthday","certificationLevel","snatchCredits","creditScore","passwordHash","createdAt"\n      FROM "User" WHERE "accountNo" =',
        f"SELECT {LEGACY_COLS}\n      FROM \"User\" WHERE \"accountNo\" =",
    ),
    (
        'SELECT "id","phone","nickname","avatarUrl","coverUrl","demandCardCoverUrl","cityCode","ipRegion","bio","birthday","certificationLevel","snatchCredits","creditScore","passwordHash","createdAt"\n      FROM "User" WHERE "id" =',
        f"SELECT {LEGACY_COLS}\n      FROM \"User\" WHERE \"id\" =",
    ),
    (
        'SELECT "id","phone","email","nickname","avatarUrl","coverUrl","demandCardCoverUrl","cityCode","ipRegion","bio","birthday","certificationLevel","snatchCredits","creditScore","passwordHash","createdAt"\n      FROM "User" WHERE LOWER("email") =',
        f"SELECT {LEGACY_COLS}\n      FROM \"User\" WHERE LOWER(\"email\") =",
    ),
    (
        'RETURNING "id","accountNo","phone","nickname","avatarUrl","coverUrl","demandCardCoverUrl","cityCode","bio","birthday","certificationLevel","snatchCredits","creditScore","createdAt"',
        f'RETURNING {RETURNING_COLS}',
    ),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"legacy SQL block not found:\n{old[:80]}...")
    text = text.replace(old, new, 1)

MODERN_SELECT_SNIPPET = """        snatchCredits: true,
        creditScore: true,
        passwordHash: true,"""

MODERN_SELECT_WITH_ORDERS = """        accountNo: true,
        snatchCredits: true,
        creditScore: true,
        completedOrders: true,
        passwordHash: true,"""

if text.count(MODERN_SELECT_SNIPPET) < 4:
    raise SystemExit("modern prisma select blocks count mismatch")

text = text.replace(MODERN_SELECT_SNIPPET, MODERN_SELECT_WITH_ORDERS)

# Blocks that already declared accountNo must not get a second one.
text = text.replace(
    """        certificationLevel: true,
        accountNo: true,
        snatchCredits: true,""",
    """        certificationLevel: true,
        snatchCredits: true,""",
)

AUTH.write_text(text)
print("auth.service.ts patched")

ROUTES = Path("/opt/ninewood/server/src/routes/auth.ts")
routes = ROUTES.read_text()

bootstrap_route = """
// GET /api/auth/bootstrap — 登录/注册页轻量探活（不计入 auth 写限流）
authRouter.get('/bootstrap', async (_req: Request, res: Response) => {
  try {
    const { UNCONFIGURED_CAPTCHA_TOKEN } = await import('./captcha.js');
    const captchaConfigured = Boolean(config.hcaptcha?.siteKey && config.hcaptcha?.secretKey);
    const smsConfigured = Boolean(
      config.sms?.secretId && config.sms?.secretKey && config.sms?.sdkAppId,
    );
    success(res, {
      ok: true,
      captcha: {
        mode: captchaConfigured ? 'hcaptcha' : 'bypass',
        bypassToken: captchaConfigured ? null : UNCONFIGURED_CAPTCHA_TOKEN,
        siteKey: config.hcaptcha?.siteKey || '',
      },
      sms: {
        configured: smsConfigured,
        fallbackEnabled: process.env.AUTH_SMS_FALLBACK === '1',
      },
    });
  } catch (e: any) {
    fail(res, e.message || '服务不可用', e.status || 500);
  }
});

"""

if "/bootstrap" not in routes:
    anchor = "// POST /api/auth/send-code — 人机验证 → 短信验证码"
    if anchor not in routes:
        raise SystemExit("auth routes anchor not found")
    routes = routes.replace(anchor, bootstrap_route + anchor, 1)
    # import config if missing
    if "import { config }" not in routes:
        routes = routes.replace(
            "import { getClientIp } from '../services/ipgeo.service.js';",
            "import { getClientIp } from '../services/ipgeo.service.js';\nimport { config } from '../config.js';",
            1,
        )
    ROUTES.write_text(routes)
    print("auth.ts bootstrap route added")
else:
    print("auth.ts bootstrap route already present")

print("OK")
