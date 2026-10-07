// Video tasmee': the room tokens for a session's LiveKit call. A token is issued only to the session's teacher or a
// student holding a seat in it, while the session is open and its call is within its window (docs/SRS.md VID-02).
import { Timestamp } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { AccessToken } from "livekit-server-sdk";
import { db } from "./admin.js";
import { policy } from "./policy.js";

const livekitURL = defineString("LIVEKIT_URL", { default: "ws://127.0.0.1:7880" });
const livekitKey = defineSecret("LIVEKIT_API_KEY");
const livekitSecret = defineSecret("LIVEKIT_API_SECRET");

export interface JoinCallResult {
  url: string;
  token: string;
  room: string;
  /** Whether the caller is the session's teacher. */
  isTeacher: boolean;
  teacherId: string;
}

/** The room a session's call happens in. */
export const roomName = (sessionId: string) => `session-${sessionId}`;

export const joinCall = onCall({ secrets: [livekitKey, livekitSecret] }, async (request): Promise<JoinCallResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const sessionId = request.data?.sessionId;
  if (typeof sessionId !== "string" || !sessionId) throw new HttpsError("invalid-argument", "Which session?");

  const session = (await db.doc(`sessions/${sessionId}`).get()).data();
  if (!session) throw new HttpsError("not-found", "There's no such session.");
  if (session.kind !== "video") throw new HttpsError("failed-precondition", "This session isn't by video.");
  if (session.status !== "open") throw new HttpsError("failed-precondition", "This session was cancelled.");

  const rules = await policy();
  const startsAt = (session.startsAt as Timestamp).toMillis();
  const now = Date.now();
  if (now < startsAt - rules.joinOpensMinutesBefore * 60_000) {
    throw new HttpsError("failed-precondition", "The call hasn't opened yet.", { opensAt: startsAt - rules.joinOpensMinutesBefore * 60_000 });
  }
  if (now > startsAt + rules.joinClosesHoursAfter * 3_600_000) {
    throw new HttpsError("failed-precondition", "The call has closed.");
  }

  const isTeacher = session.teacherId === uid;
  let name = session.teacherName as string;
  if (!isTeacher) {
    const seat = (await db.doc(`sessions/${sessionId}/seats/${uid}`).get()).data();
    if (!seat) throw new HttpsError("permission-denied", "Only students with a seat join this call.");
    name = seat.name as string;
  }

  const room = roomName(sessionId);
  const token = new AccessToken(livekitKey.value(), livekitSecret.value(), {
    identity: uid,
    name,
    ttl: `${rules.tokenTTLHours}h`,
    metadata: JSON.stringify({ role: isTeacher ? "teacher" : "student" }),
  });
  token.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true, canPublishData: true, roomAdmin: isTeacher });
  return { url: livekitURL.value(), token: await token.toJwt(), room, isTeacher, teacherId: session.teacherId };
});
