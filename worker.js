import { createClient } from '@supabase/supabase-js';
import admin from 'firebase-admin';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE; // service role (سرّي)
const FIREBASE_CRED_JSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

if (!SUPABASE_URL || !SUPABASE_KEY || !FIREBASE_CRED_JSON) {
  throw new Error('Missing env vars SUPABASE_URL/SUPABASE_SERVICE_ROLE/FIREBASE_SERVICE_ACCOUNT_JSON');
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// init firebase-admin
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(FIREBASE_CRED_JSON)),
});

async function sendMulticast(tokens, notification, data = {}) {
  if (!tokens || tokens.length === 0) return { successCount: 0, failureCount: 0 };

  const message = {
    notification,
    data,
    tokens,
    android: { priority: 'high' },
    apns: { headers: { 'apns-priority': '10' } },
  };

  const res = await admin.messaging().sendMulticast(message);
  return res;
}

async function fetchTokensForRecipient(row) {
  // إذا في recipient_user_id محدد، استخدمه، وإلا استخدم recipient_type logic
  if (row.recipient_user_id) {
    const { data } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('user_id', row.recipient_user_id)
      .eq('enabled', true);
    return data?.map(d => d.token) ?? [];
  }

  if (row.recipient_type) {
    // مثال: recipient_type = 'restaurant' مع payload.restaurant_id
    const payload = row.payload || {};
    if (row.recipient_type === 'restaurant' && payload.restaurant_id) {
      // هنا يجب أن تحدد من هم المستخدمين المرتبطين بالمطعم (admins) — تبع تصميمك.
      // مثال افتراضي: نعتبر restaurant owner_id يخزن في restaurants.owner_id
      const { data: owners } = await supabase
        .from('restaurants')
        .select('owner_id')
        .eq('id', payload.restaurant_id);

      if (owners && owners.length) {
        const ownerId = owners[0].owner_id;
        const { data: tokens } = await supabase
          .from('device_tokens')
          .select('token')
          .eq('user_id', ownerId)
          .eq('enabled', true);
        return tokens?.map(t => t.token) ?? [];
      }
    }
    // حالات أخرى: drivers broadcast, etc.
  }

  return [];
}

async function processRow(row) {
  try {
    const tokens = await fetchTokensForRecipient(row);
    if (!tokens || tokens.length === 0) {
      await supabase.from('notification_queue').update({ status: 'failed', attempted: row.attempted + 1, last_attempt: new Date().toISOString() }).eq('id', row.id);
      return;
    }

    // build notification text by event_type
    const payload = row.payload || {};
    let title = 'Update';
    let body = 'You have a new notification';
    if (row.event_type === 'order_created') {
      title = 'طلب جديد';
      body = `تم استلام طلب جديد. رقم: ${payload.order_id ?? ''}`;
    } else if (row.event_type === 'order_assigned') {
      title = 'طلب جديد - تم تعيينك';
      body = 'تم تعيينك لتوصيل طلب جديد.';
    } else if (row.event_type === 'driver_nearby') {
      title = 'السائق قريب';
      body = 'سائقك سيصل خلال دقائق.';
    }

    const res = await sendMulticast(tokens, { title, body }, { order_id: payload.order_id?.toString() ?? '' });

    // update queue row
    await supabase.from('notification_queue').update({
      status: 'sent',
      attempted: row.attempted + 1,
      last_attempt: new Date().toISOString()
    }).eq('id', row.id);

    // optionally clean tokens with failures
    if (res.failureCount > 0) {
      // inspect res.responses to find invalid tokens and disable them
      res.responses.forEach(async (r, idx) => {
        if (!r.success) {
          // error handling: disable token in db
          const badToken = tokens[idx];
          await supabase.from('device_tokens').update({ enabled: false }).eq('token', badToken);
        }
      });
    }

  } catch (err) {
    console.error('processRow error', err);
    await supabase.from('notification_queue').update({ status: 'failed', attempted: row.attempted + 1, last_attempt: new Date().toISOString() }).eq('id', row.id);
  }
}

async function main() {
  // subscribe realtime to inserts on notification_queue
  const channel = supabase.channel('notification-queue').on('postgres_changes', {
    event: 'INSERT', schema: 'public', table: 'notification_queue'
  }, payload => {
    console.log('new queue row', payload.new);
    processRow(payload.new);
  }).subscribe();

  console.log('Worker subscribed to notification_queue');
}

main().catch(console.error);
