-- Keep the existing RPC signature for installed clients. limit_count remains
-- accepted for compatibility; the display windows always include the caller.
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
  -- Rank the entire population first. The response windows limit payload only;
  -- no participant or global rank is capped by the display budget.
  , bounds as (
    select count(*) as total_count,
      max(rank) filter (where is_current_user) as own_rank from encoded
  ), visible as (
    select e.* from encoded e cross join bounds b
    where b.total_count <= 50 or e.rank <= 10 or e.rank > b.total_count - 10
      or e.rank between b.own_rank - 10 and b.own_rank + 10
  )
  select jsonb_build_object('entries',coalesce((select jsonb_agg(entry order by rank) from visible),'[]'::jsonb),
    'total_count',(select total_count from bounds),
    'current_user',(select entry from encoded where is_current_user), 'updated_at',pg_catalog.statement_timestamp()) into result;
  return result;
end;
$$;
