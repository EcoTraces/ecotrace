import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {db} from "./firebase.js";

const at = (date: Date) => Timestamp.fromDate(date);

/// Creates deterministic, dashboard-safe records. Re-running refreshes the
/// same demo documents instead of endlessly duplicating test data.
export async function seedDemoData(actorId: string) {
  const now = new Date();
  const users = await db.collection("users").get();
  const byRole = new Map<string, string[]>();
  for (const user of users.docs) {
    const role = String(user.get("role") ?? "household");
    byRole.set(role, [...(byRole.get(role) ?? []), user.id]);
  }
  const citizens = [
    ...(byRole.get("household") ?? []),
    ...(byRole.get("business") ?? []),
    ...(byRole.get("institution") ?? []),
  ];
  const drivers = byRole.get("driver") ?? [];
  const collectors = byRole.get("collector") ?? [];
  const technicians = byRole.get("repairTechnician") ?? [];
  const recyclers = byRole.get("recycler") ?? [];
  // BulkWriter keeps the seed safe if more test users are added later; unlike
  // a single batch it is not limited to 500 writes.
  const writer = db.bulkWriter();
  let records = 0;

  const set = (
    collection: string,
    id: string,
    data: Record<string, unknown>,
  ) => {
    writer.set(db.collection(collection).doc(id), {
      ...data,
      demoData: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    records++;
  };

  const categories = ["phones", "computers", "appliances", "batteries", "televisions", "accessories"];
  const locations = [
    ["Freetown Central", 8.4840, -13.2299],
    ["Waterloo", 8.3386, -13.0710],
    ["Goderich", 8.4271, -13.2870],
    ["Lumley", 8.4657, -13.2799],
    ["Kissy", 8.4705, -13.1859],
    ["Aberdeen", 8.4932, -13.2896],
  ] as const;
  const statuses = ["submitted", "approved", "assigned", "scheduled", "inProgress", "collected"];
  const pickupCount = Math.max(6, citizens.length);
  for (let index = 0; index < pickupCount; index++) {
    const location = locations[index % locations.length];
    set("pickupRequests", `demo-pickup-${index + 1}`, {
      userId: citizens[index % Math.max(citizens.length, 1)] ?? actorId,
      category: categories[index % categories.length],
      quantity: index + 1,
      estimatedWeight: 8 + index * 7,
      condition: index % 2 === 0 ? "Repairable" : "Recyclable",
      location: location[0],
      latitude: location[1],
      longitude: location[2],
      scheduledAt: at(new Date(now.getTime() + (index - 2) * 86400000)),
      urgent: index === 1,
      instructions: "Demo pickup generated for dashboard evaluation.",
      estimatedFee: 18 + index * 6,
      status: statuses[index % statuses.length],
      photoUrls: [],
      rating: index % statuses.length === 5 ? 5 : null,
      createdAt: at(new Date(now.getTime() - (index + 1) * 86400000)),
    });
  }

  for (let index = 0; index < Math.max(3, drivers.length); index++) {
    set("vehicles", `demo-vehicle-${index + 1}`, {
      registrationNumber: `SL-DEMO-${100 + index}`,
      type: index === 0 ? "van" : index === 1 ? "truck" : "pickupTruck",
      capacityKg: 750 + index * 500,
      driverId: drivers[index % Math.max(drivers.length, 1)] ?? "",
      availability: index === 2 ? "maintenance" : "available",
      mileageKm: 12400 + index * 1850,
      fuelLitres: 45 - index * 5,
      insuranceExpiry: at(new Date(now.getTime() + (180 + index * 30) * 86400000)),
      licenceExpiry: at(new Date(now.getTime() + (220 + index * 30) * 86400000)),
      latitude: locations[index][1],
      longitude: locations[index][2],
      createdAt: at(new Date(now.getTime() - 90 * 86400000)),
    });
  }

  const fieldUsers = [...drivers, ...collectors];
  for (let index = 0; index < Math.max(fieldUsers.length, 2); index++) {
    const fieldUser = fieldUsers[index % Math.max(fieldUsers.length, 1)];
    const driverId = drivers.includes(fieldUser) ? fieldUser : drivers[0] ?? actorId;
    const collectorIds = collectors.includes(fieldUser) ? [fieldUser] : collectors.slice(0, 2);
    set("collectionSchedules", `demo-schedule-${index + 1}`, {
      scheduledAt: at(new Date(now.getFullYear(), now.getMonth(), now.getDate(), 9 + index)),
      pickupIds: [`demo-pickup-${index % 6 + 1}`],
      collectorIds,
      driverId,
      vehicleId: `demo-vehicle-${index % 2 + 1}`,
      priority: index === 1 ? "urgent" : "normal",
      status: index % 3 === 0 ? "dispatched" : index % 3 === 1 ? "inProgress" : "completed",
      serviceArea: locations[index % locations.length][0],
      evidenceUrls: [],
      estimatedWeight: 15 + index * 4,
      createdAt: at(new Date(now.getTime() - 86400000)),
    });
  }

  const deviceTypes = ["Mobile Phone", "Laptop", "Television", "Printer", "Battery", "Desktop Computer"];
  for (let index = 0; index < 6; index++) {
    set("inventoryItems", `demo-item-${index + 1}`, {
      itemCode: `ECO-DEMO-${String(index + 1).padStart(3, "0")}`,
      deviceType: deviceTypes[index],
      brand: ["Samsung", "Dell", "LG", "HP", "Generic", "Lenovo"][index],
      model: `Demo Model ${index + 1}`,
      serialNumber: `DEMO-SN-${1000 + index}`,
      condition: index < 2 ? "repairable" : index === 4 ? "hazardous" : "recyclable",
      weight: 3 + index * 5,
      source: locations[index][0],
      currentLocation: index < 2 ? "Repair Bay" : "Main Storage",
      processingStatus: index < 2 ? "assignedForRepair" : "assignedForRecycling",
      batchId: index >= 2 ? "demo-recycling-1" : null,
      imageUrls: [],
      createdAt: at(new Date(now.getTime() - index * 7 * 86400000)),
    });
  }

  for (let index = 0; index < 3; index++) {
    set("repairJobs", `demo-repair-${index + 1}`, {
      itemId: `demo-item-${index % 6 + 1}`,
      itemCode: `ECO-DEMO-${String(index % 6 + 1).padStart(3, "0")}`,
      deviceName: deviceTypes[index % deviceTypes.length],
      status: ["awaitingAssessment", "repairInProgress", "completed"][index % 3],
      assessmentNotes: "Demo assessment completed.",
      diagnosis: index === 0 ? "Power fault" : "Display and battery fault",
      faults: ["Power system", "Worn component"],
      technicianId: technicians[index % Math.max(technicians.length, 1)] ?? actorId,
      estimatedRepairCost: 350 + index * 120,
      actualPartsCost: 100 + index * 80,
      progressPercent: [15, 65, 100][index % 3],
      qualityChecks: {"powersOn": index % 3 === 2, "safe": true},
      qualityNotes: "Demo quality-control record.",
      disposition: index % 3 === 2 ? "resale" : "pending",
      dispositionApproved: index % 3 === 2,
      resalePrice: index % 3 === 2 ? 2100 : null,
      donationRecipient: "",
      createdAt: at(new Date(now.getTime() - (index + 3) * 86400000)),
      completedAt: index % 3 === 2 ? at(new Date(now.getTime() - 86400000)) : null,
    });
  }

  for (let index = 0; index < 3; index++) {
    set("recyclingBatches", `demo-recycling-${index + 1}`, {
      batchCode: `RCY-DEMO-${index + 1}`,
      facilityId: recyclers[index % Math.max(recyclers.length, 1)] ?? actorId,
      facilityName: "EcoTrace Freetown Recycling Facility",
      itemIds: [`demo-item-${index + 3}`],
      itemCodes: [`ECO-DEMO-00${index + 3}`],
      inputWeightKg: 120 + index * 45,
      recoveredWeightKg: 82 + index * 30,
      hazardousWeightKg: 8 + index * 2,
      disposedWeightKg: 15 + index * 4,
      processingLossKg: 5 + index,
      stage: ["sorting", "materialRecovery", "completed"][index],
      completionVerified: index === 2,
      verificationNotes: "Demo batch verification.",
      createdAt: at(new Date(now.getTime() - (10 + index) * 86400000)),
      completedAt: index === 2 ? at(new Date(now.getTime() - 86400000)) : null,
    });
  }

  const materials = ["copper", "aluminium", "plastic", "circuitBoards"];
  for (let index = 0; index < 4; index++) {
    set("recoveredMaterialLots", `demo-material-${index + 1}`, {
      lotCode: `MAT-DEMO-${index + 1}`,
      recyclingBatchId: `demo-recycling-${index % 3 + 1}`,
      recyclingBatchCode: `RCY-DEMO-${index % 3 + 1}`,
      material: materials[index],
      weightKg: 18 + index * 11,
      quantity: 10 + index * 5,
      qualityGrade: index < 2 ? "gradeA" : "mixed",
      storageLocation: "Recovery Store A",
      unitMarketValue: 35 + index * 22,
      buyerId: "",
      status: index < 2 ? "salesReady" : "stored",
      saleRevenue: 0,
      createdAt: at(new Date(now.getTime() - index * 2 * 86400000)),
    });
  }

  set("hazardousWasteRecords", "demo-hazardous-1", {
    wasteType: "Lithium batteries",
    classification: "flammable",
    weightKg: 26,
    status: "certified",
    storageLocation: "Hazardous Store H1",
    certifiedAt: at(new Date(now.getTime() - 86400000)),
    createdAt: at(new Date(now.getTime() - 8 * 86400000)),
  });
  set("hazardousWasteRecords", "demo-hazardous-2", {
    wasteType: "CRT glass",
    classification: "toxic",
    weightKg: 42,
    status: "identified",
    storageLocation: "Hazardous Store H2",
    createdAt: at(new Date(now.getTime() - 5 * 86400000)),
  });

  for (let index = 0; index < 3; index++) {
    set("complianceInspections", `demo-inspection-${index + 1}`, {
      entityName: ["Freetown Centre", "Demo Recycler", "Waterloo Storage"][index],
      regulatoryBodyId: "demo-regulator",
      inspectorName: "Environmental Officer",
      scheduledAt: at(new Date(now.getTime() + (index - 1) * 86400000)),
      completedAt: index < 2 ? at(new Date(now.getTime() - index * 86400000)) : null,
      status: index < 2 ? "completed" : "scheduled",
      checklist: {"safeStorage": true, "ppeAvailable": index !== 1},
      score: 82 + index * 6,
      findings: "Demo inspection findings.",
      recommendations: "Continue monthly safety monitoring.",
      reportUrls: [],
      createdAt: at(new Date(now.getTime() - 4 * 86400000)),
    });
  }
  set("complianceViolations", "demo-violation-1", {
    referenceNumber: "VIO-DEMO-001",
    entityName: "Demo Recycler",
    requirement: "Safe storage",
    description: "Battery storage signage requires improvement.",
    severity: "minor",
    status: "correctiveAction",
    correctiveActionPlan: "Install compliant signage.",
    correctiveActionOwner: "Facility manager",
    correctiveActionDueAt: at(new Date(now.getTime() + 7 * 86400000)),
    resolutionEvidence: "",
    reportedAt: at(new Date(now.getTime() - 2 * 86400000)),
    createdAt: at(new Date(now.getTime() - 2 * 86400000)),
  });

  for (let index = 0; index < 2; index++) {
    set("servicePartners", `demo-partner-${index + 1}`, {
      name: index === 0 ? "GreenCycle Sierra Leone" : "Freetown Repair Hub",
      partnerCode: `PARTNER-DEMO-${index + 1}`,
      type: index === 0 ? "recycler" : "repairCentre",
      contactName: "Operations Manager",
      contactEmail: `partner${index + 1}@ecotrace.demo`,
      contactPhone: `+232 77 000 20${index}`,
      address: locations[index][0],
      serviceCategories: index === 0 ? ["electronicsRecycling"] : ["deviceRepair"],
      status: "active",
      licenceStatus: "verified",
      pricingInformation: "Contract pricing",
      currency: "SLE",
      paymentMethod: "bank",
      payeeName: index === 0 ? "GreenCycle Sierra Leone" : "Freetown Repair Hub",
      paymentTerms: "Net 30",
      suspensionReason: "",
      serviceAreas: ["Freetown", "Western Area"],
      facilityCapacityKg: 3500 + index * 1500,
      performanceRating: 4.4 + index * .2,
      complianceScore: 91 + index * 3,
      completedServiceCount: 28 + index * 9,
      onTimeServiceCount: 25 + index * 8,
      totalSpend: 14500 + index * 8000,
      createdAt: at(new Date(now.getTime() - 120 * 86400000)),
    });
  }

  for (let index = 0; index < 2; index++) {
    set("collectionCentres", `demo-centre-${index + 1}`, {
      name: index === 0 ? "Freetown EcoTrace Centre" : "Waterloo Collection Centre",
      address: locations[index][0],
      contactName: "Centre Manager",
      contactEmail: `centre${index + 1}@ecotrace.demo`,
      contactPhone: `+232 76 000 10${index}`,
      latitude: locations[index][1],
      longitude: locations[index][2],
      operatingHours: {"Monday-Friday": "08:00-17:00", "Saturday": "09:00-14:00"},
      supportedCategories: categories,
      capacityKg: 5000 + index * 2500,
      currentStockKg: 1280 + index * 540,
      capacityAlertPercent: 80,
      active: true,
      createdAt: at(new Date(now.getTime() - 180 * 86400000)),
    });
  }

  for (const uid of citizens) {
    set("rewardWallets", uid, {
      balance: 850,
      lifetimePoints: 1250,
      level: "greenAdvocate",
      referralCode: `ECO-${uid.slice(0, 6).toUpperCase()}`,
      businessSustainabilityScore: 82,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  const activityByRole: Record<string, Array<[string, string, string]>> = {
    household: [
      ["create", "pickupRequest", "Submitted an e-waste pickup request"],
      ["update", "pickupRequest", "Updated pickup instructions"],
      ["system", "rewardWallet", "Earned green participation points"],
    ],
    business: [
      ["create", "bulkPickup", "Scheduled a business bulk pickup"],
      ["update", "sustainabilityScore", "Business sustainability score updated"],
      ["system", "environmentalCertificate", "Environmental certificate generated"],
    ],
    institution: [
      ["create", "institutionPickup", "Submitted an institutional collection request"],
      ["update", "inventoryDeclaration", "Updated institutional e-waste declaration"],
      ["system", "impactReport", "Institutional impact report generated"],
    ],
    driver: [
      ["update", "collectionSchedule", "Collection route assigned"],
      ["itemMovement", "routePlan", "Reached a scheduled pickup stop"],
      ["update", "vehicle", "Vehicle location and mileage updated"],
    ],
    collector: [
      ["update", "collectionSchedule", "Collection assignment received"],
      ["itemMovement", "pickupRequest", "Pickup weight recorded"],
      ["update", "pickupRequest", "Collection proof confirmed"],
    ],
    repairTechnician: [
      ["create", "repairJob", "Repair assessment created"],
      ["update", "repairJob", "Repair progress updated"],
      ["approve", "qualityControl", "Device passed quality control"],
    ],
    recycler: [
      ["create", "recyclingBatch", "Recycling batch created"],
      ["itemMovement", "recoveredMaterial", "Recovered material recorded"],
      ["approve", "recyclingCertificate", "Recycling completion verified"],
    ],
    environmentalOfficer: [
      ["create", "complianceInspection", "Environmental inspection recorded"],
      ["update", "complianceViolation", "Corrective action reviewed"],
      ["system", "impactReport", "Environmental impact report generated"],
    ],
    collectionCentreOperator: [
      ["itemMovement", "receivingRecord", "E-waste checked into the centre"],
      ["update", "storageSection", "Storage capacity verified"],
      ["create", "safetyInspection", "Centre safety inspection completed"],
    ],
    partner: [
      ["create", "serviceRecord", "Partner service assignment accepted"],
      ["update", "serviceRecord", "Partner service progress updated"],
      ["approve", "serviceLevelAgreement", "Service-level target completed"],
    ],
    administrator: [
      ["approve", "pickupRequest", "Pickup request approved"],
      ["roleChange", "user", "User role assignment reviewed"],
      ["configurationChange", "systemConfiguration", "Platform settings updated"],
    ],
    superAdministrator: [
      ["permissionChange", "systemRole", "Role permissions reviewed"],
      ["security", "auditLog", "Security activity reviewed"],
      ["configurationChange", "systemConfiguration", "Platform configuration verified"],
    ],
  };

  for (const user of users.docs) {
    const role = String(user.get("role") ?? "household");
    const name = String(user.get("displayName") ?? user.get("email") ?? user.id);
    const activities = activityByRole[role] ?? [
      ["system", "platformActivity", "EcoTrace operational activity recorded"],
      ["update", "profile", "Account activity updated"],
      ["create", "serviceRecord", "New service event created"],
    ];
    for (let index = 0; index < 15; index++) {
      const [action, entityType, description] = activities[index % activities.length];
      const eventAt = at(new Date(now.getTime() - index * 3 * 60 * 60 * 1000));
      const eventId = "demo-event-" + String(index + 1).padStart(2, "0");
      writer.set(user.ref.collection("activityEvents").doc(eventId), {
        action,
        entityType,
        entityId: eventId,
        description,
        actorId: user.id,
        actorName: name,
        actorRole: role,
        success: true,
        demoData: true,
        createdAt: eventAt,
      }, {merge: true});
      writer.set(user.ref.collection("notifications").doc(eventId), {
        type: index % 3 === 0 ? "assignment" : index % 3 === 1 ? "statusUpdate" : "general",
        title: description,
        body: "Sample " + role + " event " + (index + 1) + " of 15.",
        read: index >= 5,
        data: {demoData: true, entityType, eventId},
        createdAt: eventAt,
      }, {merge: true});
      records += 2;
    }
  }

  const userDocs = users.docs.length === 0 ? [] : users.docs;
  for (let index = 0; index < 15 && userDocs.length > 0; index++) {
    const user = userDocs[index % userDocs.length];
    const role = String(user.get("role") ?? "household");
    const activities = activityByRole[role] ?? activityByRole.household;
    const [action, entityType, description] = activities[index % activities.length];
    set("auditLogs", "demo-audit-" + String(index + 1).padStart(2, "0"), {
      actorId: user.id,
      actorName: String(user.get("displayName") ?? user.get("email") ?? user.id),
      actorRole: role,
      action,
      entityType,
      entityId: "demo-entity-" + (index + 1),
      description,
      changes: {demoData: {before: false, after: true}},
      ipAddress: "127.0.0.1",
      deviceInformation: "EcoTrace demo-data generator",
      success: true,
      severity: index % 5 === 0 ? "notice" : "information",
      source: "server",
      integrityVersion: 1,
      createdAt: at(new Date(now.getTime() - index * 2 * 60 * 60 * 1000)),
    });
  }

  for (let index = 0; index < 15; index++) {
    const vehicleId = "demo-vehicle-" + (index % Math.max(3, drivers.length) + 1);
    writer.set(db.collection("vehicles").doc(vehicleId).collection("events").doc("demo-event-" + (index + 1)), {
      type: ["inspection", "fuel", "mileage", "location", "maintenance"][index % 5],
      details: "Demo vehicle operational event " + (index + 1),
      actorId: drivers[index % Math.max(drivers.length, 1)] ?? actorId,
      demoData: true,
      createdAt: at(new Date(now.getTime() - index * 4 * 60 * 60 * 1000)),
    }, {merge: true});
    records++;
  }

  for (let index = 0; index < 15; index++) {
    const eventAt = at(new Date(now.getTime() - index * 5 * 60 * 60 * 1000));
    const partnerId = "demo-partner-" + (index % 2 + 1);
    writer.set(db.collection("servicePartners").doc(partnerId).collection("serviceRecords").doc("demo-service-" + (index + 1)), {
      reference: "SERVICE-DEMO-" + String(index + 1).padStart(3, "0"),
      serviceCategory: index % 2 === 0 ? "electronicsRecycling" : "deviceRepair",
      targetHours: 48,
      actualHours: 24 + index,
      qualityRating: 4 + index % 5 * 0.2,
      serviceCost: 850 + index * 75,
      notes: "Demo partner service completed for dashboard evaluation.",
      demoData: true,
      completedAt: eventAt,
      createdAt: eventAt,
    }, {merge: true});
    const repairId = "demo-repair-" + (index % 3 + 1);
    writer.set(db.collection("repairJobs").doc(repairId).collection("progress").doc("demo-progress-" + (index + 1)), {
      type: ["assessment", "diagnosis", "repair", "qualityControl", "completed"][index % 5],
      details: "Demo technician workflow event " + (index + 1),
      progressPercent: Math.min(100, (index + 1) * 7),
      actorId: technicians[index % Math.max(technicians.length, 1)] ?? actorId,
      demoData: true,
      createdAt: eventAt,
    }, {merge: true});
    const recyclingId = "demo-recycling-" + (index % 3 + 1);
    writer.set(db.collection("recyclingBatches").doc(recyclingId).collection("processRecords").doc("demo-process-" + (index + 1)), {
      type: ["sorting", "dismantling", "separation", "recovery", "verification"][index % 5],
      material: materials[index % materials.length],
      component: deviceTypes[index % deviceTypes.length],
      quantity: 5 + index,
      weightKg: 4 + index * 1.5,
      notes: "Demo recycler processing event " + (index + 1),
      actorId: recyclers[index % Math.max(recyclers.length, 1)] ?? actorId,
      demoData: true,
      createdAt: eventAt,
    }, {merge: true});
    records += 3;
  }

  await writer.close();
  return {
    records,
    users: users.size,
    roles: Object.fromEntries([...byRole.entries()].map(([role, ids]) => [role, ids.length])),
  };
}
