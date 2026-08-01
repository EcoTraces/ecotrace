/* EcoTrace Firebase Messaging background service worker. */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAGK7r7U3dzAaWR3cFzBmG2rMO4tQX7i5g',
  appId: '1:900123114350:web:23b7ccb9629b7e48efdf7f',
  messagingSenderId: '900123114350',
  projectId: 'wastemanagementsystem-902eb',
  authDomain: 'wastemanagementsystem-902eb.firebaseapp.com',
  storageBucket: 'wastemanagementsystem-902eb.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  // FCM displays notification payloads automatically. Handle only data-only
  // messages here to avoid showing the same notification twice.
  if (payload.notification) return;
  const data = payload.data || {};
  const title = data.title || 'EcoTrace';
  self.registration.showNotification(title, {
    body: data.body || 'You have a new EcoTrace update.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data,
    tag: data.type || 'ecotrace-update',
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({type: 'window', includeUncontrolled: true}).then((windows) => {
      for (const windowClient of windows) {
        if ('focus' in windowClient) return windowClient.focus();
      }
      return clients.openWindow('/');
    }),
  );
});
