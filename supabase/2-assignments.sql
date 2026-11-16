-- TarihTalks: мұғалім тапсырмалары. Supabase → SQL Editor → барлығын қойып → Run
-- (supabase-teacher-setup.sql алдын ала іске қосылған болуы керек)

create table if not exists assignments (
  id bigint generated always as identity primary key,
  teacher_id uuid not null references auth.users on delete cascade,
  class_id bigint not null references classes on delete cascade,
  grade text not null,
  year_ids text[] not null,
  student_ids uuid[],          -- null болса: бүкіл сыныпқа
  title text,
  note text,
  due_date date,
  created_at timestamptz default now()
);
alter table assignments enable row level security;

create or replace function public.is_member_of(cid bigint) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from class_members where class_id = cid and student_id = auth.uid());
$$;

drop policy if exists "teacher manages own assignments" on assignments;
create policy "teacher manages own assignments" on assignments for all
  using (teacher_id = auth.uid())
  with check (teacher_id = auth.uid() and class_id in (select id from classes where teacher_id = auth.uid()));

drop policy if exists "student reads own assignments" on assignments;
create policy "student reads own assignments" on assignments for select
  using (public.is_member_of(class_id) and (student_ids is null or auth.uid() = any(student_ids)));
