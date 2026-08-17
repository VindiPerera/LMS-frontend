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
