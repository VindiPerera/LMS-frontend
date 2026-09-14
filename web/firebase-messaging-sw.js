// Firebase Cloud Messaging background-message service worker for the
// "hello-52f9b" project — kept in sync with lib/firebase_options.dart's
// `web` FirebaseOptions (this is a plain JS file served statically, so it
// can't import that Dart file and needs its own copy of the config).
//
// This only handles messages that arrive while the app/tab is closed or in
// the background. Foreground messages are handled in Dart, in
// lib/services/push_notification_service.dart.

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDGyKutN7gNC4H65mM7C4KlZ7aJDC1ZLJE',
  appId: '1:867397619439:web:6f23e33a8ecb147f8c951a',
  messagingSenderId: '867397619439',
  projectId: 'hello-52f9b',
  authDomain: 'hello-52f9b.firebaseapp.com',
  storageBucket: 'hello-52f9b.firebasestorage.app',
});

firebase.messaging();
