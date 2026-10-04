-- Boss Fridge bf-v34: link everything by dish_id.
-- Additive only: new columns are added and backfilled; nothing is dropped, renamed or deleted.
-- Run once in the Supabase SQL editor BEFORE the bf-v34 app goes live (the app writes nothing new until
-- bf_dishes.ingredient_ids exists, so running it after is also safe).

begin;

-- 1. new columns
alter table public.bf_dishes add column if not exists ingredient_ids jsonb not null default '[]'::jsonb;
comment on column public.bf_dishes.ingredient_ids is
  'Array of slots; a slot is an array of bf_dishes ids (alternatives), or a text line that matched no Library entry. The old ingredients column is kept in step.';
alter table public.bf_groceries add column if not exists dish_id uuid references public.bf_dishes(id) on delete set null;

-- 2. History: "Used up" (Ingredients / Household) joins the allowed actions
alter table public.bf_history drop constraint if exists bf_history_action_check;
alter table public.bf_history add constraint bf_history_action_check check (action = any (array[
  'ate', 'deleted', 'bought', 'bought_nostock', 'tossed', 'ate_dish', 'deleted_grocery', 'deleted_dish', 'used_up'
]));

-- 3. the name rule: exact (any case, spaces tidied); else the one entry whose name without its "( ... )" parts matches
create or replace function public.bf_v34_match(s text) returns uuid language sql stable as $$
  with k as (select lower(btrim(regexp_replace(coalesce(s, ''), '\s+', ' ', 'g'))) as v),
  d as (
    select id,
      lower(btrim(regexp_replace(name, '\s+', ' ', 'g'))) as n,
      lower(btrim(regexp_replace(regexp_replace(name, '\([^)]*\)', ' ', 'g'), '\s+', ' ', 'g'))) as b
    from public.bf_dishes
  )
  select coalesce(
    (select d.id from d, k where k.v <> '' and d.n = k.v order by d.id limit 1),
    (select min(d.id::text)::uuid from d, k where k.v <> '' and d.b = k.v having count(*) = 1)
  );
$$;

create temp table bf_v34_unmatched (dish text, line text, alt text) on commit drop;

-- 4. ingredients -> ingredient_ids ("A / B" = alternatives; a line with any unmatched alternative stays text)
do $$
declare
  r record; line text; alt text; ids jsonb; slots jsonb; ok boolean; m uuid;
begin
  for r in select id, name, ingredients from public.bf_dishes loop
    slots := '[]'::jsonb;
    foreach line in array coalesce(r.ingredients, '{}'::text[]) loop
      if btrim(coalesce(line, '')) = '' then continue; end if;
      ids := '[]'::jsonb; ok := true;
      foreach alt in array regexp_split_to_array(line, '/') loop
        alt := btrim(alt);
        if alt = '' then continue; end if;
        m := public.bf_v34_match(alt);
        if m is null then
          ok := false;
          insert into bf_v34_unmatched values (r.name, line, alt);
          raise notice 'unmatched: % -> "%"', r.name, alt;
        elsif not ids @> jsonb_build_array(m::text) then
          ids := ids || jsonb_build_array(m::text);
        end if;
      end loop;
      if ok and jsonb_array_length(ids) > 0 then slots := slots || jsonb_build_array(ids);
      else slots := slots || jsonb_build_array(btrim(line)); end if;
    end loop;
    update public.bf_dishes set ingredient_ids = slots where id = r.id and ingredient_ids is distinct from slots;
  end loop;
end $$;

-- 5. Shop rows -> dish_id; then one open row per dish (a later duplicate keeps its row, unlinked)
update public.bf_groceries set dish_id = public.bf_v34_match(name) where dish_id is null;
update public.bf_groceries g set dish_id = null
where g.dish_id is not null and g.status in ('to_buy', 'to_order')
  and exists (select 1 from public.bf_groceries o where o.dish_id = g.dish_id and o.status in ('to_buy', 'to_order')
              and (o.added_at, o.id::text) < (g.added_at, g.id::text));
create unique index if not exists bf_groceries_open_dish on public.bf_groceries (dish_id)
  where dish_id is not null and status in ('to_buy', 'to_order');

-- 6. Tomorrow board rows and swipe options -> dish_id (labels unchanged)
update public.bf_board set dish_id = public.bf_v34_match(label) where dish_id is null;
update public.bf_swipe_rounds r set options = (
  select jsonb_agg(
    case when jsonb_typeof(o) = 'object' and (o->>'dish_id') is null
      then o || jsonb_build_object('dish_id', public.bf_v34_match(o->>'label'))
      else o end
    order by i)
  from jsonb_array_elements(r.options) with ordinality as t(o, i))
where jsonb_typeof(r.options) = 'array' and jsonb_array_length(r.options) > 0;

-- 7. Eaten rows without a dish_id (none today) -> by item_name
update public.bf_eaten set dish_id = public.bf_v34_match(item_name) where dish_id is null;

-- 8. Favourites: bf_dish_favs is the one source; copy favourite = true to its creator if missing (column kept)
insert into public.bf_dish_favs (dish_id, email)
select id, lower(btrim(created_by)) from public.bf_dishes
where favourite and created_by is not null and btrim(created_by) <> ''
on conflict (dish_id, email) do nothing;

-- 9. the backfill's unmatched list (also printed above as notices)
select dish, line, alt from bf_v34_unmatched order by dish, alt;

drop function public.bf_v34_match(text);

commit;

-- Check (run after): expect "143 | 0 | t | t"  (dishes | text slots left | groceries linked | history allows used_up)
-- select count(*) as dishes,
--   (select count(*) from bf_dishes, jsonb_array_elements(ingredient_ids) s where jsonb_typeof(s) = 'string') as text_slots,
--   (select bool_and(dish_id is not null) from bf_groceries where status <> 'bought') as groceries_linked,
--   (select pg_get_constraintdef(oid) like '%used_up%' from pg_constraint where conname = 'bf_history_action_check') as used_up
-- from bf_dishes;
