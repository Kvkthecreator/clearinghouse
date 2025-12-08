-- 0.1 drop reverse FK + column
ALTER TABLE baskets DROP CONSTRAINT IF EXISTS fk_raw_dump;
ALTER TABLE baskets DROP COLUMN IF EXISTS raw_dump_id;
-- 0.2 make sure raw_dumps has the only FK
ALTER TABLE raw_dumps
  ADD CONSTRAINT raw_dumps_basket_id_fkey
  FOREIGN KEY (basket_id) REFERENCES baskets (id) ON DELETE CASCADE;
-- 0.3 back-fill user_id on existing baskets
UPDATE baskets
  SET user_id = (raw_dumps_owner.uid)
  FROM (
    SELECT rd.basket_id, rd_owner.uid
    FROM raw_dumps rd
    JOIN auth.users rd_owner ON rd_owner.id = rd.owner_id
  ) AS raw_dumps_owner
  WHERE baskets.id = raw_dumps_owner.basket_id
    AND baskets.user_id IS NULL;
-- 0.4 relax NOT-NULL just long enough for service inserts
ALTER TABLE baskets ALTER COLUMN user_id DROP NOT NULL;
-- 0.5 RLS: only workspace members can access baskets
ALTER TABLE baskets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Workspace members only"
  ON baskets FOR ALL
  USING (
    workspace_id IN (
      SELECT wm.workspace_id
        FROM workspace_memberships wm
       WHERE wm.user_id = auth.uid()
    )
  );
