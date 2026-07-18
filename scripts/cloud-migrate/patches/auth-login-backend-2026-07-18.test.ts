import { describe, it, expect } from 'vitest';
import request from 'supertest';
import express from 'express';
import { authRouter } from '../routes/auth.js';

const app = express();
app.use(express.json());
app.use('/api/auth', authRouter);

describe('Auth login contract', () => {
  it('GET /api/auth/bootstrap exposes captcha + sms mode', async () => {
    const res = await request(app).get('/api/auth/bootstrap');
    expect(res.status).toBe(200);
    expect(res.body.code).toBe(200);
    expect(res.body.data?.ok).toBe(true);
    expect(['bypass', 'hcaptcha']).toContain(res.body.data?.captcha?.mode);
  });

  it('POST /api/auth/login rejects invalid phone', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ phone: '123', password: '1' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe(400);
  });
});
