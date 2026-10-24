-- Ozzily database schema: tables, constraints, indexes, RLS.
-- GENERATED SNAPSHOT of live Supabase project siblqlstyccysqryggtr.
-- Do not edit by hand. Regenerate with generate.sql; see README.md.

-- ---------------------------------------------------------------- tables

create table public.affiliate_clicks (
  id                       uuid not null default gen_random_uuid(),
  user_id                  uuid not null,
  product_name             text not null,
  product_category         text,
  affiliate_url            text not null,
  trigger_context          text,
  created_at               timestamp with time zone not null default now()
);

create table public.messages (
  id                       uuid not null default gen_random_uuid(),
  user_id                  uuid not null,
  direction                text not null,
  body                     text,
  media_url                text,
  media_content_type       text,
  ai_analysis              jsonb,
  detected_protein_g       integer,
  message_kind             text,
  twilio_sid               text,
  twilio_status            text,
  created_at               timestamp with time zone not null default now()
);

create table public.payments (
  id                       uuid not null default gen_random_uuid(),
  user_id                  uuid not null,
  stripe_event_id          text,
  stripe_payment_intent_id text,
  stripe_invoice_id        text,
  amount_cents             integer not null,
  currency                 text not null default 'usd'::text,
  status                   text not null,
  plan                     text,
  failure_reason           text,
  created_at               timestamp with time zone not null default now()
);

create table public.scheduled_messages (
  id                       uuid not null default gen_random_uuid(),
  user_id                  uuid not null,
  scheduled_for            timestamp with time zone not null,
  message_kind             text not null,
  payload                  jsonb,
  status                   text not null default 'pending'::text,
  sent_at                  timestamp with time zone,
  error                    text,
  created_at               timestamp with time zone not null default now(),
  local_date               date
);

create table public.streaks (
  id                       uuid not null default gen_random_uuid(),
  user_id                  uuid not null,
  date                     date not null,
  protein_total_g          integer not null default 0,
  protein_goal_g           integer not null default 100,
  protein_hit              boolean not null default false,
  workout_hit              boolean not null default false,
  workout_minutes          integer,
  water_total_ml           integer not null default 0,
  water_hit                boolean not null default false,
  day_complete             boolean not null default false,
  created_at               timestamp with time zone not null default now(),
  updated_at               timestamp with time zone not null default now()
);

create table public.users (
  id                       uuid not null default gen_random_uuid(),
  phone                    text not null,
  first_name               text,
  medication               text,
  protein_goal             integer not null default 100,
  workout_days             integer not null default 3,
  water_goal_ml            integer not null default 3000,
  wake_time                time without time zone not null default '07:00:00'::time without time zone,
  timezone                 text not null default 'America/New_York'::text,
  onboarding_step          text not null default 'awaiting_weight'::text,
  onboarded_at             timestamp with time zone,
  subscription_status      text not null default 'trial'::text,
  trial_start              timestamp with time zone not null default now(),
  trial_end                timestamp with time zone not null default (now() + '3 days'::interval),
  stripe_customer_id       text,
  stripe_subscription_id   text,
  plan                     text,
  intensity_level          text not null default 'steady'::text,
  current_streak           integer not null default 0,
  longest_streak           integer not null default 0,
  last_checkin_date        date,
  last_message_at          timestamp with time zone,
  last_water_log_at        timestamp with time zone,
  last_bowel_log_at        timestamp with time zone,
  sms_opted_out            boolean not null default false,
  opted_out_at             timestamp with time zone,
  created_at               timestamp with time zone not null default now(),
  updated_at               timestamp with time zone not null default now(),
  consent_at               timestamp with time zone,
  consent_text             text,
  weight_kg                numeric(5,1)
);

-- ----------------------------------------------------------- constraints

alter table public.affiliate_clicks add constraint affiliate_clicks_pkey PRIMARY KEY (id);
alter table public.affiliate_clicks add constraint affiliate_clicks_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.affiliate_clicks add constraint affiliate_clicks_product_category_check CHECK ((product_category = ANY (ARRAY['protein'::text, 'electrolytes'::text, 'fiber'::text, 'magnesium'::text, 'other'::text])));
alter table public.messages add constraint messages_twilio_sid_key UNIQUE (twilio_sid);
alter table public.messages add constraint messages_pkey PRIMARY KEY (id);
alter table public.messages add constraint messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.messages add constraint messages_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text])));
alter table public.messages add constraint messages_message_kind_check CHECK ((message_kind = ANY (ARRAY['onboarding'::text, 'morning_checkin'::text, 'midday_checkin'::text, 'evening_checkin'::text, 'recap'::text, 'meal_photo'::text, 'workout_photo'::text, 'meal_log'::text, 'workout_log'::text, 'side_effect'::text, 'billing'::text, 'system'::text, 'freeform'::text])));
alter table public.payments add constraint payments_stripe_event_id_key UNIQUE (stripe_event_id);
alter table public.payments add constraint payments_pkey PRIMARY KEY (id);
alter table public.payments add constraint payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.payments add constraint payments_plan_check CHECK ((plan = ANY (ARRAY['monthly'::text, 'annual'::text])));
alter table public.payments add constraint payments_status_check CHECK ((status = ANY (ARRAY['succeeded'::text, 'failed'::text, 'refunded'::text, 'pending'::text])));
alter table public.scheduled_messages add constraint scheduled_messages_pkey PRIMARY KEY (id);
alter table public.scheduled_messages add constraint scheduled_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.scheduled_messages add constraint scheduled_messages_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'cancelled'::text])));
alter table public.streaks add constraint streaks_user_id_date_key UNIQUE (user_id, date);
alter table public.streaks add constraint streaks_pkey PRIMARY KEY (id);
alter table public.streaks add constraint streaks_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.users add constraint users_phone_key UNIQUE (phone);
alter table public.users add constraint users_pkey PRIMARY KEY (id);
alter table public.users add constraint users_intensity_level_check CHECK ((intensity_level = ANY (ARRAY['chill'::text, 'steady'::text, 'intense'::text])));
alter table public.users add constraint users_medication_check CHECK ((medication = ANY (ARRAY['ozempic'::text, 'wegovy'::text, 'mounjaro'::text, 'zepbound'::text, 'other'::text])));
alter table public.users add constraint users_onboarding_step_check CHECK ((onboarding_step = ANY (ARRAY['awaiting_weight'::text, 'awaiting_workout_days'::text, 'awaiting_wake_time'::text, 'complete'::text, 'awaiting_medication'::text, 'awaiting_protein_goal'::text])));
alter table public.users add constraint users_phone_e164_chk CHECK ((phone ~ '^\+[1-9][0-9]{7,14}$'::text));
alter table public.users add constraint users_plan_check CHECK ((plan = ANY (ARRAY['monthly'::text, 'annual'::text, 'unspecified'::text])));
alter table public.users add constraint users_protein_goal_check CHECK (((protein_goal >= 20) AND (protein_goal <= 400)));
alter table public.users add constraint users_subscription_status_check CHECK ((subscription_status = ANY (ARRAY['trial'::text, 'active'::text, 'past_due'::text, 'paused'::text, 'cancelled'::text, 'expired'::text])));
alter table public.users add constraint users_water_goal_ml_check CHECK (((water_goal_ml >= 500) AND (water_goal_ml <= 10000)));
alter table public.users add constraint users_weight_kg_check CHECK (((weight_kg IS NULL) OR ((weight_kg >= (25)::numeric) AND (weight_kg <= (400)::numeric))));
alter table public.users add constraint users_workout_days_check CHECK (((workout_days >= 0) AND (workout_days <= 7)));

-- --------------------------------------------------------------- indexes

CREATE INDEX affiliate_clicks_user_idx ON public.affiliate_clicks USING btree (user_id, created_at DESC);
CREATE INDEX messages_kind_idx ON public.messages USING btree (message_kind);
CREATE INDEX messages_user_created_idx ON public.messages USING btree (user_id, created_at DESC);
CREATE INDEX payments_user_idx ON public.payments USING btree (user_id, created_at DESC);
CREATE INDEX scheduled_messages_due_idx ON public.scheduled_messages USING btree (scheduled_for) WHERE (status = 'pending'::text);
CREATE UNIQUE INDEX uq_scheduled_messages_beat_claim ON public.scheduled_messages USING btree (user_id, message_kind, local_date);
CREATE INDEX streaks_user_date_idx ON public.streaks USING btree (user_id, date DESC);
CREATE INDEX users_phone_idx ON public.users USING btree (phone);
CREATE INDEX users_subscription_status_idx ON public.users USING btree (subscription_status);
CREATE INDEX users_trial_end_idx ON public.users USING btree (trial_end) WHERE (subscription_status = 'trial'::text);
CREATE INDEX users_wake_time_idx ON public.users USING btree (wake_time, timezone) WHERE (sms_opted_out = false);

-- ------------------------------------------------------------------- RLS
-- Full lockdown: RLS on with zero permissive policies. All access is
-- server-side via the service_role key; the anon key is deliberately unused.

alter table public.affiliate_clicks enable row level security;
alter table public.messages enable row level security;
alter table public.payments enable row level security;
alter table public.scheduled_messages enable row level security;
alter table public.streaks enable row level security;
alter table public.users enable row level security;
