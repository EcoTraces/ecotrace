import type {ErrorRequestHandler, RequestHandler} from "express";
import {ZodError} from "zod";

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code = "api_error",
  ) {
    super(message);
  }
}

export const notFound: RequestHandler = (request, _response, next) => {
  next(new ApiError(404, `Route ${request.method} ${request.path} was not found.`, "not_found"));
};

export const errorHandler: ErrorRequestHandler = (error, _request, response, _next) => {
  if (error instanceof ZodError) {
    response.status(400).json({
      error: {
        code: "validation_error",
        message: "The request payload is invalid.",
        details: error.issues,
      },
    });
    return;
  }
  const status = error instanceof ApiError ? error.status : 500;
  const code = error instanceof ApiError ? error.code : "internal_error";
  response.status(status).json({
    error: {
      code,
      message: status === 500 ? "An unexpected server error occurred." : error.message,
    },
  });
};
