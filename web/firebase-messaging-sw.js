// Firebase Cloud Messaging background-message service worker for the
// "hello-82bf9" project — kept in sync with lib/firebase_options.dart's
// `web` FirebaseOptions (this is a plain JS file served statically, so it
// can't import that Dart file and needs its own copy of the config).
//
// This only handles messages that arrive while the app/tab is closed or in
// the background. Foreground messages are handled in Dart, in
// lib/services/push_notification_service.dart.

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCEfR5H68krQG3f21bZDl1JhDBvaZjUTRU',
  appId: '1:227063183986:web:1bedc1dde53d82c048e0eb',
  messagingSenderId: '227063183986',
  projectId: 'hello-82bf9',
  authDomain: 'hello-82bf9.firebaseapp.com',
  storageBucket: 'hello-82bf9.firebasestorage.app',
});

firebase.messaging();
