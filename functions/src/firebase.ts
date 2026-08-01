import {cert, getApps, initializeApp, type ServiceAccount} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

function renderCredential(): ServiceAccount | undefined {
  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64?.trim();
  const raw = encoded ? Buffer.from(encoded, "base64").toString("utf8") : process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return undefined;
  const value = JSON.parse(raw) as Record<string, unknown>;
  const projectId = String(value.project_id ?? value.projectId ?? "");
  const clientEmail = String(value.client_email ?? value.clientEmail ?? "");
  const privateKey = String(value.private_key ?? value.privateKey ?? "").replace(/\\n/g, "\n");
  if (!projectId || !clientEmail || !privateKey) {
    throw new Error("The Firebase service-account secret is missing project_id, client_email, or private_key.");
  }
  return {projectId, clientEmail, privateKey};
}

if (getApps().length === 0) {
  const serviceAccount = renderCredential();
  initializeApp(serviceAccount ? {
    credential: cert(serviceAccount),
    projectId: serviceAccount.projectId,
  } : undefined);
}

export const auth = getAuth();
export const db = getFirestore();
