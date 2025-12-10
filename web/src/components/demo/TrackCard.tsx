'use client'

import { Music, Mic, User, Clock, Check, X, DollarSign } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

export interface TrackData {
  id: string
  title: string
  entity_key?: string
  content?: {
    artist_name?: string
    album?: string
    duration_seconds?: number
    genre?: string[]
    release_date?: string
    audio_features?: {
      bpm?: number
      key?: string
      energy?: number
    }
  }
  ai_permissions?: {
    training_permitted?: boolean
    generation_reference?: boolean
    generation_fee_per_use?: number
    voice_synthesis?: boolean
    voice_synthesis_rate?: number
    likeness_generation?: boolean
    likeness_rate?: number
    commercial_use?: boolean
    commercial_terms?: string
    attribution_text?: string
  }
  semantic_metadata?: {
    mood_tags?: string[]
    theme_tags?: string[]
    instrument_tags?: string[]
    vocal_tags?: string[]
  }
}

interface TrackCardProps {
  track: TrackData
  onClick?: () => void
  selected?: boolean
  compact?: boolean
}

function formatDuration(seconds?: number): string {
  if (!seconds) return '--:--'
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

function PermissionBadge({
  allowed,
  label,
  rate
}: {
  allowed?: boolean
  label: string
  rate?: number
}) {
  return (
    <div className={cn(
      "flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium",
      allowed
        ? "bg-green-500/10 text-green-600 dark:text-green-400"
        : "bg-muted text-muted-foreground"
    )}>
      {allowed ? <Check className="h-3 w-3" /> : <X className="h-3 w-3" />}
      <span>{label}</span>
      {rate !== undefined && allowed && (
        <span className="text-[10px] opacity-70">({(rate * 100).toFixed(0)}%)</span>
      )}
    </div>
  )
}

export function TrackCard({ track, onClick, selected, compact }: TrackCardProps) {
  const permissions = track.ai_permissions || {}
  const content = track.content || {}
  const metadata = track.semantic_metadata || {}

  if (compact) {
    return (
      <Card
        className={cn(
          "cursor-pointer transition-all hover:border-primary/50",
          selected && "border-primary ring-2 ring-primary/20"
        )}
        onClick={onClick}
      >
        <CardContent className="p-3">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
              <Music className="h-5 w-5 text-primary" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="font-semibold truncate">{track.title}</p>
              <p className="text-sm text-muted-foreground truncate">
                {content.artist_name || 'Unknown Artist'}
              </p>
            </div>
            <div className="flex gap-1">
              {permissions.voice_synthesis && (
                <Badge variant="secondary" className="text-[10px] px-1.5">
                  <Mic className="h-2.5 w-2.5 mr-0.5" />
                  Voice
                </Badge>
              )}
              {permissions.likeness_generation && (
                <Badge variant="secondary" className="text-[10px] px-1.5">
                  <User className="h-2.5 w-2.5 mr-0.5" />
                  Likeness
                </Badge>
              )}
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card
      className={cn(
        "cursor-pointer transition-all hover:border-primary/50",
        selected && "border-primary ring-2 ring-primary/20"
      )}
      onClick={onClick}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start gap-4">
          <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-primary/5">
            <Music className="h-7 w-7 text-primary" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="font-semibold text-lg leading-tight">{track.title}</h3>
            <p className="text-sm text-muted-foreground">
              {content.artist_name || 'Unknown Artist'}
              {content.album && <span className="opacity-70"> • {content.album}</span>}
            </p>
            <div className="mt-1 flex items-center gap-3 text-xs text-muted-foreground">
              <span className="flex items-center gap-1">
                <Clock className="h-3 w-3" />
                {formatDuration(content.duration_seconds)}
              </span>
              {content.audio_features?.bpm && (
                <span>{content.audio_features.bpm} BPM</span>
              )}
              {content.audio_features?.key && (
                <span>{content.audio_features.key}</span>
              )}
              {track.entity_key && (
                <span className="font-mono opacity-60">{track.entity_key}</span>
              )}
            </div>
          </div>
        </div>

        {/* Genre Tags */}
        {content.genre && content.genre.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-1">
            {content.genre.map((g) => (
              <Badge key={g} variant="outline" className="text-[10px]">
                {g}
              </Badge>
            ))}
          </div>
        )}

        {/* AI Permissions */}
        <div className="mt-4 pt-4 border-t border-border">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">
            AI Permissions
          </p>
          <div className="flex flex-wrap gap-2">
            <PermissionBadge
              allowed={permissions.training_permitted}
              label="Training"
            />
            <PermissionBadge
              allowed={permissions.generation_reference}
              label="Generation"
            />
            <PermissionBadge
              allowed={permissions.voice_synthesis}
              label="Voice"
              rate={permissions.voice_synthesis_rate}
            />
            <PermissionBadge
              allowed={permissions.likeness_generation}
              label="Likeness"
              rate={permissions.likeness_rate}
            />
            <PermissionBadge
              allowed={permissions.commercial_use}
              label="Commercial"
            />
          </div>

          {/* Pricing */}
          {permissions.generation_fee_per_use !== undefined && (
            <div className="mt-3 flex items-center gap-2 text-xs">
              <DollarSign className="h-3 w-3 text-muted-foreground" />
              <span className="text-muted-foreground">Generation fee:</span>
              <span className="font-mono font-medium">
                ${permissions.generation_fee_per_use}/use
              </span>
            </div>
          )}
        </div>

        {/* Mood Tags */}
        {metadata.mood_tags && metadata.mood_tags.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-1">
            {metadata.mood_tags.slice(0, 4).map((tag) => (
              <span
                key={tag}
                className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground"
              >
                {tag}
              </span>
            ))}
            {metadata.mood_tags.length > 4 && (
              <span className="text-[10px] px-1.5 py-0.5 text-muted-foreground">
                +{metadata.mood_tags.length - 4}
              </span>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
