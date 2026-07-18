#!/usr/bin/env python3
"""发布需求后端：修复 multipart 布尔字段误解析（'false' → true）。"""
from pathlib import Path

ROUTE = Path("/opt/ninewood/server/src/routes/demand.ts")


HELPER = """
/** multipart / form 字段布尔：避免 z.coerce.boolean 把非空字符串 'false' 当成 true */
const formBoolean = z.preprocess((v) => {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') {
    const s = v.trim().toLowerCase();
    if (['true', '1', 'yes', 'on'].includes(s)) return true;
    if (['false', '0', 'no', 'off', ''].includes(s)) return false;
  }
  return v;
}, z.boolean());

"""


def main() -> None:
    text = ROUTE.read_text()
    if "const formBoolean" not in text:
        text = text.replace(
            "export const demandRouter = Router();",
            "export const demandRouter = Router();\n" + HELPER,
        )

    text = text.replace(
        "isCertifiedOnly: z.coerce.boolean().optional(),",
        "isCertifiedOnly: formBoolean.optional(),",
    )
    text = text.replace(
        "tagsConfirmed: z.coerce.boolean().optional(),",
        "tagsConfirmed: formBoolean.optional(),",
    )

    # create 成功响应：确保资金摘要字段始终为 number（Prisma Decimal 偶发字符串）
    old_success = "    success(res, demand, '发布成功', 201);"
    new_success = """    const payload = {
      ...demand,
      minPrice: Number(demand.minPrice),
      amountEstimate:
        demand.amountEstimate != null ? Number(demand.amountEstimate) : null,
      deposit: demand.deposit != null ? Number(demand.deposit) : 0,
    };
    success(res, payload, '发布成功', 201);"""
    if old_success in text and "const payload = {" not in text.split("发布成功")[0][-400:]:
        # only replace the create handler success once — find first occurrence after create
        idx = text.find("// POST /api/demands — create")
        if idx < 0:
            raise SystemExit("create route marker not found")
        rest = text[idx:]
        if old_success not in rest:
            raise SystemExit("create success call not found")
        rest = rest.replace(old_success, new_success, 1)
        text = text[:idx] + rest

    ROUTE.write_text(text)
    print("patched demand create boolean + numeric money fields")


if __name__ == "__main__":
    main()
