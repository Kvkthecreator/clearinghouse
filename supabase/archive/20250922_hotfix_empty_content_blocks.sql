-- Hotfix: Handle empty content blocks before applying canonical constraints
-- This addresses the governance processor bug that was dropping content

BEGIN;

-- Step 1: Fill empty content from title (these blocks lost their content due to governance processor bug)
UPDATE blocks 
SET content = title
WHERE COALESCE(content, '') = '' AND COALESCE(title, '') != '';

-- Step 2: Handle any remaining blocks with both empty content and title
UPDATE blocks 
SET 
  content = 'Content recovered from ' || semantic_type || ' block',
  title = COALESCE(title, semantic_type || ' block')
WHERE COALESCE(content, '') = '' AND COALESCE(title, '') = '';

-- Step 3: Verify no empty content remains
DO $$
DECLARE
    empty_count integer;
BEGIN
    SELECT COUNT(*) INTO empty_count FROM blocks WHERE COALESCE(content, '') = '';
    IF empty_count > 0 THEN
        RAISE EXCEPTION 'Still have % blocks with empty content after hotfix', empty_count;
    END IF;
    RAISE NOTICE 'Hotfix successful: All blocks now have content';
END $$;

COMMIT;