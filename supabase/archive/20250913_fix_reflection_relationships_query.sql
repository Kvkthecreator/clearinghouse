-- Fix reflection agent query - remove non-existent metadata column from substrate_relationships
-- The reflection agent was querying for a metadata column that doesn't exist

-- This is a documentation-only migration since the fix needs to be made in the Python code
-- The substrate_relationships table structure is correct as-is:
-- - id, basket_id, from_type, from_id, to_type, to_id, 
-- - relationship_type, description, strength, created_at

-- No schema changes needed, just documenting the issue for clarity