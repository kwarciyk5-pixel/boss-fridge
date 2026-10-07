-- Boss Fridge bf-v37: Cook it can use part of an item; Save for later.
-- Additive only: nothing is dropped or deleted; every existing value is kept.
-- Run once BEFORE the bf-v37 app goes live (the app writes counts like 1.5).

begin;

-- 1. counts can hold quarters (2 - 1/2 = 1 1/2). integer -> numeric keeps every existing value exactly.
alter table public.bf_items alter column count type numeric using count::numeric;

-- 2. History: "cooked" (Save for later: a cooked pot goes to the fridge, nobody ate yet) joins the allowed actions
alter table public.bf_history drop constraint if exists bf_history_action_check;
alter table public.bf_history add constraint bf_history_action_check check (action = any (array[
  'ate', 'deleted', 'bought', 'bought_nostock', 'tossed', 'ate_dish', 'deleted_grocery', 'deleted_dish', 'used_up', 'cooked'
]));

commit;
