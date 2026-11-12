-- Ozzily database schema: functions and their EXECUTE grants.
-- GENERATED SNAPSHOT of live Supabase project siblqlstyccysqryggtr.
-- Do not edit by hand. Regenerate with generate.sql; see README.md.
--
-- REDACTED: the check-in trigger hook URL is replaced with a placeholder,
-- because this repository is public. The real value is in the Notion
-- Credentials Vault. Restore it before applying this file anywhere.

-- ------------------------------------------------------------- functions

CREATE OR REPLACE FUNCTION public.ai_brain_system_prompt()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$ select 'You are Ozzily, a warm SMS companion for people using GLP-1 medications. You help them protect muscle, hit protein and hydration goals, and stay consistent with strength training -- like a supportive friend who happens to be great at this. You are NOT a doctor and NOT a drill sergeant.

## Voice
- Warm, human, a little playful. Short sentences, text like a friend, not a brand.
- Never lecture, never shame a missed goal.
- Keep every reply to 160 characters or fewer. This is a hard billing limit, not a style note: one SMS segment holds exactly 160 characters, so a 161-character message costs twice as much as a 160-character one. Count before you send. Brevity is a feature here anyway -- long texts read as a wall.

## Plain text only -- this is a billing rule, not a style preference
SMS bills per 160-character segment, but a SINGLE non-standard character forces the whole
message into a 70-character-per-segment encoding, which roughly doubles its cost. Measured on
real traffic: 74% of messages were hit by this, wasting 42% of all segments sent.
- Use a plain hyphen "-" and NEVER an em dash or en dash.
- Use straight quotes '' and " and NEVER curly ones.
- Write three dots "..." and never a single ellipsis character.
- Use plain ASCII throughout. No arrows, no bullets, no special symbols.
- Emoji: at most ONE, and only for a genuine milestone -- the protein goal being hit, a
  streak continuing, or a workout logged. Never in routine chat, never decorative. One
  emoji costs the same as ten, so if you use one, make it earn its place.

## Absolute rules -- never break these
1. NEVER give medical advice. Never discuss medication dosing, timing, or clinical treatment of side effects -- only basic OTC lifestyle suggestions (water, fiber, electrolytes, small meals).
2. NEVER diagnose. NEVER tell someone to stop, start, or change their medication.
3. If a message describes a possible medical emergency (chest pain, severe vomiting, fainting, suicidal ideation, etc.), your ENTIRE reply must just tell them to contact a doctor or emergency services right now. Skip onboarding/coaching entirely in that reply, and set message_kind to system.
4. Never invent numbers you were not given -- only reference values present in USER CONTEXT below, or what you can genuinely see in an attached photo.
5. When the user gives you a number (weight, protein goal, workout days, wake time), copy it exactly as given -- double-check the digit before writing your reply or setting user_updates. Never round, estimate, or substitute a nearby number.
6. You do not know the real-world current date or time, and must never guess or invent one -- never set onboarded_at or any other timestamp yourself; the database handles that automatically.
7. Arithmetic must be exact. Before writing any reply involving protein totals, work out the sum on a separate line first, then use that exact result in your reply. Never state a total without having explicitly added the numbers.
8. NEVER name a specific medication or drug brand in your replies, even if the user names one themselves. Say "your medication" or "your treatment" instead. Never ask which medication they are on.

## Photos
Sometimes an image is attached to the user''s message. When there is one:
- If it is FOOD or a drink: identify what you can actually see, estimate the protein in grams, and put that estimate in detected_protein_g. Then do the NEWTOTAL / REMAINING maths below. Set message_kind to meal_photo (only when a photo is genuinely attached; a meal described in text is meal_log). Be honest that it is an estimate -- say "looks like roughly 30g" not "that is exactly 30g". Never pretend to see detail you cannot make out.
- If it shows a WORKOUT (gym equipment, a watch/tracker screen, a post-session selfie): acknowledge the specific thing you can see and celebrate it warmly. Set message_kind to workout_photo (only when a photo is genuinely attached; a workout described in text is workout_log). Do NOT set detected_protein_g.
- If the image is unclear, unrelated, or you genuinely cannot tell what it is: say so kindly and ask what it was. Never guess wildly, and never invent a protein number you cannot support.
- If there is NO image attached, never claim or imply you looked at one.

## Where this user is right now
Read USER CONTEXT below before writing your reply -- it is a live database snapshot, not something to infer.

If onboarding_step is not complete, you are still onboarding them. Ask exactly ONE onboarding question per message, in this fixed order, and do not move on until the current one is answered:
1. awaiting_weight -> ask roughly what they weigh, in pounds or kilograms, whichever they prefer. Convert pounds to kilograms using kg = lb / 2.205, round to one decimal, and put that in weight_kg. Then work out their daily protein target on a separate line first: TARGET = weight_kg * 1.6, rounded to the nearest whole number and kept between 20 and 400. Put TARGET in protein_goal and state it in your reply so they know what they are aiming for. Worked example: user says "180 lb" -> 180 / 2.205 = 81.6 kg -> 81.6 * 1.6 = 130.56 -> TARGET = 131. So weight_kg is 81.6 and protein_goal is 131.
2. awaiting_workout_days -> ask how many days a week they can realistically strength-train (0-7).
3. awaiting_wake_time -> ask what time they usually wake up, so morning check-ins land well. Normalize casual answers (around 7) to 24h HH:MM:SS.

The moment a slot is answered, put it in user_updates, advance onboarding_step to the next value in the sequence, and ask the NEXT question in the SAME reply. When wake_time is filled, set onboarding_step to complete and send a short warm welcome-aboard message instead of another question -- do NOT set onboarded_at, the database sets it automatically.

A few older users may still have onboarding_step set to awaiting_medication or awaiting_protein_goal. Treat either as if it were awaiting_weight: ask the weight question and advance to awaiting_workout_days. Never ask about medication.

If an answer is unclear or off-topic, gently re-ask the SAME question -- don''t advance, don''t guess.

## Once onboarding is complete
Use the RECENT CONVERSATION transcript below for continuity -- don''t repeat yourself or re-ask what''s already been answered there.
- A workout mentioned -> celebrate it specifically.
- Nausea, low appetite, constipation, fatigue -> use the Side Effect Protocol below.
- General chat -> be a good companion, brief and human.
- Billing/subscription/cancel/refund questions -> tell them to email hello@ozzily.com, and set message_kind to billing. Never process a payment, confirm a cancellation, or promise a refund yourself.
- If they tell you their weight has changed, update weight_kg and recompute protein_goal the same way as in onboarding.

### Tracking daily protein -- IMPORTANT, READ CAREFULLY
USER CONTEXT below gives you two numbers you MUST use together: "Protein logged today so far" (call this SOFAR) and "Protein goal" (call this GOAL). Both are already provided -- never guess them.

If this message (or its photo) describes food, a drink, or a shake with protein in it, extract the grams mentioned or reasonably estimated from THIS message only (call this THISMSG) and put THISMSG in detected_protein_g. If nothing food-or-protein-related is involved, omit detected_protein_g entirely.

When you do detect protein (THISMSG is set), you MUST compute, step by step, before writing your reply:
NEWTOTAL = SOFAR + THISMSG (add them -- do not just repeat THISMSG as if it were the total)
REMAINING = GOAL - NEWTOTAL
Then state NEWTOTAL and REMAINING in your reply, plus ONE or TWO specific foods/shakes to help close REMAINING. Keep it short, no meal plans.

Worked example -- follow this pattern exactly: SOFAR=25g, GOAL=80g, user says "had a 20g shake" so THISMSG=20. NEWTOTAL = 25 + 20 = 45. REMAINING = 80 - 45 = 35. Reply should say something like "You''re at 45/80g today, 35g to go" -- NOT "You''re at 20/80g" (that would be wrong, since it ignores SOFAR).

### Side Effect Protocol
- Nausea -> small frequent meals, clear liquids, ginger tea.
- Constipation -> water, fiber, gentle movement; if 48h+, gently suggest mentioning it to their doctor if it continues.
- Fatigue/dehydration -> water and rest.
- Frame anything beyond mild as worth mentioning to your doctor if it keeps up.

## Output format -- CRITICAL
Respond with ONLY one valid JSON object as plain text. No markdown fences, no commentary before or after, nothing but the object itself. It must have these keys: reply (a string -- the SMS text in Ozzily''s voice), user_updates (an object containing ONLY the columns that changed this turn, or an empty object if none), message_kind (a string, one of: meal_photo, workout_photo, meal_log, workout_log, side_effect, billing, system, freeform -- use meal_photo or workout_photo ONLY when a photo is genuinely attached to this message; when the user merely described a meal or a workout in text, use meal_log or workout_log), and detected_protein_g (a number -- grams of protein detected in THIS message only -- omit this key entirely if this message didn''t involve food or protein).

user_updates may only contain these keys: weight_kg, protein_goal, workout_days, wake_time, onboarding_step, intensity_level, first_name. NEVER include medication, onboarded_at, or any other timestamp -- the database sets those automatically.
- onboarding_step is one of awaiting_weight, awaiting_workout_days, awaiting_wake_time, complete
- weight_kg is a number in kilograms, 25-400, one decimal place
- wake_time is 24h HH:MM:SS; protein_goal is an integer 20-400; workout_days is an integer 0-7'::text $function$
;

CREATE OR REPLACE FUNCTION public.apply_ai_turn(p_user_id text, p_inbound_body text DEFAULT NULL::text, p_twilio_sid text DEFAULT NULL::text, p_media_url text DEFAULT NULL::text, p_media_content_type text DEFAULT NULL::text, p_detected_protein text DEFAULT NULL::text, p_reply text DEFAULT NULL::text, p_message_kind text DEFAULT NULL::text, p_medication text DEFAULT NULL::text, p_protein_goal text DEFAULT NULL::text, p_workout_days text DEFAULT NULL::text, p_wake_time text DEFAULT NULL::text, p_onboarding_step text DEFAULT NULL::text, p_intensity_level text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_weight_kg text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := p_user_id::uuid;
  v_step      text;
  v_model     text;
  v_has_media boolean;
  v_in_kind   text;
  v_out_kind  text;
  v_updated   boolean := false;
  v_streak    integer;
  -- Kinds the model may legitimately use. The four check-in beats are deliberately
  -- absent: those are written by the check-in scenario, and mark_checkin_delivered()
  -- acts on them, so accepting one here would let a model-chosen label mark a beat
  -- delivered that was never sent.
  c_allowed   constant text[] := array[
    'meal_photo','workout_photo','meal_log','workout_log',
    'side_effect','billing','system','freeform'
  ];
begin
  select onboarding_step into v_step from public.users where id = v_uid;
  if v_step is null then
    return jsonb_build_object('ok', false, 'error', 'user not found');
  end if;

  v_has_media := nullif(p_media_url, '') is not null;
  v_model     := lower(btrim(coalesce(p_message_kind, '')));
  if not (v_model = any (c_allowed)) then
    v_model := 'freeform';
  end if;

  -- A *_photo kind is a claim about this message, so it requires an actual photo.
  -- Demote only: keep the topic, drop the false claim. Never promote -- media does
  -- not imply a meal (an inbound photo asking "what colour is this square?" is not
  -- a meal_photo).
  if not v_has_media then
    v_model := case v_model
                 when 'meal_photo'    then 'meal_log'
                 when 'workout_photo' then 'workout_log'
                 else v_model
               end;
  end if;

  -- The inbound row carries the user's content -- media_url and detected_protein_g
  -- already live there -- so it is the row the classification describes.
  v_in_kind := case when v_step <> 'complete' then 'onboarding' else v_model end;

  -- The outbound row describes Ozzily's reply, not the user's message. system and
  -- billing genuinely characterise the reply (a safety redirect, a billing handoff);
  -- everything else is ordinary coaching text.
  v_out_kind := case
                  when v_step <> 'complete'            then 'onboarding'
                  when v_model in ('system','billing')  then v_model
                  else 'freeform'
                end;

  -- 1. log the user's inbound message (idempotent on twilio_sid)
  insert into public.messages
    (user_id, direction, body, twilio_sid, media_url, media_content_type, detected_protein_g, message_kind)
  values
    (v_uid, 'inbound', p_inbound_body,
     nullif(p_twilio_sid,''), nullif(p_media_url,''), nullif(p_media_content_type,''),
     nullif(btrim(coalesce(p_detected_protein,'')),'')::numeric, v_in_kind)
  on conflict (twilio_sid) do nothing;

  -- 2. apply only the whitelisted fields the model actually returned
  if coalesce(nullif(p_medication,''), nullif(p_protein_goal,''), nullif(p_workout_days,''),
              nullif(p_wake_time,''), nullif(p_onboarding_step,''), nullif(p_intensity_level,''),
              nullif(p_first_name,''), nullif(p_weight_kg,'')) is not null then
    update public.users u set
      medication      = coalesce(nullif(p_medication,''),                u.medication),
      weight_kg       = coalesce(nullif(p_weight_kg,'')::numeric,        u.weight_kg),
      protein_goal    = coalesce(nullif(p_protein_goal,'')::integer,     u.protein_goal),
      workout_days    = coalesce(nullif(p_workout_days,'')::integer,     u.workout_days),
      wake_time       = coalesce(nullif(p_wake_time,'')::time,           u.wake_time),
      onboarding_step = coalesce(nullif(p_onboarding_step,''),           u.onboarding_step),
      intensity_level = coalesce(nullif(p_intensity_level,''),           u.intensity_level),
      first_name      = coalesce(nullif(p_first_name,''),                u.first_name),
      updated_at      = now()
     where u.id = v_uid;
    v_updated := true;
  end if;

  -- 3. refresh today's streak. A streak day = the protein goal was met, so this
  --    runs after any protein_goal change above and recomputes from the message
  --    log rather than incrementing, which keeps it correct on replays.
  v_streak := public.upsert_streak_day(v_uid);

  update public.users set last_message_at = now() where id = v_uid;

  -- 4. log Ozzily's reply
  if nullif(btrim(coalesce(p_reply,'')),'') is not null then
    insert into public.messages (user_id, direction, body, message_kind)
    values (v_uid, 'outbound', p_reply, v_out_kind);
  end if;

  return jsonb_build_object('ok', true,
                            'inbound_kind', v_in_kind,
                            'outbound_kind', v_out_kind,
                            'user_updated', v_updated,
                            'current_streak', v_streak);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.apply_payment_event(p_event_id text, p_event_type text, p_occurred_at text DEFAULT NULL::text, p_user_id text DEFAULT NULL::text, p_provider_customer_id text DEFAULT NULL::text, p_provider_subscription_id text DEFAULT NULL::text, p_provider_transaction_id text DEFAULT NULL::text, p_amount_cents text DEFAULT NULL::text, p_currency text DEFAULT NULL::text, p_plan text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text, p_paddle_status text DEFAULT NULL::text, p_next_billed_at text DEFAULT NULL::text, p_tax_cents text DEFAULT NULL::text, p_fee_cents text DEFAULT NULL::text, p_earnings_cents text DEFAULT NULL::text, p_environment text DEFAULT NULL::text, p_adjustment_id text DEFAULT NULL::text, p_adjustment_action text DEFAULT NULL::text, p_adjustment_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid        uuid;
  v_event      text := lower(btrim(coalesce(p_event_type,'')));
  v_eid        text := nullif(btrim(coalesce(p_event_id,'')),'');
  v_occurred   timestamptz := nullif(btrim(coalesce(p_occurred_at,'')),'')::timestamptz;
  v_next       timestamptz := nullif(btrim(coalesce(p_next_billed_at,'')),'')::timestamptz;
  v_pstatus    text := lower(btrim(coalesce(p_paddle_status,'')));
  v_last       timestamptz;
  v_sub_status text;
  v_source     text;
  v_pay_status text;
  v_amount     integer := nullif(btrim(coalesce(p_amount_cents,'')),'')::integer;
  v_tax        integer := nullif(btrim(coalesce(p_tax_cents,'')),'')::integer;
  v_fee        integer := nullif(btrim(coalesce(p_fee_cents,'')),'')::integer;
  v_earn       integer := nullif(btrim(coalesce(p_earnings_cents,'')),'')::integer;
  v_plan       text := lower(nullif(btrim(coalesce(p_plan,'')),''));
  v_env        text := lower(btrim(coalesce(p_environment,'')));
  v_inserted   boolean := false;
  v_applied    boolean := false;
  v_skipped    text;
  v_actual     text;
  v_trial_end  timestamptz;
  v_adj_id      text := nullif(btrim(coalesce(p_adjustment_id,'')),'');
  v_adj_action  text := lower(btrim(coalesce(p_adjustment_action,'')));
  v_adj_status  text := lower(btrim(coalesce(p_adjustment_status,'')));
  v_pay_skipped text;
  v_resolved    text;
begin
  if v_eid is null then
    return jsonb_build_object('ok', false, 'error', 'missing event id');
  end if;

  -- Fail closed on a missing or unrecognised environment rather than guessing live. A
  -- caller that cannot say which secret matched is a caller that must not apply
  -- anything. An empty string lands here too, which is what the not-yet-updated
  -- webhook produces, so the deploy window refuses rather than applies.
  if v_env not in ('live','sandbox') then
    insert into public.payment_events_refused
      (event_id, event_type, environment, user_id, reason)
    values (v_eid, v_event, nullif(v_env,''), null,
            'missing or unrecognised environment; caller did not say which signing secret matched')
    on conflict (event_id) do nothing;

    raise warning 'apply_payment_event: refused event % (%) for unrecognised environment %',
                  v_eid, v_event, coalesce(nullif(v_env,''), '(none)');
    return jsonb_build_object('ok', false, 'error', 'unrecognised environment',
                              'environment', coalesce(nullif(v_env,''), '(none)'),
                              'event_id', v_eid);
  end if;

  v_uid := nullif(btrim(coalesce(p_user_id,'')),'')::uuid;
  if v_uid is not null then
    v_resolved := 'custom_data.user_id';
  end if;

  if v_uid is null and nullif(btrim(coalesce(p_provider_subscription_id,'')),'') is not null then
    select id into v_uid from public.users
     where provider_subscription_id = btrim(p_provider_subscription_id) limit 1;
    if v_uid is not null then
      v_resolved := 'users.provider_subscription_id';
    end if;
  end if;

  if v_uid is null and nullif(btrim(coalesce(p_provider_customer_id,'')),'') is not null then
    select id into v_uid from public.users
     where provider_customer_id = btrim(p_provider_customer_id) limit 1;
    if v_uid is not null then
      v_resolved := 'users.provider_customer_id';
    end if;
  end if;

  -- FOURTH FALLBACK: the user the PURCHASE resolved to.
  --
  -- An adjustment carries no custom_data, so user_id is absent on every refund. Its
  -- transaction_id is the original transaction's id, and that purchase row was
  -- attributed via custom_data.user_id when it was written. So this recovers a refund
  -- whose users row lost (or never got) its provider ids.
  --
  -- `environment` is matched, not ignored. Transaction ids do not collide across
  -- environments in practice, but attributing a LIVE refund to a user found through a
  -- SANDBOX payment row would be a cross-environment write, and the column is NOT NULL
  -- so the match costs nothing. The sandbox allowlist guard below is a second line of
  -- defence, not a substitute: it only constrains sandbox events.
  --
  -- The ordering is deterministic because one transaction can hold both a purchase and a
  -- refund row: prefer the succeeded purchase, then the oldest. Both carry the same
  -- user_id in every case this can construct, so the ordering is about being repeatable
  -- rather than about choosing between different answers.
  if v_uid is null and nullif(btrim(coalesce(p_provider_transaction_id,'')),'') is not null then
    select p.user_id into v_uid
      from public.payments p
     where p.provider_transaction_id = btrim(p_provider_transaction_id)
       and p.environment = v_env
     order by (p.status = 'succeeded') desc, p.created_at asc
     limit 1;
    if v_uid is not null then
      v_resolved := 'payments.provider_transaction_id';
    end if;
  end if;

  if v_uid is null or not exists (select 1 from public.users where id = v_uid) then
    -- Recorded for BOTH environments, not just live. A ledger that covers only some
    -- refusal kinds answers "did the guard fire" but not "what did we drop", and an
    -- unattributable live payment is the single most expensive thing to lose silently.
    insert into public.payment_events_refused
      (event_id, event_type, environment, user_id, reason)
    values (v_eid, v_event, v_env, null,
            'user not resolved from custom_data.user_id, users.provider_subscription_id, users.provider_customer_id or payments.provider_transaction_id')
    on conflict (event_id) do nothing;

    raise warning 'apply_payment_event: refused % event % (%): user not resolved',
                  v_env, v_eid, v_event;
    return jsonb_build_object('ok', false, 'error', 'user not resolved',
                              'event_id', v_eid, 'event_type', v_event,
                              'environment', v_env);
  end if;

  -- THE GUARD. A sandbox event may only touch an allowlisted test user. This sits
  -- ahead of every write below, including the provider-id update, because a sandbox
  -- customer id written onto a real user would corrupt the live resolution path for
  -- every later event.
  --
  -- Returns ok:true so the caller answers 2xx and Paddle stops retrying: a sandbox
  -- event aimed at a real user will never become applicable. The refusal is recorded
  -- in payment_events_refused, in the Postgres log, and in the return value.
  if v_env = 'sandbox'
     and not exists (select 1 from public.payment_test_users t where t.user_id = v_uid) then
    insert into public.payment_events_refused
      (event_id, event_type, environment, user_id, reason)
    values (v_eid, v_event, v_env, v_uid,
            'sandbox event for a user that is not in payment_test_users')
    on conflict (event_id) do nothing;

    raise warning 'apply_payment_event: refused sandbox event % (%) for non-test user %',
                  v_eid, v_event, v_uid;
    return jsonb_build_object(
      'ok', true,
      'user_id', v_uid,
      'event_type', v_event,
      'environment', v_env,
      'payment_recorded', false,
      'status_change_applied', false,
      'skipped_reason', 'sandbox event for a user that is not in payment_test_users; nothing was written'
    );
  end if;

  v_sub_status := case v_pstatus
                    when 'trialing' then 'trial'
                    when 'active'   then 'active'
                    when 'past_due' then 'past_due'
                    when 'paused'   then 'paused'
                    when 'canceled' then 'cancelled'
                    else null
                  end;
  if v_sub_status is not null then
    v_source := 'paddle data.status';
  end if;

  if v_sub_status is null then
    v_sub_status := case
      when v_event in ('subscription.activated','subscription.created',
                       'subscription.resumed','transaction.completed')    then 'active'
      when v_event = 'subscription.trialing'                             then 'trial'
      when v_event in ('subscription.canceled','subscription.cancelled')  then 'cancelled'
      when v_event in ('subscription.past_due','transaction.payment_failed') then 'past_due'
      when v_event = 'subscription.paused'                               then 'paused'
      else null
    end;
    if v_sub_status is not null then
      v_source := 'event name';
    end if;
  end if;

  -- ADJUSTMENTS MAP ON THE ADJUSTMENT'S OWN STATUS AND ACTION, NEVER ON THE EVENT
  -- NAME. `adjustment.created` fires while a refund is still `pending_approval`,
  -- and that status can go on to `rejected`, so treating the event name as proof
  -- would record refunds that never happened -- the same class of error as a status
  -- written by the step that STARTS an action instead of the step that confirms it.
  -- Only `approved` is money that actually moved.
  --
  -- The `*_reverse` actions (chargeback_reverse, chargeback_warning_reverse,
  -- credit_reverse) move money back TOWARDS us. Recording one as a refund would
  -- double-count a loss, so they are deliberately not recorded and say why.
  if v_event like 'adjustment.%' then
    if v_adj_status <> 'approved' then
      v_pay_skipped := format('adjustment status is %s, not approved; no payment row written',
                              coalesce(nullif(v_adj_status,''), '(none)'));
    elsif v_adj_action = 'refund' then
      v_pay_status := 'refunded';
    elsif v_adj_action = 'chargeback' then
      v_pay_status := 'chargeback';
    else
      v_pay_skipped := format('adjustment action %s is approved but is not money leaving us; no payment row written',
                              coalesce(nullif(v_adj_action,''), '(none)'));
    end if;
  else
    v_pay_status := case
      when v_event = 'transaction.completed'      then 'succeeded'
      when v_event = 'transaction.payment_failed' then 'failed'
      else null
    end;
  end if;

  if v_pay_status is not null then
    begin
      insert into public.payments
        (user_id, provider, provider_event_id, provider_transaction_id,
         provider_adjustment_id,
         amount_cents, currency, status, plan, failure_reason,
         tax_cents, fee_cents, earnings_cents, environment)
      values
        (v_uid, 'paddle', v_eid, nullif(btrim(coalesce(p_provider_transaction_id,'')),''),
         v_adj_id,
         coalesce(v_amount, 0), coalesce(nullif(lower(btrim(coalesce(p_currency,''))),''), 'usd'),
         v_pay_status,
         case when v_plan in ('monthly','annual') then v_plan else null end,
         nullif(btrim(coalesce(p_failure_reason,'')),''),
         v_tax, v_fee, v_earn, v_env)
      on conflict (provider_event_id) do nothing;

      v_inserted := found;
    exception when unique_violation then
      -- provider_adjustment_id is UNIQUE, so a second approved event for the same
      -- adjustment -- which carries a DIFFERENT event id, and so is invisible to the
      -- provider_event_id guard -- lands here instead of double-recording the refund.
      v_inserted := false;
      v_pay_skipped := 'this adjustment is already recorded under a different event id';
    end;
  end if;

  update public.users u set
    provider_customer_id     = coalesce(nullif(btrim(coalesce(p_provider_customer_id,'')),''),
                                        u.provider_customer_id),
    provider_subscription_id = coalesce(nullif(btrim(coalesce(p_provider_subscription_id,'')),''),
                                        u.provider_subscription_id),
    updated_at               = now()
   where u.id = v_uid;

  if v_sub_status is null then
    v_skipped := case
      when v_event = 'subscription.updated'
        then 'subscription.updated carried no data.status, so no status could be applied'
      else 'event type carries no subscription status change'
    end;
  else
    select last_billing_event_at into v_last from public.users where id = v_uid;

    if v_occurred is not null and v_last is not null and v_occurred <= v_last then
      v_skipped := 'event is not newer than the last applied event (retry, or out-of-order delivery)';
    else
      v_trial_end := case when v_sub_status = 'trial' then v_next else null end;

      update public.users u set
        subscription_status   = v_sub_status,
        plan                  = case when v_plan in ('monthly','annual') then v_plan else u.plan end,
        trial_end             = coalesce(v_trial_end, u.trial_end),
        last_billing_event_at = coalesce(v_occurred, now()),
        updated_at            = now()
       where u.id = v_uid;
      v_applied := true;
    end if;
  end if;

  select subscription_status into v_actual from public.users where id = v_uid;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_uid,
    'event_type', v_event,
    'environment', v_env,
    'payment_recorded', v_inserted,
    'status_change_applied', v_applied,
    'mapped_status', coalesce(v_sub_status, '(none)'),
    'status_source', coalesce(v_source, '(none)'),
    'subscription_status', v_actual,
    'trial_end_set', v_trial_end,
    'skipped_reason', v_skipped,
    'payment_skipped_reason', v_pay_skipped,
    'resolved_by', coalesce(v_resolved, '(none)')
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.build_ai_request(p_phone text, p_body text DEFAULT NULL::text, p_media_url text DEFAULT NULL::text, p_media_type text DEFAULT NULL::text, p_media_b64 text DEFAULT NULL::text)
 RETURNS TABLE(user_id uuid, request_json text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    u.id,
    (jsonb_build_object(
      'model', 'claude-sonnet-5',
      'max_tokens', 600,
      'system',
          public.ai_brain_system_prompt()
       || E'\n\n---\nUSER CONTEXT\nName: '   || coalesce(u.first_name, '(not set)')
       || E'\nOnboarding step: '             || coalesce(u.onboarding_step, '')
       || E'\nWeight: '                      || coalesce(u.weight_kg::text || ' kg', '(not set)')
       || E'\nProtein goal: '                || coalesce(u.protein_goal::text, '') || 'g'
       || E'\nProtein logged today so far (before this message): '
                                             || coalesce(public.get_todays_protein_total(u.id)::text, '0') || 'g'
       || E'\nWorkout days/week: '           || coalesce(u.workout_days::text, '')
       || E'\nWake time: '                   || coalesce(u.wake_time::text, '')
       || E'\nIntensity level: '             || coalesce(u.intensity_level, '')
       || E'\nCurrent streak: '              || coalesce(u.current_streak::text, '0') || ' days'
       || E'\nSubscription status: '         || coalesce(u.subscription_status, '')
       || E'\nPhoto attached: '              || case
                                                  when nullif(btrim(coalesce(p_media_b64,'')),'') is not null then 'yes (image included below)'
                                                  when nullif(btrim(coalesce(p_media_url,'')),'') is not null then 'yes, but NOT viewable this turn'
                                                  else 'no' end
       || E'\n\nRECENT CONVERSATION:\n'      || coalesce(public.get_recent_transcript(u.id, 12), ''),
      'messages', jsonb_build_array(
        jsonb_build_object(
          'role', 'user',
          'content',
            case
              -- image bytes supplied -> real vision (proven working)
              when nullif(btrim(coalesce(p_media_b64,'')),'') is not null then
                jsonb_build_array(
                  jsonb_build_object(
                    'type','image',
                    'source', jsonb_build_object(
                      'type','base64',
                      'media_type', coalesce(nullif(p_media_type,''), 'image/jpeg'),
                      'data', btrim(p_media_b64)
                    )
                  ),
                  jsonb_build_object('type','text','text', coalesce(nullif(btrim(coalesce(p_body,'')),''), '[photo]'))
                )
              -- photo exists but bytes not available -> degrade gracefully, never 400
              when nullif(btrim(coalesce(p_media_url,'')),'') is not null then
                jsonb_build_array(
                  jsonb_build_object('type','text','text',
                    coalesce(nullif(btrim(coalesce(p_body,'')),''), '')
                    || E'\n\n[The user attached a photo, but it is not viewable on this turn. Do NOT claim to have seen it. Warmly acknowledge they sent one and ask them to tell you in words what it was.]')
                )
              else
                jsonb_build_array(
                  jsonb_build_object('type','text','text', coalesce(nullif(btrim(coalesce(p_body,'')),''), '[empty message]'))
                )
            end
        )
      )
    ))::text
  from public.users u
  where u.phone = p_phone
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.checkin_delivery_health()
 RETURNS TABLE(window_label text, claimed bigint, delivered bigint, failed bigint, stuck_pending bigint, last_delivered_at timestamp with time zone, healthy boolean, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with w as (
    select
      count(*)::bigint as claimed,
      count(*) filter (where status = 'sent')::bigint as delivered,
      count(*) filter (where status = 'failed')::bigint as failed,
      count(*) filter (where status = 'pending'
                         and scheduled_for < now() - interval '20 minutes')::bigint as stuck
    from public.scheduled_messages
    where scheduled_for > now() - interval '48 hours'
  )
  select
    'last 48h'::text,
    w.claimed, w.delivered, w.failed, w.stuck,
    (select max(created_at) from public.messages
      where direction='outbound'
        and message_kind in ('morning_checkin','midday_checkin','evening_checkin','recap')),
    (w.stuck = 0 and w.failed = 0 and (w.claimed = 0 or w.delivered > 0)),
    case
      when w.stuck > 0  then w.stuck || ' beat(s) claimed but never delivered — Twilio or the Make scenario is failing silently'
      when w.failed > 0 then w.failed || ' beat(s) failed in the last 48h'
      when w.claimed > 0 and w.delivered = 0 then 'beats were claimed but none delivered'
      when w.claimed = 0 then 'no beats were due in this window (check eligibility: onboarding complete, active trial, not opted out)'
      else 'delivering normally'
    end::text
  from w;
$function$
;

CREATE OR REPLACE FUNCTION public.count_due_checkins()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int
    from public.users u
   where u.onboarding_step = 'complete'
     and coalesce(u.sms_opted_out,false) = false
     and u.phone is not null
     and u.phone <> ''
     and (
       u.subscription_status = 'active'
       or (u.subscription_status = 'trial' and (u.trial_end is null or u.trial_end > now()))
     )
     and (
       case
         when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= u.wake_time
          and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '11:30' then 'morning_checkin'
         when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= time '12:00'
          and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '14:30' then 'midday_checkin'
         when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= time '17:30'
          and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '19:30' then 'evening_checkin'
         when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= time '20:30'
          and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '22:30' then 'recap'
       end
     ) = any (
       case coalesce(u.intensity_level,'steady')
         when 'chill'   then array['morning_checkin']
         when 'intense' then array['morning_checkin','midday_checkin','evening_checkin','recap']
         else                array['morning_checkin','midday_checkin','recap']
       end
     )
     and not exists (
       select 1 from public.scheduled_messages sm
        where sm.user_id = u.id
          and sm.local_date = (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date
          and sm.message_kind = (
            case
              when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= u.wake_time
               and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '11:30' then 'morning_checkin'
              when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= time '12:00'
               and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '14:30' then 'midday_checkin'
              when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= time '17:30'
               and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '19:30' then 'evening_checkin'
              when (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time >= time '20:30'
               and (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time < time '22:30' then 'recap'
            end
          )
     );
$function$
;

CREATE OR REPLACE FUNCTION public.create_verified_user(p_phone text, p_preferred_plan text DEFAULT NULL::text, p_consent_text text DEFAULT 'sms_opt_in_v2'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id      uuid;
  v_new     boolean;
  v_status  text;
  v_step    text;
  v_plan    text;
begin
  if p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_phone');
  end if;

  v_plan := case when p_preferred_plan in ('monthly', 'annual')
                 then p_preferred_plan else null end;

  insert into public.users (phone, preferred_plan, consent_at, consent_text)
  values (p_phone, v_plan, now(), coalesce(p_consent_text, 'sms_opt_in_v2'))
  on conflict (phone) do update
    set preferred_plan = coalesce(excluded.preferred_plan, public.users.preferred_plan),
        -- The FIRST consent is the one that matters for the audit trail; a later
        -- signup must not overwrite when it was given.
        consent_at     = coalesce(public.users.consent_at, excluded.consent_at),
        consent_text   = coalesce(public.users.consent_text, excluded.consent_text),
        -- A verified signup with the consent box ticked is a genuine re-opt-in, so
        -- it clears an earlier STOP. Nothing else in the system may do that.
        sms_opted_out  = false,
        opted_out_at   = case when public.users.sms_opted_out then null
                              else public.users.opted_out_at end,
        updated_at     = now()
  returning id, (xmax = 0), subscription_status, onboarding_step
       into v_id, v_new, v_status, v_step;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_id,
    'is_new', v_new,
    'subscription_status', v_status,
    'onboarding_step', v_step
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.expire_lapsed_trials()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n integer;
begin
  update public.users
     set subscription_status = 'expired',
         updated_at = now()
   where subscription_status = 'trial'
     and trial_end is not null
     and trial_end < now()
     and phone ~ '^\+[1-9][0-9]{7,14}$';
  get diagnostics n = row_count;
  return n;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_billing_due()
 RETURNS TABLE(id uuid, phone text, first_name text, plan text, trial_end timestamp with time zone, hours_left numeric, local_date date)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with eligible as (
    select u.*,
           (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date as local_date,
           round(extract(epoch from (u.trial_end - now())) / 3600.0, 1) as hours_left
      from public.users u
     where u.subscription_status = 'trial'
       and u.onboarding_step = 'complete'
       and coalesce(u.sms_opted_out,false) = false
       and u.phone is not null and u.phone <> ''
       and u.trial_end is not null
       -- never chase someone who has already subscribed
       and u.provider_subscription_id is null
       -- inside the last 24h of trial, and not already past it
       and u.trial_end > now()
       and u.trial_end <= now() + interval '24 hours'
  ),
  claimed as (
    insert into public.scheduled_messages (user_id, message_kind, local_date, scheduled_for, status, sent_at)
    select e.id, 'billing', e.local_date, now(), 'pending', null
      from eligible e
    on conflict (user_id, message_kind, local_date) do nothing
    returning user_id
  )
  select e.id, e.phone, e.first_name, e.plan, e.trial_end, e.hours_left, e.local_date
    from eligible e
    join claimed c on c.user_id = e.id;
$function$
;

CREATE OR REPLACE FUNCTION public.get_due_checkins()
 RETURNS TABLE(id uuid, phone text, first_name text, medication text, protein_goal integer, workout_days integer, current_streak integer, intensity_level text, beat text, focus_angle text, protein_today numeric, recent_checkins text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with base as (
    select u.*,
           (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date as local_date,
           (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::time as local_time
      from public.users u
     where u.onboarding_step = 'complete'
       and coalesce(u.sms_opted_out,false) = false
       and u.phone is not null
       and u.phone <> ''
       and (
         u.subscription_status = 'active'
         or (u.subscription_status = 'trial' and (u.trial_end is null or u.trial_end > now()))
       )
  ),
  candidates as (
    select b.*,
           case
             when b.local_time >= b.wake_time   and b.local_time < time '11:30' then 'morning_checkin'
             when b.local_time >= time '12:00'  and b.local_time < time '14:30' then 'midday_checkin'
             when b.local_time >= time '17:30'  and b.local_time < time '19:30' then 'evening_checkin'
             when b.local_time >= time '20:30'  and b.local_time < time '22:30' then 'recap'
           end as beat
      from base b
  ),
  allowed as (
    select c.* from candidates c
     where c.beat is not null
       and c.beat = any (
         case coalesce(c.intensity_level,'steady')
           when 'chill'   then array['morning_checkin']
           when 'intense' then array['morning_checkin','midday_checkin','evening_checkin','recap']
           else                array['morning_checkin','midday_checkin','recap']
         end
       )
  ),
  claimed as (
    insert into public.scheduled_messages (user_id, message_kind, local_date, scheduled_for, status, sent_at)
    select a.id, a.beat, a.local_date, now(), 'pending', null
      from allowed a
    on conflict (user_id, message_kind, local_date) do nothing
    returning user_id, message_kind
  )
  select
    a.id, a.phone, a.first_name, a.medication, a.protein_goal, a.workout_days,
    a.current_streak, a.intensity_level, a.beat,
    (array['protein','training','hydration','encouragement','consistency','practical_tip'])[
      1 + ((extract(doy from a.local_date)::int
            + get_byte(decode(replace(a.id::text,'-',''),'hex'),0)) % 6)
    ]::text as focus_angle,
    coalesce(public.get_todays_protein_total(a.id), 0)::numeric as protein_today,
    coalesce(
      (select string_agg('- ' || r.body, chr(10))
         from (select m.body
                 from public.messages m
                where m.user_id = a.id
                  and m.direction = 'outbound'
                  and m.message_kind = a.beat
                order by m.created_at desc
                limit 5) r),
      '(none yet)')::text as recent_checkins
  from allowed a
  join claimed k on k.user_id = a.id and k.message_kind = a.beat;
$function$
;

CREATE OR REPLACE FUNCTION public.get_inbound_context(p_phone text)
 RETURNS TABLE(user_id uuid, first_name text, medication text, protein_goal integer, workout_days integer, wake_time time without time zone, intensity_level text, current_streak integer, subscription_status text, onboarding_step text, protein_today numeric, transcript text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u.id, u.first_name, u.medication, u.protein_goal, u.workout_days,
         u.wake_time, u.intensity_level, u.current_streak, u.subscription_status,
         u.onboarding_step,
         public.get_todays_protein_total(u.id),
         public.get_recent_transcript(u.id, 12)
    from public.users u
   where u.phone = p_phone
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.get_recent_transcript(p_user_id uuid, p_limit integer DEFAULT 12)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    string_agg(
      case when direction = 'inbound' then 'User: ' || coalesce(body, '[photo]')
           else 'Ozzily: ' || coalesce(body, '')
      end,
      chr(10)
      order by created_at asc
    ),
    ''
  )
  from (
    select direction, body, created_at
    from public.messages
    where user_id = p_user_id
    order by created_at desc
    limit p_limit
  ) recent;
$function$
;

CREATE OR REPLACE FUNCTION public.get_todays_protein_total(p_user_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(sum(m.detected_protein_g), 0)
    from public.messages m
    join public.users u on u.id = m.user_id
   where m.user_id = p_user_id
     and m.direction = 'inbound'
     and (m.created_at at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date
       = (now()        at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date;
$function$
;

CREATE OR REPLACE FUNCTION public.infer_timezone_from_phone(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d  text;
  ac text;
begin
  if p_phone is null or btrim(p_phone) = '' then
    return 'America/New_York';
  end if;

  d := regexp_replace(p_phone, '\D', '', 'g');

  -- ---------- NANP (+1): US / Canada / Caribbean, resolved by area code ----------
  if left(d, 1) = '1' and length(d) = 11 then
    ac := substring(d from 2 for 3);

    if ac = '808' then return 'Pacific/Honolulu'; end if;
    if ac = '907' then return 'America/Anchorage'; end if;
    if ac = '787' or ac = '939' then return 'America/Puerto_Rico'; end if;
    if ac = '340' then return 'America/St_Thomas'; end if;

    if ac = any (array['480','520','602','623','928']) then
      return 'America/Phoenix';
    end if;

    if ac = any (array[
      '206','209','213','253','279','310','323','341','350','360','408','415','424','425',
      '442','458','503','509','510','530','541','559','562','564','604','619','626','628',
      '650','657','661','669','672','707','714','747','760','775','778','805','818','820',
      '831','858','909','916','925','949','951','971','236','250']) then
      return 'America/Los_Angeles';
    end if;

    if ac = any (array[
      '303','307','308','385','406','435','505','575','719','720','915','970','983','403',
      '587','780','825','368']) then
      return 'America/Denver';
    end if;

    if ac = any (array[
      '205','214','217','218','224','225','228','251','254','256','262','270','281','309',
      '312','314','316','318','319','320','325','331','334','337','346','361','364','402',
      '405','409','414','417','430','432','469','479','501','504','507','512','515','531',
      '534','539','563','573','580','601','608','612','615','618','620','630','636','641',
      '651','660','662','682','701','708','712','713','715','731','737','763','769','773',
      '779','785','806','812','815','816','817','830','832','847','850','870','872','901',
      '903','913','918','920','931','936','940','952','956','972','979','985','204','431',
      '306','639','474']) then
      return 'America/Chicago';
    end if;

    -- everything else in NANP defaults to Eastern
    return 'America/New_York';
  end if;

  -- ---------- International: longest country-code prefix first ----------
  if left(d,3) = '880' then return 'Asia/Dhaka';        end if;
  if left(d,3) = '886' then return 'Asia/Taipei';       end if;
  if left(d,3) = '852' then return 'Asia/Hong_Kong';    end if;
  if left(d,3) = '971' then return 'Asia/Dubai';        end if;
  if left(d,3) = '966' then return 'Asia/Riyadh';       end if;
  if left(d,3) = '972' then return 'Asia/Jerusalem';    end if;
  if left(d,3) = '977' then return 'Asia/Kathmandu';    end if;
  if left(d,3) = '353' then return 'Europe/Dublin';     end if;
  if left(d,3) = '351' then return 'Europe/Lisbon';     end if;
  if left(d,3) = '358' then return 'Europe/Helsinki';   end if;
  if left(d,3) = '234' then return 'Africa/Lagos';      end if;
  if left(d,3) = '254' then return 'Africa/Nairobi';    end if;

  if left(d,2) = '91' then return 'Asia/Kolkata';                  end if;
  if left(d,2) = '44' then return 'Europe/London';                 end if;
  if left(d,2) = '61' then return 'Australia/Sydney';              end if;
  if left(d,2) = '64' then return 'Pacific/Auckland';              end if;
  if left(d,2) = '49' then return 'Europe/Berlin';                 end if;
  if left(d,2) = '33' then return 'Europe/Paris';                  end if;
  if left(d,2) = '34' then return 'Europe/Madrid';                 end if;
  if left(d,2) = '39' then return 'Europe/Rome';                   end if;
  if left(d,2) = '31' then return 'Europe/Amsterdam';              end if;
  if left(d,2) = '46' then return 'Europe/Stockholm';              end if;
  if left(d,2) = '47' then return 'Europe/Oslo';                   end if;
  if left(d,2) = '45' then return 'Europe/Copenhagen';             end if;
  if left(d,2) = '48' then return 'Europe/Warsaw';                 end if;
  if left(d,2) = '30' then return 'Europe/Athens';                 end if;
  if left(d,2) = '41' then return 'Europe/Zurich';                 end if;
  if left(d,2) = '43' then return 'Europe/Vienna';                 end if;
  if left(d,2) = '32' then return 'Europe/Brussels';               end if;
  if left(d,2) = '90' then return 'Europe/Istanbul';               end if;
  if left(d,2) = '52' then return 'America/Mexico_City';           end if;
  if left(d,2) = '55' then return 'America/Sao_Paulo';             end if;
  if left(d,2) = '54' then return 'America/Argentina/Buenos_Aires';end if;
  if left(d,2) = '56' then return 'America/Santiago';              end if;
  if left(d,2) = '57' then return 'America/Bogota';                end if;
  if left(d,2) = '51' then return 'America/Lima';                  end if;
  if left(d,2) = '27' then return 'Africa/Johannesburg';           end if;
  if left(d,2) = '20' then return 'Africa/Cairo';                  end if;
  if left(d,2) = '86' then return 'Asia/Shanghai';                 end if;
  if left(d,2) = '81' then return 'Asia/Tokyo';                    end if;
  if left(d,2) = '82' then return 'Asia/Seoul';                    end if;
  if left(d,2) = '65' then return 'Asia/Singapore';                end if;
  if left(d,2) = '60' then return 'Asia/Kuala_Lumpur';             end if;
  if left(d,2) = '62' then return 'Asia/Jakarta';                  end if;
  if left(d,2) = '63' then return 'Asia/Manila';                   end if;
  if left(d,2) = '66' then return 'Asia/Bangkok';                  end if;
  if left(d,2) = '84' then return 'Asia/Ho_Chi_Minh';              end if;
  if left(d,2) = '92' then return 'Asia/Karachi';                  end if;
  if left(d,2) = '94' then return 'Asia/Colombo';                  end if;
  if left(d,1) = '7'  then return 'Europe/Moscow';                 end if;

  return 'America/New_York';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.log_outbound_sms(p_user_id uuid, p_body text, p_kind text DEFAULT 'onboarding'::text, p_twilio_sid text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
begin
  insert into public.messages (user_id, direction, body, message_kind, twilio_sid)
  values (p_user_id, 'outbound', p_body, p_kind, p_twilio_sid)
  returning id into v_id;
  return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.mark_checkin_delivered()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.direction = 'outbound'
     and new.message_kind in ('morning_checkin','midday_checkin','evening_checkin','recap','billing') then
    update public.scheduled_messages s
       set status = 'sent', sent_at = now()
     where s.id = (
       select s2.id from public.scheduled_messages s2
        where s2.user_id = new.user_id
          and s2.message_kind = new.message_kind
          and s2.status = 'pending'
          and s2.scheduled_for > now() - interval '12 hours'
        order by s2.scheduled_for desc
        limit 1
     );
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.recalculate_streak(p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_streak   integer := 0;
  v_date     date;
  v_expected date;
  v_today    date;
begin
  select (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date
    into v_today
    from public.users u where u.id = p_user_id;

  if v_today is null then
    return 0;
  end if;

  v_expected := v_today;

  for v_date in
    select s.date from public.streaks s
     where s.user_id = p_user_id and s.day_complete = true
     order by s.date desc
  loop
    -- A streak stays "current" while today is still in progress: allow the most
    -- recent completed day to be today or yesterday, but no older.
    if v_streak = 0 and v_date < v_today - 1 then
      exit;
    end if;

    if v_streak = 0 then
      v_expected := v_date;
    elsif v_date <> v_expected then
      exit;
    end if;

    v_streak   := v_streak + 1;
    v_expected := v_date - 1;
  end loop;

  update public.users
     set current_streak    = v_streak,
         longest_streak    = greatest(coalesce(longest_streak,0), v_streak),
         last_checkin_date = v_today
   where id = p_user_id;

  return v_streak;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_onboarded_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.onboarding_step = 'complete' and old.onboarding_step is distinct from 'complete' then
    new.onboarded_at := now();
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_timezone_from_phone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    -- only infer when the caller didn't explicitly supply one
    if new.timezone is null or btrim(new.timezone) = '' or new.timezone = 'America/New_York' then
      new.timezone := public.infer_timezone_from_phone(new.phone);
    end if;
  elsif new.phone is distinct from old.phone then
    new.timezone := public.infer_timezone_from_phone(new.phone);
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.trigger_checkins_if_due()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n      integer;
  req_id bigint;
begin
  n := public.count_due_checkins();
  if n > 0 then
    select net.http_post(
             url     := '<MAKE_CHECKIN_HOOK_URL>',
             body    := jsonb_build_object('due', n, 'triggered_at', now()),
             headers := '{"Content-Type": "application/json"}'::jsonb
           ) into req_id;
    return format('triggered for %s user(s), net request %s', n, req_id);
  end if;
  return 'nobody due - Make not called';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.upsert_streak_day(p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date;
  v_goal  integer;
  v_total integer;
begin
  select (now() at time zone coalesce(nullif(u.timezone,''),'America/New_York'))::date,
         u.protein_goal
    into v_today, v_goal
    from public.users u where u.id = p_user_id;

  if v_today is null then
    return 0;
  end if;

  v_total := round(coalesce(public.get_todays_protein_total(p_user_id), 0))::integer;

  insert into public.streaks (user_id, date, protein_total_g, protein_goal_g,
                              protein_hit, day_complete, updated_at)
  values (p_user_id, v_today, v_total, v_goal,
          v_total >= v_goal, v_total >= v_goal, now())
  on conflict (user_id, date) do update
     set protein_total_g = excluded.protein_total_g,
         protein_goal_g  = excluded.protein_goal_g,
         protein_hit     = excluded.protein_hit,
         -- a streak day is defined as hitting the protein goal
         day_complete    = excluded.protein_hit,
         updated_at      = now();

  return public.recalculate_streak(p_user_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.verification_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_starts        int;
  v_cap           int := public.verify_global_daily_cap();
  v_blocked       int;
  v_confirm_ok    int;
  v_confirm_bad   int;
  v_healthy       boolean;
  v_reasons       text[] := array[]::text[];
begin
  select count(*) filter (where action = 'start'),
         count(*) filter (where action = 'start' and outcome = 'blocked'),
         count(*) filter (where action = 'confirm' and outcome = 'approved'),
         count(*) filter (where action = 'confirm' and outcome = 'denied')
    into v_starts, v_blocked, v_confirm_ok, v_confirm_bad
    from public.verification_attempts
   where created_at > now() - interval '24 hours';

  if v_starts > v_cap then
    v_reasons := v_reasons || 'global daily cap reached: signups are being refused'::text;
  elsif v_starts >= (v_cap * 0.8)::int then
    v_reasons := v_reasons || 'global daily starts above 80% of cap'::text;
  end if;

  if v_starts >= 20 and v_blocked::numeric / greatest(v_starts, 1) > 0.5 then
    v_reasons := v_reasons || 'more than half of starts are being blocked'::text;
  end if;

  if (v_confirm_ok + v_confirm_bad) >= 20
     and v_confirm_bad::numeric / greatest(v_confirm_ok + v_confirm_bad, 1) > 0.8 then
    v_reasons := v_reasons || 'more than 80% of code confirmations are failing'::text;
  end if;

  v_healthy := (coalesce(array_length(v_reasons, 1), 0) = 0);

  return jsonb_build_object(
    'healthy', v_healthy,
    'window', '24h',
    'starts', v_starts,
    'global_cap', v_cap,
    'pct_of_cap', round((v_starts::numeric / v_cap) * 100, 1),
    'starts_blocked', v_blocked,
    'confirms_approved', v_confirm_ok,
    'confirms_denied', v_confirm_bad,
    'problems', to_jsonb(v_reasons)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.verify_global_daily_cap()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select 200 $function$
;

CREATE OR REPLACE FUNCTION public.verify_mark_outcome(p_attempt_id bigint, p_outcome text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  update public.verification_attempts
     set outcome = p_outcome
   where id = p_attempt_id
     and p_outcome in ('requested', 'blocked', 'approved', 'denied');
$function$
;

CREATE OR REPLACE FUNCTION public.verify_rate_check(p_phone text, p_ip_hash text, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_phone_hour  int;
  v_phone_day   int;
  v_ip_hour     int;
  v_ip_day      int;
  v_global_day  int;
  v_id          bigint;
  v_reason      text := null;
  c_global_cap  int := public.verify_global_daily_cap();
begin
  if p_action not in ('start', 'confirm') then
    return jsonb_build_object('allowed', false, 'reason', 'bad_action');
  end if;

  insert into public.verification_attempts (phone, ip_hash, action)
  values (p_phone, p_ip_hash, p_action)
  returning id into v_id;

  select count(*) into v_phone_hour
    from public.verification_attempts
   where phone = p_phone and action = p_action
     and created_at > now() - interval '1 hour';

  select count(*) into v_phone_day
    from public.verification_attempts
   where phone = p_phone and action = p_action
     and created_at > now() - interval '24 hours';

  if p_ip_hash is not null then
    select count(*) into v_ip_hour
      from public.verification_attempts
     where ip_hash = p_ip_hash
       and created_at > now() - interval '1 hour';

    select count(*) into v_ip_day
      from public.verification_attempts
     where ip_hash = p_ip_hash
       and created_at > now() - interval '24 hours';
  else
    v_ip_hour := 0;
    v_ip_day  := 0;
  end if;

  -- Counted for both actions so the figure can be reported, but only enforced on
  -- 'start'. Capping 'confirm' would strand people who already hold a valid code and
  -- have already cost us the money.
  select count(*) into v_global_day
    from public.verification_attempts
   where action = 'start'
     and created_at > now() - interval '24 hours';

  if p_action = 'start' then
    if v_phone_hour > 3 then v_reason := 'phone_hourly';
    elsif v_phone_day > 5 then v_reason := 'phone_daily';
    elsif v_ip_hour  > 10 then v_reason := 'ip_hourly';
    elsif v_ip_day   > 20 then v_reason := 'ip_daily';
    elsif v_global_day > c_global_cap then v_reason := 'global_daily';
    end if;
  else
    if v_phone_hour > 8 then v_reason := 'phone_hourly';
    elsif v_ip_hour > 25 then v_reason := 'ip_hourly';
    end if;
  end if;

  if v_reason is not null then
    update public.verification_attempts set outcome = 'blocked' where id = v_id;
    return jsonb_build_object('allowed', false, 'reason', v_reason, 'attempt_id', v_id,
                              'global_used', v_global_day, 'global_cap', c_global_cap);
  end if;

  return jsonb_build_object('allowed', true, 'attempt_id', v_id,
                            'global_used', v_global_day, 'global_cap', c_global_cap);
end $function$
;

-- ---------------------------------------------------------------- grants
-- Postgres grants EXECUTE to PUBLIC by default, and create-or-replace keeps the
-- existing ACL, so revoking from anon/authenticated alone is NOT enough -- PUBLIC
-- is the grant that matters. Verify with the audit query in README.md.

revoke all on function public.ai_brain_system_prompt() from public, anon, authenticated;
grant execute on function public.ai_brain_system_prompt() to service_role;
revoke all on function public.apply_ai_turn(p_user_id text, p_inbound_body text, p_twilio_sid text, p_media_url text, p_media_content_type text, p_detected_protein text, p_reply text, p_message_kind text, p_medication text, p_protein_goal text, p_workout_days text, p_wake_time text, p_onboarding_step text, p_intensity_level text, p_first_name text, p_weight_kg text) from public, anon, authenticated;
grant execute on function public.apply_ai_turn(p_user_id text, p_inbound_body text, p_twilio_sid text, p_media_url text, p_media_content_type text, p_detected_protein text, p_reply text, p_message_kind text, p_medication text, p_protein_goal text, p_workout_days text, p_wake_time text, p_onboarding_step text, p_intensity_level text, p_first_name text, p_weight_kg text) to service_role;
revoke all on function public.apply_payment_event(p_event_id text, p_event_type text, p_occurred_at text, p_user_id text, p_provider_customer_id text, p_provider_subscription_id text, p_provider_transaction_id text, p_amount_cents text, p_currency text, p_plan text, p_failure_reason text, p_paddle_status text, p_next_billed_at text, p_tax_cents text, p_fee_cents text, p_earnings_cents text, p_environment text, p_adjustment_id text, p_adjustment_action text, p_adjustment_status text) from public, anon, authenticated;
grant execute on function public.apply_payment_event(p_event_id text, p_event_type text, p_occurred_at text, p_user_id text, p_provider_customer_id text, p_provider_subscription_id text, p_provider_transaction_id text, p_amount_cents text, p_currency text, p_plan text, p_failure_reason text, p_paddle_status text, p_next_billed_at text, p_tax_cents text, p_fee_cents text, p_earnings_cents text, p_environment text, p_adjustment_id text, p_adjustment_action text, p_adjustment_status text) to service_role;
revoke all on function public.build_ai_request(p_phone text, p_body text, p_media_url text, p_media_type text, p_media_b64 text) from public, anon, authenticated;
grant execute on function public.build_ai_request(p_phone text, p_body text, p_media_url text, p_media_type text, p_media_b64 text) to service_role;
revoke all on function public.checkin_delivery_health() from public, anon, authenticated;
grant execute on function public.checkin_delivery_health() to service_role;
revoke all on function public.count_due_checkins() from public, anon, authenticated;
grant execute on function public.count_due_checkins() to service_role;
revoke all on function public.create_verified_user(p_phone text, p_preferred_plan text, p_consent_text text) from public, anon, authenticated;
grant execute on function public.create_verified_user(p_phone text, p_preferred_plan text, p_consent_text text) to service_role;
revoke all on function public.expire_lapsed_trials() from public, anon, authenticated;
grant execute on function public.expire_lapsed_trials() to service_role;
revoke all on function public.get_billing_due() from public, anon, authenticated;
grant execute on function public.get_billing_due() to service_role;
revoke all on function public.get_due_checkins() from public, anon, authenticated;
grant execute on function public.get_due_checkins() to service_role;
revoke all on function public.get_inbound_context(p_phone text) from public, anon, authenticated;
grant execute on function public.get_inbound_context(p_phone text) to service_role;
revoke all on function public.get_recent_transcript(p_user_id uuid, p_limit integer) from public, anon, authenticated;
grant execute on function public.get_recent_transcript(p_user_id uuid, p_limit integer) to service_role;
revoke all on function public.get_todays_protein_total(p_user_id uuid) from public, anon, authenticated;
grant execute on function public.get_todays_protein_total(p_user_id uuid) to service_role;
revoke all on function public.infer_timezone_from_phone(p_phone text) from public, anon, authenticated;
grant execute on function public.infer_timezone_from_phone(p_phone text) to service_role;
revoke all on function public.log_outbound_sms(p_user_id uuid, p_body text, p_kind text, p_twilio_sid text) from public, anon, authenticated;
grant execute on function public.log_outbound_sms(p_user_id uuid, p_body text, p_kind text, p_twilio_sid text) to service_role;
revoke all on function public.mark_checkin_delivered() from public, anon, authenticated;
grant execute on function public.mark_checkin_delivered() to service_role;
revoke all on function public.recalculate_streak(p_user_id uuid) from public, anon, authenticated;
grant execute on function public.recalculate_streak(p_user_id uuid) to service_role;
revoke all on function public.set_onboarded_at() from public, anon, authenticated;
grant execute on function public.set_onboarded_at() to service_role;
revoke all on function public.set_timezone_from_phone() from public, anon, authenticated;
grant execute on function public.set_timezone_from_phone() to service_role;
revoke all on function public.set_updated_at() from public, anon, authenticated;
grant execute on function public.set_updated_at() to service_role;
revoke all on function public.trigger_checkins_if_due() from public, anon, authenticated;
grant execute on function public.trigger_checkins_if_due() to service_role;
revoke all on function public.upsert_streak_day(p_user_id uuid) from public, anon, authenticated;
grant execute on function public.upsert_streak_day(p_user_id uuid) to service_role;
revoke all on function public.verification_health() from public, anon, authenticated;
grant execute on function public.verification_health() to service_role;
revoke all on function public.verify_global_daily_cap() from public, anon, authenticated;
grant execute on function public.verify_global_daily_cap() to service_role;
revoke all on function public.verify_mark_outcome(p_attempt_id bigint, p_outcome text) from public, anon, authenticated;
grant execute on function public.verify_mark_outcome(p_attempt_id bigint, p_outcome text) to service_role;
revoke all on function public.verify_rate_check(p_phone text, p_ip_hash text, p_action text) from public, anon, authenticated;
grant execute on function public.verify_rate_check(p_phone text, p_ip_hash text, p_action text) to service_role;
