#!/usr/bin/env python3
"""发布附件：兼容 macOS multipart 字段名 files（服务端原先只认 images/video）。"""
from pathlib import Path

p = Path("/opt/ninewood/server/src/routes/demand.ts")
text = p.read_text()

old_fields = """demandRouter.post('/', authMiddleware, upload.fields([
  { name: 'images', maxCount: 9 },
  { name: 'video', maxCount: 1 },
]), verifyUpload, async (req: Request, res: Response) => {"""

new_fields = """demandRouter.post('/', authMiddleware, upload.fields([
  { name: 'images', maxCount: 9 },
  { name: 'files', maxCount: 9 }, // macOS 客户端附件字段名
  { name: 'video', maxCount: 1 },
]), verifyUpload, async (req: Request, res: Response) => {"""

if "name: 'files'" not in text:
    if old_fields not in text:
        raise SystemExit("upload.fields block not found")
    text = text.replace(old_fields, new_fields, 1)

old_media = """    const mediaUrls: string[] = [];
    if (files.images) files.images.forEach(f => mediaUrls.push(`/uploads/${f.filename}`));
    if (files.video) files.video.forEach(f => mediaUrls.push(`/uploads/${f.filename}`));"""

new_media = """    const mediaUrls: string[] = [];
    if (files.images) files.images.forEach(f => mediaUrls.push(`/uploads/${f.filename}`));
    if (files.files) files.files.forEach(f => mediaUrls.push(`/uploads/${f.filename}`));
    if (files.video) files.video.forEach(f => mediaUrls.push(`/uploads/${f.filename}`));"""

if "files.files" not in text:
    if old_media not in text:
        raise SystemExit("mediaUrls block not found")
    text = text.replace(old_media, new_media, 1)

p.write_text(text)
print("patched demand upload files field")
