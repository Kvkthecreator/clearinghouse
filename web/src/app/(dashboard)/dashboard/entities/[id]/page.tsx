"use client"

import { useEffect, useState, useCallback } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { ArrowLeft, ShieldCheck, Sparkles } from "lucide-react"
import { createClient } from "@/lib/supabase/client"
import { entities, assets, jobs, type RightsEntity, type Asset } from "@/lib/api"
import { ProcessingStatus, EmbeddingStatusBadge } from "@/components/ProcessingStatus"
import { AssetUploader } from "@/components/AssetUploader"
import { AssetGallery } from "@/components/AssetGallery"
import { useEntityJobPolling } from "@/hooks/useJobPolling"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"

export default function EntityDetailPage() {
  const params = useParams()
  const router = useRouter()
  const entityId = params.id as string

  const [entity, setEntity] = useState<RightsEntity | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [token, setToken] = useState<string | null>(null)
  const [assetRefreshKey, setAssetRefreshKey] = useState(0)
  const supabase = createClient()

  // Job polling
  const { jobs: entityJobs, refetch: refetchJobs, hasActiveJobs } = useEntityJobPolling(
    entityId,
    token || undefined,
    { enabled: !!token, stopOnComplete: false }
  )

  const loadData = useCallback(async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        setError('Not authenticated')
        setIsLoading(false)
        return
      }

      const entityResult = await entities.get(entityId, session.access_token)

      setEntity(entityResult.entity)
      setToken(session.access_token)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load entity')
    } finally {
      setIsLoading(false)
    }
  }, [entityId, supabase.auth])

  useEffect(() => {
    loadData()
  }, [loadData])

  const handleAssetUpload = async (asset: Asset) => {
    // Refresh asset list when new asset is uploaded
    setAssetRefreshKey(k => k + 1)

    // Trigger processing for the new asset
    if (token) {
      try {
        await assets.triggerProcessing(asset.id, token)
      } catch {
        console.warn('Asset uploaded but processing trigger failed')
      }
    }
  }

  const handleTriggerEmbedding = async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      await entities.triggerProcessing(entityId, session.access_token)

      // Refresh jobs and entity
      await loadData()
      refetchJobs()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to trigger processing')
    }
  }

  const handleJobRetry = async (jobId: string) => {
    if (!token) return
    try {
      await jobs.retry(jobId, token)
      refetchJobs()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to retry job')
    }
  }

  const handleJobCancel = async (jobId: string) => {
    if (!token) return
    try {
      await jobs.cancel(jobId, token)
      refetchJobs()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel job')
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-10 w-32" />
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Skeleton className="h-64 rounded-2xl lg:col-span-2" />
          <Skeleton className="h-64 rounded-2xl" />
        </div>
      </div>
    )
  }

  if (!entity) {
    return (
      <div className="py-12 text-center">
        <h2 className="text-xl font-semibold">Entity not found</h2>
        <Button variant="ghost" onClick={() => router.back()} className="mt-3 gap-2">
          <ArrowLeft className="h-4 w-4" />
          Go back
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="space-y-3">
          <Button variant="ghost" size="sm" onClick={() => router.back()} className="gap-2 text-muted-foreground">
            <ArrowLeft className="h-4 w-4" />
            Back
          </Button>
          <div className="space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant={entity.status === "active" ? "success" : "outline"}>
                {entity.status}
              </Badge>
              <EmbeddingStatusBadge status={entity.embedding_status} />
              <Badge variant="outline" className="capitalize">
                {entity.rights_type.replace(/_/g, " ")}
              </Badge>
            </div>
            <h1 className="text-3xl font-bold tracking-tight">{entity.title}</h1>
            <div className="flex flex-wrap items-center gap-4 text-sm text-muted-foreground">
              <span>Version {entity.version}</span>
              <span>Created {new Date(entity.created_at).toLocaleDateString()}</span>
              {entity.entity_key && <span className="font-mono text-xs">{entity.entity_key}</span>}
            </div>
          </div>
        </div>
        <div className="flex gap-2">
          {entity.embedding_status !== "processing" && entity.embedding_status !== "ready" && (
            <Button variant="outline" onClick={handleTriggerEmbedding} className="gap-2">
              <Sparkles className="h-4 w-4" />
              Generate embeddings
            </Button>
          )}
        </div>
      </div>

      {error && (
        <Card className="border-destructive/30 bg-destructive/10">
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <div>
              <CardTitle className="text-destructive">Something went wrong</CardTitle>
              <CardDescription className="text-destructive">{error}</CardDescription>
            </div>
            <Button variant="ghost" size="sm" onClick={() => setError(null)} className="text-destructive">
              Dismiss
            </Button>
          </CardHeader>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Main Content */}
        <div className="space-y-6 lg:col-span-2">
          {/* Assets Section */}
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle>Upload assets</CardTitle>
                  <CardDescription>Audio, images, video, contracts up to 50MB.</CardDescription>
                </div>
                <Badge variant="outline" className="gap-1 text-xs">
                  <ShieldCheck className="h-4 w-4" />
                  Stored with provenance
                </Badge>
              </div>
            </CardHeader>
            <CardContent className="space-y-6">
              {token && (
                <AssetUploader
                  entityId={entityId}
                  token={token}
                  onUploadComplete={handleAssetUpload}
                />
              )}
              {token && (
                <div className="space-y-3">
                  <h3 className="text-sm font-semibold">Uploaded files</h3>
                  <AssetGallery key={assetRefreshKey} entityId={entityId} token={token} />
                </div>
              )}
            </CardContent>
          </Card>

          {/* AI Permissions */}
          {entity.ai_permissions && Object.keys(entity.ai_permissions).length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>AI permissions</CardTitle>
                <CardDescription>Training, generation, and style allowances for this asset.</CardDescription>
              </CardHeader>
              <CardContent>
                <pre className="max-h-80 overflow-x-auto rounded-lg bg-muted p-4 text-sm">
                  {JSON.stringify(entity.ai_permissions, null, 2)}
                </pre>
              </CardContent>
            </Card>
          )}
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Processing Jobs */}
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0">
              <div>
                <CardTitle>Processing jobs</CardTitle>
                <CardDescription>Embedding and asset analysis tasks.</CardDescription>
              </div>
              {hasActiveJobs && <Badge variant="default">Processing…</Badge>}
            </CardHeader>
            <CardContent className="space-y-3">
              {entityJobs.length === 0 ? (
                <p className="text-sm text-muted-foreground">No processing jobs yet.</p>
              ) : (
                <div className="divide-y divide-border rounded-lg border border-border">
                  {entityJobs.map((job) => (
                    <div key={job.id} className="space-y-1 p-4">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-semibold capitalize">
                          {job.job_type.replace(/_/g, " ")}
                        </span>
                        <ProcessingStatus status={job.status} size="sm" />
                      </div>
                      <p className="text-xs text-muted-foreground">
                        {new Date(job.created_at).toLocaleString()}
                      </p>
                      {job.error_message && (
                        <p className="text-xs text-destructive mt-1 truncate" title={job.error_message}>
                          {job.error_message}
                        </p>
                      )}
                      <div className="flex gap-2 pt-1">
                        {job.status === "failed" && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-8 px-2 text-xs"
                            onClick={() => handleJobRetry(job.id)}
                          >
                            Retry
                          </Button>
                        )}
                        {(job.status === "queued" || job.status === "processing") && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-8 px-2 text-xs text-muted-foreground"
                            onClick={() => handleJobCancel(job.id)}
                          >
                            Cancel
                          </Button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Metadata */}
          <Card>
            <CardHeader>
              <CardTitle>Details</CardTitle>
              <CardDescription>Identifiers and verification state.</CardDescription>
            </CardHeader>
            <CardContent>
              <dl className="space-y-3 text-sm">
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">ID</dt>
                  <dd className="font-mono text-xs">{entity.id.slice(0, 8)}...</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">Catalog</dt>
                  <dd>
                    <Link href={`/dashboard/catalogs/${entity.catalog_id}`} className="text-primary hover:underline">
                      View
                    </Link>
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">Verification</dt>
                  <dd className="capitalize">{entity.verification_status}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">Updated</dt>
                  <dd>{new Date(entity.updated_at).toLocaleDateString()}</dd>
                </div>
              </dl>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
