-- TarihTalks: мұғалім / оқушы жүйесі. Supabase → SQL Editor → барлығын қойып → Run

-- 1. Профиль тіркелгенде автоматты түрде жасалады
alter table profiles add column if not exists role text default 'student';
alter table profiles add column if not exists school text;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name, role, school)
  values (new.id, new.raw_user_meta_data->>'name',
          case when new.raw_user_meta_data->>'role' = 'teacher' then 'teacher' else 'student' end,
          new.raw_user_meta_data->>'school')
  on conflict (id) do update set name = excluded.name, role = excluded.role, school = excluded.school;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- бұрын тіркелген аккаунттар үшін
insert into profiles (id, name, role)
select id, raw_user_meta_data->>'name', 'student' from auth.users
on conflict (id) do nothing;

-- оқушы өз рөлін «мұғалім» деп өзгерте алмайды
revoke insert, update on profiles from authenticated;
grant update (name, school, grade) on profiles to authenticated;

-- 2. Сыныптар
create table if not exists classes (
  id bigint generated always as identity primary key,
  teacher_id uuid not null references auth.users on delete cascade,
  name text not null,
  code text unique not null,
  created_at timestamptz default now()
);
create table if not exists class_members (
  class_id bigint references classes on delete cascade,
  student_id uuid references auth.users on delete cascade,
  joined_at timestamptz default now(),
  primary key (class_id, student_id)
);
alter table classes enable row level security;
alter table class_members enable row level security;

create or replace function public.is_teacher_of(stu uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from class_members m join classes c on c.id = m.class_id
                 where m.student_id = stu and c.teacher_id = auth.uid());
$$;

create policy "teacher manages own classes" on classes for all
  using (teacher_id = auth.uid())
  with check (teacher_id = auth.uid() and exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'teacher'));

create policy "student sees own membership" on class_members for select using (student_id = auth.uid());
create policy "student leaves class" on class_members for delete using (student_id = auth.uid());
create policy "teacher sees members" on class_members for select
  using (class_id in (select id from classes where teacher_id = auth.uid()));
create policy "teacher removes members" on class_members for delete
  using (class_id in (select id from classes where teacher_id = auth.uid()));

-- 3. Мұғалім өз оқушыларының деректерін көреді
create policy "teacher reads students" on profiles for select using (public.is_teacher_of(id));
create policy "teacher reads progress" on progress for select using (public.is_teacher_of(user_id));
create policy "teacher reads results" on check_results for select using (public.is_teacher_of(user_id));

-- 4. Сыныпқа код арқылы қосылу және өз сыныптарын көру
create or replace function public.join_class(p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare cid bigint; cname text;
begin
  select id, name into cid, cname from classes where code = upper(trim(p_code));
  if cid is null then raise exception 'CLASS_NOT_FOUND'; end if;
  insert into class_members (class_id, student_id) values (cid, auth.uid()) on conflict do nothing;
  return cname;
end $$;

create or replace function public.my_classes()
returns table (class_id bigint, class_name text, teacher_name text)
language sql security definer stable set search_path = public as $$
  select c.id, c.name, p.name from class_members m
  join classes c on c.id = m.class_id
  left join profiles p on p.id = c.teacher_id
  where m.student_id = auth.uid();
$$;

-- 5. Әкімшіге шолу: кім, қай мектептен, қандай рөлмен тіркелді
-- Table Editor → users_overview (немесе SQL: select * from users_overview;)
create or replace view public.users_overview with (security_invoker = on) as
select p.name as "Аты-жөні", u.email as "Пошта",
       case when p.role = 'teacher' then 'Мұғалім' else 'Оқушы' end as "Рөлі",
       p.school as "Мектеп", u.created_at as "Тіркелген уақыты",
       u.last_sign_in_at as "Соңғы кіру"
from profiles p join auth.users u on u.id = p.id
order by u.created_at desc;
revoke all on public.users_overview from anon, authenticated;

-- мектеп бойынша жиынтық
create or replace view public.schools_summary with (security_invoker = on) as
select coalesce(school, '—') as "Мектеп",
       count(*) filter (where role = 'teacher') as "Мұғалім",
       count(*) filter (where role <> 'teacher') as "Оқушы",
       count(*) as "Барлығы"
from profiles group by school order by count(*) desc;
revoke all on public.schools_summary from anon, authenticated;
