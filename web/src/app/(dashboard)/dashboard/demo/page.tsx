'use client'

import { useEffect, useState, useMemo } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Music, BarChart3, AlertCircle, ChevronRight, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { TrackCard, type TrackData } from '@/components/demo/TrackCard'
import { TrackDetail } from '@/components/demo/TrackDetail'
import { PermissionFilters, type FilterState } from '@/components/demo/PermissionFilters'
import { RevenueDashboard } from '@/components/demo/RevenueDashboard'
import { entities } from '@/lib/api'
import { cn } from '@/lib/utils'

// Demo catalog ID - Nova Entertainment Demo
const DEMO_CATALOG_ID = '10ea7870-458b-4620-8df3-0676f2ef8b14'

type ViewMode = 'catalog' | 'dashboard'

export default function DemoPage() {
  const [tracks, setTracks] = useState<TrackData[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedTrack, setSelectedTrack] = useState<TrackData | null>(null)
  const [viewMode, setViewMode] = useState<ViewMode>('catalog')
  const [filters, setFilters] = useState<FilterState>({
    voiceSynthesis: null,
    likenessGeneration: null,
    trainingPermitted: null,
    commercialUse: null,
    artist: null,
    moodTag: null
  })

  const supabase = createClient()

  useEffect(() => {
    async function loadTracks() {
      try {
        const { data: { session } } = await supabase.auth.getSession()
        if (!session) {
          setError('Please sign in to view the demo')
          setIsLoading(false)
          return
        }

        const response = await entities.list(DEMO_CATALOG_ID, session.access_token, {
          status: 'active',
          limit: 100
        })

        setTracks(response.entities as TrackData[])
      } catch (err) {
        console.error('Failed to load tracks:', err)
        setError(err instanceof Error ? err.message : 'Failed to load demo catalog')
      } finally {
        setIsLoading(false)
      }
    }

    loadTracks()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Extract unique artists and mood tags for filters
  const { artists, moodTags } = useMemo(() => {
    const artistSet = new Set<string>()
    const moodSet = new Set<string>()

    tracks.forEach(track => {
      if (track.content?.artist_name) {
        artistSet.add(track.content.artist_name)
      }
      track.semantic_metadata?.mood_tags?.forEach(tag => moodSet.add(tag))
    })

    return {
      artists: Array.from(artistSet).sort(),
      moodTags: Array.from(moodSet).sort()
    }
  }, [tracks])

  // Filter tracks based on current filter state
  const filteredTracks = useMemo(() => {
    return tracks.filter(track => {
      const perms = track.ai_permissions || {}
      const content = track.content || {}
      const metadata = track.semantic_metadata || {}

      if (filters.voiceSynthesis !== null) {
        if (Boolean(perms.voice_synthesis) !== filters.voiceSynthesis) return false
      }
      if (filters.likenessGeneration !== null) {
        if (Boolean(perms.likeness_generation) !== filters.likenessGeneration) return false
      }
      if (filters.trainingPermitted !== null) {
        if (Boolean(perms.training_permitted) !== filters.trainingPermitted) return false
      }
      if (filters.commercialUse !== null) {
        if (Boolean(perms.commercial_use) !== filters.commercialUse) return false
      }
      if (filters.artist !== null) {
        if (content.artist_name !== filters.artist) return false
      }
      if (filters.moodTag !== null) {
        if (!metadata.mood_tags?.includes(filters.moodTag)) return false
      }

      return true
    })
  }, [tracks, filters])

  // Track counts for filter UI
  const trackCounts = useMemo(() => ({
    total: tracks.length,
    filtered: filteredTracks.length,
    voiceSynthesis: tracks.filter(t => t.ai_permissions?.voice_synthesis).length,
    likeness: tracks.filter(t => t.ai_permissions?.likeness_generation).length
  }), [tracks, filteredTracks])

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <Skeleton className="h-10 w-64" />
          <Skeleton className="h-10 w-32" />
        </div>
        <Skeleton className="h-32 w-full" />
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => (
            <Skeleton key={i} className="h-48" />
          ))}
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <Card className="border-destructive">
        <CardContent className="p-6">
          <div className="flex items-center gap-3 text-destructive">
            <AlertCircle className="h-5 w-5" />
            <div>
              <p className="font-semibold">Error loading demo</p>
              <p className="text-sm text-muted-foreground">{error}</p>
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2 text-sm text-muted-foreground mb-1">
            <Badge variant="outline">Demo</Badge>
            <span>Nova Entertainment</span>
          </div>
          <h1 className="text-3xl font-bold">
            {viewMode === 'catalog' ? 'AI-Ready Catalog' : 'Revenue Dashboard'}
          </h1>
          <p className="text-muted-foreground mt-1">
            {viewMode === 'catalog'
              ? `${tracks.length} tracks with structured AI permissions`
              : 'Projected revenue from AI platform licensing'}
          </p>
        </div>

        {/* View Toggle */}
        <div className="flex items-center gap-2 p-1 rounded-lg bg-muted">
          <Button
            variant={viewMode === 'catalog' ? 'default' : 'ghost'}
            size="sm"
            onClick={() => setViewMode('catalog')}
            className="gap-2"
          >
            <Music className="h-4 w-4" />
            Catalog
          </Button>
          <Button
            variant={viewMode === 'dashboard' ? 'default' : 'ghost'}
            size="sm"
            onClick={() => setViewMode('dashboard')}
            className="gap-2"
          >
            <BarChart3 className="h-4 w-4" />
            Revenue
          </Button>
        </div>
      </div>

      {/* Content */}
      {viewMode === 'dashboard' ? (
        <RevenueDashboard />
      ) : (
        <div className="flex gap-6">
          {/* Main Content */}
          <div className={cn(
            "flex-1 space-y-6",
            selectedTrack && "lg:max-w-[60%]"
          )}>
            {/* Filters */}
            <PermissionFilters
              filters={filters}
              onFiltersChange={setFilters}
              artists={artists}
              moodTags={moodTags}
              trackCounts={trackCounts}
            />

            {/* Track Grid */}
            {filteredTracks.length === 0 ? (
              <Card>
                <CardContent className="p-8 text-center">
                  <Music className="h-12 w-12 mx-auto text-muted-foreground/50" />
                  <p className="mt-4 font-semibold">No tracks match your filters</p>
                  <p className="text-sm text-muted-foreground mt-1">
                    Try adjusting your filter criteria
                  </p>
                  <Button
                    variant="outline"
                    size="sm"
                    className="mt-4"
                    onClick={() => setFilters({
                      voiceSynthesis: null,
                      likenessGeneration: null,
                      trainingPermitted: null,
                      commercialUse: null,
                      artist: null,
                      moodTag: null
                    })}
                  >
                    Clear Filters
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <div className={cn(
                "grid gap-4",
                selectedTrack
                  ? "grid-cols-1"
                  : "grid-cols-1 md:grid-cols-2 xl:grid-cols-3"
              )}>
                {filteredTracks.map((track) => (
                  <TrackCard
                    key={track.id}
                    track={track}
                    onClick={() => setSelectedTrack(
                      selectedTrack?.id === track.id ? null : track
                    )}
                    selected={selectedTrack?.id === track.id}
                    compact={selectedTrack !== null}
                  />
                ))}
              </div>
            )}
          </div>

          {/* Track Detail Panel */}
          {selectedTrack && (
            <div className="hidden lg:block w-[40%] min-w-[400px]">
              <div className="sticky top-6">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="font-semibold text-lg">Track Details</h3>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setSelectedTrack(null)}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                </div>
                <TrackDetail
                  track={selectedTrack}
                  onGenerateDemo={() => {
                    // TODO: Implement generation demo
                    alert('Generation demo coming soon!')
                  }}
                />
              </div>
            </div>
          )}
        </div>
      )}

      {/* Demo Explanation */}
      <Card className="border-dashed mt-8">
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10">
              <Music className="h-5 w-5 text-primary" />
            </div>
            <div className="text-sm">
              <p className="font-semibold text-foreground">What you&apos;re seeing</p>
              <p className="text-muted-foreground mt-1">
                This is how <strong>your catalog</strong> would appear to AI platforms. Each track shows
                its AI permissions (training, generation, voice synthesis), licensing terms, and semantic
                metadata for discovery. Rights holders set these terms; platforms query and license accordingly.
              </p>
              <div className="flex items-center gap-2 mt-3">
                <Button variant="outline" size="sm" className="gap-2" asChild>
                  <Link href="/dashboard/workspaces">
                    View Your Catalogs
                    <ChevronRight className="h-3 w-3" />
                  </Link>
                </Button>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
