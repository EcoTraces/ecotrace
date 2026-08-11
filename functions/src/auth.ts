import type {RequestHandler} from "express";
import {auth, db} from "./firebase.js";
import {ApiError} from "./errors.js";
import type {EcoTraceRole} from "./types.js";

const defaultRole: EcoTraceRole = "household";

export const authenticate: RequestHandler = async (request, _response, next) => {
  try {
    const header = request.header("authorization");
    if (!header?.startsWith("Bearer ")) {
      throw new ApiError(401, "A Firebase ID token is required.", "unauthenticated");
    }
    const token = await auth.verifyIdToken(header.slice(7), true);
    const profile = await db.collection("users").doc(token.uid).get();
    const accountStatus = String(profile.get("accountStatus") ?? "active");
    if (["suspended", "disabled", "deleted"].includes(accountStatus)) {
      throw new ApiError(403, "This account is not active.", "account_inactive");
    }
    let role = token.role as EcoTraceRole | undefined;
    if (!role) {
      role = profile.get("role") as EcoTraceRole | undefined;
    }
    request.user = {
      uid: token.uid,
      email: token.email,
      role: role ?? defaultRole,
      token,
    };
    next();
  } catch (error) {
    if (!(error instanceof ApiError)) {
      console.error("Token verification failed.", error);
    }
    next(error instanceof ApiError ? error : new ApiError(401, "The Firebase ID token is invalid or expired.", "unauthenticated"));
  }
};

export const requireRoles = (...roles: EcoTraceRole[]): RequestHandler =>
  (request, _response, next) => {
    if (!request.user) {
      next(new ApiError(401, "Authentication is required.", "unauthenticated"));
      return;
    }
    if (!roles.includes(request.user.role)) {
      next(new ApiError(403, "You do not have permission to perform this operation.", "forbidden"));
      return;
    }
    next();
  };

export const requirePermission = (permission: string): RequestHandler =>
  async (request, _response, next) => {
    try {
      if (!request.user) throw new ApiError(401, "Authentication is required.", "unauthenticated");
      if (request.user.role === "superAdministrator") return next();
      const role = await db.collection("systemRoles").doc(request.user.role).get();
      const permissions = role.get("permissions") as string[] | undefined;
      if (!permissions?.includes(permission)) throw new ApiError(403, `Permission ${permission} is required.`, "forbidden");
      next();
    } catch (error) { next(error); }
  };
