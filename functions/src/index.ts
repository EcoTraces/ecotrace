import {setGlobalOptions} from "firebase-functions/v2";
import {onRequest} from "firebase-functions/v2/https";
import {app} from "./app.js";

setGlobalOptions({region: "europe-west1", maxInstances: 10});

export const api = onRequest({timeoutSeconds: 60, memory: "256MiB"}, app);
export {
  notifyPickupCreated,
  notifyPickupStatusChanged,
  notifyScheduleCreated,
  notifyScheduleStatusChanged,
} from "./notifications.js";
export {deliverScheduledReports} from "./report-scheduler.js";
export {sendScheduledReminders} from "./reminder-scheduler.js";
