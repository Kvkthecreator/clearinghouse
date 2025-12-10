# Clearinghouse Refactoring Plan

## Current State Assessment

### Database Schema: COMPLETE
The following tables already exist and are properly configured:

| Table | Status | Notes |
|-------|--------|-------|
| `rights_entities` | ✅ Ready | Has `embedding_status`, `semantic_metadata` columns |
| `reference_assets` | ✅ Ready | Full schema with `processing_status`, audio metadata fields |
| `processing_jobs` | ✅ Ready | Job queue with status trigger to update entity `embedding_status` |
| `entity_embeddings` | ✅ Ready | pgvector with HNSW index, supports 1536-dim embeddings |
| `rights_schemas` | ✅ Ready | 7 IP types seeded (music, voice, character, visual, literary, video) |

### Storage: NEEDS SETUP
- **Existing bucket**: `yarnnn-assets` (50MB limit, docs/images only)
- **Required**: `reference-assets` bucket for audio/video/larger files
- **Note**: `reference_assets.storage_bucket` defaults to `'reference-assets'`

### API Routes: PARTIAL
| Route | Status | Gap |
|-------|--------|-----|
| `/entities` | ⚠️ Partial | Missing `embedding_status` in response |
| `/assets` | ⚠️ Partial | No file upload, just metadata CRUD |
| `/jobs` | ❌ Stubbed | Returns 501 |
| `/search/semantic` | ❌ Stubbed | Returns 501 |
| Bulk import | ❌ Missing | No endpoint exists |

### Frontend: PARTIAL
- Entity creation: Only `type` + `title` fields
- No file upload UI
- No processing status display
- No bulk import UI

---

## Implementation Phases

### Phase 1: Storage & File Upload API
**Goal**: Enable file uploads to Supabase Storage via API

#### 1.1 Create Storage Bucket (Supabase Dashboard or SQL)
```sql
-- Run in Supabase SQL Editor
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'reference-assets',
  'reference-assets',
  false,
  104857600, -- 100MB
  ARRAY[
    'audio/*',
    'video/*',
    'image/*',
    'application/pdf',
    'text/*',
    'application/json'
  ]
);

-- RLS Policy: Users can upload to paths under their entity's catalog
CREATE POLICY "Users can upload assets" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'reference-assets' AND
  EXISTS (
    SELECT 1 FROM reference_assets ra
    JOIN rights_entities re ON re.id = ra.rights_entity_id
    JOIN catalogs c ON c.id = re.catalog_id
    JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
    WHERE wm.user_id = auth.uid()::text
    AND storage.foldername(name)[1] = c.id::text
  )
);

-- RLS Policy: Users can read their own assets
CREATE POLICY "Users can read own assets" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'reference-assets' AND
  EXISTS (
    SELECT 1 FROM reference_assets ra
    JOIN rights_entities re ON re.id = ra.rights_entity_id
    JOIN catalogs c ON c.id = re.catalog_id
    JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
    WHERE wm.user_id = auth.uid()::text
    AND storage.foldername(name)[1] = c.id::text
  )
);
```

#### 1.2 Update assets.py Route
```python
# New endpoints needed:
POST /api/v1/entities/{entity_id}/assets/upload
  - Accept multipart/form-data
  - Upload to Supabase Storage
  - Create reference_assets record
  - Return signed URL

GET /api/v1/assets/{asset_id}/url
  - Generate signed download URL
```

#### 1.3 Files to Modify
- `substrate-api/api/src/app/routes/assets.py` - Add upload endpoint
- `substrate-api/api/src/app/deps.py` - Add Supabase storage client

---

### Phase 2: Processing Jobs API
**Goal**: Enable job creation, status polling, and job queue management

#### 2.1 Update jobs.py Route
```python
# Endpoints to implement (currently stubbed):
POST /api/v1/entities/{entity_id}/process
  - Create processing_job record
  - Set entity embedding_status = 'processing'
  - Return job_id

GET /api/v1/jobs/{job_id}
  - Return job status, progress, error if any

GET /api/v1/entities/{entity_id}/jobs
  - List all jobs for entity

POST /api/v1/jobs/{job_id}/cancel
  - Cancel queued job
```

#### 2.2 Update rights_entities.py
- Include `embedding_status` in list/get responses (currently omitted)

#### 2.3 Files to Modify
- `substrate-api/api/src/app/routes/jobs.py` - Implement endpoints
- `substrate-api/api/src/app/routes/rights_entities.py` - Add embedding_status to responses

---

### Phase 3: Bulk Import API
**Goal**: Support CSV/JSON upload for batch entity creation

#### 3.1 New Endpoint
```python
POST /api/v1/catalogs/{catalog_id}/import
  - Accept JSON array or CSV file
  - Validate against rights_schema
  - Create processing_job with type='batch_import'
  - Return job_id for status tracking

# Request body (JSON):
{
  "entities": [
    {
      "rights_type": "sound_recording",
      "title": "Track 1",
      "entity_key": "ISRC123",
      "content": {...},
      "ai_permissions": {...}
    },
    ...
  ]
}

# Or CSV with headers matching schema fields
```

#### 3.2 Files to Create/Modify
- `substrate-api/api/src/app/routes/imports.py` - New route file
- `substrate-api/api/src/app/main.py` - Register route

---

### Phase 4: Frontend Upload & Status UI
**Goal**: File upload, processing status, bulk import UI

#### 4.1 Entity Detail Page (NEW)
```
/dashboard/entities/[id]/page.tsx
- Full entity view with all fields
- File upload dropzone
- Asset list with download links
- Processing status indicator
- Timeline history
```

#### 4.2 Update Catalog Detail Page
```
/dashboard/catalogs/[id]/page.tsx
- Add embedding_status badge to entity cards
- Add bulk import button
- Show processing progress bar
```

#### 4.3 New Components
```
/components/FileUpload.tsx - Drag-drop upload with progress
/components/ProcessingStatus.tsx - Status badge with polling
/components/BulkImportModal.tsx - CSV/JSON import wizard
```

#### 4.4 API Client Updates
```typescript
// web/src/lib/api.ts additions:
assets.upload(entityId, file, assetType)
assets.getUrl(assetId)
jobs.get(jobId)
jobs.list(entityId)
imports.bulk(catalogId, entities)
```

#### 4.5 Files to Create/Modify
- `web/src/app/(dashboard)/dashboard/entities/[id]/page.tsx` - NEW
- `web/src/app/(dashboard)/dashboard/catalogs/[id]/page.tsx` - Update
- `web/src/components/FileUpload.tsx` - NEW
- `web/src/components/ProcessingStatus.tsx` - NEW
- `web/src/components/BulkImportModal.tsx` - NEW
- `web/src/lib/api.ts` - Add new methods

---

### Phase 5: Auto-Workspace on Signup
**Goal**: Reduce onboarding friction

#### 5.1 Option A: Database Trigger (Recommended)
```sql
-- Trigger on auth.users insert
CREATE OR REPLACE FUNCTION create_default_workspace()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO workspaces (name, slug, created_by)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'name', 'My Workspace'),
    'default-' || NEW.id::text,
    NEW.id::text
  );

  INSERT INTO workspace_memberships (workspace_id, user_id, role)
  SELECT id, NEW.id::text, 'owner'
  FROM workspaces
  WHERE created_by = NEW.id::text
  LIMIT 1;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION create_default_workspace();
```

#### 5.2 Option B: API Middleware
- Check for workspace on each authenticated request
- Auto-create if none exists
- Less elegant but more controllable

#### 5.3 Frontend Updates
- Dashboard: Skip "Create Workspace" CTA if default exists
- Sidebar: Collapse workspace selector for single-workspace users

---

## Execution Order

```
Week 1: Phase 1 (Storage) + Phase 2 (Jobs API)
        ├─ Create bucket, policies
        ├─ Implement upload endpoint
        ├─ Implement jobs endpoints
        └─ Update entity responses

Week 2: Phase 3 (Bulk Import) + Phase 4 (Frontend)
        ├─ Bulk import endpoint
        ├─ Entity detail page
        ├─ File upload component
        └─ Processing status component

Week 3: Phase 5 (Auto-workspace) + Polish
        ├─ Auto-workspace trigger
        ├─ UI refinements
        └─ Error handling
```

---

## Storage Configuration Reference

### Bucket: `reference-assets`
| Setting | Value |
|---------|-------|
| Public | false |
| Max file size | 100MB |
| Allowed MIME types | audio/*, video/*, image/*, application/pdf, text/*, application/json |

### Storage Path Convention
```
{catalog_id}/{entity_id}/{asset_type}/{filename}
```
Example: `abc123/def456/audio_master/track.wav`

### Signed URL Expiry
- Download URLs: 1 hour (configurable)
- Upload URLs: 15 minutes

---

## Worker/Background Processing (Future)

The `processing_jobs` table is designed for a job queue worker. Options:

1. **Supabase Edge Functions** - Trigger on job insert
2. **External Worker** - Poll `processing_jobs` table
3. **Render Background Worker** - Separate service

Worker responsibilities:
- Poll for `status='queued'` jobs
- Download asset from storage
- Generate embeddings (OpenAI, CLAP, etc.)
- Insert into `entity_embeddings`
- Update job status → triggers `update_entity_embedding_status()`

This is deferred until core upload/CRUD flows are working.

---

## API Response Schema Updates

### Entity Response (Updated)
```json
{
  "id": "uuid",
  "catalog_id": "uuid",
  "rights_type": "sound_recording",
  "title": "My Track",
  "status": "active",
  "embedding_status": "pending",  // ADD THIS
  "version": 1,
  "created_at": "...",
  "updated_at": "..."
}
```

### Asset Upload Response
```json
{
  "asset": {
    "id": "uuid",
    "rights_entity_id": "uuid",
    "asset_type": "audio_master",
    "filename": "track.wav",
    "mime_type": "audio/wav",
    "file_size_bytes": 12345678,
    "storage_path": "catalog_id/entity_id/audio_master/track.wav",
    "processing_status": "uploaded"
  },
  "upload_url": "https://..."  // If using signed upload
}
```

### Job Response
```json
{
  "job": {
    "id": "uuid",
    "job_type": "embedding_generation",
    "status": "queued",
    "priority": 0,
    "retry_count": 0,
    "created_at": "..."
  }
}
```
