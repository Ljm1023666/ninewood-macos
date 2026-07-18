#!/usr/bin/env python3
from pathlib import Path

setup = Path("/opt/ninewood/server/src/__tests__/setup.ts")
s = setup.read_text()
needle = "process.env.NODE_ENV = 'test';\n"
forced = (
    "process.env.NODE_ENV = 'test';\n"
    # 覆盖生产 .env：否则 Vite/dotenv 会先注入真实 ADMIN_API_KEY，导致门禁测试失败
    "process.env.ADMIN_API_KEY = 'ninewood-local-admin-key';\n"
)
if "ADMIN_API_KEY = 'ninewood-local-admin-key'" not in s:
    if needle not in s:
        raise SystemExit("setup.ts NODE_ENV line not found")
    setup.write_text(s.replace(needle, forced, 1))
    print("patched setup.ts")
else:
    print("setup.ts already forces ADMIN_API_KEY")

admin = Path("/opt/ninewood/server/src/__tests__/admin-api-key.test.ts")
admin.write_text(
    """import { describe, it, expect, vi, beforeAll } from 'vitest';
import express from 'express';
import request from 'supertest';

process.env.ADMIN_API_KEY = 'ninewood-local-admin-key';
process.env.NODE_ENV = 'test';

vi.mock('../config.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../config.js')>();
  return {
    ...actual,
    config: {
      ...actual.config,
      adminApiKey: 'ninewood-local-admin-key',
      adminSystemUserId: '',
    },
  };
});

vi.mock('../lib/prisma.js', () => ({
  prisma: {
    user: { count: vi.fn().mockResolvedValue(3), findMany: vi.fn().mockResolvedValue([]) },
    userTag: { count: vi.fn().mockResolvedValue(0) },
    order: {
      count: vi.fn().mockResolvedValue(0),
      findMany: vi.fn().mockResolvedValue([]),
    },
    demand: {
      count: vi.fn().mockResolvedValue(1),
      groupBy: vi.fn().mockResolvedValue([]),
    },
    circle: {
      count: vi.fn().mockResolvedValue(2),
      groupBy: vi.fn().mockResolvedValue([]),
    },
  },
}));

vi.mock('../middleware/auth.js', () => ({
  authMiddleware: (_req: express.Request, res: express.Response) => {
    res.status(401).json({ code: 401, message: '未登录', timestamp: Date.now() });
  },
  optionalAuthMiddleware: (_req: express.Request, _res: express.Response, next: express.NextFunction) => next(),
}));

vi.mock('../middleware/admin.js', () => ({
  adminMiddleware: (_req: express.Request, res: express.Response) => {
    res.status(403).json({ code: 403, message: '无权访问', timestamp: Date.now() });
  },
}));

describe('admin API key gate', () => {
  let app: express.Express;

  beforeAll(async () => {
    const { adminRouter } = await import('../routes/admin.js');
    app = express();
    app.use(express.json());
    app.use('/api/admin', adminRouter);
  });

  it('rejects requests without key or JWT', async () => {
    const res = await request(app).get('/api/admin/health');
    expect(res.status).toBe(401);
  });

  it('allows health with valid X-Admin-Api-Key', async () => {
    const res = await request(app)
      .get('/api/admin/health')
      .set('X-Admin-Api-Key', 'ninewood-local-admin-key');
    expect(res.status).toBe(200);
    expect(res.body.data.ok).toBe(true);
  });
});
"""
)
print("rewrote admin-api-key.test.ts")

hub = Path("/opt/ninewood/server/src/__tests__/circle-hub.test.ts")
h = hub.read_text()
old = """vi.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, _res: any, next: any) => {
    req.user = { userId: req.headers['x-test-userid'] || 'u1', phone: '13800000000', certLevel: 'NONE' };
    next();
  },
}));"""
new = """vi.mock('../middleware/auth.js', () => ({
  authMiddleware: (req: any, _res: any, next: any) => {
    req.user = { userId: req.headers['x-test-userid'] || 'u1', phone: '13800000000', certLevel: 'NONE' };
    next();
  },
  optionalAuthMiddleware: (req: any, _res: any, next: any) => {
    const uid = req.headers['x-test-userid'];
    if (uid) req.user = { userId: uid, phone: '13800000000', certLevel: 'NONE' };
    next();
  },
}));"""
if old not in h:
    raise SystemExit("circle-hub auth mock block not found")
hub.write_text(h.replace(old, new, 1))
print("patched circle-hub.test.ts")
print("OK")
