-- TarihTalks: әкімші шолуы. SQL Editor → Run
create or replace view public.users_overview with (security_invoker = on) as
select p.name as "Аты-жөні", u.email as "Пошта",
       case when p.role = 'teacher' then 'Мұғалім' else 'Оқушы' end as "Рөлі",
       p.school as "Мектеп", u.created_at as "Тіркелген уақыты",
       u.last_sign_in_at as "Соңғы кіру"
from profiles p join auth.users u on u.id = p.id
order by u.created_at desc;
revoke all on public.users_overview from anon, authenticated;

create or replace view public.schools_summary with (security_invoker = on) as
select coalesce(school, '—') as "Мектеп",
       count(*) filter (where role = 'teacher') as "Мұғалім",
       count(*) filter (where role <> 'teacher') as "Оқушы",
       count(*) as "Барлығы"
from profiles group by school order by count(*) desc;
revoke all on public.schools_summary from anon, authenticated;
