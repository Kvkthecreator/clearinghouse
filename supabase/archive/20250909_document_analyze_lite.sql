-- Canon v2.0 — Documents Analyze Lite Views
-- Creates staleness and composition overview views for P4 Analyze Lite UI

-- View: document_staleness
-- For each document, compare latest referenced substrate update vs current version created_at
CREATE OR REPLACE VIEW public.document_staleness AS
WITH latest_times AS (
  SELECT 
    d.id AS document_id,
    dv.version_hash,
    dv.created_at AS version_created_at,
    GREATEST(
      COALESCE(MAX(CASE WHEN sr.substrate_type = 'dump' THEN rd.created_at END), TIMESTAMPTZ '1970-01-01'),
      COALESCE(MAX(CASE WHEN sr.substrate_type = 'block' THEN cb.created_at END), TIMESTAMPTZ '1970-01-01'),
      COALESCE(MAX(CASE WHEN sr.substrate_type = 'context_item' THEN ci.updated_at END), TIMESTAMPTZ '1970-01-01')
    ) AS last_substrate_updated_at
  FROM public.documents d
  LEFT JOIN public.document_versions dv 
    ON dv.version_hash = d.current_version_hash
  LEFT JOIN public.substrate_references sr 
    ON sr.document_id = d.id
  LEFT JOIN public.raw_dumps rd 
    ON rd.id = sr.substrate_id AND sr.substrate_type = 'dump'
  LEFT JOIN public.blocks cb 
    ON cb.id = sr.substrate_id AND sr.substrate_type = 'block'
  LEFT JOIN public.context_items ci 
    ON ci.id = sr.substrate_id AND sr.substrate_type = 'context_item'
  -- Timeline events use bigint IDs; substrate_references uses uuid. Excluded from staleness.
  GROUP BY d.id, dv.version_hash, dv.created_at
)
SELECT 
  document_id,
  version_hash,
  version_created_at,
  last_substrate_updated_at,
  (last_substrate_updated_at > version_created_at) AS is_stale
FROM latest_times;

-- View: vw_document_analyze_lite
-- Combines composition stats, average reference weight, and staleness indicators
CREATE OR REPLACE VIEW public.vw_document_analyze_lite AS
SELECT 
  d.id AS document_id,
  d.title,
  d.basket_id,
  d.workspace_id,
  d.current_version_hash,
  d.updated_at AS document_updated_at,
  stats.blocks_count,
  stats.dumps_count,
  stats.context_items_count,
  stats.timeline_events_count,
  stats.total_substrate_references,
  ROUND(COALESCE(AVG(sr.weight), 0)::numeric, 2) AS avg_reference_weight,
  st.version_created_at,
  st.last_substrate_updated_at,
  st.is_stale
FROM public.documents d
LEFT JOIN public.document_composition_stats stats 
  ON stats.document_id = d.id
LEFT JOIN public.substrate_references sr 
  ON sr.document_id = d.id
LEFT JOIN public.document_staleness st 
  ON st.document_id = d.id
GROUP BY 
  d.id, d.title, d.basket_id, d.workspace_id, d.current_version_hash, d.updated_at,
  stats.blocks_count, stats.dumps_count, stats.context_items_count, stats.timeline_events_count, stats.total_substrate_references,
  st.version_created_at, st.last_substrate_updated_at, st.is_stale;
