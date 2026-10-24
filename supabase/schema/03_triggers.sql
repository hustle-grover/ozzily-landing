-- Ozzily database schema: triggers.
-- GENERATED SNAPSHOT of live Supabase project siblqlstyccysqryggtr.
-- Do not edit by hand. Regenerate with generate.sql; see README.md.
-- Trigger functions live in 02_functions.sql and must be created first.

CREATE TRIGGER trg_mark_checkin_delivered AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION mark_checkin_delivered();
CREATE TRIGGER streaks_set_updated_at BEFORE UPDATE ON public.streaks FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_set_onboarded_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION set_onboarded_at();
CREATE TRIGGER trg_set_timezone_from_phone BEFORE INSERT OR UPDATE OF phone ON public.users FOR EACH ROW EXECUTE FUNCTION set_timezone_from_phone();
CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
