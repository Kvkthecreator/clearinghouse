-- Canon-Compliant Substrate Schema Cleanup
-- Removes duplicate fields and enforces clear semantic separation

BEGIN;

-- Step 1: Update blocks to use canonical fields only
-- Canon principle: Each substrate type has ONE authoritative field for its content

-- First, ensure content field has all the data (migrate from body_md if needed)
UPDATE blocks 
SET content = COALESCE(content, body_md, '')
WHERE content IS NULL OR content = '';

-- Ensure title field has all the data (migrate from label if needed)
UPDATE blocks
SET title = COALESCE(title, label, semantic_type || ' block')
WHERE title IS NULL OR title = '';

-- Step 2: Update context_items to have meaningful content
-- Currently they just have entity labels, not semantic meaning
-- This will be populated by the refactored P1 agent
ALTER TABLE context_items 
ADD COLUMN IF NOT EXISTS semantic_meaning text,
ADD COLUMN IF NOT EXISTS semantic_category varchar(50);

COMMENT ON COLUMN context_items.semantic_meaning IS 'Canon-compliant semantic interpretation of the entity/concept';
COMMENT ON COLUMN context_items.semantic_category IS 'Type of semantic meaning: theme, pattern, relationship, concept';

-- Step 3: Add constraints to ensure data quality
ALTER TABLE blocks
ADD CONSTRAINT blocks_content_not_empty CHECK (content IS NOT NULL AND content != ''),
ADD CONSTRAINT blocks_title_not_empty CHECK (title IS NOT NULL AND title != '');

ALTER TABLE context_items
ADD CONSTRAINT context_items_label_not_empty CHECK (title IS NOT NULL AND title != '');

-- Step 4: Create indexes for commonly queried fields
CREATE INDEX IF NOT EXISTS idx_blocks_semantic_type ON blocks(semantic_type);
CREATE INDEX IF NOT EXISTS idx_context_items_semantic_category ON context_items(semantic_category);

-- Step 5: Update comments for clarity
COMMENT ON COLUMN blocks.content IS 'Canon: Primary knowledge content - facts, insights, actions';
COMMENT ON COLUMN blocks.title IS 'Canon: Brief descriptive title for the knowledge';
COMMENT ON COLUMN blocks.body_md IS 'DEPRECATED: Use content field instead';
COMMENT ON COLUMN blocks.label IS 'DEPRECATED: Use title field instead';

COMMENT ON COLUMN context_items.content IS 'Canon: Entity/concept description';
COMMENT ON COLUMN context_items.title IS 'Canon: Entity/concept name or label';

COMMIT;