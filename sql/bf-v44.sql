-- bf-v44: History may log "moved" (the Take sheet: Fridge / Freezer / Storage moves).
-- Only the allowed list of bf_history.action grows; nothing else changes.
alter table bf_history drop constraint bf_history_action_check;
alter table bf_history add constraint bf_history_action_check check (action = any (array[
  'ate', 'deleted', 'bought', 'bought_nostock', 'tossed', 'ate_dish',
  'deleted_grocery', 'deleted_dish', 'used_up', 'cooked', 'moved'
]));

-- Check: should return one row containing 'moved'.
-- select pg_get_constraintdef(oid) from pg_constraint where conname = 'bf_history_action_check';

-- UNDO (only after deleting any 'moved' rows):
-- delete from bf_history where action = 'moved';
-- alter table bf_history drop constraint bf_history_action_check;
-- alter table bf_history add constraint bf_history_action_check check (action = any (array[
--   'ate', 'deleted', 'bought', 'bought_nostock', 'tossed', 'ate_dish',
--   'deleted_grocery', 'deleted_dish', 'used_up', 'cooked'
-- ]));
