#!/usr/bin/env python3
from pathlib import Path
import re

p = Path("/opt/ninewood/server/src/routes/message.ts")
text = p.read_text()

unread = """
// GET /api/messages/unread-count
messageRouter.get('/unread-count', authMiddleware, async (req: Request, res: Response) => {
  try {
    const count = await messageService.getUnreadCount(req.user!.userId);
    success(res, { count });
  } catch (e: any) {
    fail(res, e.message || '服务器错误', e.status || 500);
  }
});

"""

anchor = "// GET /api/messages/:userId"
text = re.sub(
    r"\n// GET /api/messages/unread-count\nmessageRouter\.get\('/unread-count'[\s\S]*?\}\);\n",
    "\n",
    text,
    count=1,
)
before, _, after = text.partition(anchor)
if "/unread-count" not in before:
    text = before + unread + anchor + after
p.write_text(text)
lines = [i + 1 for i, line in enumerate(text.splitlines()) if "unread-count" in line or "/:userId" in line]
print("lines", lines)
