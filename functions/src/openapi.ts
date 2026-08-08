export const openApiDocument = {
  openapi: "3.1.0",
  info: {
    title: "EcoTrace API",
    version: "1.0.0",
    description:
      "Versioned API for EcoTrace e-waste collection and processing workflows.",
  },
  servers: [{ url: "/api/v1", description: "Current deployment" }],
  components: {
    securitySchemes: {
      firebaseAuth: {
        type: "http",
        scheme: "bearer",
        bearerFormat: "Firebase ID token",
      },
    },
  },
  paths: {
    "/organizations": {
      get: {security: [{firebaseAuth: []}], summary: "List accessible organizations with search and status filters", responses: {"200": {description: "Organizations"}}},
      post: {security: [{firebaseAuth: []}], summary: "Register a business, institution, recycler, collection company, or repair provider", responses: {"201": {description: "Organization submitted for verification"}}},
    },
    "/organizations/{id}": {
      get: {security: [{firebaseAuth: []}], summary: "Get an organization profile", responses: {"200": {description: "Organization"}}},
      patch: {security: [{firebaseAuth: []}], summary: "Update organization contact and operational information", responses: {"200": {description: "Organization updated"}}},
    },
    "/organizations/{id}/submit": {patch: {security: [{firebaseAuth: []}], summary: "Resubmit a draft or rejected organization", responses: {"200": {description: "Organization submitted"}}}},
    "/organizations/{id}/review": {patch: {security: [{firebaseAuth: []}], summary: "Approve or reject organization verification", responses: {"200": {description: "Organization reviewed"}}}},
    "/organizations/{id}/status": {
      get: {security: [{firebaseAuth: []}], summary: "Get organization verification and operational status", responses: {"200": {description: "Organization status"}}},
      patch: {security: [{firebaseAuth: []}], summary: "Activate, reject, or suspend an organization", responses: {"200": {description: "Status updated"}}},
    },
    "/organizations/{id}/service-areas": {put: {security: [{firebaseAuth: []}], summary: "Replace organization service areas", responses: {"200": {description: "Service areas updated"}}}},
    "/organizations/{id}/branches": {
      get: {security: [{firebaseAuth: []}], summary: "List organization branches", responses: {"200": {description: "Branches"}}},
      post: {security: [{firebaseAuth: []}], summary: "Create an organization branch", responses: {"201": {description: "Branch created"}}},
    },
    "/organizations/{id}/branches/{branchId}": {
      patch: {security: [{firebaseAuth: []}], summary: "Update an organization branch", responses: {"200": {description: "Branch updated"}}},
      delete: {security: [{firebaseAuth: []}], summary: "Archive an organization branch", responses: {"200": {description: "Branch archived"}}},
    },
    "/organizations/{id}/members": {get: {security: [{firebaseAuth: []}], summary: "List organization owners, managers, staff, and viewers", responses: {"200": {description: "Members"}}}},
    "/organizations/{id}/members/{uid}": {
      patch: {security: [{firebaseAuth: []}], summary: "Update staff role, branch, or status", responses: {"200": {description: "Member updated"}}},
      delete: {security: [{firebaseAuth: []}], summary: "Remove organization staff", responses: {"200": {description: "Member removed"}}},
    },
    "/organizations/{id}/invitations": {post: {security: [{firebaseAuth: []}], summary: "Invite organization staff", responses: {"201": {description: "Invitation created"}}}},
    "/organization-invitations": {get: {security: [{firebaseAuth: []}], summary: "List invitations for the authenticated email", responses: {"200": {description: "Invitations"}}}},
    "/organization-invitations/{id}/respond": {patch: {security: [{firebaseAuth: []}], summary: "Accept or decline an organization invitation", responses: {"200": {description: "Invitation response recorded"}}}},
    "/organizations/{id}/documents": {
      get: {security: [{firebaseAuth: []}], summary: "List organization verification documents", responses: {"200": {description: "Documents"}}},
      post: {security: [{firebaseAuth: []}], summary: "Register an uploaded Cloudinary organization document", responses: {"201": {description: "Document registered"}}},
    },
    "/organizations/{id}/documents/{documentId}/verify": {patch: {security: [{firebaseAuth: []}], summary: "Verify or reject an organization document", responses: {"200": {description: "Document reviewed"}}}},
    "/identity/bootstrap": {post: {security: [{firebaseAuth: []}], summary: "Complete a Firebase self-service registration and record consent", responses: {"201": {description: "Identity profile created"}}}},
    "/identity/profile": {
      get: {security: [{firebaseAuth: []}], summary: "Get the authenticated identity profile", responses: {"200": {description: "Identity profile"}}},
      patch: {security: [{firebaseAuth: []}], summary: "Update the authenticated identity profile", responses: {"200": {description: "Profile updated"}}},
    },
    "/identity/verification/sync": {post: {security: [{firebaseAuth: []}], summary: "Synchronize Firebase email and phone verification state", responses: {"200": {description: "Verification synchronized"}}}},
    "/identity/providers": {get: {security: [{firebaseAuth: []}], summary: "List linked password, phone, and social identity providers", responses: {"200": {description: "Linked providers"}}}},
    "/identity/mfa": {
      get: {security: [{firebaseAuth: []}], summary: "Get multi-factor enrollment status", responses: {"200": {description: "MFA status"}}},
      delete: {security: [{firebaseAuth: []}], summary: "Remove enrolled factors and revoke sessions", responses: {"200": {description: "MFA removed"}}},
    },
    "/identity/sessions": {
      get: {security: [{firebaseAuth: []}], summary: "List active and historical devices and sessions", responses: {"200": {description: "Sessions"}}},
      post: {security: [{firebaseAuth: []}], summary: "Register a successful login session", responses: {"201": {description: "Session registered"}}},
    },
    "/identity/sessions/{id}": {delete: {security: [{firebaseAuth: []}], summary: "Revoke a device session", responses: {"200": {description: "Session revoked"}}}},
    "/identity/sessions/revoke-all": {post: {security: [{firebaseAuth: []}], summary: "Revoke all refresh tokens and active sessions", responses: {"200": {description: "Sessions revoked"}}}},
    "/identity/login-history": {get: {security: [{firebaseAuth: []}], summary: "List the current user's successful login history", responses: {"200": {description: "Login history"}}}},
    "/identity/consents": {put: {security: [{firebaseAuth: []}], summary: "Accept current terms and privacy policy versions", responses: {"200": {description: "Consent recorded"}}}},
    "/identity/permissions": {get: {security: [{firebaseAuth: []}], summary: "Get effective role permissions", responses: {"200": {description: "Effective permissions"}}}},
    "/identity/deletion-request": {
      get: {security: [{firebaseAuth: []}], summary: "Get the current account-deletion request", responses: {"200": {description: "Deletion request"}}},
      post: {security: [{firebaseAuth: []}], summary: "Request account deletion", responses: {"201": {description: "Deletion requested"}}},
      delete: {security: [{firebaseAuth: []}], summary: "Cancel a pending account-deletion request", responses: {"200": {description: "Deletion cancelled"}}},
    },
    "/identity/deletion-requests": {get: {security: [{firebaseAuth: []}], summary: "List account-deletion requests for administrators", responses: {"200": {description: "Deletion requests"}}}},
    "/identity/deletion-requests/{uid}": {patch: {security: [{firebaseAuth: []}], summary: "Approve or reject an account-deletion request", responses: {"200": {description: "Deletion request reviewed"}}}},
    "/media/upload-signature": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a short-lived signed Cloudinary image upload request",
        responses: { "200": { description: "Signed upload parameters" } },
      },
    },
    "/me": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return the authenticated user profile",
        responses: { "200": { description: "Current user" } },
      },
    },
    "/admin/demo-data": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create deterministic dashboard demo records",
        responses: {
          "200": { description: "Demo records created or refreshed" },
        },
      },
    },
    "/collection-centres": {
      get: {
        summary: "List the public collection-centre directory",
        responses: { "200": { description: "Active centres" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Register a collection centre",
        responses: { "201": { description: "Centre created" } },
      },
    },
    "/vehicles": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List vehicles",
        responses: { "200": { description: "Vehicles" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Register a vehicle",
        responses: { "201": { description: "Vehicle created" } },
      },
    },
    "/pickup-requests": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List accessible pickup requests",
        responses: { "200": { description: "Pickup requests" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Submit a pickup request",
        responses: { "201": { description: "Pickup created" } },
      },
    },
    "/pickup-requests/{id}/cancel": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Cancel an owned pickup request",
        responses: { "200": { description: "Pickup cancelled" } },
      },
    },
    "/pickup-requests/{id}/reschedule": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Reschedule an owned pickup request",
        responses: { "200": { description: "Pickup rescheduled" } },
      },
    },
    "/pickup-requests/{id}/rating": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Rate a completed pickup",
        responses: { "200": { description: "Rating saved" } },
      },
    },
    "/dispatch/schedules": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List collection schedules in a date range",
        responses: { "200": { description: "Role-filtered schedules" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create and assign a collection schedule",
        responses: { "201": { description: "Schedule created" } },
      },
    },
    "/dispatch/assignable-pickups": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List pickups ready for assignment",
        responses: { "200": { description: "Assignable pickups" } },
      },
    },
    "/dispatch/staff": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List collectors and drivers",
        responses: { "200": { description: "Dispatch staff" } },
      },
    },
    "/dispatch/schedules/{id}/dispatch": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Dispatch an assigned collection team",
        responses: { "200": { description: "Schedule dispatched" } },
      },
    },
    "/dispatch/schedules/{id}/start": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Start an assigned collection",
        responses: { "200": { description: "Collection started" } },
      },
    },
    "/dispatch/schedules/{id}/complete": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Complete an assigned collection",
        responses: { "200": { description: "Collection completed" } },
      },
    },
    "/dispatch/schedules/{id}/reschedule": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Reschedule a missed collection",
        responses: { "200": { description: "Collection rescheduled" } },
      },
    },
    "/routes": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List routes visible to the authenticated user",
        responses: { "200": { description: "Role-filtered routes" } },
      },
    },
    "/routes/schedulable": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List schedules available for route generation",
        responses: { "200": { description: "Schedulable collections" } },
      },
    },
    "/routes/optimize": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate an ordered route from pickup GPS coordinates",
        responses: { "201": { description: "Route generated" } },
      },
    },
    "/routes/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an accessible route",
        responses: { "200": { description: "Route details" } },
      },
    },
    "/routes/{id}/start": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Start live route navigation",
        responses: { "200": { description: "Route activated" } },
      },
    },
    "/routes/{id}/positions": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record an assigned driver's GPS position",
        responses: { "200": { description: "Position processed" } },
      },
    },
    "/routes/{id}/complete": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Complete an assigned route",
        responses: { "200": { description: "Route completed" } },
      },
    },
    "/collection-centres/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an operational collection-centre record",
        responses: { "200": { description: "Collection centre" } },
      },
    },
    "/collection-centres/{id}/storageSections": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List storage sections",
        responses: { "200": { description: "Storage sections" } },
      },
    },
    "/collection-centres/{id}/receivingRecords": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List receiving records",
        responses: { "200": { description: "Receiving records" } },
      },
    },
    "/collection-centres/{id}/stockMovements": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List stock movements",
        responses: { "200": { description: "Stock movements" } },
      },
    },
    "/collection-centres/{id}/staffAssignments": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List centre staff assignments",
        responses: { "200": { description: "Staff assignments" } },
      },
    },
    "/collection-centres/{id}/safetyInspections": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List safety inspections",
        responses: { "200": { description: "Safety inspections" } },
      },
    },
    "/collection-centres/{id}/sections": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a storage section",
        responses: { "201": { description: "Section created" } },
      },
    },
    "/collection-centres/{id}/staff": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign centre staff",
        responses: { "201": { description: "Staff assigned" } },
      },
    },
    "/collection-centres/{id}/check-ins": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Receive and check in e-waste",
        responses: { "201": { description: "Receiving record created" } },
      },
    },
    "/collection-centres/{id}/receiving/{recordId}/verify": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Verify a receiving weight",
        responses: { "200": { description: "Weight verified" } },
      },
    },
    "/collection-centres/{id}/check-outs": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Check stock out of a centre",
        responses: { "201": { description: "Stock checked out" } },
      },
    },
    "/collection-centres/{id}/inspections": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record a safety inspection",
        responses: { "201": { description: "Inspection recorded" } },
      },
    },
    "/inventory/items": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List e-waste inventory items",
        responses: { "200": { description: "Inventory items" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Register a tracked e-waste item",
        responses: { "201": { description: "Item registered" } },
      },
    },
    "/inventory/items/by-code/{code}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Find an item by its EcoTrace code",
        responses: { "200": { description: "Inventory item" } },
      },
    },
    "/inventory/items/{id}/history": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List item processing history",
        responses: { "200": { description: "History events" } },
      },
    },
    "/inventory/items/{id}/state": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Move an item to a processing state and location",
        responses: { "200": { description: "Item updated" } },
      },
    },
    "/inventory/batches": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List inventory batches",
        responses: { "200": { description: "Inventory batches" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create an inventory batch",
        responses: { "201": { description: "Batch created" } },
      },
    },
    "/inventory/items/{id}/batch": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign an item to an inventory batch",
        responses: { "200": { description: "Batch assigned" } },
      },
    },
    "/inventory/items/{id}/assessments": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List item classification assessments",
        responses: { "200": { description: "Assessments" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Submit an item classification assessment",
        responses: { "201": { description: "Assessment submitted" } },
      },
    },
    "/inventory/items/{id}/assessments/{assessmentId}/review": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Approve or reject a classification assessment",
        responses: { "200": { description: "Assessment reviewed" } },
      },
    },
    "/inventory/items/{id}/traceability": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List chain-of-custody events",
        responses: { "200": { description: "Traceability events" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record a chain-of-custody event",
        responses: { "201": { description: "Traceability event recorded" } },
      },
    },
    "/repairs": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List accessible repair jobs",
        responses: { "200": { description: "Repair jobs" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a repair assessment",
        responses: { "201": { description: "Repair job created" } },
      },
    },
    "/repairs/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a repair job",
        responses: { "200": { description: "Repair job" } },
      },
    },
    "/repairs/{id}/assignment": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign a repair technician",
        responses: { "200": { description: "Technician assigned" } },
      },
    },
    "/repairs/{id}/diagnosis": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Record diagnosis, faults, and cost estimate",
        responses: { "200": { description: "Diagnosis recorded" } },
      },
    },
    "/repairs/{id}/review": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Approve or reject a repair",
        responses: { "200": { description: "Repair reviewed" } },
      },
    },
    "/repairs/{id}/start": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Start an approved repair",
        responses: { "200": { description: "Repair started" } },
      },
    },
    "/repairs/{id}/parts": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List spare parts used",
        responses: { "200": { description: "Spare parts" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record a spare part",
        responses: { "201": { description: "Spare part recorded" } },
      },
    },
    "/repairs/{id}/progress": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List repair progress events",
        responses: { "200": { description: "Progress events" } },
      },
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update repair progress",
        responses: { "200": { description: "Progress updated" } },
      },
    },
    "/repairs/{id}/quality-testing": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Submit repair for quality testing",
        responses: { "200": { description: "Quality testing started" } },
      },
    },
    "/repairs/{id}/quality-control": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Complete quality control and refurbishment grading",
        responses: { "200": { description: "Quality control recorded" } },
      },
    },
    "/repairs/{id}/unrepairable": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Mark an item unrepairable and send it to recycling",
        responses: { "200": { description: "Repair closed" } },
      },
    },
    "/repairs/{id}/warranty": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update refurbished-device warranty",
        responses: { "200": { description: "Warranty updated" } },
      },
    },
    "/repairs/{id}/disposition": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Approve a repaired device for donation or resale",
        responses: { "200": { description: "Disposition approved" } },
      },
    },
    "/recycling/batches": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List recycling batches",
        responses: { "200": { description: "Recycling batches" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a recycling batch",
        responses: { "201": { description: "Batch created" } },
      },
    },
    "/recycling/batches/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a recycling batch",
        responses: { "200": { description: "Recycling batch" } },
      },
    },
    "/recycling/batches/{id}/facility": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign a recycling facility",
        responses: { "200": { description: "Facility assigned" } },
      },
    },
    "/recycling/batches/{id}/stage": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Advance the recycling stage",
        responses: { "200": { description: "Stage updated" } },
      },
    },
    "/recycling/batches/{id}/process-records": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List dismantling and separation records",
        responses: { "200": { description: "Process records" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record recycling work",
        responses: { "201": { description: "Process record created" } },
      },
    },
    "/recycling/batches/{id}/outputs": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record recovered or hazardous material",
        responses: { "201": { description: "Output recorded" } },
      },
    },
    "/recycling/batches/{id}/losses": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record a processing loss",
        responses: { "201": { description: "Loss recorded" } },
      },
    },
    "/recycling/batches/{id}/disposals": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List final disposal records",
        responses: { "200": { description: "Disposal records" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record final disposal",
        responses: { "201": { description: "Disposal recorded" } },
      },
    },
    "/recycling/batches/{id}/verify": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Verify recycling completion",
        responses: { "200": { description: "Batch completed" } },
      },
    },
    "/recycling/batches/{id}/certificate": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate recycling certificate data",
        responses: { "200": { description: "Certificate data" } },
      },
    },
    "/recycling/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return recycling performance totals",
        responses: { "200": { description: "Recycling performance" } },
      },
    },
    "/recovery/categories": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List recoverable material categories",
        responses: { "200": { description: "Material categories" } },
      },
    },
    "/recovery/categories/{material}": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update a material category",
        responses: { "200": { description: "Category saved" } },
      },
    },
    "/recovery/buyers": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List material buyers",
        responses: { "200": { description: "Material buyers" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Register a material buyer",
        responses: { "201": { description: "Buyer created" } },
      },
    },
    "/recovery/lots": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List recovered material lots",
        responses: { "200": { description: "Recovered material lots" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record recovered material and update batch mass balance",
        responses: { "201": { description: "Material lot created" } },
      },
    },
    "/recovery/lots/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a recovered material lot",
        responses: { "200": { description: "Material lot" } },
      },
    },
    "/recovery/lots/{id}/buyer": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign a material buyer",
        responses: { "200": { description: "Buyer assigned" } },
      },
    },
    "/recovery/lots/{id}/sales-ready": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Mark material as sales-ready",
        responses: { "200": { description: "Lot is sales-ready" } },
      },
    },
    "/recovery/lots/{id}/transfers": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List material transfer records",
        responses: { "200": { description: "Transfer records" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Transfer a material lot",
        responses: { "201": { description: "Transfer recorded" } },
      },
    },
    "/recovery/lots/{id}/sale": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record recovered-material sale revenue",
        responses: { "200": { description: "Sale recorded" } },
      },
    },
    "/recovery/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary:
          "Return recovery inventory, efficiency, value, and revenue totals",
        responses: { "200": { description: "Resource recovery summary" } },
      },
    },
    "/hazardous/records": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List hazardous waste records",
        responses: { "200": { description: "Hazardous waste records" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Identify and classify hazardous waste",
        responses: { "201": { description: "Hazardous waste record created" } },
      },
    },
    "/hazardous/records/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a hazardous waste record",
        responses: { "200": { description: "Hazardous waste record" } },
      },
    },
    "/hazardous/records/{id}/storage": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign special storage and containment",
        responses: { "200": { description: "Storage assigned" } },
      },
    },
    "/hazardous/records/{id}/battery-handling": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record safe battery handling",
        responses: { "201": { description: "Battery handling recorded" } },
      },
    },
    "/hazardous/records/{id}/safety-checks": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Complete PPE and safety checklist",
        responses: { "201": { description: "Safety check recorded" } },
      },
    },
    "/hazardous/incidents": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List hazardous waste incidents",
        responses: { "200": { description: "Hazardous waste incidents" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Report a hazardous waste incident",
        responses: { "201": { description: "Incident reported" } },
      },
    },
    "/hazardous/incidents/{id}/response": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Manage emergency response and incident closure",
        responses: { "200": { description: "Incident response updated" } },
      },
    },
    "/hazardous/records/{id}/transfers": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List hazardous waste transfer manifests",
        responses: { "200": { description: "Hazardous waste transfers" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Dispatch hazardous waste with a manifest",
        responses: { "201": { description: "Transfer dispatched" } },
      },
    },
    "/hazardous/records/{id}/disposal": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Record compliant hazardous waste disposal",
        responses: { "200": { description: "Disposal recorded" } },
      },
    },
    "/hazardous/training-records": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List hazardous-waste safety training records",
        responses: { "200": { description: "Training records" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record staff hazardous-waste safety training",
        responses: { "201": { description: "Training record created" } },
      },
    },
    "/hazardous/records/{id}/certificate": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate hazardous waste disposal certificate data",
        responses: { "200": { description: "Hazardous waste certificate" } },
      },
    },
    "/hazardous/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return hazardous waste, incident, and training metrics",
        responses: { "200": { description: "Hazardous waste summary" } },
      },
    },
    "/logistics/transfers": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List accessible reverse-logistics transfers",
        responses: { "200": { description: "Logistics transfers" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create and assign a reverse-logistics transfer",
        responses: { "201": { description: "Transfer created" } },
      },
    },
    "/logistics/transfers/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an accessible logistics transfer",
        responses: { "200": { description: "Logistics transfer" } },
      },
    },
    "/logistics/transfers/{id}/review": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Approve or reject a transfer",
        responses: { "200": { description: "Transfer reviewed" } },
      },
    },
    "/logistics/transfers/{id}/dispatch": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Dispatch a transfer with transport documents",
        responses: { "200": { description: "Transfer dispatched" } },
      },
    },
    "/logistics/transfers/{id}/custody-events": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List chain-of-custody events",
        responses: { "200": { description: "Custody events" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record a chain-of-custody event",
        responses: { "201": { description: "Custody event recorded" } },
      },
    },
    "/logistics/transfers/{id}/exceptions": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Report a transfer exception",
        responses: { "201": { description: "Exception reported" } },
      },
    },
    "/logistics/transfers/{id}/receive": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Confirm receipt and delivery proof",
        responses: { "200": { description: "Transfer received" } },
      },
    },
    "/logistics/transfers/{id}/document": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate transport and chain-of-custody document data",
        responses: { "200": { description: "Transport document" } },
      },
    },
    "/logistics/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return reverse-logistics analytics",
        responses: { "200": { description: "Reverse-logistics summary" } },
      },
    },
    "/partners": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List recycling and service partners",
        responses: { "200": { description: "Partners" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Register a partner",
        responses: { "201": { description: "Partner registered" } },
      },
    },
    "/partners/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a partner record",
        responses: { "200": { description: "Partner" } },
      },
    },
    "/partners/{id}/profile": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update partner services, areas, and capacity",
        responses: { "200": { description: "Partner updated" } },
      },
    },
    "/partners/{id}/documents": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List partner licences and certificates",
        responses: { "200": { description: "Partner documents" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Upload partner licence or certificate metadata",
        responses: { "201": { description: "Document created" } },
      },
    },
    "/partners/{id}/documents/{documentId}/verify": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Verify a partner licence or certificate",
        responses: { "200": { description: "Document verified" } },
      },
    },
    "/partners/{id}/contracts": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List partner contracts",
        responses: { "200": { description: "Contracts" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a partner contract",
        responses: { "201": { description: "Contract created" } },
      },
    },
    "/partners/{id}/commercial": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update pricing and payment information",
        responses: { "200": { description: "Commercial information updated" } },
      },
    },
    "/partners/{id}/ratings": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record a partner performance rating",
        responses: { "201": { description: "Rating recorded" } },
      },
    },
    "/partners/{id}/compliance-records": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record partner compliance performance",
        responses: { "201": { description: "Compliance recorded" } },
      },
    },
    "/partners/{id}/slas": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a service-level agreement",
        responses: { "201": { description: "SLA created" } },
      },
    },
    "/partners/{id}/status": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Suspend, reactivate, or terminate a partner",
        responses: { "200": { description: "Partner status updated" } },
      },
    },
    "/partners/alerts/document-expiry": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List expiring partner documents",
        responses: { "200": { description: "Document expiry alerts" } },
      },
    },
    "/partners/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return partner capacity, rating, and compliance analytics",
        responses: { "200": { description: "Partner analytics" } },
      },
    },
    "/marketplace/listings": {
      get: {
        summary:
          "Search active refurbished-device and recovered-material listings",
        responses: { "200": { description: "Marketplace listings" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a marketplace listing",
        responses: { "201": { description: "Listing created" } },
      },
    },
    "/marketplace/listings/{id}": {
      get: {
        summary: "Return an active marketplace listing",
        responses: { "200": { description: "Marketplace listing" } },
      },
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update a seller listing",
        responses: { "200": { description: "Listing updated" } },
      },
    },
    "/marketplace/buyer-profile": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update buyer registration",
        responses: { "200": { description: "Buyer profile saved" } },
      },
    },
    "/marketplace/seller-profile": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update seller profile",
        responses: { "200": { description: "Seller profile saved" } },
      },
    },
    "/marketplace/sellers/{id}": {
      get: {
        summary: "Return an active seller profile",
        responses: { "200": { description: "Seller profile" } },
      },
    },
    "/marketplace/quotations": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Request a price quotation",
        responses: { "201": { description: "Quotation requested" } },
      },
    },
    "/marketplace/quotations/{id}/respond": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Accept, reject, or counter a quotation",
        responses: { "200": { description: "Quotation answered" } },
      },
    },
    "/marketplace/orders": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List buyer or seller orders",
        responses: { "200": { description: "Marketplace orders" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Place an order and reserve inventory",
        responses: { "201": { description: "Order placed" } },
      },
    },
    "/marketplace/orders/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an accessible marketplace order",
        responses: { "200": { description: "Marketplace order" } },
      },
    },
    "/marketplace/orders/{id}/payment": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update marketplace payment status",
        responses: { "200": { description: "Payment updated" } },
      },
    },
    "/marketplace/orders/{id}/delivery": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update delivery tracking and proof",
        responses: { "200": { description: "Delivery updated" } },
      },
    },
    "/marketplace/orders/{id}/confirm-receipt": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Confirm receipt and finalize inventory sale",
        responses: { "200": { description: "Receipt confirmed" } },
      },
    },
    "/marketplace/orders/{id}/cancel": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Cancel an eligible order and release inventory",
        responses: { "200": { description: "Order cancelled" } },
      },
    },
    "/marketplace/orders/{id}/receipt": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate a digital marketplace receipt",
        responses: { "200": { description: "Digital receipt" } },
      },
    },
    "/marketplace/orders/{id}/reviews": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Review a completed marketplace order",
        responses: { "201": { description: "Review created" } },
      },
    },
    "/marketplace/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return marketplace inventory, order, and revenue analytics",
        responses: { "200": { description: "Marketplace analytics" } },
      },
    },
    "/donations/beneficiaries": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List donation beneficiaries",
        responses: { "200": { description: "Beneficiaries" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Register a donation beneficiary",
        responses: { "201": { description: "Beneficiary registered" } },
      },
    },
    "/donations/beneficiaries/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an accessible beneficiary",
        responses: { "200": { description: "Beneficiary" } },
      },
    },
    "/donations/beneficiaries/{id}/eligibility": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assess beneficiary eligibility",
        responses: { "200": { description: "Eligibility assessed" } },
      },
    },
    "/donations/requests": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List accessible donation requests",
        responses: { "200": { description: "Donation requests" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Submit a donation request",
        responses: { "201": { description: "Donation request submitted" } },
      },
    },
    "/donations/requests/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an accessible donation request",
        responses: { "200": { description: "Donation request" } },
      },
    },
    "/donations/requests/{id}/review": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Approve or reject a donation request",
        responses: { "200": { description: "Donation reviewed" } },
      },
    },
    "/donations/requests/{id}/allocation": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Allocate refurbished devices",
        responses: { "200": { description: "Devices allocated" } },
      },
    },
    "/donations/requests/{id}/delivery": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Schedule and record donation delivery",
        responses: { "200": { description: "Delivery updated" } },
      },
    },
    "/donations/requests/{id}/confirm": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Confirm donation delivery as beneficiary",
        responses: { "200": { description: "Donation confirmed" } },
      },
    },
    "/donations/requests/{id}/follow-ups": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record donated-device usage follow-up",
        responses: { "201": { description: "Follow-up recorded" } },
      },
    },
    "/donations/requests/{id}/history": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return donation and follow-up history",
        responses: { "200": { description: "Donation history" } },
      },
    },
    "/donations/requests/{id}/certificate": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate donation certificate data",
        responses: { "200": { description: "Donation certificate" } },
      },
    },
    "/donations/reports/impact": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return donation and social-impact metrics",
        responses: { "200": { description: "Donation impact report" } },
      },
    },
    "/rewards/wallet": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return the current green-point wallet",
        responses: { "200": { description: "Reward wallet" } },
      },
    },
    "/rewards/history": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List reward transaction history",
        responses: { "200": { description: "Reward history" } },
      },
    },
    "/rewards/rules": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List active reward rules",
        responses: { "200": { description: "Reward rules" } },
      },
    },
    "/rewards/rules/{id}": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update a reward rule",
        responses: { "200": { description: "Reward rule saved" } },
      },
    },
    "/rewards/award": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Award idempotent green points",
        responses: { "201": { description: "Points awarded" } },
      },
    },
    "/rewards/referrals": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a referral invitation",
        responses: { "201": { description: "Referral created" } },
      },
    },
    "/rewards/referrals/{id}/complete": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Complete a verified referral",
        responses: { "200": { description: "Referral completed" } },
      },
    },
    "/rewards/challenges": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List active recycling challenges",
        responses: { "200": { description: "Challenges" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a recycling challenge",
        responses: { "201": { description: "Challenge created" } },
      },
    },
    "/rewards/challenges/{id}/join": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Join a recycling challenge",
        responses: { "201": { description: "Challenge joined" } },
      },
    },
    "/rewards/challenges/{id}/progress": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update verified challenge progress",
        responses: { "200": { description: "Progress updated" } },
      },
    },
    "/rewards/catalog": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List available rewards and coupons",
        responses: { "200": { description: "Reward catalog" } },
      },
    },
    "/rewards/catalog/{id}": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update a coupon or partner reward",
        responses: { "200": { description: "Catalog reward saved" } },
      },
    },
    "/rewards/redemptions": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Redeem green points and issue a coupon",
        responses: { "201": { description: "Reward redeemed" } },
      },
    },
    "/rewards/fraud-flags": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Flag suspicious reward activity",
        responses: { "201": { description: "Fraud flag created" } },
      },
    },
    "/rewards/leaderboard": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return the green-point leaderboard",
        responses: { "200": { description: "Leaderboard" } },
      },
    },
    "/rewards/business-score/{userId}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Calculate a business sustainability score",
        responses: { "200": { description: "Sustainability score" } },
      },
    },
    "/rewards/certificate": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate a digital environmental certificate",
        responses: { "200": { description: "Environmental certificate" } },
      },
    },
    "/rewards/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary:
          "Return reward issuance, redemption, fraud, and level analytics",
        responses: { "200": { description: "Reward analytics" } },
      },
    },
    "/payments/fees/calculate": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Calculate pickup, tax, and service charges",
        responses: { "200": { description: "Calculated fees" } },
      },
    },
    "/payments/intents": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Initiate mobile-money, bank, or card payment",
        responses: { "201": { description: "Payment initiated" } },
      },
    },
    "/payments/transactions": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List accessible payment transactions",
        responses: { "200": { description: "Transactions" } },
      },
    },
    "/payments/transactions/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an accessible payment transaction",
        responses: { "200": { description: "Transaction" } },
      },
    },
    "/payments/transactions/{id}/confirm": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Confirm or fail a provider payment",
        responses: { "200": { description: "Payment updated" } },
      },
    },
    "/payments/transactions/{id}/retry": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Retry a failed payment",
        responses: { "200": { description: "Payment retried" } },
      },
    },
    "/payments/transactions/{id}/refunds": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Process a full or partial refund",
        responses: { "201": { description: "Refund processed" } },
      },
    },
    "/payments/invoices": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List accessible invoices",
        responses: { "200": { description: "Invoices" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate an invoice",
        responses: { "201": { description: "Invoice generated" } },
      },
    },
    "/payments/payouts": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create partner, collector, driver, or seller payout",
        responses: { "201": { description: "Payout created" } },
      },
    },
    "/payments/payouts/{id}/process": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Complete or fail a payout",
        responses: { "200": { description: "Payout processed" } },
      },
    },
    "/payments/reconciliation": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Reconcile financial transactions",
        responses: { "201": { description: "Reconciliation generated" } },
      },
    },
    "/payments/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return collections, refunds, payouts, and net cash",
        responses: { "200": { description: "Financial summary" } },
      },
    },
    "/impact/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return platform or user environmental impact",
        responses: { "200": { description: "Environmental impact" } },
      },
    },
    "/impact/formulas": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return environmental calculation formulas",
        responses: { "200": { description: "Impact formulas" } },
      },
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Configure environmental formulas",
        responses: { "200": { description: "Impact formulas updated" } },
      },
    },
    "/impact/snapshots": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate a monthly impact snapshot",
        responses: { "201": { description: "Impact snapshot generated" } },
      },
    },
    "/impact/monthly": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List monthly environmental impact",
        responses: { "200": { description: "Monthly impact" } },
      },
    },
    "/impact/comparison": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Compare two monthly impact periods",
        responses: { "200": { description: "Impact comparison" } },
      },
    },
    "/impact/adjustments": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Record an audited impact adjustment",
        responses: { "201": { description: "Impact adjustment created" } },
      },
    },
    "/impact/report": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate environmental impact report data",
        responses: { "200": { description: "Environmental impact report" } },
      },
    },
    "/analytics/overview": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return date-filtered business overview",
        responses: { "200": { description: "Analytics overview" } },
      },
    },
    "/analytics/collections/trends": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return collection trends",
        responses: { "200": { description: "Collection trends" } },
      },
    },
    "/analytics/waste/categories": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Analyze waste categories",
        responses: { "200": { description: "Waste category analytics" } },
      },
    },
    "/analytics/waste/regions": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Analyze regional waste distribution",
        responses: { "200": { description: "Regional analytics" } },
      },
    },
    "/analytics/operations": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary:
          "Return pickup, collector, centre, recycling, and recovery performance",
        responses: { "200": { description: "Operations analytics" } },
      },
    },
    "/analytics/revenue": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return payment, marketplace, and material revenue analytics",
        responses: { "200": { description: "Revenue analytics" } },
      },
    },
    "/analytics/users/growth": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return user growth by role",
        responses: { "200": { description: "User growth" } },
      },
    },
    "/analytics/partners/performance": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return partner performance analytics",
        responses: { "200": { description: "Partner performance" } },
      },
    },
    "/analytics/environmental": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return date-filtered environmental analytics",
        responses: { "200": { description: "Environmental analytics" } },
      },
    },
    "/analytics/widgets": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List dashboard widgets for the current role",
        responses: { "200": { description: "Dashboard widgets" } },
      },
    },
    "/analytics/widgets/{id}": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update a dashboard widget",
        responses: { "200": { description: "Widget saved" } },
      },
    },
    "/analytics/exports": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Queue PDF, CSV, or Excel analytics export",
        responses: { "202": { description: "Export queued" } },
      },
    },
    "/reports/definitions": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List report definitions",
        responses: { "200": { description: "Report definitions" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a report definition",
        responses: { "201": { description: "Report definition created" } },
      },
    },
    "/reports/generate": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate a report payload",
        responses: { "201": { description: "Report generated" } },
      },
    },
    "/reports/schedules": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List report schedules",
        responses: { "200": { description: "Report schedules" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a report schedule",
        responses: { "201": { description: "Report schedule created" } },
      },
    },
    "/reports/schedules/{id}": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update a report schedule",
        responses: { "200": { description: "Schedule updated" } },
      },
    },
    "/reports/generated": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List generated reports",
        responses: { "200": { description: "Generated reports" } },
      },
    },
    "/reports/generated/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a generated report",
        responses: { "200": { description: "Generated report" } },
      },
    },
    "/reports/catalog": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List report catalog entries",
        responses: { "200": { description: "Report catalog" } },
      },
    },
    "/communication/preferences": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Get notification preferences",
        responses: { "200": { description: "Notification preferences" } },
      },
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Save notification preferences",
        responses: { "200": { description: "Preferences saved" } },
      },
    },
    "/communication/templates": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List notification templates",
        responses: { "200": { description: "Notification templates" } },
      },
    },
    "/communication/templates/{id}": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update a notification template",
        responses: { "200": { description: "Template saved" } },
      },
    },
    "/communication/send": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Queue outbound notifications",
        responses: { "202": { description: "Notifications queued" } },
      },
    },
    "/communication/notifications": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List user notifications",
        responses: { "200": { description: "Notifications" } },
      },
    },
    "/communication/notifications/{id}/read": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Mark a notification as read",
        responses: { "200": { description: "Notification marked read" } },
      },
    },
    "/communication/conversations": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List user conversations",
        responses: { "200": { description: "Conversations" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a conversation",
        responses: { "201": { description: "Conversation created" } },
      },
    },
    "/communication/conversations/{id}/messages": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List conversation messages",
        responses: { "200": { description: "Messages" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Send a message",
        responses: { "201": { description: "Message created" } },
      },
    },
    "/communication/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return communication analytics",
        responses: { "200": { description: "Communication analytics" } },
      },
    },
    "/support/tickets": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List support tickets",
        responses: { "200": { description: "Support tickets" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a support ticket",
        responses: { "201": { description: "Support ticket created" } },
      },
    },
    "/support/tickets/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a support ticket",
        responses: { "200": { description: "Support ticket" } },
      },
    },
    "/support/tickets/{id}/assignment": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Assign a support agent",
        responses: { "200": { description: "Ticket assigned" } },
      },
    },
    "/support/tickets/{id}/status": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Update ticket status",
        responses: { "200": { description: "Ticket updated" } },
      },
    },
    "/support/tickets/{id}/messages": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Post a ticket message",
        responses: { "201": { description: "Message created" } },
      },
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List ticket messages",
        responses: { "200": { description: "Ticket messages" } },
      },
    },
    "/support/tickets/{id}/internal-notes": {
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Add an internal support note",
        responses: { "201": { description: "Internal note created" } },
      },
    },
    "/support/tickets/{id}/escalate": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Escalate a support ticket",
        responses: { "200": { description: "Ticket escalated" } },
      },
    },
    "/support/tickets/{id}/resolve": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Resolve a support ticket",
        responses: { "200": { description: "Ticket resolved" } },
      },
    },
    "/support/tickets/{id}/rating": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Rate a resolved ticket",
        responses: { "200": { description: "Rating saved" } },
      },
    },
    "/support/knowledge-base": {
      get: {
        summary: "List published knowledge-base articles",
        responses: { "200": { description: "Knowledge-base articles" } },
      },
    },
    "/support/knowledge-base/{id}": {
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Create or update a knowledge-base article",
        responses: { "200": { description: "Knowledge-base article saved" } },
      },
    },
    "/support/reports/summary": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return support analytics",
        responses: { "200": { description: "Support analytics" } },
      },
    },
    "/compliance/regulatory-bodies": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List regulatory bodies",
        responses: { "200": { description: "Regulatory bodies" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a regulatory body",
        responses: { "201": { description: "Regulatory body created" } },
      },
    },
    "/incidents": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List incidents and safety events",
        responses: { "200": { description: "Incidents" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create an incident report",
        responses: { "201": { description: "Incident created" } },
      },
    },
    "/incidents/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return an incident record",
        responses: { "200": { description: "Incident" } },
      },
    },
    "/incidents/{id}/close": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Close an incident workflow",
        responses: { "200": { description: "Incident closed" } },
      },
    },
    "/incidents/{id}/investigate": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Start incident investigation",
        responses: { "200": { description: "Incident investigation started" } },
      },
    },
    "/incidents/{id}/root-cause": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Record root cause and corrective action",
        responses: { "200": { description: "Incident root cause recorded" } },
      },
    },
    "/incidents/{id}/follow-ups": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List incident follow-up entries",
        responses: { "200": { description: "Incident follow-ups" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create an incident follow-up entry",
        responses: { "201": { description: "Incident follow-up recorded" } },
      },
    },
    "/incidents/statistics": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return incident safety statistics",
        responses: { "200": { description: "Statistics" } },
      },
    },
    "/documents": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List stored documents",
        responses: { "200": { description: "Documents" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Upload and register a document",
        responses: { "201": { description: "Document created" } },
      },
    },
    "/documents/{id}": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Return a document record",
        responses: { "200": { description: "Document" } },
      },
    },
    "/documents/{id}/approve": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Approve a document",
        responses: { "200": { description: "Document approved" } },
      },
    },
    "/documents/{id}/archive": {
      patch: {
        security: [{ firebaseAuth: [] }],
        summary: "Archive a document",
        responses: { "200": { description: "Document archived" } },
      },
    },
    "/documents/{id}/versions": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List document versions",
        responses: { "200": { description: "Document versions" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Add a document version",
        responses: { "201": { description: "Document version created" } },
      },
    },
    "/documents/{id}/audit": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List document audit trail entries",
        responses: { "200": { description: "Document audit events" } },
      },
    },
    "/documents/expiring": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List documents nearing expiry",
        responses: { "200": { description: "Expiring documents" } },
      },
    },
    "/compliance/licences": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List licences",
        responses: { "200": { description: "Licences" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a compliance licence",
        responses: { "201": { description: "Licence created" } },
      },
    },
    "/compliance/certifications": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List recycler certifications",
        responses: { "200": { description: "Certifications" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a recycler certification",
        responses: { "201": { description: "Certification created" } },
      },
    },
    "/compliance/checklists": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List compliance checklists",
        responses: { "200": { description: "Checklists" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a compliance checklist",
        responses: { "201": { description: "Checklist created" } },
      },
    },
    "/compliance/inspections": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List compliance inspections",
        responses: { "200": { description: "Inspections" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Schedule a compliance inspection",
        responses: { "201": { description: "Inspection scheduled" } },
      },
    },
    "/compliance/violations": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List compliance violations",
        responses: { "200": { description: "Violations" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Report a compliance violation",
        responses: { "201": { description: "Violation reported" } },
      },
    },
    "/compliance/corrective-actions": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List corrective action plans",
        responses: { "200": { description: "Corrective actions" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a corrective action plan",
        responses: { "201": { description: "Corrective action created" } },
      },
    },
    "/compliance/penalties": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List penalty records",
        responses: { "200": { description: "Penalties" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a penalty record",
        responses: { "201": { description: "Penalty created" } },
      },
    },
    "/compliance/certificates": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List environmental certificates",
        responses: { "200": { description: "Certificates" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create an environmental certificate",
        responses: { "201": { description: "Certificate created" } },
      },
    },
    "/compliance/expiry-alerts": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List document expiry alerts",
        responses: { "200": { description: "Expiry alerts" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a document expiry alert",
        responses: { "201": { description: "Expiry alert created" } },
      },
    },
    "/compliance/submissions": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "List regulatory submissions",
        responses: { "200": { description: "Submissions" } },
      },
      post: {
        security: [{ firebaseAuth: [] }],
        summary: "Create a regulatory submission",
        responses: { "201": { description: "Submission created" } },
      },
    },
    "/compliance/score": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Get compliance score",
        responses: { "200": { description: "Compliance score" } },
      },
      put: {
        security: [{ firebaseAuth: [] }],
        summary: "Set compliance score",
        responses: { "200": { description: "Compliance score updated" } },
      },
    },
    "/audit/events": {
      get: {security: [{firebaseAuth: []}], summary: "Search and filter tamper-evident audit records", responses: {"200": {description: "Audit records"}}},
      post: {security: [{firebaseAuth: []}], summary: "Record a user or system activity", responses: {"201": {description: "Audit event recorded"}}},
    },
    "/audit/export": {
      get: {security: [{firebaseAuth: []}], summary: "Export filtered audit records as JSON or CSV", responses: {"200": {description: "Audit export"}}},
    },
    "/audit/integrity": {
      get: {security: [{firebaseAuth: []}], summary: "Verify the audit SHA-256 hash chain", responses: {"200": {description: "Integrity result"}}},
    },
    "/administration/dashboard": {
      get: {security: [{firebaseAuth: []}], summary: "Get administrative platform totals", responses: {"200": {description: "Administration dashboard"}}},
    },
    "/administration/users": {
      get: {security: [{firebaseAuth: []}], summary: "List authentication users and profiles", responses: {"200": {description: "Users"}}},
    },
    "/administration/users/{uid}": {
      patch: {security: [{firebaseAuth: []}], summary: "Update or suspend a user", responses: {"200": {description: "User updated"}}},
    },
    "/administration/users/{uid}/role": {
      put: {security: [{firebaseAuth: []}], summary: "Assign a role and synchronize Firebase claims", responses: {"200": {description: "Role assigned"}}},
    },
    "/administration/roles": {
      get: {security: [{firebaseAuth: []}], summary: "List roles and their permissions", responses: {"200": {description: "Roles"}}},
    },
    "/administration/roles/{role}": {
      put: {security: [{firebaseAuth: []}], summary: "Configure a role and permissions", responses: {"200": {description: "Role configured"}}},
    },
    "/administration/permissions": {
      get: {security: [{firebaseAuth: []}], summary: "List platform permissions", responses: {"200": {description: "Permissions"}}},
    },
    "/administration/permissions/{code}": {
      put: {security: [{firebaseAuth: []}], summary: "Create or update a permission", responses: {"200": {description: "Permission configured"}}},
    },
    "/administration/catalogs/{catalog}": {
      get: {security: [{firebaseAuth: []}], summary: "List configurable catalog items", responses: {"200": {description: "Catalog items"}}},
      post: {security: [{firebaseAuth: []}], summary: "Create a catalog item", responses: {"201": {description: "Catalog item created"}}},
    },
    "/administration/catalogs/{catalog}/{id}": {
      put: {security: [{firebaseAuth: []}], summary: "Update a catalog item", responses: {"200": {description: "Catalog item updated"}}},
      delete: {security: [{firebaseAuth: []}], summary: "Archive a catalog item", responses: {"200": {description: "Catalog item archived"}}},
    },
    "/administration/configuration/{name}": {
      get: {security: [{firebaseAuth: []}], summary: "Read formulas, system settings, or integrations", responses: {"200": {description: "Configuration"}}},
      put: {security: [{firebaseAuth: []}], summary: "Update formulas, system settings, or integrations", responses: {"200": {description: "Configuration updated"}}},
    },
    "/administration/health": {
      get: {security: [{firebaseAuth: []}], summary: "Monitor platform health", responses: {"200": {description: "Platform health"}}},
    },
    "/compliance/audit-report": {
      get: {
        security: [{ firebaseAuth: [] }],
        summary: "Generate an audit-ready compliance report",
        responses: { "200": { description: "Audit-ready report" } },
      },
    },
  },
};
