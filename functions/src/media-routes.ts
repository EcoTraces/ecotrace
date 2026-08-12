import {createHash, randomUUID} from "node:crypto";
import {Router} from "express";
import {z} from "zod";
import {authenticate} from "./auth.js";
import {ApiError} from "./errors.js";

const router = Router();
const scopeSchema = z.enum([
  "pickups", "inventory", "collection-evidence", "incidents", "donations",
  "support", "compliance", "partners", "organizations", "reverse-logistics", "profiles",
  "documents", "traceability", "marketplace", "hazardous",
]);

router.post("/media/upload-signature", authenticate, (request, response) => {
  const {scope} = z.object({scope: scopeSchema}).parse(request.body);
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME?.trim();
  const apiKey = process.env.CLOUDINARY_API_KEY?.trim();
  const apiSecret = process.env.CLOUDINARY_API_SECRET?.trim();
  if (!cloudName || !apiKey || !apiSecret) {
    throw new ApiError(503, "Cloudinary image storage is not configured.", "media_unavailable");
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const folder = `ecotrace/${scope}/${request.user!.uid}`;
  const publicId = randomUUID();
  const value = `folder=${folder}&public_id=${publicId}&timestamp=${timestamp}${apiSecret}`;
  const signature = createHash("sha1").update(value).digest("hex");
  response.json({data: {
    uploadUrl: `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/upload`,
    cloudName, apiKey, timestamp, folder, publicId, signature,
  }});
});

export default router;
