#!/usr/bin/env python3
"""Patch production server for AC-P1: service-fee escrow hold semantics."""
from __future__ import annotations

from pathlib import Path

ROOT = Path("/opt/ninewood/server")


def patch_wallet() -> None:
    path = ROOT / "src/services/wallet.service.ts"
    text = path.read_text()
    if "holdServiceFee(" in text:
        print("wallet: already patched")
        return

    anchor = "  async settleDemand("
    methods = '''
  /**
   * 订单服务费托管（预付）：冻结点数，不计入平台收入。
   * 验收成功后 consume；取消/争议退款 release 全额退回。
   */
  async holdServiceFee(
    userId: string,
    orderId: string,
    amount: number,
    tx?: Tx,
  ): Promise<{ held: number; balanceAfter: number }> {
    const run = async (client: Tx) => {
      const amt = roundPoints(amount)
      if (amt <= 0) {
        throw Object.assign(new Error('托管金额必须大于 0'), { status: 400 })
      }

      const existing = await client.walletServiceFeeHold.findUnique({ where: { orderId } })
      if (existing?.status === 'HELD') {
        throw Object.assign(new Error('服务费已托管'), { status: 400 })
      }
      if (existing) {
        throw Object.assign(new Error('该订单服务费托管已结束，不可再次预付'), { status: 400 })
      }

      const updated = await client.user.updateMany({
        where: { id: userId, points: { gte: amt } },
        data: { points: { decrement: amt } },
      })
      if (updated.count === 0) {
        throw Object.assign(new Error('点数不足，无法预付服务费'), {
          status: 400,
          code: 'INSUFFICIENT_POINTS',
        })
      }

      const balanceAfter = await readBalance(client, userId)
      await client.walletServiceFeeHold.create({
        data: {
          userId,
          orderId,
          amount: amt,
          status: 'HELD',
        },
      })
      await writeLedger(client, userId, 'HOLD', -amt, balanceAfter, {
        referenceType: 'ORDER',
        referenceId: orderId,
        memo: '预付服务费托管（验收成功后才计入平台收入）',
      })
      return { held: amt, balanceAfter }
    }

    if (tx) return run(tx)
    return prisma.$transaction(run)
  },

  /** 取消/争议退款：服务费托管全额退回（未达成结果 → 零平台收入） */
  async releaseServiceFeeHold(
    orderId: string,
    reason: string,
    tx?: Tx,
  ): Promise<{ released: number; hadHold: boolean }> {
    const run = async (client: Tx) => {
      const hold = await client.walletServiceFeeHold.findUnique({ where: { orderId } })
      if (!hold || hold.status !== 'HELD') {
        return { released: 0, hadHold: false }
      }
      const released = roundPoints(Number(hold.amount))
      if (released > 0) {
        await client.user.update({
          where: { id: hold.userId },
          data: { points: { increment: released } },
        })
        const balanceAfter = await readBalance(client, hold.userId)
        await writeLedger(client, hold.userId, 'RELEASE', released, balanceAfter, {
          referenceType: 'ORDER',
          referenceId: orderId,
          memo: `服务费托管全额退回（${reason}）`,
        })
      }
      await client.walletServiceFeeHold.update({
        where: { id: hold.id },
        data: { status: 'RELEASED', releasedAt: new Date() },
      })
      return { released, hadHold: true }
    }

    if (tx) return run(tx)
    return prisma.$transaction(run)
  },

  /** 验收成功：托管转为平台收入（余额已在预付时冻结，此处不再扣款） */
  async consumeServiceFeeHold(
    orderId: string,
    tx?: Tx,
  ): Promise<{ consumed: number; hadHold: boolean }> {
    const run = async (client: Tx) => {
      const hold = await client.walletServiceFeeHold.findUnique({ where: { orderId } })
      if (!hold || hold.status !== 'HELD') {
        return { consumed: 0, hadHold: false }
      }
      const consumed = roundPoints(Number(hold.amount))
      await client.walletServiceFeeHold.update({
        where: { id: hold.id },
        data: { status: 'CONSUMED', releasedAt: new Date() },
      })
      // 可用余额已在 HOLD 时冻结；平台收入以 Settlement.platformRevenue 为准。
      return { consumed, hadHold: true }
    }

    if (tx) return run(tx)
    return prisma.$transaction(run)
  },

'''
    if anchor not in text:
        raise SystemExit("wallet settleDemand anchor missing")
    path.write_text(text.replace(anchor, methods + anchor, 1))
    print("wallet: patched")


def patch_order() -> None:
    path = ROOT / "src/services/order.service.ts"
    text = path.read_text()

    old_prepay = """    await prisma.$transaction(async (tx) => {
      // 真实扣减服务费，走 wallet.ledger 可追溯
      await walletService.debit(
        userId,
        breakdown.serviceFee,
        {
          referenceType: 'ORDER',
          referenceId: orderId,
          memo: 'prepay 服务费(5%)',
        },
        tx,
      )
      await tx.order.update({
        where: { id: orderId },
        data: { paidAt: new Date() },
      })
    })

    return { message: '点数已扣除，支付完成', amount: Number(order.agreedPrice), serviceFee: breakdown.serviceFee }
"""
    new_prepay = """    await prisma.$transaction(async (tx) => {
      // AC-P1：预付=托管，验收成功后才计入平台收入
      await walletService.holdServiceFee(userId, orderId, breakdown.serviceFee, tx)
      await tx.order.update({
        where: { id: orderId },
        data: { paidAt: new Date() },
      })
    })

    return {
      message: '服务费已托管（验收成功后才计入平台收入）',
      amount: Number(order.agreedPrice),
      serviceFee: breakdown.serviceFee,
    }
"""
    if "holdServiceFee(userId, orderId" not in text:
        if old_prepay not in text:
            raise SystemExit("prepay block not found")
        text = text.replace(old_prepay, new_prepay, 1)
        print("order: prepay patched")
    else:
        print("order: prepay already patched")

    old_confirm_tx = """    const { breakdown } = await prisma.$transaction(async (tx) => {
      const { breakdown } = await walletService.settleDemand(
        order.demandId,
        Number(order.agreedPrice),
        { skipServiceFee },
        tx,
      );

      await tx.order.update({
        where: { id: orderId },
        data: { status: 'COMPLETED', completedAt: new Date() },
      });
"""
    new_confirm_tx = """    const { breakdown } = await prisma.$transaction(async (tx) => {
      if (skipServiceFee) {
        await walletService.consumeServiceFeeHold(orderId, tx)
      }
      const { breakdown } = await walletService.settleDemand(
        order.demandId,
        Number(order.agreedPrice),
        { skipServiceFee },
        tx,
      );

      await tx.order.update({
        where: { id: orderId },
        data: { status: 'COMPLETED', completedAt: new Date() },
      });
"""
    if "consumeServiceFeeHold(orderId" not in text:
        if old_confirm_tx not in text:
            raise SystemExit("confirm tx block not found")
        text = text.replace(old_confirm_tx, new_confirm_tx, 1)
        print("order: confirm patched")
    else:
        print("order: confirm already patched")

    old_confirm_msg = """        content: `订单已完成验收，¥${Number(order.agreedPrice)} 已结算。服务费 ¥${breakdown.serviceFee.toFixed(2)}。`,"""
    new_confirm_msg = """        content: `订单已完成验收，¥${Number(order.agreedPrice)} 已结算。平台服务费 ¥${breakdown.serviceFee.toFixed(2)} 已计入平台收入。`,"""
    if old_confirm_msg in text:
        text = text.replace(old_confirm_msg, new_confirm_msg, 1)
        print("order: confirm message patched")

    old_cancel_refund = """      if (order.paidAt && breakdown && breakdown.serviceFee > 0) {
        await walletService.credit(
          userId,
          breakdown.serviceFee,
          {
            referenceType: 'ORDER',
            referenceId: orderId,
            memo: '取消订单退还服务费',
          },
          tx,
        );
      }
"""
    new_cancel_refund = """      // AC-P1：优先释放服务费托管；兼容旧 debit 预付路径
      const released = await walletService.releaseServiceFeeHold(orderId, 'ORDER_CANCELLED', tx)
      if (!released.hadHold && order.paidAt && breakdown && breakdown.serviceFee > 0) {
        await walletService.credit(
          userId,
          breakdown.serviceFee,
          {
            referenceType: 'ORDER',
            referenceId: orderId,
            memo: '取消订单退还服务费（旧预付路径）',
          },
          tx,
        );
      }
"""
    if "releaseServiceFeeHold(orderId, 'ORDER_CANCELLED'" not in text:
        if old_cancel_refund not in text:
            raise SystemExit("cancel refund block not found")
        text = text.replace(old_cancel_refund, new_cancel_refund, 1)
        print("order: cancel patched")
    else:
        print("order: cancel already patched")

    # partialComplete also settles with skipServiceFee — consume hold there too
    old_partial = """    const { remainingDemand } = await prisma.$transaction(async (tx) => {
      const { breakdown } = await walletService.settleDemand(
        order.demandId,
        newPrice,
        { skipServiceFee },
        tx,
      );
"""
    new_partial = """    const { remainingDemand } = await prisma.$transaction(async (tx) => {
      if (skipServiceFee) {
        await walletService.consumeServiceFeeHold(orderId, tx)
      }
      const { breakdown } = await walletService.settleDemand(
        order.demandId,
        newPrice,
        { skipServiceFee },
        tx,
      );
"""
    if old_partial in text:
        text = text.replace(old_partial, new_partial, 1)
        print("order: partialComplete patched")
    elif text.count("consumeServiceFeeHold(orderId, tx)") >= 2:
        print("order: partialComplete already patched")
    else:
        print("WARN: partialComplete may need manual check")

    path.write_text(text)


def patch_admin() -> None:
    path = ROOT / "src/routes/admin.ts"
    text = path.read_text()

    old_refund = """  if (action === 'refund') {
    const { walletService } = await import('../services/wallet.service.js');
    await prisma.$transaction(async (tx) => {
      await walletService.releaseHold(order.demandId, 'WITHDRAWN', tx);
      if (order.paidAt && order.demand) {
        const breakdown = calculateSettlement(
          Number(order.demand.minPrice),
          Number(order.agreedPrice),
          Number(order.demand.minPrice),
        );
        if (breakdown.serviceFee > 0) {
          await walletService.credit(
            order.requesterId,
            breakdown.serviceFee,
            {
              referenceType: 'ORDER',
              referenceId: order.id,
              memo: '争议退款退还已付服务费',
            },
            tx,
          );
        }
      }
"""
    new_refund = """  if (action === 'refund') {
    const { walletService } = await import('../services/wallet.service.js');
    await prisma.$transaction(async (tx) => {
      await walletService.releaseHold(order.demandId, 'WITHDRAWN', tx);
      // AC-P1：争议退款 → 服务费托管全额退回
      const released = await walletService.releaseServiceFeeHold(order.id, 'DISPUTE_REFUND', tx)
      if (!released.hadHold && order.paidAt && order.demand) {
        const breakdown = calculateSettlement(
          Number(order.demand.minPrice),
          Number(order.agreedPrice),
          Number(order.demand.minPrice),
        );
        if (breakdown.serviceFee > 0) {
          await walletService.credit(
            order.requesterId,
            breakdown.serviceFee,
            {
              referenceType: 'ORDER',
              referenceId: order.id,
              memo: '争议退款退还已付服务费（旧预付路径）',
            },
            tx,
          );
        }
      }
"""
    if "releaseServiceFeeHold(order.id, 'DISPUTE_REFUND'" not in text:
        if old_refund not in text:
            raise SystemExit("admin refund block not found")
        text = text.replace(old_refund, new_refund, 1)
        print("admin: refund patched")
    else:
        print("admin: refund already patched")

    old_complete = """  } else {
    try {
      const { walletService } = await import('../services/wallet.service.js');
      await walletService.settleDemand(order.demandId, Number(order.agreedPrice));
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.warn('[admin.disputes.resolve] settleDemand failed:', msg);
    }
    await prisma.order.update({
      where: { id: req.params.id as string },
      data: { status: 'COMPLETED', completedAt: new Date() },
    });
  }
"""
    new_complete = """  } else {
    try {
      const { walletService } = await import('../services/wallet.service.js');
      const skipServiceFee = Boolean(order.paidAt);
      await prisma.$transaction(async (tx) => {
        if (skipServiceFee) {
          await walletService.consumeServiceFeeHold(order.id, tx);
        }
        await walletService.settleDemand(
          order.demandId,
          Number(order.agreedPrice),
          { skipServiceFee },
          tx,
        );
        await tx.order.update({
          where: { id: req.params.id as string },
          data: { status: 'COMPLETED', completedAt: new Date() },
        });
      });
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.warn('[admin.disputes.resolve] settleDemand failed:', msg);
      await prisma.order.update({
        where: { id: req.params.id as string },
        data: { status: 'COMPLETED', completedAt: new Date() },
      });
    }
  }
"""
    if "consumeServiceFeeHold(order.id, tx)" not in text:
        if old_complete not in text:
            raise SystemExit("admin complete block not found")
        text = text.replace(old_complete, new_complete, 1)
        print("admin: complete patched")
    else:
        print("admin: complete already patched")

    path.write_text(text)


def main() -> None:
    patch_wallet()
    patch_order()
    patch_admin()
    print("done")


if __name__ == "__main__":
    main()
