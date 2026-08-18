/**
 * Cloud Functions for FaceTalk's Moments feature.
 *
 * Schema note: unlike a flat `userId`/`userName`/`userAvatar` shape, this
 * app denormalizes the author onto every moments/comments/notifications doc
 * as a `user`/`actor` object ({ id, name, avatarUrl, ... }) — the same shape
 * AppUser already uses on the Flutter side (see lib/models/moment.dart and
 * lib/services/moment_service.dart). All functions below read/write that
 * shape rather than separate flat fields.
 */

const { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } =
  require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const { setGlobalOptions } = require("firebase-functions/v2");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
setGlobalOptions({ maxInstances: 10, region: "us-central1" });

const db = getFirestore();

// ----------------------------------------------------------------------
// Shared helpers
// ----------------------------------------------------------------------

/** Writes one notification doc under notifications/{uid}/items. */
async function writeNotification(uid, payload) {
  if (!uid) return;
  const ref = db.collection("notifications").doc(uid).collection("items").doc();
  await ref.set({
    notifId: ref.id,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    ...payload,
  });
}

/** Sends an FCM push to a single user's registered token, if any. Never
 * throws — a missing/stale token should not fail the triggering write. */
async function sendPushToUser(uid, { title, body, data }) {
  if (!uid) return;
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    const token = userSnap.exists ? userSnap.get("fcmToken") : null;
    if (!token) return;

    await getMessaging().send({
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v)])
      ),
    });
  } catch (err) {
    logger.warn(`sendPushToUser(${uid}) failed, continuing`, err);
  }
}

/** Best-effort commentCount adjustment that never goes below 0. */
async function adjustCommentCount(postId, delta) {
  const postRef = db.collection("moments").doc(postId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(postRef);
    if (!snap.exists) return;
    const current = snap.get("commentCount") || 0;
    tx.update(postRef, { commentCount: Math.max(0, current + delta) });
  });
}

/** Best-effort reshareCount adjustment that never goes below 0. */
async function adjustReshareCount(postId, delta) {
  const postRef = db.collection("moments").doc(postId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(postRef);
    if (!snap.exists) return;
    const current = snap.get("reshareCount") || 0;
    tx.update(postRef, { reshareCount: Math.max(0, current + delta) });
  });
}

// ----------------------------------------------------------------------
// 1. onCommentCreate
// ----------------------------------------------------------------------
exports.onCommentCreate = onDocumentCreated(
  "moments/{postId}/comments/{commentId}",
  async (event) => {
    const { postId } = event.params;
    const comment = event.data.data();
    if (!comment) return;

    await adjustCommentCount(postId, 1);

    const postSnap = await db.collection("moments").doc(postId).get();
    if (!postSnap.exists) return;
    const post = postSnap.data();
    const postOwnerId = post.user?.id;
    // Comment authors are stored flat (userId/userName/userAvatar) — see
    // lib/models/comment_model.dart — unlike the nested `user` object on
    // moments/notifications.
    const commenterId = comment.userId;

    if (postOwnerId && postOwnerId !== commenterId) {
      await writeNotification(postOwnerId, {
        type: "comment",
        actorId: commenterId,
        actorName: comment.userName || "Someone",
        actorAvatar: comment.userAvatar || "",
        postId,
      });
      await sendPushToUser(postOwnerId, {
        title: comment.userName || "Someone",
        body: `commented: ${truncate(comment.text)}`,
        data: { type: "comment", postId },
      });
    }

    const mentioned = Array.isArray(comment.mentionedUserIds)
      ? comment.mentionedUserIds
      : [];
    for (const mentionedUid of mentioned) {
      if (!mentionedUid || mentionedUid === commenterId) continue;
      await writeNotification(mentionedUid, {
        type: "mention",
        actorId: commenterId,
        actorName: comment.userName || "Someone",
        actorAvatar: comment.userAvatar || "",
        postId,
      });
      await sendPushToUser(mentionedUid, {
        title: comment.userName || "Someone",
        body: `mentioned you: ${truncate(comment.text)}`,
        data: { type: "mention", postId },
      });
    }
  }
);

function truncate(text, max = 80) {
  if (!text) return "";
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

// ----------------------------------------------------------------------
// 2. onCommentDelete
// ----------------------------------------------------------------------
exports.onCommentDelete = onDocumentDeleted(
  "moments/{postId}/comments/{commentId}",
  async (event) => {
    await adjustCommentCount(event.params.postId, -1);
  }
);

// ----------------------------------------------------------------------
// 3. onReshare
// ----------------------------------------------------------------------
exports.onReshare = onDocumentCreated("moments/{postId}", async (event) => {
  const post = event.data.data();
  if (!post || post.isReshare !== true || !post.originalPostId) return;

  await adjustReshareCount(post.originalPostId, 1);

  const originalSnap = await db
    .collection("moments")
    .doc(post.originalPostId)
    .get();
  if (!originalSnap.exists) return;
  const original = originalSnap.data();
  const originalOwnerId = original.user?.id;
  const resharerId = post.user?.id;

  if (originalOwnerId && originalOwnerId !== resharerId) {
    await writeNotification(originalOwnerId, {
      type: "reshare",
      actorId: resharerId,
      actorName: post.user?.name || "Someone",
      actorAvatar: post.user?.avatarUrl || "",
      postId: post.originalPostId,
    });
    await sendPushToUser(originalOwnerId, {
      title: post.user?.name || "Someone",
      body: "reshared your moment",
      data: { type: "reshare", postId: post.originalPostId },
    });
  }
});

// ----------------------------------------------------------------------
// 4. onPostDelete
// ----------------------------------------------------------------------
exports.onPostDelete = onDocumentDeleted("moments/{postId}", async (event) => {
  const { postId } = event.params;
  const post = event.data.data();
  if (!post) return;

  // Storage cleanup: media_service.dart uploads everything for a post under
  // moments/{uid}/{postId}/..., so a single prefix delete covers images,
  // video, and the video thumbnail without needing to parse each URL.
  const ownerId = post.user?.id;
  if (ownerId) {
    try {
      await getStorage().bucket().deleteFiles({
        prefix: `moments/${ownerId}/${postId}/`,
      });
    } catch (err) {
      logger.warn(`Storage cleanup failed for moments/${postId}`, err);
    }
  }

  // Comment subcollection cleanup.
  try {
    await db.recursiveDelete(db.collection("moments").doc(postId).collection("comments"));
  } catch (err) {
    logger.warn(`Comment cleanup failed for moments/${postId}`, err);
  }

  // If this was a reshare, give back the count it added to the original.
  if (post.isReshare === true && post.originalPostId) {
    await adjustReshareCount(post.originalPostId, -1);
  }
});

// ----------------------------------------------------------------------
// 5. onUserProfileUpdate — fan out name/avatar changes to that user's posts
// ----------------------------------------------------------------------
exports.onUserProfileUpdate = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;

  const nameChanged = before.name !== after.name;
  const avatarChanged = before.avatarUrl !== after.avatarUrl;
  if (!nameChanged && !avatarChanged) return;

  const { uid } = event.params;
  const postsSnap = await db
    .collection("moments")
    .where("user.id", "==", uid)
    .get();
  if (postsSnap.empty) return;

  // Firestore batches cap at 500 writes; chunk defensively.
  const docs = postsSnap.docs;
  for (let i = 0; i < docs.length; i += 500) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 500)) {
      batch.update(doc.ref, {
        "user.name": after.name,
        "user.avatarUrl": after.avatarUrl,
      });
    }
    await batch.commit();
  }
});

// ----------------------------------------------------------------------
// 6. rateLimitPostCreate — max 5 posts per user per rolling hour
// ----------------------------------------------------------------------
exports.rateLimitPostCreate = onDocumentCreated("moments/{postId}", async (event) => {
  const { postId } = event.params;
  const post = event.data.data();
  const uid = post?.user?.id;
  if (!uid) return;

  const oneHourAgo = Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
  const recentSnap = await db
    .collection("moments")
    .where("user.id", "==", uid)
    .where("isDeleted", "==", false)
    .where("createdAt", ">=", oneHourAgo)
    .get();

  if (recentSnap.size > 5) {
    logger.warn(
      `Rate limit: user ${uid} created ${recentSnap.size} posts in the last hour, deleting ${postId}`
    );
    await db.collection("moments").doc(postId).delete();
  }
});

// ----------------------------------------------------------------------
// Bonus: onReportCreate — keeps reportCount on the post in sync. Not in the
// original spec's function list, but reportCount exists on the moments
// schema and nothing else would ever populate it.
// ----------------------------------------------------------------------
exports.onReportCreate = onDocumentCreated("reports/{reportId}", async (event) => {
  const report = event.data.data();
  if (!report?.postId) return;

  const postRef = db.collection("moments").doc(report.postId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(postRef);
    if (!snap.exists) return;
    const current = snap.get("reportCount") || 0;
    tx.update(postRef, { reportCount: current + 1 });
  });
});

// ----------------------------------------------------------------------
// Bonus: onChatMessageCreate — push notification for a new 1:1 chat
// message. Not part of the original Moments spec, but chat had zero push
// support (only the in-app unread badge — see chat_service.dart's
// streamTotalUnread) until this: the recipient now gets notified even while
// the app is backgrounded or they're sitting on a different tab. No
// in-app `notifications/{uid}/items` entry is written here on purpose —
// that feed (notification_screen.dart) is Moments-flavored (renders a
// post thumbnail, taps open a post) and chat already has its own read/
// unread model per-thread; mixing the two would need a screen rewrite for
// no real benefit over the existing chat badge.
// ----------------------------------------------------------------------
exports.onChatMessageCreate = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const { chatId } = event.params;
    const message = event.data.data();
    if (!message) return;

    const senderId = message.senderId;
    // sendMessage() (chat_service.dart) stores the sorted participant pair
    // on every message doc, so the recipient can be read straight off it
    // without an extra fetch of the parent chat document.
    const participants = Array.isArray(message.participants) ? message.participants : [];
    const recipientId = participants.find((id) => id && id !== senderId);
    if (!recipientId || !senderId) return;

    let senderName = "Someone";
    try {
      const chatSnap = await db.collection("chats").doc(chatId).get();
      senderName = chatSnap.get(`participantInfo.${senderId}.name`) || senderName;
    } catch (err) {
      logger.warn(`onChatMessageCreate: couldn't read sender name for chat ${chatId}`, err);
    }

    const body = message.type === "text" ? truncate(message.text) : "Sent you a message";

    await sendPushToUser(recipientId, {
      title: senderName,
      body,
      data: { type: "chat", chatId, senderId },
    });
  }
);

// ----------------------------------------------------------------------
// Bonus: onFriendRequestCreate — notifies the recipient of a new friend
// request. Triggers on users/{uid}/friend_requests/{requestId} — written
// under the RECIPIENT's own uid by the sender (see
// FriendService.sendFriendRequest), so `uid` here IS the recipient.
// ----------------------------------------------------------------------
exports.onFriendRequestCreate = onDocumentCreated(
  "users/{uid}/friend_requests/{requestId}",
  async (event) => {
    const { uid } = event.params;
    const request = event.data.data();
    if (!request?.fromUserId) return;

    const senderSnap = await db.collection("users").doc(request.fromUserId).get();
    const sender = senderSnap.exists ? senderSnap.data() : {};
    const senderName = sender?.name || "Someone";

    await writeNotification(uid, {
      type: "friendRequest",
      actorId: request.fromUserId,
      actorName: senderName,
      actorAvatar: sender?.avatarUrl || "",
      postId: "",
    });
    await sendPushToUser(uid, {
      title: senderName,
      body: "sent you a friend request",
      data: { type: "friendRequest", actorId: request.fromUserId },
    });
  }
);

// ----------------------------------------------------------------------
// Bonus: onFriendshipAccepted — notifies the original requester once the
// other side accepts. Triggers on friendships/{docId} update; fires only
// on the pending -> friends transition (acceptRequest() is the only
// FriendService method that makes that specific change).
// ----------------------------------------------------------------------
exports.onFriendshipAccepted = onDocumentUpdated("friendships/{docId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;
  if (before.status === "friends" || after.status !== "friends") return;

  const requesterId = after.requesterId;
  const userIds = Array.isArray(after.userIds) ? after.userIds : [];
  const accepterId = userIds.find((id) => id && id !== requesterId);
  if (!requesterId || !accepterId) return;

  const accepterSnap = await db.collection("users").doc(accepterId).get();
  const accepter = accepterSnap.exists ? accepterSnap.data() : {};
  const accepterName = accepter?.name || "Someone";

  await writeNotification(requesterId, {
    type: "friendAccept",
    actorId: accepterId,
    actorName: accepterName,
    actorAvatar: accepter?.avatarUrl || "",
    postId: "",
  });
  await sendPushToUser(requesterId, {
    title: accepterName,
    body: "accepted your friend request",
    data: { type: "friendAccept", actorId: accepterId },
  });
});

// ----------------------------------------------------------------------
// Bonus: onVoiceRoomInviteCreate — a host invites one friend to their live
// room (lib/services/notification_service.dart's inviteToVoiceRoom). The
// client can only ever write the lightweight `voiceRoomInvites` trigger
// doc, never the notification itself — same pattern as every other type.
// ----------------------------------------------------------------------
exports.onVoiceRoomInviteCreate = onDocumentCreated(
  "voiceRoomInvites/{inviteId}",
  async (event) => {
    const invite = event.data.data();
    if (!invite?.recipientId || !invite?.roomId) return;

    await writeNotification(invite.recipientId, {
      type: "voiceroom",
      actorId: invite.hostId || "",
      actorName: invite.hostName || "Someone",
      actorAvatar: invite.hostAvatar || "",
      postId: invite.roomId,
    });
    await sendPushToUser(invite.recipientId, {
      title: invite.hostName || "Someone",
      body: "invited you to a Voice Room",
      data: { type: "voiceroom", roomId: invite.roomId },
    });
  }
);
