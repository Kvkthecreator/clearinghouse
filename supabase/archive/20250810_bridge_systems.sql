-- Bridge Systems: Ensure basket_deltas populate baskets table
-- This connects the Manager Agent system (basket_deltas) to the Frontend system (baskets)

-- Function to create/update basket when delta is created
CREATE OR REPLACE FUNCTION sync_basket_from_delta()
RETURNS TRIGGER AS $$
BEGIN
  -- When a basket_delta is inserted, ensure the basket exists
  INSERT INTO baskets (id, name, status, workspace_id, created_at, updated_at)
  VALUES (
    NEW.basket_id::UUID,
    'Project ' || LEFT(NEW.basket_id, 8),  -- Generate name from basket_id
    'active',
    '00000000-0000-0000-0000-000000000001'::UUID,  -- Default workspace, update as needed
    NEW.created_at,
    NEW.created_at
  )
  ON CONFLICT (id) DO UPDATE SET
    updated_at = NEW.created_at,
    status = CASE 
      WHEN NEW.applied_at IS NOT NULL THEN 'active'
      ELSE baskets.status
    END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to sync baskets when basket_deltas are created/updated
DROP TRIGGER IF EXISTS sync_basket_trigger ON basket_deltas;
CREATE TRIGGER sync_basket_trigger
  AFTER INSERT OR UPDATE ON basket_deltas
  FOR EACH ROW
  EXECUTE FUNCTION sync_basket_from_delta();

-- Backfill existing deltas to create baskets
INSERT INTO baskets (id, name, status, workspace_id, created_at, updated_at)
SELECT DISTINCT
  basket_id::UUID,
  'Project ' || LEFT(basket_id, 8),
  'active',
  '00000000-0000-0000-0000-000000000001'::UUID,
  MIN(created_at),
  MAX(created_at)
FROM basket_deltas
WHERE NOT EXISTS (
  SELECT 1 FROM baskets WHERE baskets.id = basket_deltas.basket_id::UUID
)
GROUP BY basket_id
ON CONFLICT (id) DO NOTHING;

-- Create a default workspace if it doesn't exist
INSERT INTO workspaces (id, name, created_at)
VALUES (
  '00000000-0000-0000-0000-000000000001'::UUID,
  'Default Workspace',
  NOW()
)
ON CONFLICT (id) DO NOTHING;

COMMENT ON FUNCTION sync_basket_from_delta() IS 'Ensures baskets table is populated when Manager Agent creates basket_deltas';
COMMENT ON TRIGGER sync_basket_trigger ON basket_deltas IS 'Bridges Manager Agent results to Frontend basket display';