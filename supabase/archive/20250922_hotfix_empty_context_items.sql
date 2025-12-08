-- Hotfix: Handle empty titles in context_items before applying canonical constraints

BEGIN;

-- Step 1: Fill empty titles from content (first 30 chars)
UPDATE context_items 
SET title = LEFT(COALESCE(content, ''), 30) || CASE WHEN LENGTH(content) > 30 THEN '...' ELSE '' END
WHERE COALESCE(title, '') = '' AND COALESCE(content, '') != '';

-- Step 2: Handle context_items with both empty title and content
UPDATE context_items 
SET 
  title = type || ' entity',
  content = COALESCE(content, 'Context item of type ' || type)
WHERE COALESCE(title, '') = '';

-- Step 3: Verify no empty titles remain
DO $$
DECLARE
    empty_count integer;
BEGIN
    SELECT COUNT(*) INTO empty_count FROM context_items WHERE COALESCE(title, '') = '';
    IF empty_count > 0 THEN
        RAISE EXCEPTION 'Still have % context_items with empty titles after hotfix', empty_count;
    END IF;
    RAISE NOTICE 'Hotfix successful: All context_items now have titles';
END $$;

COMMIT;