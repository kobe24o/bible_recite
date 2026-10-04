alter table public.leaderboard_score
  add column devotion_days bigint not null default 0 check (devotion_days >= 0),
  add column total_devotion_seconds bigint not null default 0 check (total_devotion_seconds >= 0),
  add column max_devotion_day_streak bigint not null default 0 check (max_devotion_day_streak >= 0),
  add column current_devotion_day_streak bigint not null default 0 check (current_devotion_day_streak >= 0);

create index leaderboard_devotion_days on public.leaderboard_score (devotion_days desc, updated_at, user_id);
create index leaderboard_devotion_seconds on public.leaderboard_score (total_devotion_seconds desc, updated_at, user_id);
create index leaderboard_max_devotion_streak on public.leaderboard_score (max_devotion_day_streak desc, updated_at, user_id);
create index leaderboard_current_devotion_streak on public.leaderboard_score (current_devotion_day_streak desc, updated_at, user_id);

create function leaderboard_private.submit_snapshot(
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
     or max_day_streak < previous.max_day_streak or badge_awards < previous.badge_awards
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

create or replace function leaderboard_private.submit_snapshot(
  display_name text, install_alias text, total_sessions bigint, unique_verses bigint,
  max_day_streak bigint, badge_awards bigint, total_recitation_seconds bigint,
  current_day_streak bigint, quiz_answered bigint, quiz_correct bigint
) returns void language plpgsql security definer set search_path = '' as $$
declare previous public.leaderboard_score;
begin
  select * into previous from public.leaderboard_score where user_id = auth.uid();
  perform leaderboard_private.submit_snapshot(
    display_name, install_alias, total_sessions, unique_verses, max_day_streak,
    badge_awards, total_recitation_seconds, current_day_streak, quiz_answered,
    quiz_correct, coalesce(previous.devotion_days, 0),
    coalesce(previous.total_devotion_seconds, 0),
    coalesce(previous.max_devotion_day_streak, 0),
    coalesce(previous.current_devotion_day_streak, 0)
  );
end;
$$;

create function public.submit_leaderboard_snapshot(
  display_name text, install_alias text, total_sessions bigint, unique_verses bigint,
  max_day_streak bigint, badge_awards bigint, total_recitation_seconds bigint,
  current_day_streak bigint, quiz_answered bigint, quiz_correct bigint,
  devotion_days bigint, total_devotion_seconds bigint, max_devotion_day_streak bigint,
  current_devotion_day_streak bigint
) returns void language sql security invoker set search_path = '' as $$
  select leaderboard_private.submit_snapshot(display_name,install_alias,total_sessions,unique_verses,max_day_streak,badge_awards,total_recitation_seconds,current_day_streak,quiz_answered,quiz_correct,devotion_days,total_devotion_seconds,max_devotion_day_streak,current_devotion_day_streak);
$$;

create or replace function public.submit_leaderboard_snapshot(
  display_name text, install_alias text, total_sessions bigint, unique_verses bigint,
  max_day_streak bigint, badge_awards bigint, total_recitation_seconds bigint,
  current_day_streak bigint, quiz_answered bigint, quiz_correct bigint
) returns void language sql security invoker set search_path = '' as $$
  select leaderboard_private.submit_snapshot(display_name,install_alias,total_sessions,unique_verses,max_day_streak,badge_awards,total_recitation_seconds,current_day_streak,quiz_answered,quiz_correct);
$$;

create or replace function leaderboard_private.read_board(metric text, limit_count integer default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller uuid := auth.uid(); result jsonb;
begin
  if caller is null then raise exception 'authentication required' using errcode='42501'; end if;
  if metric is null or metric not in (
    'total_sessions','unique_verses','max_day_streak','badge_awards',
    'total_recitation_seconds','current_day_streak','quiz_accuracy','devotion_days',
    'total_devotion_seconds','max_devotion_day_streak','current_devotion_day_streak'
  ) then raise exception 'unsupported metric' using errcode='22023'; end if;
  with values_for_metric as (
    select s.user_id, p.display_name, s.updated_at,
      case metric when 'total_sessions' then s.total_sessions::numeric
        when 'unique_verses' then s.unique_verses::numeric
        when 'max_day_streak' then s.max_day_streak::numeric
        when 'badge_awards' then s.badge_awards::numeric
        when 'total_recitation_seconds' then s.total_recitation_seconds::numeric
        when 'current_day_streak' then s.current_day_streak::numeric
        when 'devotion_days' then s.devotion_days::numeric
        when 'total_devotion_seconds' then s.total_devotion_seconds::numeric
        when 'max_devotion_day_streak' then s.max_devotion_day_streak::numeric
        when 'current_devotion_day_streak' then s.current_devotion_day_streak::numeric
        when 'quiz_accuracy' then s.quiz_correct::numeric / nullif(s.quiz_answered,0) end as value
    from public.leaderboard_score s join public.leaderboard_profile p using (user_id)
    where metric <> 'quiz_accuracy' or s.quiz_answered > 0
  ), ranked as (
    select row_number() over (order by value desc, updated_at asc, user_id asc) as rank,
      display_name, value, user_id=caller as is_current_user from values_for_metric
  ), encoded as (
    select rank, is_current_user, jsonb_build_object('rank',rank,'display_name',display_name,'value',value,'is_current_user',is_current_user) as entry from ranked
  )
  select jsonb_build_object('entries',coalesce((select jsonb_agg(entry order by rank) from encoded where rank <= greatest(1,least(50,coalesce(limit_count,50)))),'[]'::jsonb),
    'current_user',(select entry from encoded where is_current_user), 'updated_at',pg_catalog.statement_timestamp()) into result;
  return result;
end;
$$;

revoke all on function
  leaderboard_private.submit_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  leaderboard_private.submit_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  leaderboard_private.read_board(text,integer),
  public.submit_leaderboard_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  public.submit_leaderboard_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  public.get_leaderboard(text,integer)
from public, anon;
grant execute on function
  leaderboard_private.submit_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  leaderboard_private.submit_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  leaderboard_private.read_board(text,integer),
  public.submit_leaderboard_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  public.submit_leaderboard_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint),
  public.get_leaderboard(text,integer)
to authenticated;
