import fs from "node:fs";
import path from "node:path";
import { Router } from "express";
import type { Response } from "express";
import multer from "multer";
import { v4 as uuidv4 } from "uuid";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";

const uploadRoot = path.join(process.cwd(), "uploads", "disputes");
fs.mkdirSync(uploadRoot, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    cb(null, uploadRoot);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const safe = [".jpg", ".jpeg", ".png", ".webp", ".gif"].includes(ext) ? ext : ".jpg";
    cb(null, `${uuidv4()}${safe}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 6 * 1024 * 1024, files: 12 },
  fileFilter: (_req, file, cb) => {
    if (/^image\/(jpeg|png|webp|gif)$/i.test(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Only JPEG, PNG, WebP, or GIF images are allowed"));
    }
  },
});

const router = Router();

/**
 * Multipart field name: `photos` (repeat for multiple files).
 * Returns `{ urls: string[] }` with absolute URLs for `POST /disputes` → `evidencePhotos`.
 */
router.post(
  "/dispute-evidence",
  authMiddleware(),
  (req: AuthedRequest, res: Response, next) => {
    upload.array("photos", 12)(req, res, (err: unknown) => {
      if (err) {
        const msg = err instanceof Error ? err.message : "Upload failed";
        res.status(400).json({ error: msg });
        return;
      }
      next();
    });
  },
  (req: AuthedRequest, res: Response) => {
    const files = req.files as Express.Multer.File[] | undefined;
    if (!files?.length) {
      res.status(400).json({ error: "No image files received. Use form field name \"photos\"." });
      return;
    }
    const publicBase =
      process.env.PUBLIC_API_URL?.replace(/\/$/, "") ||
      `${req.protocol}://${req.get("host")}`;
    const urls = files.map((f) => `${publicBase}/uploads/disputes/${f.filename}`);
    res.json({ urls });
  }
);

export default router;
