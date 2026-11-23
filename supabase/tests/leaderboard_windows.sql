-- Run on the local/test database. Fixtures are rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(1);
insert into auth.users (id)
select md5('leaderboard-window-test-' || n)::uuid from generate_series(1,101) n;
insert into public.leaderboard_profile (user_id,display_name,install_alias)
select md5('leaderboard-window-test-' || n)::uuid,'Window test ' || n,'TEST01'
from generate_series(1,101) n;
insert into public.leaderboard_score (
  user_id,total_sessions,unique_verses,max_day_streak,badge_awards,
  total_recitation_seconds,current_day_streak,quiz_answered,quiz_correct
)
select md5('leaderboard-window-test-' || n)::uuid,n,n,n,n,n,n,
  case when n <= 25 then 1 else 0 end,case when n <= 25 then 1 else 0 end
from generate_series(1,101) n;
do $$
declare
  sample record;
  board jsonb;
  expected bigint[];
  actual bigint[];
begin
  for sample in
    with scores as (
      select s.user_id,s.updated_at,v.metric,v.value
      from public.leaderboard_score s
      join public.leaderboard_profile p using (user_id)
      cross join lateral (values
        ('total_sessions',s.total_sessions::numeric),
        ('unique_verses',s.unique_verses::numeric),
        ('max_day_streak',s.max_day_streak::numeric),
        ('badge_awards',s.badge_awards::numeric),
        ('total_recitation_seconds',s.total_recitation_seconds::numeric),
        ('current_day_streak',s.current_day_streak::numeric),
        ('devotion_days',s.devotion_days::numeric),
        ('total_devotion_seconds',s.total_devotion_seconds::numeric),
        ('max_devotion_day_streak',s.max_devotion_day_streak::numeric),
        ('current_devotion_day_streak',s.current_devotion_day_streak::numeric),
        ('quiz_accuracy',s.quiz_correct::numeric/nullif(s.quiz_answered,0))
      ) v(metric,value)
      where v.value is not null
    )
    select user_id,metric,
      row_number() over (partition by metric order by value desc,updated_at,user_id) as rank,
      count(*) over (partition by metric) as total
    from scores
  loop
    perform set_config('request.jwt.claim.sub',sample.user_id::text,true);
    board := public.get_leaderboard(sample.metric,50);
    select array_agg(pos order by pos) into expected
      from generate_series(1::bigint,sample.total) pos
      where sample.total <= 50 or pos <= 10 or pos > sample.total - 10
        or pos between sample.rank - 10 and sample.rank + 10;
    select array_agg((e->>'rank')::bigint order by ordinal) into actual
      from jsonb_array_elements(board->'entries') with ordinality as item(e,ordinal);
    if actual is distinct from expected
      or (board->'current_user'->>'rank')::bigint is distinct from sample.rank
      or (board->>'total_count')::bigint is distinct from sample.total
      or jsonb_array_length(board->'entries') > 50
      or (select count(*) from jsonb_array_elements(board->'entries') e
          where (e->>'is_current_user')::boolean) <> 1 then
      raise exception 'ranking windows verification failed for metric % at rank %', sample.metric,sample.rank;
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.get_leaderboard('total_sessions',50);
    raise exception 'missing authentication was accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;
select extensions.pass('ranking windows and caller position for all participants and metrics; unauthenticated reads rejected');
select * from extensions.finish();
rollback;
