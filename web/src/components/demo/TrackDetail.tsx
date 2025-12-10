'use client'

import { Music, Mic, User, Clock, DollarSign, FileText, Shield, ExternalLink } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { TrackData } from './TrackCard'

interface TrackDetailProps {
  track: TrackData
  onGenerateDemo?: () => void
}

function formatDuration(seconds?: number): string {
  if (!seconds) return '--:--'
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

function PermissionRow({
  icon: Icon,
  label,
  allowed,
  rate,
  details
}: {
  icon: React.ElementType
  label: string
  allowed?: boolean
  rate?: number
  details?: string
}) {
  return (
    <div className="flex items-center justify-between py-2 border-b border-border last:border-0">
      <div className="flex items-center gap-3">
        <Icon className={cn(
          "h-4 w-4",
          allowed ? "text-green-500" : "text-muted-foreground"
        )} />
        <span className="text-sm font-medium">{label}</span>
      </div>
      <div className="flex items-center gap-2">
        {rate !== undefined && allowed && (
          <span className="text-xs text-muted-foreground">
            {(rate * 100).toFixed(0)}% rate
          </span>
        )}
        {details && (
          <span className="text-xs text-muted-foreground">{details}</span>
        )}
        <Badge
          variant={allowed ? "default" : "secondary"}
          className={cn(
            "text-[10px]",
            allowed
              ? "bg-green-500/10 text-green-600 dark:text-green-400 hover:bg-green-500/20"
              : "bg-muted text-muted-foreground"
          )}
        >
          {allowed ? "Permitted" : "Not Permitted"}
        </Badge>
      </div>
    </div>
  )
}

export function TrackDetail({ track, onGenerateDemo }: TrackDetailProps) {
  const permissions = track.ai_permissions || {}
  const content = track.content || {}
  const metadata = track.semantic_metadata || {}

  return (
    <div className="space-y-4">
      {/* Header */}
      <Card>
        <CardContent className="p-6">
          <div className="flex items-start gap-4">
            <div className="flex h-20 w-20 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/20 to-primary/5">
              <Music className="h-10 w-10 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <h2 className="text-2xl font-bold">{track.title}</h2>
              <p className="text-lg text-muted-foreground">
                {content.artist_name || 'Unknown Artist'}
              </p>
              <div className="mt-2 flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
                {content.album && (
                  <span className="flex items-center gap-1">
                    <FileText className="h-3.5 w-3.5" />
                    {content.album}
                  </span>
                )}
                <span className="flex items-center gap-1">
                  <Clock className="h-3.5 w-3.5" />
                  {formatDuration(content.duration_seconds)}
                </span>
                {content.release_date && (
                  <span>{new Date(content.release_date).getFullYear()}</span>
                )}
                {track.entity_key && (
                  <Badge variant="outline" className="font-mono text-[10px]">
                    ISRC: {track.entity_key}
                  </Badge>
                )}
              </div>
            </div>
            {onGenerateDemo && (
              <Button onClick={onGenerateDemo} className="shrink-0">
                <ExternalLink className="h-4 w-4 mr-2" />
                Try Generation Demo
              </Button>
            )}
          </div>

          {/* Genre & Audio Features */}
          <div className="mt-4 pt-4 border-t border-border flex flex-wrap gap-4">
            {content.genre && content.genre.length > 0 && (
              <div>
                <p className="text-xs font-medium text-muted-foreground mb-1">Genre</p>
                <div className="flex gap-1">
                  {content.genre.map((g) => (
                    <Badge key={g} variant="secondary">{g}</Badge>
                  ))}
                </div>
              </div>
            )}
            {content.audio_features && (
              <div className="flex gap-4">
                {content.audio_features.bpm && (
                  <div>
                    <p className="text-xs font-medium text-muted-foreground">BPM</p>
                    <p className="font-semibold">{content.audio_features.bpm}</p>
                  </div>
                )}
                {content.audio_features.key && (
                  <div>
                    <p className="text-xs font-medium text-muted-foreground">Key</p>
                    <p className="font-semibold">{content.audio_features.key}</p>
                  </div>
                )}
                {content.audio_features.energy !== undefined && (
                  <div>
                    <p className="text-xs font-medium text-muted-foreground">Energy</p>
                    <p className="font-semibold">{(content.audio_features.energy * 100).toFixed(0)}%</p>
                  </div>
                )}
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* AI Permissions */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <Shield className="h-5 w-5" />
            AI Permissions
          </CardTitle>
        </CardHeader>
        <CardContent>
          <PermissionRow
            icon={Music}
            label="AI Training"
            allowed={permissions.training_permitted}
            details={permissions.training_permitted ? "Blanket license" : undefined}
          />
          <PermissionRow
            icon={Music}
            label="Generation Reference"
            allowed={permissions.generation_reference}
            details={permissions.generation_fee_per_use ? `$${permissions.generation_fee_per_use}/use` : undefined}
          />
          <PermissionRow
            icon={Music}
            label="Style Reference"
            allowed={permissions.generation_reference}
          />
          <PermissionRow
            icon={Mic}
            label="Voice Synthesis"
            allowed={permissions.voice_synthesis}
            rate={permissions.voice_synthesis_rate}
          />
          <PermissionRow
            icon={User}
            label="Likeness Generation"
            allowed={permissions.likeness_generation}
            rate={permissions.likeness_rate}
          />
          <PermissionRow
            icon={DollarSign}
            label="Commercial Use"
            allowed={permissions.commercial_use}
            details={permissions.commercial_terms}
          />

          {/* Attribution */}
          {permissions.attribution_text && (
            <div className="mt-4 p-3 rounded-lg bg-muted/50">
              <p className="text-xs font-medium text-muted-foreground mb-1">Required Attribution</p>
              <p className="text-sm italic">&quot;{permissions.attribution_text}&quot;</p>
            </div>
          )}

          {/* Pricing Summary */}
          <div className="mt-4 p-4 rounded-lg bg-primary/5 border border-primary/20">
            <p className="text-sm font-semibold mb-2">Licensing Rates</p>
            <div className="grid grid-cols-2 gap-2 text-sm">
              {permissions.generation_fee_per_use && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Generation:</span>
                  <span className="font-mono">${permissions.generation_fee_per_use}/use</span>
                </div>
              )}
              {permissions.voice_synthesis && permissions.voice_synthesis_rate && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Voice:</span>
                  <span className="font-mono">{(permissions.voice_synthesis_rate * 100).toFixed(0)}% rev share</span>
                </div>
              )}
              {permissions.likeness_generation && permissions.likeness_rate && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Likeness:</span>
                  <span className="font-mono">{(permissions.likeness_rate * 100).toFixed(0)}% rev share</span>
                </div>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Semantic Metadata */}
      {(metadata.mood_tags?.length || metadata.theme_tags?.length || metadata.instrument_tags?.length) && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-lg">Semantic Metadata</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {metadata.mood_tags && metadata.mood_tags.length > 0 && (
              <div>
                <p className="text-xs font-medium text-muted-foreground mb-1">Mood</p>
                <div className="flex flex-wrap gap-1">
                  {metadata.mood_tags.map((tag) => (
                    <Badge key={tag} variant="outline" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
            {metadata.theme_tags && metadata.theme_tags.length > 0 && (
              <div>
                <p className="text-xs font-medium text-muted-foreground mb-1">Themes</p>
                <div className="flex flex-wrap gap-1">
                  {metadata.theme_tags.map((tag) => (
                    <Badge key={tag} variant="outline" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
            {metadata.instrument_tags && metadata.instrument_tags.length > 0 && (
              <div>
                <p className="text-xs font-medium text-muted-foreground mb-1">Instruments</p>
                <div className="flex flex-wrap gap-1">
                  {metadata.instrument_tags.map((tag) => (
                    <Badge key={tag} variant="outline" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
            {metadata.vocal_tags && metadata.vocal_tags.length > 0 && (
              <div>
                <p className="text-xs font-medium text-muted-foreground mb-1">Vocals</p>
                <div className="flex flex-wrap gap-1">
                  {metadata.vocal_tags.map((tag) => (
                    <Badge key={tag} variant="outline" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}
