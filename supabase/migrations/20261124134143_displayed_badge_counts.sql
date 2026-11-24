-- Badge totals follow the visible gallery, including repeats.
-- Allow derived badge corrections while retaining other cumulative guards.
create or replace function leaderboard_private.submit_snapshot(
  display_name text, install_alias text, total_sessions bigint, unique_verses bigint,
  max_day_streak bigint, badge_awards bigint, total_recitation_seconds bigint,
  current_day_streak bigint, quiz_answered bigint, quiz_correct bigint,
  devotion_days bigint, total_devotion_seconds bigint, max_devotion_day_streak bigint,
  current_devotion_day_streak bigint
) returns void language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := auth.uid();
  previous public.leaderboard_score;
  stamp timestamptz := pg_catalog.clock_timestamp();
begin
  if caller is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if pg_catalog.num_nonnulls(total_sessions, unique_verses, max_day_streak, badge_awards,
       total_recitation_seconds, current_day_streak, quiz_answered, quiz_correct,
       devotion_days, total_devotion_seconds, max_devotion_day_streak, current_devotion_day_streak) <> 12
     or least(total_sessions, unique_verses, max_day_streak, badge_awards,
          total_recitation_seconds, current_day_streak, quiz_answered, quiz_correct,
          devotion_days, total_devotion_seconds, max_devotion_day_streak,
          current_devotion_day_streak) < 0
     or quiz_correct > quiz_answered then
    raise exception 'invalid snapshot' using errcode = '22023';
  end if;
  if display_name is null or char_length(trim(display_name)) not between 1 and 80
     or install_alias is null or install_alias !~ '^[A-Z0-9]{6}$' then
    raise exception 'invalid identity' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(caller::text,0));
  select * into previous from public.leaderboard_score s where s.user_id = caller for update;
  if found and (total_sessions < previous.total_sessions or unique_verses < previous.unique_verses
     or max_day_streak < previous.max_day_streak
     or total_recitation_seconds < previous.total_recitation_seconds
     or devotion_days < previous.devotion_days
     or total_devotion_seconds < previous.total_devotion_seconds
     or max_devotion_day_streak < previous.max_devotion_day_streak) then
    raise exception 'cumulative values cannot decrease' using errcode = '22023';
  end if;
  insert into public.leaderboard_profile as p values (caller, trim(display_name), install_alias, stamp)
  on conflict (user_id) do update set display_name=excluded.display_name, install_alias=excluded.install_alias, updated_at=excluded.updated_at;
  insert into public.leaderboard_score as s (
    user_id, total_sessions, unique_verses, max_day_streak, badge_awards,
    total_recitation_seconds, current_day_streak, quiz_answered, quiz_correct,
    devotion_days, total_devotion_seconds, max_devotion_day_streak,
    current_devotion_day_streak, updated_at
  ) values (
    caller, total_sessions, unique_verses, max_day_streak, badge_awards,
    total_recitation_seconds, current_day_streak, quiz_answered, quiz_correct,
    devotion_days, total_devotion_seconds, max_devotion_day_streak,
    current_devotion_day_streak, stamp
  ) on conflict (user_id) do update set
    total_sessions=excluded.total_sessions, unique_verses=excluded.unique_verses,
    max_day_streak=excluded.max_day_streak, badge_awards=excluded.badge_awards,
    total_recitation_seconds=excluded.total_recitation_seconds,
    current_day_streak=excluded.current_day_streak, quiz_answered=excluded.quiz_answered,
    quiz_correct=excluded.quiz_correct, devotion_days=excluded.devotion_days,
    total_devotion_seconds=excluded.total_devotion_seconds,
    max_devotion_day_streak=excluded.max_devotion_day_streak,
    current_devotion_day_streak=excluded.current_devotion_day_streak,
    updated_at=excluded.updated_at;
end;
$$;
