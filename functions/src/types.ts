import type {DecodedIdToken} from "firebase-admin/auth";

export type EcoTraceRole =
  | "household"
  | "business"
  | "institution"
  | "collector"
  | "driver"
  | "collectionCentreOperator"
  | "repairTechnician"
  | "recycler"
  | "administrator"
  | "environmentalOfficer"
  | "superAdministrator";

export interface RequestUser {
  uid: string;
  email?: string;
  role: EcoTraceRole;
  token: DecodedIdToken;
}

declare global {
  namespace Express {
    interface Request {
      user?: RequestUser;
    }
  }
}
